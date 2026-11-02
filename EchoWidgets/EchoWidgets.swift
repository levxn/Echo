import ActivityKit
import SwiftUI
import WidgetKit

@main
struct EchoWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PromisesWidget()
        PromiseLiveActivity()
    }
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

/// Promises still open today: on the Home Screen and Lock Screen.
struct PromisesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EchoPromises", provider: SnapshotProvider()) { entry in
            PromisesWidgetView(snapshot: entry.snapshot)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Promises")
        .description("What you said you would do today.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

private struct PromisesWidgetView: View {
    let snapshot: WidgetSnapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            Label(snapshot.summary, systemImage: "checkmark.circle")
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("\(snapshot.openCount)").font(.title2.weight(.bold)).monospacedDigit()
                    Image(systemName: "checkmark.circle").font(.caption2)
                }
            }
            .accessibilityLabel(snapshot.summary)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label(snapshot.summary, systemImage: "checkmark.circle").font(.caption.weight(.semibold))
                if let first = snapshot.items.first {
                    Text(first.text).font(.caption2).lineLimit(2)
                    if let due = first.due { Text(due).font(.caption2).foregroundStyle(.secondary) }
                }
            }
        case .systemSmall:
            VStack(alignment: .leading, spacing: 6) {
                header
                if let first = snapshot.items.first {
                    Text(first.text).font(.footnote.weight(.medium)).lineLimit(4)
                    if let due = first.due { Text(due).font(.caption2).foregroundStyle(.secondary) }
                } else {
                    Text("Nothing to do from what you said today.").font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                header
                if snapshot.items.isEmpty {
                    Text("Nothing to do from what you said today.").font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(snapshot.items.prefix(3)) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "circle").font(.caption2).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.text).font(.footnote).lineLimit(2)
                            if let due = item.due { Text(due).font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var header: some View {
        HStack {
            Label(snapshot.summary, systemImage: "waveform").font(.caption.weight(.semibold)).foregroundStyle(.tint)
            Spacer(minLength: 0)
        }
    }
}

/// A promise coming due: on the Lock Screen and in the Dynamic Island, with a countdown to its reminder.
struct PromiseLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PromiseActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle").font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.title).font(.caption).foregroundStyle(.secondary)
                    Text(context.state.text).font(.callout.weight(.medium)).lineLimit(2)
                }
                Spacer(minLength: 0)
                Text(timerInterval: Date()...max(context.state.due, Date().addingTimeInterval(1)), countsDown: true)
                    .font(.title3.weight(.semibold)).monospacedDigit().multilineTextAlignment(.trailing).frame(maxWidth: 80)
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: "checkmark.circle").font(.title2).foregroundStyle(.tint) }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: Date()...max(context.state.due, Date().addingTimeInterval(1)), countsDown: true).monospacedDigit().frame(maxWidth: 70)
                }
                DynamicIslandExpandedRegion(.bottom) { Text(context.state.text).font(.callout).lineLimit(2) }
            } compactLeading: {
                Image(systemName: "checkmark.circle")
            } compactTrailing: {
                Text(timerInterval: Date()...max(context.state.due, Date().addingTimeInterval(1)), countsDown: true).monospacedDigit().frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "checkmark.circle")
            }
        }
    }
}
