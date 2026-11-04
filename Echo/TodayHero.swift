import SwiftUI

/// The top of the Today page once there is a day to show: how the day went, a few numbers that open what is behind them, and what is coming up.
struct TodayHero: View {
    let model: PipelineModel
    /// The same number as on the Promises tab below.
    let openPromises: Int
    let conversations: Int
    let onOpenPromises: () -> Void
    var onOpenTimeline: () -> Void = {}
    var onOpenMoments: () -> Void = {}
    var onOpenActions: () -> Void = {}
    /// Opens the editor for this action in the Actions tab.
    var onReview: (ActionItem) -> Void = { _ in }

    @Environment(ActionsModel.self) private var actions
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: Spacing.xl) {
            strip
            stats
            comingUp
        }
    }

    // MARK: Coming up

    /// The next few things with a date in the coming week. (Overdue ones are counted in "due today" and live in Actions.)
    private var upcoming: [ActionItem] {
        let now = actions.now(), cal = actions.calendar
        let today = cal.startOfDay(for: now)
        guard let horizon = cal.date(byAdding: .day, value: 7, to: today) else { return [] }
        return actions.pending
            .filter { item in
                guard let due = item.due, due >= today, due < horizon else { return false }
                return actions.section(of: item) != .overdue
            }
            .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
            .reduce(into: [ActionItem]()) { kept, item in   // the same thing heard twice is one line
                if !kept.contains(where: { $0.title.lowercased() == item.title.lowercased() && $0.due == item.due }) { kept.append(item) }
            }
            .prefix(3).map { $0 }
    }

    @ViewBuilder
    private var comingUp: some View {
        let items = upcoming
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    SectionHeader("Coming up", style: .overline)
                    Button(action: onOpenActions) {
                        Text("All actions").font(Font.echoMeta.weight(.semibold)).foregroundStyle(Palette.teal).frame(minHeight: 32)
                    }
                    .buttonStyle(.plain)
                }
                VStack(spacing: Spacing.sm) {
                    ForEach(items) { item in
                        Button { onReview(item) } label: { upcomingRow(item) }
                            .buttonStyle(EchoPressStyle())
                    }
                }
            }
        }
    }

    private func upcomingRow(_ item: ActionItem) -> some View {
        let due = item.due ?? actions.now()
        return HStack(spacing: Spacing.md) {
            // A little calendar leaf: the weekday over the day number.
            VStack(spacing: 0) {
                Text(due.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.rose)
                Text(due.formatted(.dateTime.day()))
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)
                    .monospacedDigit()
            }
            .frame(width: 46, height: 46)
            .background(Palette.fillStrong, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text([ActionFormat.when(item, now: actions.now()), item.person].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: item.kind.symbol).font(.caption.weight(.semibold)).foregroundStyle(Palette.textTertiary).accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .echoRow(horizontal: Spacing.md, vertical: Spacing.sm)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens it to review")
    }

    // MARK: How the day went

    @ViewBuilder
    private var strip: some View {
        let chunks = model.todayChunks.filter { $0.status != .dropped }
        if !chunks.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                SectionHeader("Today's listening", style: .overline)
                DayActivityChart(chunks: chunks, groups: [], compact: true) { _ in }
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onOpenMoments)
                    .accessibilityHint("Opens Moments")
            }
        }
    }

    // MARK: Numbers

    private var dueToday: Int {
        actions.groups(.all).filter { $0.section == .overdue || $0.section == .today }.reduce(0) { $0 + $1.items.count }
    }

    private var stats: some View {
        let columns = typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible(), spacing: Spacing.sm), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: Spacing.sm) {
            stat(dueToday, dueToday == 1 ? "due today" : "due today", symbol: "clock.badge.exclamationmark", tint: Palette.amber, action: onOpenActions, hint: "Opens Actions")
            stat(conversations, conversations == 1 ? "conversation" : "conversations", symbol: "bubble.left.and.bubble.right.fill", tint: Palette.violet,
                 action: onOpenTimeline, hint: "Opens the timeline")
            stat(openPromises, openPromises == 1 ? "promise" : "promises", symbol: "checkmark.circle.fill", tint: Palette.teal, action: onOpenPromises, hint: "Opens your promises")
            stat(model.todayChunks.filter { $0.status == .stored }.count, "moments", symbol: "waveform", tint: Palette.blue, action: onOpenMoments, hint: "Opens Moments")
        }
    }

    private func stat(_ value: Int, _ label: String, symbol: String, tint: Color, action: @escaping () -> Void, hint: String) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.16), in: Circle())
                    .accessibilityHidden(true)
                Text("\(value)")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.textPrimary)
                    .contentTransition(.numericText())
                Text(label)
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .padding(.horizontal, Spacing.md)
            .background(Palette.fill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(EchoPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label)")
        .accessibilityHint(hint)
    }
}
