import SwiftUI

/// How the little equalizer moves. Pure, so it can be tested: a bar's height (0.3...1) at a moment.
nonisolated enum WaveLevels {
    private static let speeds: [Double] = [5.1, 7.4, 6.2, 8.3, 5.7, 7.0, 6.6]
    private static let offsets: [Double] = [0.0, 1.7, 3.1, 0.9, 2.4, 4.0, 1.2]

    static func level(_ i: Int, at t: Double) -> Double {
        let k = i % speeds.count
        return 0.3 + 0.7 * (0.5 + 0.5 * sin(speeds[k] * t + offsets[k]))
    }

    /// What a still equalizer looks like (Reduce Motion, or nothing playing).
    static func resting(_ i: Int) -> Double { [0.45, 0.8, 0.6, 1.0, 0.55, 0.75, 0.5][i % 7] }
}

/// A few bars that bounce like live audio. Used while Echo is thinking and while a moment's audio plays.
struct WaveBars: View {
    var count = 4
    var height: CGFloat = 16
    var tint: Color = Palette.teal
    var active = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || !active)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: height * 0.13) {
                ForEach(0..<count, id: \.self) { i in
                    Capsule()
                        .fill(tint)
                        .frame(width: height * 0.17, height: height * (reduceMotion || !active ? WaveLevels.resting(i) : WaveLevels.level(i, at: t)))
                }
            }
            .frame(height: height)
        }
        .accessibilityHidden(true)
    }
}

/// A soft highlight that sweeps across a placeholder while something is on its way.
struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.overlay {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    GeometryReader { geo in
                        let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                        LinearGradient(colors: [.clear, .white.opacity(0.22), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.6)
                            .offset(x: -geo.size.width * 0.6 + (geo.size.width * 1.6) * phase)
                    }
                }
                .mask(content)
                .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    func shimmer() -> some View { modifier(Shimmer()) }

    /// Fades the trailing edge of a horizontal scroller, so a chip cut off by the screen edge reads as "there is more".
    func trailingFade(_ length: CGFloat = 0.1) -> some View {
        mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 1 - length), .init(color: .clear, location: 1)],
                            startPoint: .leading, endPoint: .trailing))
    }
}

/// Grey placeholder lines that say "an answer is coming" instead of leaving a bare spinner.
struct SkeletonLines: View {
    var widths: [CGFloat] = [1, 0.92, 0.6]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(widths.indices, id: \.self) { i in
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Palette.fillStrong)
                        .frame(width: geo.size.width * widths[i])
                }
                .frame(height: 12)
            }
        }
        .shimmer()
        .accessibilityHidden(true)
    }
}

/// When each word of an answer appears, as it is revealed word by word. Pure, so it can be tested.
nonisolated struct RevealSchedule: Equatable {
    let words: Int
    /// The answer never takes longer than this to appear in full, however long it is.
    static let maxTotal = 1.8
    static let fade = 0.28
    static let idealPerWord = 0.05

    var perWord: Double { words <= 1 ? 0 : min(Self.idealPerWord, (Self.maxTotal - Self.fade) / Double(words - 1)) }
    var duration: Double { words == 0 ? 0 : Double(words - 1) * perWord + Self.fade }

    /// 0...1: how visible word `i` is at time `t` since the reveal began.
    func opacity(ofWord i: Int, at t: Double) -> Double { min(1, max(0, (t - Double(i) * perWord) / Self.fade)) }
}

/// Answers that have already been revealed once this launch, so coming back to the Ask tab doesn't replay them.
@MainActor
enum RevealMemory {
    private static var seen: Set<Int> = []
    static func hasSeen(_ text: String) -> Bool { seen.contains(text.hashValue) }
    static func markSeen(_ text: String) { seen.insert(text.hashValue) }
}

/// Text that appears word by word, each word fading in as it arrives. Every word takes its space from the start, so nothing shifts.
struct RevealingText: View {
    let text: String
    var font: Font = .echoAnswer
    var color: Color = Palette.textPrimary

    @State private var start = Date()
    @State private var finished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var words: [String] { text.split(separator: " ", omittingEmptySubsequences: false).map(String.init) }

    var body: some View {
        Group {
            if reduceMotion || finished || RevealMemory.hasSeen(text) {
                Text(text).font(font).foregroundStyle(color)
            } else {
                let schedule = RevealSchedule(words: words.count)
                TimelineView(.animation(minimumInterval: 1.0 / 60)) { context in
                    let t = context.date.timeIntervalSince(start)
                    words.enumerated().reduce(Text("")) { partial, item in
                        partial + Text(item.offset == words.count - 1 ? item.element : item.element + " ")
                            .foregroundStyle(color.opacity(schedule.opacity(ofWord: item.offset, at: t)))
                    }
                    .font(font)
                }
                .task {
                    try? await Task.sleep(for: .seconds(schedule.duration + 0.1))
                    RevealMemory.markSeen(text)
                    finished = true
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}
