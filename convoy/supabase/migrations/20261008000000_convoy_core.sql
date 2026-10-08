-- Convoy core schema.
--
-- Isolation model: every party-scoped row carries trip_id, and every policy
-- funnels through is_trip_member(). Writes that need cross-row checks
-- (joining, approving, publishing, lead changes) go through SECURITY DEFINER
-- RPCs so the rules live in one place and the client cannot skip them.

create extension if not exists pgcrypto;

-- ───────────────────────────── profiles ─────────────────────────────

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default 'Traveller' check (char_length(display_name) between 1 and 60),
  avatar_url text,
  -- Set by an ID check provider (or an admin). Phone confirmation from
  -- Supabase Auth also counts towards verification; see is_verified_party().
  identity_verified_at timestamptz,
  created_at timestamptz not null default now()
);

create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(nullif(new.raw_user_meta_data ->> 'display_name', ''), 'Traveller'))
  on conflict (id) do nothing;
  insert into public.entitlements (user_id) values (new.id) on conflict (user_id) do nothing;
  return new;
end $$;

-- ─────────────────────────── entitlements ───────────────────────────

create table public.entitlements (
  user_id uuid primary key references auth.users (id) on delete cascade,
  tier text not null default 'free' check (tier in ('free', 'premium')),
  expires_at timestamptz,
  source text check (source in ('google_play', 'app_store', 'promo', 'admin')),
  product_id text,
  original_transaction_id text unique,
  updated_at timestamptz not null default now()
);

create trigger on_auth_user_created
after insert on auth.users for each row execute function public.handle_new_user();

create function public.is_premium(uid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.entitlements e
    where e.user_id = uid and e.tier = 'premium'
      and (e.expires_at is null or e.expires_at > now())
  )
$$;

-- ──────────────────── guidelines & driver terms ─────────────────────

create table public.guideline_documents (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('platform_guidelines', 'driver_terms')),
  version int not null check (version > 0),
  title text not null,
  body text not null,
  published_at timestamptz not null default now(),
  unique (kind, version)
);

create table public.guideline_acceptances (
  user_id uuid not null references auth.users (id) on delete cascade,
  document_id uuid not null references public.guideline_documents (id),
  accepted_at timestamptz not null default now(),
  -- Driver attestations captured with driver_terms, e.g.
  -- {"licensed": true, "insured": true, "roadworthy": true}
  attestation jsonb not null default '{}'::jsonb,
  primary key (user_id, document_id)
);

create function public.current_document(doc_kind text) returns public.guideline_documents
language sql stable set search_path = public as $$
  select * from public.guideline_documents
  where kind = doc_kind and published_at <= now()
  order by version desc limit 1
$$;

create function public.accepted_version(uid uuid, doc_kind text) returns int
language sql stable security definer set search_path = public as $$
  select max(d.version) from public.guideline_acceptances a
  join public.guideline_documents d on d.id = a.document_id
  where a.user_id = uid and d.kind = doc_kind
$$;

create function public.has_accepted_current(uid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.accepted_version(uid, 'platform_guidelines') >= (public.current_document('platform_guidelines')).version, false)
     and coalesce(public.accepted_version(uid, 'driver_terms') >= (public.current_document('driver_terms')).version, false)
$$;

/** A verified party: confirmed phone or ID check, plus current guidelines and driver terms. */
create function public.is_verified_party(uid uuid) returns boolean
language sql stable security definer set search_path = public, auth as $$
  select public.has_accepted_current(uid) and exists (
    select 1 from auth.users u left join public.profiles p on p.id = u.id
    where u.id = uid and (u.phone_confirmed_at is not null or p.identity_verified_at is not null)
  )
$$;

create function public.accept_guideline(document uuid, attestation jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare d public.guideline_documents;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  select * into d from public.guideline_documents where id = document;
  if not found then raise exception 'unknown_document'; end if;
  if d.kind = 'driver_terms' and not (
       coalesce((attestation ->> 'licensed')::boolean, false)
   and coalesce((attestation ->> 'insured')::boolean, false)
   and coalesce((attestation ->> 'roadworthy')::boolean, false)) then
    raise exception 'driver_attestation_required';
  end if;
  insert into public.guideline_acceptances (user_id, document_id, attestation)
  values (auth.uid(), document, attestation)
  on conflict (user_id, document_id) do update set accepted_at = now(), attestation = excluded.attestation;
end $$;

-- ─────────────────────────────── trips ──────────────────────────────

create table public.trips (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users (id) on delete cascade,
  title text not null check (char_length(title) between 1 and 80),
  description text not null default '',
  invite_code text not null unique default upper(substr(encode(gen_random_bytes(6), 'hex'), 1, 8)),
  visibility text not null default 'private' check (visibility in ('private', 'public')),
  lead_member_id uuid,
  starts_at timestamptz,
  ends_at timestamptz,
  max_vehicles int check (max_vehicles between 1 and 50),
  -- Discovery listing (public trips only).
  published_at timestamptz,
  summary text not null default '',
  tags text[] not null default '{}',
  start_lat double precision, start_lng double precision,
  end_lat double precision, end_lng double precision,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.trip_members (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null default 'driver' check (role in ('owner', 'lead', 'driver', 'passenger')),
  vehicle_label text check (char_length(vehicle_label) <= 40),
  vehicle_color int not null default -13730314, -- 0xFF2E7DF6 as signed int32
  has_vehicle boolean not null default true,
  joined_at timestamptz not null default now(),
  unique (trip_id, user_id)
);
create index on public.trip_members (user_id);

alter table public.trips
  add constraint trips_lead_fk foreign key (lead_member_id)
  references public.trip_members (id) on delete set null deferrable initially deferred;

create function public.is_trip_member(trip uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.trip_members m where m.trip_id = trip and m.user_id = auth.uid())
$$;

create function public.is_trip_owner(trip uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.trips t where t.id = trip and t.owner_id = auth.uid())
$$;

-- Freemium cap: two vehicles per trip on the free tier, enforced here so no
-- client path (invite, discovery approval, direct update) can exceed it.
create function public.vehicle_cap(trip uuid) returns int
language sql stable security definer set search_path = public as $$
  select least(
    case when public.is_premium(t.owner_id) then 25 else 2 end,
    coalesce(t.max_vehicles, 50))
  from public.trips t where t.id = trip
$$;

create function public.enforce_vehicle_cap() returns trigger
language plpgsql security definer set search_path = public as $$
declare used int; cap int;
begin
  if not new.has_vehicle then return new; end if;
  if tg_op = 'UPDATE' and old.has_vehicle then return new; end if;
  perform 1 from public.trips where id = new.trip_id for update; -- serialise concurrent joins
  select count(*) into used from public.trip_members
   where trip_id = new.trip_id and has_vehicle and id <> new.id;
  cap := public.vehicle_cap(new.trip_id);
  if used >= cap then
    raise exception 'vehicle_cap_reached' using hint = format('This convoy allows %s vehicles. The organiser can upgrade to Premium for larger convoys.', cap);
  end if;
  return new;
end $$;

create trigger trip_members_vehicle_cap
before insert or update of has_vehicle on public.trip_members
for each row execute function public.enforce_vehicle_cap();

create function public.touch_updated_at() returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end $$;
create trigger trips_touch before update on public.trips for each row execute function public.touch_updated_at();

-- ───────────────────────────── itinerary ────────────────────────────

create table public.waypoints (
  id uuid primary key,
  trip_id uuid not null references public.trips (id) on delete cascade,
  name text not null default '' check (char_length(name) <= 120),
  lat double precision not null check (lat between -90 and 90),
  lng double precision not null check (lng between -180 and 180),
  kind text not null default 'waypoint'
    check (kind in ('origin', 'waypoint', 'rest_stop', 'fuel', 'lodging', 'campsite', 'destination')),
  sort_key double precision not null,
  hlc text not null,
  planned_arrival timestamptz,
  planned_departure timestamptz,
  notes text not null default '' check (char_length(notes) <= 2000),
  deleted boolean not null default false,
  updated_by uuid references auth.users (id) on delete set null,
  affiliate_offer_id text,
  updated_at timestamptz not null default now()
);
create index on public.waypoints (trip_id);

-- Last-writer-wins by hybrid logical clock. An upsert carrying an older clock
-- (a phone replaying its offline outbox after someone else edited the stop)
-- is dropped silently instead of clobbering the newer row.
create function public.waypoints_lww() returns trigger language plpgsql as $$
begin
  if new.hlc <= old.hlc then return null; end if;
  if new.trip_id <> old.trip_id then raise exception 'trip_id_immutable'; end if;
  new.updated_at := now();
  return new;
end $$;
create trigger waypoints_lww before update on public.waypoints
for each row execute function public.waypoints_lww();

-- ───────────────────────────── messaging ────────────────────────────

create table public.messages (
  id uuid primary key, -- client-generated so outbox replays are idempotent
  trip_id uuid not null references public.trips (id) on delete cascade,
  sender_id uuid not null references auth.users (id) on delete cascade,
  body text not null check (char_length(body) between 1 and 2000),
  kind text not null default 'text' check (kind in ('text', 'quick', 'system')),
  created_at timestamptz not null default now()
);
create index on public.messages (trip_id, created_at desc);

-- ──────────────────────── last-known positions ──────────────────────
-- Live fixes travel over Realtime broadcast only. This table holds one row
-- per member, upserted every ~30 s, so a driver who opens the app late (or
-- reconnects) sees everyone immediately.

create table public.member_locations (
  member_id uuid primary key references public.trip_members (id) on delete cascade,
  trip_id uuid not null references public.trips (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  lat double precision not null,
  lng double precision not null,
  speed_mps real not null default 0,
  heading_deg real not null default 0,
  accuracy_m real not null default 0,
  recorded_at timestamptz not null
);
create index on public.member_locations (trip_id);

-- ───────────────────── discovery & join requests ────────────────────

create table public.join_requests (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips (id) on delete cascade,
  requester_id uuid not null references auth.users (id) on delete cascade,
  vehicle_label text not null default '' check (char_length(vehicle_label) <= 40),
  message text not null default '' check (char_length(message) <= 500),
  status text not null default 'pending' check (status in ('pending', 'approved', 'declined', 'withdrawn')),
  -- Mutual acceptance is recorded on the request itself: the versions each
  -- side had accepted at the moment they committed.
  requester_guidelines_version int,
  requester_terms_version int,
  owner_guidelines_version int,
  owner_terms_version int,
  decided_by uuid references auth.users (id),
  decided_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index join_requests_one_pending on public.join_requests (trip_id, requester_id) where status = 'pending';

-- ───────────────────────── affiliate & sponsors ─────────────────────

create table public.affiliate_clicks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users (id) on delete set null,
  trip_id uuid references public.trips (id) on delete set null,
  offer_id text not null,
  provider text not null,
  category text not null check (category in ('hotel', 'campsite', 'fuel', 'rest_area')),
  created_at timestamptz not null default now()
);

create table public.affiliate_conversions (
  id uuid primary key default gen_random_uuid(),
  click_id uuid references public.affiliate_clicks (id) on delete set null,
  provider text not null,
  external_ref text not null,
  commission_cents int not null default 0,
  currency text not null default 'USD',
  status text not null default 'pending' check (status in ('pending', 'confirmed', 'cancelled')),
  created_at timestamptz not null default now(),
  unique (provider, external_ref)
);

-- Tourism boards and highway businesses featured in discovery and along routes.
create table public.sponsored_placements (
  id uuid primary key default gen_random_uuid(),
  partner_name text not null,
  category text not null check (category in ('hotel', 'campsite', 'fuel', 'rest_area', 'attraction')),
  name text not null,
  lat double precision not null,
  lng double precision not null,
  radius_km double precision not null default 50,
  url text not null,
  weight int not null default 1,
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  active boolean not null default true
);

-- ─────────────────────────────── RPCs ───────────────────────────────

create function public.require_accepted() returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  if not public.has_accepted_current(auth.uid()) then
    raise exception 'guidelines_not_accepted' using hint = 'Accept the current platform guidelines and driver terms first.';
  end if;
end $$;

create function public.create_trip(
  p_title text, p_description text default '', p_starts_at timestamptz default null,
  p_vehicle_label text default null
) returns public.trips
language plpgsql security definer set search_path = public as $$
declare t public.trips; m uuid;
begin
  perform public.require_accepted();
  insert into public.trips (owner_id, title, description, starts_at)
  values (auth.uid(), p_title, coalesce(p_description, ''), p_starts_at) returning * into t;
  insert into public.trip_members (trip_id, user_id, role, vehicle_label)
  values (t.id, auth.uid(), 'owner', p_vehicle_label) returning id into m;
  update public.trips set lead_member_id = m where id = t.id returning * into t;
  return t;
end $$;

/** Private invite (friends and family). Still requires current guidelines. */
create function public.join_by_invite(p_code text, p_vehicle_label text default null, p_has_vehicle boolean default true)
returns public.trips
language plpgsql security definer set search_path = public as $$
declare t public.trips;
begin
  perform public.require_accepted();
  select * into t from public.trips where invite_code = upper(trim(p_code));
  if not found then raise exception 'invalid_invite'; end if;
  insert into public.trip_members (trip_id, user_id, role, vehicle_label, has_vehicle)
  values (t.id, auth.uid(), case when p_has_vehicle then 'driver' else 'passenger' end, p_vehicle_label, p_has_vehicle)
  on conflict (trip_id, user_id) do nothing;
  insert into public.messages (id, trip_id, sender_id, body, kind)
  values (gen_random_uuid(), t.id, auth.uid(), 'joined the convoy', 'system');
  return t;
end $$;

create function public.set_lead_vehicle(p_trip uuid, p_member uuid) returns void
language plpgsql security definer set search_path = public as $$
declare t public.trips;
begin
  select * into t from public.trips where id = p_trip;
  if not found then raise exception 'unknown_trip'; end if;
  if not (t.owner_id = auth.uid() or exists (
      select 1 from public.trip_members where id = t.lead_member_id and user_id = auth.uid())) then
    raise exception 'not_allowed';
  end if;
  if not exists (select 1 from public.trip_members where id = p_member and trip_id = p_trip and has_vehicle) then
    raise exception 'not_a_vehicle_in_trip';
  end if;
  update public.trips set lead_member_id = p_member where id = p_trip;
  update public.trip_members set role = 'driver' where trip_id = p_trip and role = 'lead';
  update public.trip_members set role = 'lead' where id = p_member and role <> 'owner';
  insert into public.messages (id, trip_id, sender_id, body, kind)
  values (gen_random_uuid(), p_trip, auth.uid(), 'changed the lead vehicle', 'system');
end $$;

/** Publish to discovery. Only verified parties may list a trip. */
create function public.publish_trip(
  p_trip uuid, p_summary text, p_tags text[],
  p_start_lat double precision, p_start_lng double precision,
  p_end_lat double precision, p_end_lng double precision,
  p_max_vehicles int default null
) returns public.trips
language plpgsql security definer set search_path = public as $$
declare t public.trips;
begin
  if not public.is_trip_owner(p_trip) then raise exception 'not_owner'; end if;
  if not public.is_verified_party(auth.uid()) then
    raise exception 'not_verified' using hint = 'Confirm your phone number and accept the current guidelines and driver terms to publish trips.';
  end if;
  update public.trips set
    visibility = 'public', published_at = now(), summary = coalesce(p_summary, ''),
    tags = coalesce(p_tags, '{}'), start_lat = p_start_lat, start_lng = p_start_lng,
    end_lat = p_end_lat, end_lng = p_end_lng, max_vehicles = coalesce(p_max_vehicles, max_vehicles)
  where id = p_trip returning * into t;
  return t;
end $$;

create function public.unpublish_trip(p_trip uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_trip_owner(p_trip) then raise exception 'not_owner'; end if;
  update public.trips set visibility = 'private', published_at = null where id = p_trip;
  update public.join_requests set status = 'withdrawn' where trip_id = p_trip and status = 'pending';
end $$;

/** Step one of mutual acceptance: the traveller commits to the current terms. */
create function public.request_to_join(p_trip uuid, p_vehicle_label text, p_message text default '')
returns public.join_requests
language plpgsql security definer set search_path = public as $$
declare t public.trips; r public.join_requests;
begin
  perform public.require_accepted();
  select * into t from public.trips where id = p_trip and visibility = 'public' and published_at is not null;
  if not found then raise exception 'trip_not_open'; end if;
  if public.is_trip_member(p_trip) then raise exception 'already_member'; end if;
  insert into public.join_requests (trip_id, requester_id, vehicle_label, message,
    requester_guidelines_version, requester_terms_version)
  values (p_trip, auth.uid(), coalesce(p_vehicle_label, ''), coalesce(p_message, ''),
    public.accepted_version(auth.uid(), 'platform_guidelines'),
    public.accepted_version(auth.uid(), 'driver_terms'))
  returning * into r;
  return r;
end $$;

/**
 * Step two: the organiser, who must themselves be a verified party on the
 * current terms, accepts the traveller. Only now does membership exist.
 */
create function public.decide_join_request(p_request uuid, p_approve boolean)
returns public.join_requests
language plpgsql security definer set search_path = public as $$
declare r public.join_requests;
begin
  select * into r from public.join_requests where id = p_request for update;
  if not found then raise exception 'unknown_request'; end if;
  if not public.is_trip_owner(r.trip_id) then raise exception 'not_owner'; end if;
  if r.status <> 'pending' then raise exception 'already_decided'; end if;

  if p_approve then
    if not public.is_verified_party(auth.uid()) then raise exception 'not_verified'; end if;
    -- The traveller may have accepted an older version before terms changed.
    if not public.has_accepted_current(r.requester_id) then
      raise exception 'requester_terms_outdated' using hint = 'The traveller must accept the updated guidelines before joining.';
    end if;
    insert into public.trip_members (trip_id, user_id, role, vehicle_label)
    values (r.trip_id, r.requester_id, 'driver', nullif(r.vehicle_label, ''));
    insert into public.messages (id, trip_id, sender_id, body, kind)
    values (gen_random_uuid(), r.trip_id, r.requester_id, 'joined the convoy from Discover', 'system');
  end if;

  update public.join_requests set
    status = case when p_approve then 'approved' else 'declined' end,
    owner_guidelines_version = public.accepted_version(auth.uid(), 'platform_guidelines'),
    owner_terms_version = public.accepted_version(auth.uid(), 'driver_terms'),
    decided_by = auth.uid(), decided_at = now()
  where id = p_request returning * into r;
  return r;
end $$;

/** Public listing with only the fields safe to show strangers. */
create function public.discover_trips(
  p_south double precision default -90, p_west double precision default -180,
  p_north double precision default 90, p_east double precision default 180,
  p_from timestamptz default now(), p_limit int default 50
) returns table (
  id uuid, title text, summary text, tags text[], starts_at timestamptz,
  start_lat double precision, start_lng double precision,
  end_lat double precision, end_lng double precision,
  owner_name text, owner_verified boolean, vehicle_count int, open_slots int
)
language sql stable security definer set search_path = public as $$
  select t.id, t.title, t.summary, t.tags, t.starts_at,
         t.start_lat, t.start_lng, t.end_lat, t.end_lng,
         p.display_name, public.is_verified_party(t.owner_id),
         v.n, greatest(public.vehicle_cap(t.id) - v.n, 0)
  from public.trips t
  join public.profiles p on p.id = t.owner_id
  cross join lateral (select count(*)::int n from public.trip_members m where m.trip_id = t.id and m.has_vehicle) v
  where t.visibility = 'public' and t.published_at is not null
    and (t.starts_at is null or t.starts_at >= p_from - interval '1 day')
    and t.start_lat between p_south and p_north
    and t.start_lng between p_west and p_east
  order by t.starts_at nulls last
  limit least(greatest(p_limit, 1), 200)
$$;

-- ─────────────────────────────── RLS ────────────────────────────────

alter table public.profiles enable row level security;
alter table public.entitlements enable row level security;
alter table public.guideline_documents enable row level security;
alter table public.guideline_acceptances enable row level security;
alter table public.trips enable row level security;
alter table public.trip_members enable row level security;
alter table public.waypoints enable row level security;
alter table public.messages enable row level security;
alter table public.member_locations enable row level security;
alter table public.join_requests enable row level security;
alter table public.affiliate_clicks enable row level security;
alter table public.affiliate_conversions enable row level security;
alter table public.sponsored_placements enable row level security;

create policy "profiles readable" on public.profiles for select to authenticated using (true);
create policy "own profile" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
revoke update on public.profiles from authenticated;
grant update (display_name, avatar_url) on public.profiles to authenticated;

create policy "own entitlement" on public.entitlements for select to authenticated using (user_id = auth.uid());

create policy "documents readable" on public.guideline_documents for select to anon, authenticated using (published_at <= now());
create policy "own acceptances" on public.guideline_acceptances for select to authenticated using (user_id = auth.uid());

create policy "members see trip" on public.trips for select to authenticated
  using (public.is_trip_member(id) or (visibility = 'public' and published_at is not null));
create policy "owner edits trip" on public.trips for update to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
revoke update on public.trips from authenticated;
grant update (title, description, starts_at, ends_at) on public.trips to authenticated;

create policy "party sees members" on public.trip_members for select to authenticated using (public.is_trip_member(trip_id));
create policy "edit own vehicle" on public.trip_members for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "leave trip" on public.trip_members for delete to authenticated
  using (user_id = auth.uid() and role <> 'owner');
revoke update on public.trip_members from authenticated;
grant update (vehicle_label, vehicle_color, has_vehicle) on public.trip_members to authenticated;

create policy "party reads itinerary" on public.waypoints for select to authenticated using (public.is_trip_member(trip_id));
create policy "party adds stops" on public.waypoints for insert to authenticated
  with check (public.is_trip_member(trip_id) and updated_by = auth.uid());
create policy "party edits stops" on public.waypoints for update to authenticated
  using (public.is_trip_member(trip_id)) with check (public.is_trip_member(trip_id) and updated_by = auth.uid());

create policy "party reads chat" on public.messages for select to authenticated using (public.is_trip_member(trip_id));
create policy "party posts chat" on public.messages for insert to authenticated
  with check (public.is_trip_member(trip_id) and sender_id = auth.uid() and kind in ('text', 'quick'));

create policy "party reads positions" on public.member_locations for select to authenticated using (public.is_trip_member(trip_id));
create policy "write own position" on public.member_locations for insert to authenticated
  with check (user_id = auth.uid() and exists (
    select 1 from public.trip_members m where m.id = member_id and m.user_id = auth.uid() and m.trip_id = member_locations.trip_id));
create policy "update own position" on public.member_locations for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "requester or owner sees request" on public.join_requests for select to authenticated
  using (requester_id = auth.uid() or public.is_trip_owner(trip_id));
create policy "requester withdraws" on public.join_requests for update to authenticated
  using (requester_id = auth.uid() and status = 'pending') with check (status = 'withdrawn');
revoke update on public.join_requests from authenticated;
grant update (status) on public.join_requests to authenticated;

create policy "active sponsors readable" on public.sponsored_placements for select to anon, authenticated
  using (active and starts_at <= now() and (ends_at is null or ends_at > now()));
-- affiliate_clicks / affiliate_conversions: service role only (no policies).

grant execute on function public.discover_trips to anon, authenticated;
revoke execute on function public.handle_new_user from public, anon, authenticated;
revoke execute on function public.enforce_vehicle_cap from public, anon, authenticated;

-- ──────────────────────── Realtime authorisation ────────────────────
-- Private channels named trip:<uuid> carry position broadcasts, presence and
-- WebRTC signalling. Only members of that trip may join or send.

create policy "party joins trip channel" on realtime.messages for select to authenticated
  using (
    realtime.topic() like 'trip:%'
    and public.is_trip_member(nullif(split_part(realtime.topic(), ':', 2), '')::uuid)
  );
create policy "party sends on trip channel" on realtime.messages for insert to authenticated
  with check (
    realtime.topic() like 'trip:%'
    and public.is_trip_member(nullif(split_part(realtime.topic(), ':', 2), '')::uuid)
  );

alter publication supabase_realtime add table public.waypoints, public.messages, public.trip_members, public.trips, public.join_requests;
