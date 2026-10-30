-- Lets the app read display names alongside members, messages and join
-- requests in one query (PostgREST embeds `profiles` through these keys).
-- The existing keys to auth.users stay; these add a path to public.profiles,
-- which every user has (created at sign-up by handle_new_user).

-- Backfill any user who somehow has no profile row, so the keys validate.
insert into public.profiles (id, display_name)
select u.id, coalesce(nullif(left(trim(u.raw_user_meta_data ->> 'display_name'), 60), ''), 'Traveller')
from auth.users u
where not exists (select 1 from public.profiles p where p.id = u.id)
on conflict (id) do nothing;

alter table public.trip_members
  add constraint trip_members_user_profile_fkey foreign key (user_id) references public.profiles (id) on delete cascade;
alter table public.messages
  add constraint messages_sender_profile_fkey foreign key (sender_id) references public.profiles (id) on delete cascade;
alter table public.join_requests
  add constraint join_requests_requester_profile_fkey foreign key (requester_id) references public.profiles (id) on delete cascade;

-- Make the API see the new relationships straight away.
notify pgrst, 'reload schema';
