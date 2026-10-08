-- Version 1 of the documents every traveller accepts. Publishing a new
-- version (same kind, version + 1) forces re-acceptance before anyone can
-- create, join or approve a trip.
insert into public.guideline_documents (kind, version, title, body) values
('platform_guidelines', 1, 'Convoy community guidelines', $$
1. Safety first. Never type, read chat or handle the phone while the vehicle is moving. Use push-to-talk and quick messages only when it is safe, or let a passenger operate the app.
2. Respect the party. Location, chat and voice are visible only to members of your trip. Do not record, screenshot or share another member's location or voice outside the trip.
3. Honest listings. Public trips must describe the real route, dates, pace and requirements. No commercial transport for hire through Convoy.
4. Mutual consent. A traveller joins a public trip only when they have requested it and the organiser has accepted them. Either side may leave or remove a member at any time.
5. No harassment, discrimination or unlawful activity. Reports are reviewed and accounts may be suspended.
6. Follow the law. Traffic law and the instructions of authorities always override the itinerary or the lead vehicle.
$$),
('driver_terms', 1, 'Driver terms', $$
By accepting you confirm, for every trip you drive in:
- you hold a valid licence for the vehicle you drive (attestation: licensed);
- the vehicle is insured as required where you travel (attestation: insured);
- the vehicle is roadworthy and fit for the planned route (attestation: roadworthy).
You remain solely responsible for how you drive. Following the lead vehicle never requires you to break traffic law, exceed safe speeds or drive tired. Convoy provides coordination tools only and is not a transport provider.
$$)
on conflict (kind, version) do nothing;
