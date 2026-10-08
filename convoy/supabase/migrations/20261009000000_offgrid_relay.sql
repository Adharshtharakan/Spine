-- Gateway relaying for the off-grid links.
--
-- A car that still has signal uploads what it heard over the LoRa radio /
-- phone mesh on behalf of cars that have none. Party isolation still holds:
-- the caller must be a member of the trip, every relayed member/sender must
-- belong to the same trip, and an older relayed fix never overwrites a newer
-- one.

create function public.relay_positions(p_trip uuid, p_positions jsonb)
returns int
language plpgsql security definer set search_path = public as $$
declare
  p jsonb;
  m public.trip_members;
  n int := 0;
begin
  if not public.is_trip_member(p_trip) then raise exception 'not_a_member'; end if;
  if jsonb_typeof(p_positions) <> 'array' or jsonb_array_length(p_positions) > 100 then
    raise exception 'bad_positions';
  end if;
  for p in select * from jsonb_array_elements(p_positions) loop
    select * into m from public.trip_members
      where id = (p ->> 'member_id')::uuid and trip_id = p_trip;
    if not found then continue; end if;
    -- Reject fixes from the future (clock skew or forgery) beyond 2 minutes.
    if (p ->> 'recorded_at')::timestamptz > now() + interval '2 minutes' then continue; end if;
    insert into public.member_locations as l
      (member_id, trip_id, user_id, lat, lng, speed_mps, heading_deg, accuracy_m, recorded_at)
    values (
      m.id, p_trip, m.user_id,
      (p ->> 'lat')::double precision, (p ->> 'lng')::double precision,
      coalesce((p ->> 'speed_mps')::real, 0), coalesce((p ->> 'heading_deg')::real, 0),
      coalesce((p ->> 'accuracy_m')::real, 0), (p ->> 'recorded_at')::timestamptz)
    on conflict (member_id) do update set
      lat = excluded.lat, lng = excluded.lng, speed_mps = excluded.speed_mps,
      heading_deg = excluded.heading_deg, accuracy_m = excluded.accuracy_m,
      recorded_at = excluded.recorded_at
    where l.recorded_at < excluded.recorded_at;
    n := n + 1;
  end loop;
  return n;
end $$;

create function public.relay_message(p_row jsonb)
returns void
language plpgsql security definer set search_path = public as $$
declare
  trip uuid := (p_row ->> 'trip_id')::uuid;
  sender uuid := (p_row ->> 'sender_id')::uuid;
begin
  if not public.is_trip_member(trip) then raise exception 'not_a_member'; end if;
  if not exists (select 1 from public.trip_members where trip_id = trip and user_id = sender) then
    raise exception 'sender_not_in_trip';
  end if;
  if coalesce(p_row ->> 'kind', 'text') not in ('text', 'quick') then raise exception 'bad_kind'; end if;
  insert into public.messages (id, trip_id, sender_id, body, kind, created_at)
  values ((p_row ->> 'id')::uuid, trip, sender, p_row ->> 'body', coalesce(p_row ->> 'kind', 'text'),
          least(coalesce((p_row ->> 'created_at')::timestamptz, now()), now()))
  on conflict (id) do nothing;
end $$;
