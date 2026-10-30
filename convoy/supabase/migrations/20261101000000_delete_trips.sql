-- The organiser can delete a trip. Everything belonging to it (members,
-- stops, chat, positions, events, checklists, join requests) goes with it
-- through the existing ON DELETE CASCADE keys. Other members leave instead
-- (policy "leave trip" on trip_members).
create policy "owner deletes trip" on public.trips for delete to authenticated
  using (owner_id = auth.uid());
grant delete on public.trips to authenticated;
