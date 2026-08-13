# The iOS home-screen widget

`SpineWidget.swift` is complete, but a WidgetKit extension is an **Xcode
target**, and targets live inside `Runner.xcodeproj/project.pbxproj`. That file
cannot be edited safely by hand, so the target has to be added once through
Xcode. It takes about five minutes; everything after that is automatic.

Android needs none of this — its widget is already wired up and will work on the
next build.

## Adding the target

1. Open `ios/Runner.xcworkspace` in Xcode.
2. **File → New → Target… → Widget Extension.**
   - Product Name: `SpineWidget`
   - Uncheck *Include Configuration Intent* and *Include Live Activity*.
   - When Xcode offers to activate the new scheme, accept.
3. Xcode generates a `SpineWidget` group with template files. Delete the
   generated `SpineWidget.swift` **and** `SpineWidgetBundle.swift` if present,
   then drag `ios/SpineWidget/SpineWidget.swift` (this file's neighbour) in,
   with *Copy items if needed* unchecked and target membership set to
   `SpineWidget` only.
4. Add the App Group to **both** targets — this is the shared container the app
   writes to and the widget reads from, and the widget stays blank without it:
   - Select the `Runner` target → *Signing & Capabilities* → **+ Capability** →
     *App Groups* → add `group.com.spineapp.spine`.
   - Repeat for the `SpineWidget` target.
5. Set the `SpineWidget` deployment target to iOS 14.0 or later.
6. Build and run `Runner`. Long-press the home screen → **+** → Spine.

## If you change the bundle identifier

The App Group id is referenced in three places and all three must match:

- `ios/SpineWidget/SpineWidget.swift` — `appGroupId`
- `lib/services/widgets/home_widget_publisher.dart` — `appGroupId`
- The App Groups capability on both Xcode targets

## What the widget shows

Whatever the app last wrote: today's idea title, its opening, and the book it
came from. The app republishes on every launch, and the widget's own timeline
refreshes after midnight. There is no background work and no network — if the
app hasn't been opened yet, the widget invites the reader to open it.
