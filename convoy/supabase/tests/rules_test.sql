-- Exercises party isolation, mutual acceptance, the vehicle cap and the
-- itinerary clock guard. Run after supabase_stub.sql, the migrations and seed.sql.
\set ON_ERROR_STOP 1
\set alice '''a0000000-0000-4000-8000-000000000001'''
\set bob   '''b0000000-0000-4000-8000-000000000002'''
\set carol '''c0000000-0000-4000-8000-000000000003'''
\set dave  '''d0000000-0000-4000-8000-000000000004'''

insert into auth.users (id, phone_confirmed_at, raw_user_meta_data) values
  (:alice, now(), '{"display_name":"Alice"}'),
  (:bob, null, '{"display_name":"Bob"}'),
  (:carol, null, '{"display_name":"Carol"}'),
  (:dave, null, '{"display_name":"Dave"}');

create function pg_temp.as_user(uid uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', uid::text, false);
$$;
create function pg_temp.expect_error(sql text, needle text) returns void language plpgsql as $$
begin
  execute sql;
  raise exception 'expected error containing "%" but statement succeeded: %', needle, sql;
exception when others then
  if position(needle in sqlerrm) = 0 then
    raise exception 'expected "%" got "%" for %', needle, sqlerrm, sql;
  end if;
end $$;
create function pg_temp.accept_all() returns void language sql as $$
  select public.accept_guideline((public.current_document('platform_guidelines')).id);
  select public.accept_guideline((public.current_document('driver_terms')).id,
    '{"licensed":true,"insured":true,"roadworthy":true}');
$$;

set role authenticated;

-- Guidelines gate everything.
select pg_temp.as_user(:alice);
select pg_temp.expect_error($$select public.create_trip('Coast run')$$, 'guidelines_not_accepted');
select pg_temp.expect_error(
  $$select public.accept_guideline((public.current_document('driver_terms')).id, '{"licensed":true}')$$,
  'driver_attestation_required');
select pg_temp.accept_all();
create temp table t as select * from public.create_trip('Coast run', '', null, 'Alice''s Jeep');
grant select on t to authenticated;

-- Bob joins by invite (free tier: second vehicle ok).
select pg_temp.as_user(:bob);
select pg_temp.accept_all();
select public.join_by_invite((select invite_code from t), 'Bob''s van');

-- Carol cannot join a third vehicle on the free tier.
select pg_temp.as_user(:carol);
select pg_temp.accept_all();
select pg_temp.expect_error(format($$select public.join_by_invite(%L, 'Carol''s car')$$, (select invite_code from t)), 'vehicle_cap_reached');
-- …but can ride as a passenger.
select public.join_by_invite((select invite_code from t), null, false);

-- Party isolation: Dave sees nothing of a private trip.
select pg_temp.as_user(:dave);
do $$ begin
  if exists (select 1 from public.trips) then raise exception 'dave sees private trip'; end if;
  if exists (select 1 from public.trip_members) then raise exception 'dave sees members'; end if;
end $$;
select pg_temp.expect_error(format($$insert into public.messages (id, trip_id, sender_id, body) values (gen_random_uuid(), %L, %L, 'hi')$$,
  (select id from t), 'd0000000-0000-4000-8000-000000000004'), 'row-level security');

-- Itinerary clock guard: an older HLC never overwrites a newer one.
select pg_temp.as_user(:bob);
insert into public.waypoints (id, trip_id, name, lat, lng, sort_key, hlc, updated_by)
values ('e0000000-0000-4000-8000-000000000001', (select id from t), 'Diner', 1, 1, 1024,
        '000000000002000-00000-b', :bob);
insert into public.waypoints (id, trip_id, name, lat, lng, sort_key, hlc, updated_by)
values ('e0000000-0000-4000-8000-000000000001', (select id from t), 'Stale name', 1, 1, 1024,
        '000000000001000-00000-a', :bob)
on conflict (id) do update set name = excluded.name, hlc = excluded.hlc;
do $$ begin
  if (select name from public.waypoints) <> 'Diner' then raise exception 'stale write won'; end if;
end $$;

-- Lead vehicle: only owner/lead may change it, and only to a vehicle.
select pg_temp.expect_error(format($$select public.set_lead_vehicle(%L, %L)$$, (select id from t),
  (select id from public.trip_members where user_id = 'b0000000-0000-4000-8000-000000000002')), 'not_allowed');
select pg_temp.as_user(:alice);
select public.set_lead_vehicle((select id from t),
  (select id from public.trip_members where user_id = 'b0000000-0000-4000-8000-000000000002'));
select pg_temp.expect_error(format($$select public.set_lead_vehicle(%L, %L)$$, (select id from t),
  (select id from public.trip_members where user_id = 'c0000000-0000-4000-8000-000000000003')), 'not_a_vehicle_in_trip');

-- Discovery: unverified owners cannot publish; verified ones can.
select pg_temp.as_user(:bob);
create temp table bt as select * from public.create_trip('Bob trip');
grant select on bt to authenticated;
select pg_temp.expect_error(format($$select public.publish_trip(%L, 's', '{}', 1, 1, 2, 2)$$, (select id from bt)), 'not_verified');

select pg_temp.as_user(:alice);
select public.publish_trip((select id from t), 'Weekend coast convoy', '{coast,4x4}', 10, 10, 11, 11, 10);

-- Upgrade Alice so the trip has room (service role writes entitlements).
reset role;
update public.entitlements set tier = 'premium', source = 'admin' where user_id = 'a0000000-0000-4000-8000-000000000001';
set role authenticated;

-- Dave must accept terms before requesting.
select pg_temp.as_user(:dave);
do $$ begin
  if (select count(*) from public.discover_trips()) <> 1 then raise exception 'discovery count'; end if;
end $$;
-- Public listing must not leak the invite code (it bypasses mutual acceptance).
do $$ begin
  if exists (select 1 from public.trips) then raise exception 'stranger can read published trip row'; end if;
end $$;
select pg_temp.expect_error(format($$select public.request_to_join(%L, 'Dave''s bike')$$, (select id from t)), 'guidelines_not_accepted');
select pg_temp.accept_all();
create temp table jr as select * from public.request_to_join((select id from t), 'Dave''s bike', 'Happy to sweep');
grant select on jr to authenticated;
select pg_temp.expect_error(format($$select public.decide_join_request(%L, true)$$, (select id from jr)), 'not_owner');

-- Alice approves: mutual acceptance recorded, Dave becomes a member.
select pg_temp.as_user(:alice);
select public.decide_join_request((select id from jr), true);
select pg_temp.as_user(:dave);
do $$ begin
  if not exists (select 1 from public.trip_members where user_id = 'd0000000-0000-4000-8000-000000000004') then
    raise exception 'dave not a member';
  end if;
  if exists (select 1 from public.join_requests where owner_terms_version is null or requester_terms_version is null) then
    raise exception 'mutual acceptance not recorded';
  end if;
end $$;

-- Realtime channel authorisation.
select set_config('realtime.topic', 'trip:' || (select id from t), false);
insert into realtime.messages (topic, payload) values ('trip:' || (select id from t), '{}');
select pg_temp.as_user('e0000000-0000-4000-8000-00000000000f');
select pg_temp.expect_error($$insert into realtime.messages (topic, payload) values ('x', '{}')$$, 'row-level security');

\echo 'ALL RULE TESTS PASSED'
