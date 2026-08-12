# Spine

A vertical, snap-scrolling feed of books. Five ideas per book. Read, listen, or
(soon) watch.

This is the Flutter application, migrated from the React prototype. The
prototype's UX and visual identity are the source of truth: the same palette,
the same three typefaces, the same signature bookmark ribbon down the left edge,
the same Read / Listen / Watch card. What changed is everything underneath —
real audio, a content system, configurable ads, persistence, and Android/iOS
build configuration.

---

## Running it

Requires Flutter 3.22 or newer (developed on 3.35.4).

```bash
flutter pub get
flutter run
```

**Android emulator or device**

```bash
flutter devices                 # confirm the device is attached
flutter run -d <device-id>      # debug
flutter run -d <device-id> --release
```

Android Studio's SDK, an emulator image, and USB debugging on a physical device
are the only prerequisites. `flutter doctor` will name anything missing.

**If Gradle can't find a JDK**, point it at one in your *personal* Gradle
properties — never in `android/gradle.properties`, which is committed and has to
work on every machine that clones the repo:

```properties
# ~/.gradle/gradle.properties
# Windows: %USERPROFILE%\.gradle\gradle.properties
org.gradle.java.home=C:/Users/you/.jdks/ms-17.0.20
```

The same rule covers any other machine-local setting (cache locations, proxy
hosts, memory tuning for your box).

**iOS simulator or device** (macOS only)

```bash
cd ios && pod install && cd ..   # first run only
open ios/Runner.xcworkspace      # set your signing team under Signing & Capabilities
flutter run -d <device-id>
```

A physical device needs a development team selected in Xcode; the simulator
does not.

**Tests**

```bash
flutter test        # 40 tests: catalogue, feed composition, playback, persistence, UI
flutter analyze
```

---

## How it's put together

```
lib/
  main.dart                  bootstrap: orientation, audio session, storage
  app.dart                   composition root — every dependency is built and injected here
  core/
    config/                  AppConfig, AdConfig (both --dart-define driven)
    theme/                   palette, type scale, ThemeData
  data/
    models/                  Book, Idea, WatchTrack, BookProgress, SessionState, FeedItem
    repository/              BookRepository + the bundled-asset implementation
  services/
    ads/                     FeedComposer, AdProvider, placeholder creatives
    audio/                   the audio contract and its two implementations
    persistence/             ProgressStore + SharedPreferences implementation
  state/                     LibraryController, ProgressController, PlaybackController, ShellController
  ui/
    screens/                 shell, shelf (the feed), search, saved, profile
    feed/                    ribbon, cover, mode toggle, the three mode panels, ad card
    widgets/                 shared pieces
```

State is `ChangeNotifier` + `provider` — enough for an app this size and no
codegen. Each controller owns one concern, and the UI subscribes narrowly:
a card rebuilds when *that book's* progress changes, and only the ribbon and
the transport follow the playhead.

---

## Content

Books live in `assets/content/books.json` — currently 25 books, 125 ideas.
Nothing about the catalogue is hard-coded in a widget: the feed doesn't know how
many books exist, so 25 → 50 → 500 is a data change.

```jsonc
{
  "id": "atomic-habits",
  "title": "Atomic Habits",
  "author": "James Clear",
  "genre": "Self-Improvement",
  "durationLabel": "14 MIN",
  "spine": "brass",                    // palette name or #RRGGBB
  "cover": null,                       // optional "asset:…" or "https://…"
  "watch": { "available": false },     // fill in videoUrl to switch Watch on
  "ideas": [
    {
      "id": "atomic-habits-1",
      "title": "Identity Over Outcome",
      "body": "…",
      "seconds": 11,
      "audio": "asset:assets/audio/atomic-habits/01.wav"   // optional
    }
  ]
}
```

**Adding a book.** Append an entry and run `flutter test test/catalogue_test.dart`
— it enforces what the app assumes:

- exactly five ideas per book (the ribbon is drawn from that number)
- unique book and idea ids
- title, author, genre, duration label and idea bodies all present
- `spine` is a palette name (`brass`, `teal`, `brick`, `indigo`, `olive`) or a
  hex value
- no two neighbouring books share a spine colour — consecutive cards in the same
  colour make the feed look stuck when you swipe, so ordering is part of editing
- any `asset:` audio reference actually exists in the bundle

One editorial constraint that isn't machine-checkable: the five ideas must be
original distillations written in Spine's voice, not passages lifted from the
book. That's what keeps a catalogue of this shape publishable at any size.

Point the app at a different manifest without touching code:

```bash
flutter run --dart-define=SPINE_CONTENT=assets/content/staging.json
```

Moving the catalogue to a backend means writing one more `BookRepository`
implementation and swapping it in `app.dart`. No screen changes.

---

## Audio

`SpineAudioPlayer` is the contract. Two implementations satisfy it:

- **`JustAudioPlayer`** — real playback via just_audio (ExoPlayer on Android,
  AVPlayer on iOS). Handles bundled assets, cached files, and remote URLs.
- **`SimulatedAudioPlayer`** — a silent, correctly-timed playhead used for ideas
  that have no narration recorded yet.

`SpineAudioEngine` picks between them per track and republishes both as one
stream, so nothing above it knows which is playing. Play/pause, a draggable
progress bar, real durations, automatic advance to the next idea, and resume
where you stopped all work identically either way.

**Narration in this build is placeholder audio.** *Atomic Habits* ships five
generated WAV files (a soft chime, silence, a closing chime, at the exact
declared duration) so the whole path — load, buffer, progress, completion,
auto-advance — can be exercised on a device. The other four books have no
`audio` field and fall back to the timed playhead, which the transport labels
`PREVIEW`. Dropping real narration at the same paths, or adding `audio` fields
to the other books, needs no code change.

Regenerate the placeholders after editing durations:

```bash
python3 tool/generate_placeholder_audio.py
```

Cloud-hosted narration is already accounted for: set
`--dart-define=SPINE_CONTENT_BASE_URL=https://…`, use relative or absolute URLs
in the `audio` field, and `AudioSourceResolver` caches downloads on device.
AI voice generation is deliberately not built.

Audio stops when you swipe to another card, leave the Shelf tab, or background
the app — a voice never follows the reader off the page. (Consequently there is
no iOS background-audio entitlement; add `UIBackgroundModes: audio` and a
background service if that changes.)

---

## Watch

Still the Coming Soon card, with Notify Me — the preference persists per book.
The data model is ready for real video: set `watch.available` to `true` and give
it a `videoUrl`, and the lock disappears from the mode toggle. No
video-generation pipeline is included.

---

## Ads

Ad cadence is configuration, not code. `FeedComposer` interleaves ad cards into
the book list:

```
Book Book Book Ad Book Book Book Ad …
```

`AdConfig` controls it:

| Field | Default | Meaning |
|---|---|---|
| `enabled` | `true` | master switch |
| `frequency` | `4` | insert an ad after every N books |
| `leadIn` | `4` | books shown before the first ad is allowed |
| `maxAdsPerSession` | `null` | optional ceiling |

```bash
flutter run --dart-define=SPINE_AD_FREQUENCY=3 --dart-define=SPINE_ADS=false
```

The feed renders `FeedItem`s, never books directly, so changing the cadence — or
turning ads off entirely — never touches the scrolling architecture. The feed
also never opens or ends on an ad.

For MVP, `PlaceholderAdProvider` serves clearly-marked **TEST AD** creatives, so
the app is fully testable with no advertising account. Swapping in Google Mobile
Ads means one new `AdProvider` implementation: `initialize()` becomes
`MobileAds.instance.initialize()`, `creativeFor` returns a loaded native ad, and
the impression/click hooks forward to the SDK.

---

## What's remembered

Locally, via `SharedPreferences` behind a `ProgressStore` interface (one record
per book, so a move to Firebase/Supabase is a per-record copy):

- current idea, per book
- Read / Listen / Watch mode, per book
- saved books
- playback position, so Listen resumes where it stopped
- ideas completed (this drives the ribbon and the profile figures)
- Notify Me preference
- which card the reader left the feed on
- day streak

---

## Release builds

**Android**

Create `android/key.properties` (git-ignored) pointing at your upload keystore:

```properties
storePassword=…
keyPassword=…
keyAlias=upload
storeFile=/absolute/path/to/upload-keystore.jks
```

Generate one with:

```bash
keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA \
  -keysize 2048 -validity 10000 -alias upload
```

Then:

```bash
flutter build appbundle --release   # build/app/outputs/bundle/release/app-release.aab → Play
flutter build apk --release         # build/app/outputs/flutter-apk/app-release.apk → sideload
flutter build apk --split-per-abi --release
```

Without `key.properties` the release build falls back to debug keys so
`flutter run --release` works on a fresh clone — such a build **cannot** be
uploaded to Play.

**iOS** (macOS + Xcode)

```bash
flutter build ipa --release
```

Then upload `build/ios/ipa/*.ipa` with Transporter, or open
`build/ios/archive/Runner.xcarchive` in Xcode and distribute from there. Signing
is configured in Xcode under Runner → Signing & Capabilities.

**Store submission checklist**

- Bundle/application id is `com.spineapp.spine` — change it in
  `android/app/build.gradle.kts` and Xcode before your first upload if you want
  a different one.
- Version comes from `pubspec.yaml` (`0.1.0+1` → name `0.1.0`, code `1`); bump
  it for every upload.
- Replace the placeholder launcher icon and splash: edit
  `tool/generate_branding.py` or drop your own artwork in `assets/branding/`,
  then `dart run flutter_launcher_icons && dart run flutter_native_splash:create`.
- Screenshots, description, and a privacy policy are required by both stores.
  Spine collects nothing and has no accounts, which makes the privacy
  declarations short — but they still have to be filled in.
- If you ship real ads, both stores require the advertising-identifier
  declaration, and iOS requires an `NSUserTrackingUsageDescription` string if
  you request tracking permission.

Nothing here publishes automatically; no store credentials are configured.

---

## Notes on this build

- `flutter analyze` is clean and all 35 tests pass.
- The Android and iOS build configuration is complete, but neither store binary
  was compiled in the environment this migration was done in: the Android SDK
  download host is blocked there, and iOS builds need macOS. Run
  `flutter build apk` / `flutter build ipa` locally — the first Gradle or
  CocoaPods run will fetch its own dependencies.
- Narration and ad creatives are placeholders, as described above. Both are
  labelled in the UI so a test build can never be mistaken for the real thing.
