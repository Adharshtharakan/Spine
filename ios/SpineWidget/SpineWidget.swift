import SwiftUI
import WidgetKit

/// Today's idea on the iOS home screen.
///
/// The widget reads what the app wrote into the shared App Group container; it
/// never computes a pick itself, so the phone and the widget can't disagree
/// about what today's idea is.
private let appGroupId = "group.com.spineapp.spine"

struct SpineEntry: TimelineEntry {
    let date: Date
    let title: String
    let body: String
    let source: String

    static let placeholder = SpineEntry(
        date: Date(),
        title: "Open Spine",
        body: "Today's idea will appear here.",
        source: ""
    )
}

struct SpineProvider: TimelineProvider {
    func placeholder(in context: Context) -> SpineEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (SpineEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SpineEntry>) -> Void) {
        // One entry, refreshed after midnight: the pick only changes by day, and
        // the app rewrites it on every launch anyway.
        let entry = readEntry()
        let midnight = Calendar.current.startOfDay(for: Date().addingTimeInterval(86_400))
        completion(Timeline(entries: [entry], policy: .after(midnight)))
    }

    private func readEntry() -> SpineEntry {
        let defaults = UserDefaults(suiteName: appGroupId)

        guard let title = defaults?.string(forKey: "idea_title") else {
            return .placeholder
        }

        return SpineEntry(
            date: Date(),
            title: title,
            body: defaults?.string(forKey: "idea_body") ?? "",
            source: (defaults?.string(forKey: "idea_source") ?? "").uppercased()
        )
    }
}

struct SpineWidgetView: View {
    var entry: SpineEntry

    // Spine's palette. Kept in step with lib/core/theme/spine_colors.dart by
    // hand — SwiftUI cannot read the Dart tokens.
    private let ink = Color(red: 0.051, green: 0.047, blue: 0.035)
    private let parchment = Color(red: 0.945, green: 0.914, blue: 0.839)
    private let brass = Color(red: 0.788, green: 0.635, blue: 0.153)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TODAY")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .kerning(1.6)
                .foregroundColor(brass)

            Text(entry.title)
                .font(.system(size: 17, weight: .semibold, design: .serif))
                .foregroundColor(parchment)
                .lineLimit(2)

            Text(entry.body)
                .font(.system(size: 13))
                .foregroundColor(parchment.opacity(0.7))
                .lineLimit(4)

            Spacer(minLength: 0)

            if !entry.source.isEmpty {
                Text(entry.source)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .kerning(1.2)
                    .foregroundColor(parchment.opacity(0.4))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .background(ink)
    }
}

@main
struct SpineWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SpineWidget", provider: SpineProvider()) { entry in
            if #available(iOS 17.0, *) {
                SpineWidgetView(entry: entry)
                    .containerBackground(for: .widget) { Color.black }
            } else {
                SpineWidgetView(entry: entry)
            }
        }
        .configurationDisplayName("Spine · the day's idea")
        .description("One idea from your library, on the home screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
