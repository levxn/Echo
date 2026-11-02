import SwiftUI
import WidgetKit

@main
struct EchoWatchWidgetsBundle: WidgetBundle {
    var body: some Widget { PromisesComplication() }
}

private struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

private struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: Date(), snapshot: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: context.isPreview ? .sample : WidgetSnapshot.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date()
        completion(Timeline(entries: [SnapshotEntry(date: now, snapshot: WidgetSnapshot.load())], policy: .after(now.addingTimeInterval(30 * 60))))
    }
}

/// The watch face complication: how many promises are open, and the next one.
struct PromisesComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EchoPromisesWatch", provider: SnapshotProvider()) { entry in
            ComplicationView(snapshot: entry.snapshot)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Promises")
        .description("What you said you would do today.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

private struct ComplicationView: View {
    let snapshot: WidgetSnapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            Label(snapshot.summary, systemImage: "checkmark.circle")
        case .accessoryCorner:
            Text("\(snapshot.openCount)").font(.title3.weight(.bold)).widgetLabel(snapshot.summary)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label(snapshot.summary, systemImage: "waveform").font(.caption.weight(.semibold))
                if let first = snapshot.items.first {
                    Text(first.text).font(.caption2).lineLimit(2)
                } else {
                    Text("All clear").font(.caption2).foregroundStyle(.secondary)
                }
            }
        default:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("\(snapshot.openCount)").font(.title3.weight(.bold)).monospacedDigit()
                    Image(systemName: "checkmark.circle").font(.caption2)
                }
            }
            .accessibilityLabel(snapshot.summary)
        }
    }
}
