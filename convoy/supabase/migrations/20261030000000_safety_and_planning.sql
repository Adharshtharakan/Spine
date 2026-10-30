-- Safety and planning: convoy events (SOS, hazards, regroup points,
-- headcount), convoy roles, fuel and toll settings, multi-day itineraries,
-- checklists and push-notification device tokens.

-- ─────────────────────────── roles and fuel ─────────────────────────

alter table public.trip_members
  -- Lead is trips.lead_member_id. Sweep drives last and watches for stragglers;
  -- the navigator is a passenger who runs the phone.
  add column convoy_role text check (convoy_role in ('sweep', 'navigator')),
  -- Full-tank range and fuel economy, for range warnings and cost estimates.
  add column tank_range_km int check (tank_range_km between 50 and 3000),
  add column fuel_kmpl real check (fuel_kmpl between 2 and 80);

alter table public.trips
  add column fuel_price numeric(8, 2) check (fuel_price > 0),
  add column toll_per_plaza numeric(8, 2) check (toll_per_plaza >= 0),
  add column currency text not null default 'INR' check (char_length(currency) = 3);

-- Owner or lead assigns sweep/navigator; anyone may take or drop navigator
-- for themselves. One sweep per trip.
create function public.set_convoy_role(p_member uuid, p_role text) returns void
language plpgsql security definer set search_path = public as $$
declare m public.trip_members; t public.trips; manager boolean;
begin
  select * into m from public.trip_members where id = p_member;
  if not found then raise exception 'unknown_member'; end if;
  select * into t from public.trips where id = m.trip_id;
  if not public.is_trip_member(m.trip_id) then raise exception 'not_a_member'; end if;
  if p_role is not null and p_role not in ('sweep', 'navigator') then raise exception 'bad_role'; end if;
  manager := t.owner_id = auth.uid() or exists (
    select 1 from public.trip_members where id = t.lead_member_id and user_id = auth.uid());
  if not manager and not (m.user_id = auth.uid() and coalesce(p_role, 'navigator') = 'navigator') then
    raise exception 'not_allowed';
  end if;
  if p_role = 'sweep' then
    if not m.has_vehicle then raise exception 'not_a_vehicle_in_trip'; end if;
    update public.trip_members set convoy_role = null where trip_id = m.trip_id and convoy_role = 'sweep';
  end if;
  update public.trip_members set convoy_role = p_role where id = p_member;
end $$;

-- ─────────────────────────── multi-day trips ────────────────────────

alter table public.waypoints add column day smallint check (day between 1 and 60);

-- ──────────────────────────── convoy events ─────────────────────────
-- Append-only: the app derives current state (who needs help, which hazards
-- are live, the regroup point, who is ready) from the sequence. Ids are
-- client-generated so the radio relay and the outbox can replay safely.

create table public.trip_events (
  id uuid primary key,
  trip_id uuid not null references public.trips (id) on delete cascade,
  member_id uuid not null references public.trip_members (id) on delete cascade,
  kind text not null check (kind in (
    'sos', 'sos_clear', 'hazard', 'hazard_clear', 'regroup', 'regroup_clear', 'headcount', 'ready', 'go')),
  lat double precision check (lat between -90 and 90),
  lng double precision check (lng between -180 and 180),
  payload jsonb not null default '{}' check (pg_column_size(payload) <= 2048),
  created_at timestamptz not null default now(),
  created_by uuid not null default auth.uid() references auth.users (id) on delete cascade
);
create index on public.trip_events (trip_id, created_at desc);

-- Events raised offline keep their own time, but never one in the future.
create function public.trip_events_clamp() returns trigger language plpgsql as $$
begin
  new.created_at := least(coalesce(new.created_at, now()), now());
  return new;
end $$;
create trigger trip_events_clamp before insert on public.trip_events
for each row execute function public.trip_events_clamp();

create function public.is_own_member(member uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.trip_members m where m.id = member and m.user_id = auth.uid())
$$;

alter table public.trip_events enable row level security;
create policy "party reads events" on public.trip_events for select to authenticated
  using (public.is_trip_member(trip_id));
create policy "member raises own events" on public.trip_events for insert to authenticated
  with check (
    public.is_trip_member(trip_id) and created_by = auth.uid() and exists (
      select 1 from public.trip_members m where m.id = member_id and m.trip_id = trip_events.trip_id and m.user_id = auth.uid()));

-- Gateway relay for events heard over the radio (an SOS from a car with no signal).
create function public.relay_event(p_row jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare trip uuid := (p_row ->> 'trip_id')::uuid;
begin
  if not public.is_trip_member(trip) then raise exception 'not_a_member'; end if;
  if not exists (select 1 from public.trip_members where id = (p_row ->> 'member_id')::uuid and trip_id = trip) then
    raise exception 'member_not_in_trip';
  end if;
  insert into public.trip_events (id, trip_id, member_id, kind, lat, lng, payload, created_at, created_by)
  values ((p_row ->> 'id')::uuid, trip, (p_row ->> 'member_id')::uuid, p_row ->> 'kind',
          (p_row ->> 'lat')::double precision, (p_row ->> 'lng')::double precision,
          coalesce(p_row -> 'payload', '{}'), coalesce((p_row ->> 'created_at')::timestamptz, now()), auth.uid())
  on conflict (id) do nothing;
end $$;

-- ───────────────────────────── checklists ───────────────────────────
-- member_id null: shared with the party (tent, stove). Otherwise personal
-- (documents, my car's pre-trip check) and visible only to its owner.

create table public.checklist_items (
  id uuid primary key,
  trip_id uuid not null references public.trips (id) on delete cascade,
  member_id uuid references public.trip_members (id) on delete cascade,
  category text not null check (category in ('packing', 'documents', 'vehicle', 'group')),
  title text not null check (char_length(title) between 1 and 120),
  done boolean not null default false,
  done_by uuid references auth.users (id) on delete set null,
  sort double precision not null default 0,
  created_by uuid not null default auth.uid() references auth.users (id) on delete cascade,
  updated_at timestamptz not null default now()
);
create index on public.checklist_items (trip_id);
create trigger checklist_touch before update on public.checklist_items
for each row execute function public.touch_updated_at();

alter table public.checklist_items enable row level security;
create policy "see shared and own items" on public.checklist_items for select to authenticated
  using (public.is_trip_member(trip_id) and (member_id is null or public.is_own_member(member_id)));
create policy "add shared or own items" on public.checklist_items for insert to authenticated
  with check (public.is_trip_member(trip_id) and created_by = auth.uid()
              and (member_id is null or public.is_own_member(member_id)));
create policy "tick shared or own items" on public.checklist_items for update to authenticated
  using (public.is_trip_member(trip_id) and (member_id is null or public.is_own_member(member_id)))
  with check (public.is_trip_member(trip_id) and (member_id is null or public.is_own_member(member_id)));
create policy "remove own or owned items" on public.checklist_items for delete to authenticated
  using (public.is_trip_member(trip_id) and (public.is_own_member(member_id)
         or (member_id is null and (created_by = auth.uid() or public.is_trip_owner(trip_id)))));

-- ─────────────────────── push notification tokens ───────────────────

create table public.device_tokens (
  token text primary key check (char_length(token) between 10 and 4096),
  user_id uuid not null references auth.users (id) on delete cascade,
  platform text not null check (platform in ('android', 'ios', 'web')),
  updated_at timestamptz not null default now()
);
create index on public.device_tokens (user_id);
alter table public.device_tokens enable row level security;
create policy "own tokens" on public.device_tokens for select to authenticated using (user_id = auth.uid());
create policy "drop own tokens" on public.device_tokens for delete to authenticated using (user_id = auth.uid());

-- A phone that changes hands (sign out, sign in as someone else) moves its
-- token to the new user rather than failing on the old owner's row.
create function public.register_device_token(p_token text, p_platform text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  insert into public.device_tokens (token, user_id, platform) values (p_token, auth.uid(), p_platform)
  on conflict (token) do update set user_id = auth.uid(), platform = excluded.platform, updated_at = now();
end $$;

revoke execute on function public.trip_events_clamp from public, anon, authenticated;
alter publication supabase_realtime add table public.trip_events, public.checklist_items;
