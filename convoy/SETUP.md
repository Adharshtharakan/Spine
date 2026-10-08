# Setting up Convoy and running it from Android Studio

This takes you from an empty PC to the app running on your phone. Steps 1–4
are all you need for a first run; everything after that is optional and can
be done later.

| What | Needed for | Cost |
|---|---|---|
| Flutter SDK + Android Studio | building the app | free |
| Supabase project | sign-in, trips, chat, live sync | free tier |
| Map | nothing to set up: OpenFreeMap is used until you self-host | free |
| Cloudflare Worker | Discover, Stops, road routes, subscriptions | free tier |
| Cloudflare R2 + PMTiles | your own basemap (optional) | ~free, needs a card on file |

---

## 1. Tools on your PC

You already have Android Studio. Android Studio does **not** include
Flutter, so install that too.

1. **Flutter SDK**
   - Download the Windows zip from <https://docs.flutter.dev/get-started/install/windows/mobile>.
   - Extract it to `C:\src\flutter`. Don't use `C:\Program Files`: spaces
     and permissions in that path break builds.
   - Add `C:\src\flutter\bin` to your **Path**: Start → "Edit the system
     environment variables" → Environment Variables → *Path* → New.
   - Open a **new** terminal and run `flutter --version`.
2. **Android Studio plugins**: File → Settings → Plugins → Marketplace → install
   **Flutter** (it also installs Dart) → restart.
3. **Android SDK pieces**: File → Settings → Languages & Frameworks → Android SDK.
   - *SDK Platforms*: tick the newest Android version.
   - *SDK Tools*: tick **Android SDK Command-line Tools**, **Android SDK
     Build-Tools** and **Android SDK Platform-Tools** → Apply.
4. In a terminal:
   ```
   flutter doctor --android-licenses     (answer y to each)
   flutter doctor
   ```
   Everything under *Android toolchain* and *Android Studio* should be ✓.
   Windows/Chrome/Visual Studio warnings don't matter for this app.
5. **Git** (<https://git-scm.com/download/win>), then:
   ```
   git clone https://github.com/angith-anmesrisha/drivesync.git
   ```
   The repo is private, so Git will ask you to sign in to GitHub; a
   browser window opens.
6. **Node.js 22 LTS** (<https://nodejs.org>). You only need it for step 5.

---

## 2. Supabase (backend)

1. Go to <https://supabase.com> → sign in with GitHub → **New project**.
   - Name `convoy`, pick the region closest to your users (e.g. *Mumbai*),
     and save the database password somewhere safe.
2. **Create the database.** Open **SQL Editor** → *New query*. For each file
   below, in this order, paste the whole file and press **Run**. Each should
   say "Success. No rows returned".
   1. `supabase/migrations/20261008000000_convoy_core.sql`
   2. `supabase/migrations/20261009000000_offgrid_relay.sql`
   3. `supabase/seed.sql` (the community guidelines and driver terms)
3. **Email sign-in with a code.** The app asks for a 6-digit code, but
   Supabase's default emails contain a link instead.
   - **Authentication → Emails → Templates**. Edit both **Confirm signup**
     and **Magic Link** so the body includes the code:
     ```html
     <h2>Your Convoy code</h2>
     <p>Enter this code in the app: <strong>{{ .Token }}</strong></p>
     ```
   - The built-in email sender allows only a few emails per hour. That's
     fine for testing; for real users add your own SMTP under
     **Authentication → Emails → SMTP** (e.g. Resend or Brevo, both have
     free tiers).
4. **Phone verification.** Only needed to *publish* public trips, so you
   can skip it for now. When you want it: **Authentication → Sign In / Providers →
   Phone** → enable, connect an SMS provider (Twilio, MessageBird, Vonage or
   Textlocal), and add a test number with a fixed code (e.g. `919999999999` →
   `123456`) so you don't pay for test SMS.
5. **Copy your keys** (Project Settings → **API Keys**):
   - **Project URL**, e.g. `https://abcdefghijk.supabase.co` (also shown
     under Project Settings → Data API)
   - **anon / publishable key**: this goes into the app; it is safe to ship
   - **service_role / secret key**: this is used **only** by the Worker.
     Never put it in the app or commit it.
6. **Give yourself Premium for testing.** Free allows 2 vehicles per trip.
   After you've signed in once from the app, run in the SQL Editor:
   ```sql
   update public.entitlements set tier = 'premium', source = 'admin'
   where user_id = (select id from auth.users where email = 'you@example.com');
   ```

---

## 3. Configure the app

In the cloned repo, open the `app` folder and copy `env.example.json` to
`env.json` (same folder). Fill in:

```json
{
  "SUPABASE_URL": "https://abcdefghijk.supabase.co",
  "SUPABASE_ANON_KEY": "your anon / publishable key",
  "EDGE_BASE_URL": "",
  "SELF_HOSTED_TILES": "false",
  "TURN_URL": "",
  "TURN_USERNAME": "",
  "TURN_CREDENTIAL": ""
}
```

`env.json` is git-ignored, so your keys stay on your PC. With
`EDGE_BASE_URL` empty, the map uses OpenFreeMap and everything except
Discover, Stops, road-following routes and purchases works.

---

## 4. Run it from Android Studio

1. **File → Open** → select the **`app`** folder (not the repo root) → Trust project.
2. Open the built-in terminal (View → Tool Windows → Terminal) and run:
   ```
   flutter pub get
   ```
3. **Pass the config to the app.** Run → **Edit Configurations…** → select
   **main.dart** (create it if it's missing: **+** → Flutter → Dart entrypoint
   `lib/main.dart`) → **Additional run args**:
   ```
   --dart-define-from-file=env.json
   ```
   → OK.
4. **Pick a device.**
   - **Real phone (recommended).** GPS, Bluetooth and the mesh need real
     hardware. On the phone: Settings → About phone → tap **Build number**
     7 times → Developer options → enable **USB debugging**. Plug in, accept
     the prompt, and the phone appears in the device dropdown.
   - **Emulator.** Device Manager → **+** → Pixel 8 → choose a system image
     with the **Google Play** logo (Nearby Connections needs Play services).
     To fake driving: emulator **⋯ → Location → Routes**, set two points,
     and press **Play route**.
5. Press **Run ▶**. The first build downloads Gradle and dependencies and can
   take 5–15 minutes. Later builds are much faster.
6. **Try it out**
   1. Sign in with your email and type the 6-digit code.
   2. Accept the guidelines and the three driver statements.
   3. **New convoy**, then on the map **long-press** to add stops (start,
      rest stop, destination). Tap **Plan** to set times.
   4. On a second phone (or the emulator), sign in with another email,
      choose **Join with code**, and enter the invite code shown in the
      Convoy tab.
   5. Watch both cars on the map, chat, and hold the mic button to talk.

If something fails, see **Troubleshooting** at the end.

---

## 5. Cloudflare Worker (Discover, Stops, road routes, purchases)

1. Create a free account at <https://dash.cloudflare.com/sign-up>.
2. In a terminal, from the repo root:
   ```
   cd edge
   npm ci
   npx wrangler login                          (opens the browser)
   npx wrangler kv namespace create CACHE
   ```
   Copy the printed `id` into `edge/wrangler.toml` under `[[kv_namespaces]]`.
3. In `edge/wrangler.toml`, set `SUPABASE_URL` and `SUPABASE_ANON_KEY` to the
   same values as in `env.json`.
4. Add the secrets. Each command prompts you to paste a value:
   ```
   npx wrangler secret put SUPABASE_SERVICE_ROLE_KEY     (the service_role / secret key)
   npx wrangler secret put AFFILIATE_SIGNING_KEY         (any long random string)
   ```
   To generate a random string, run this in PowerShell:
   `[Convert]::ToBase64String((1..32 | % {Get-Random -Max 256}))`.
5. **JWT setting.** In Supabase go to Project Settings → **JWT Keys**.
   - If the current key is the **Legacy JWT secret (HS256)**, also run
     `npx wrangler secret put SUPABASE_JWT_SECRET` and paste that secret.
   - If it uses the newer signing keys (ECC/RSA), skip this; the Worker reads
     the public keys automatically.
6. Deploy:
   ```
   npx wrangler deploy
   ```
   It prints a URL like `https://convoy-edge.<your-subdomain>.workers.dev`.
   Open `<that URL>/health` and you should see `{"ok":true}`.
7. Put that URL in `app/env.json` as `EDGE_BASE_URL` and run the app again.
   Discover, Stops (hotels, campsites, fuel, rest areas along the route) and
   road-following prediction now work.

Road routes use the public OSRM demo server by default, which is fine while
developing. Before launch, self-host OSRM (Docker, one region's OSM extract)
and set `OSRM_URL` in `wrangler.toml`.

---

## 6. Your own map tiles (optional, later)

OpenFreeMap is free and needs no key, so you can launch on it. To host your
own Protomaps basemap instead:

1. Cloudflare dashboard → **R2** → enable it (asks for a card; the first
   10 GB are free and there are no egress fees) → create a bucket named
   `convoy-tiles`.
2. Install the `pmtiles` CLI (<https://github.com/protomaps/go-pmtiles/releases>).
   Then run the script from **Git Bash** or WSL:
   ```
   cd tiles
   ./build_region.sh india 68.1,6.5,97.4,35.7 14
   ```
3. Uncomment the `[[r2_buckets]]` block in `edge/wrangler.toml` and run
   `npx wrangler deploy`.
4. In `env.json` set `"SELF_HOSTED_TILES": "true"`.

---

## 7. Subscriptions, affiliates and radios (before launch)

- **Google Play billing.**
  1. Play Console → create the app → Monetize → Subscriptions → create
     `convoy_premium_monthly` and `convoy_premium_yearly`.
  2. Create a Google Cloud service account with access to the Play Developer
     API, invite it in Play Console (Users and permissions), and store its
     JSON key with `npx wrangler secret put GOOGLE_SERVICE_ACCOUNT_JSON`.
  3. Set `ANDROID_PACKAGE_NAME` (default `app.convoy.convoy`; change it to
     your own before publishing).
  4. Purchases only work for builds installed from a Play testing track.
- **Real-time renewal updates.** Create a Pub/Sub topic, point Play's
  Real-time developer notifications at it, and add a push subscription to
  `<worker URL>/billing/google/rtdn`.
- **Affiliates.** Join Booking.com Affiliate Partner and/or Hipcamp's
  programme, then
  `npx wrangler secret put BOOKING_AFFILIATE_ID` / `HIPCAMP_AFFILIATE_ID`.
  Ask partners to send conversions to `<worker URL>/affiliates/postback`,
  signed with your `AFFILIATE_SIGNING_KEY`.
- **Sponsored stops.** Insert rows into `public.sponsored_placements` from the
  Supabase table editor.
- **LoRa radios.** Buy one Meshtastic-compatible node per car (Heltec V3,
  RAK WisBlock or LilyGO T-Echo).
  1. Flash Meshtastic from <https://flasher.meshtastic.org>.
  2. In the Meshtastic app, set **Region** to your country's band (India:
     `IN`, 865 MHz) and keep the default primary channel.
  3. In Convoy: menu → **Convoy radio** → Find radios nearby → Pair.
  An external car antenna makes a big difference to range.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| "Convoy is not configured" | The run args are missing: add `--dart-define-from-file=env.json` (step 4.3), and check `env.json` is inside `app/`. |
| The email contains a link, not a code | Edit the email templates (step 2.3). |
| "Please accept the current guidelines…" right after accepting | `seed.sql` wasn't run (step 2.2). |
| Map is grey or blank | The phone has no internet on first launch, or `MAP_STYLE_URL` / `SELF_HOSTED_TILES` points at a Worker without tiles. |
| Discover/Stops say "needs the Convoy Worker" | Set `EDGE_BASE_URL` (step 5). |
| Third car can't join | The free plan allows 2 vehicles; give the organiser Premium (step 2.6). |
| `flutter doctor` says the Android license status is unknown | Run `flutter doctor --android-licenses`. |
| Gradle build error | Copy the **first** red error from the Build window and send it over. The native mesh code (Kotlin/Swift) hasn't been compiled on a real machine yet, so the first build may surface a small fix. |
| Can't see other cars | Both phones need location permission set to "Allow all the time". Check that Realtime is enabled in Supabase (it is by default). |
