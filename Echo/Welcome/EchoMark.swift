import SwiftUI

/// A four-point star with concave sides: the "AI" sparkle.
struct SparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let k = r * 0.17
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - r))
        p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + k, y: c.y - k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + k, y: c.y + k))
        p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - k, y: c.y + k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - k, y: c.y - k))
        p.closeSubpath()
        return p
    }
}

/// The Echo logo: uneven sound bars with a sparkle riding the tallest. `frame` says how it looks right now (bar heights,
/// sparkle size), so the same view is the finished logo, the idling one and every moment of the launch animation.
struct EchoLogo: View {
    var height: CGFloat = 120
    var frame: LaunchFrame = LaunchChoreography.idle(at: 0)

    private var barWidth: CGFloat { height * LogoGeometry.barWidth }
    private var gap: CGFloat { height * LogoGeometry.gap }
    private var rowWidth: CGFloat { CGFloat(frame.levels.count) * barWidth + CGFloat(frame.levels.count - 1) * gap }
    /// Where the tallest bar is, measured from the middle of the row.
    private var peakX: CGFloat { CGFloat(LogoGeometry.peak) * (barWidth + gap) + barWidth / 2 - rowWidth / 2 }

    var body: some View {
        let sparkle = height * LogoGeometry.sparkleRadius * 2
        let star = height * LogoGeometry.starRadius * 2
        ZStack {
            HStack(spacing: gap) {
                ForEach(frame.levels.indices, id: \.self) { i in
                    Capsule()
                        .fill(LinearGradient(colors: [.white, Color(red: 0.80, green: 0.97, blue: 0.96)], startPoint: .top, endPoint: .bottom))
                        .frame(width: barWidth, height: max(barWidth, height * frame.levels[i]))
                }
            }
            .shadow(color: Palette.teal.opacity(0.75 * frame.glow), radius: height * 0.09)

            SparkleShape()
                .fill(.white)
                .frame(width: sparkle, height: sparkle)
                .shadow(color: Palette.teal.opacity(0.9), radius: height * 0.08)
                .rotationEffect(.degrees(frame.sparkleDegrees))
                .scaleEffect(max(0.0001, frame.sparkleScale))
                .opacity(frame.sparkleScale > 0.001 ? 1 : 0)
                .offset(x: peakX, y: -(height / 2 + height * LogoGeometry.sparkleLift))

            SparkleShape()
                .fill(Palette.teal.opacity(0.95))
                .frame(width: star, height: star)
                .shadow(color: Palette.teal.opacity(0.8), radius: height * 0.04)
                .scaleEffect(max(0.0001, frame.starScale))
                .opacity(frame.starScale > 0.001 ? 1 : 0)
                .offset(x: peakX + height * 0.30, y: -(height / 2 + height * 0.40))
        }
        .frame(width: rowWidth + height * 0.7, height: height * 1.6)
        .accessibilityHidden(true)
    }
}

/// The logo with a gentle idle motion (the welcome screen). Still when Reduce Motion is on.
struct IdleLogo: View {
    var height: CGFloat = 108
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            EchoLogo(height: height, frame: reduceMotion ? LaunchChoreography.reducedFrame(at: 0) : LaunchChoreography.idle(at: context.date.timeIntervalSinceReferenceDate))
        }
    }
}

/// The launch animation: the logo plays like live audio, freezes onto its shape, the sparkle springs in, and a ring of light
/// opens onto the app. A tap jumps to the opening. It draws `LaunchChoreography` and nothing else.
struct LaunchMark: View {
    @Binding var visible: Bool
    @State private var start = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `-launch-mark-freeze T` draws the single moment T (screenshots).
    private let frozen: Double? = {
        let args = ProcessInfo.processInfo.arguments
        return args.firstIndex(of: "-launch-mark-freeze").flatMap { $0 + 1 < args.count ? Double(args[$0 + 1]) : nil }
    }()

    private var total: Double { reduceMotion ? LaunchChoreography.reducedTotal : LaunchChoreography.total }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(paused: frozen != nil)) { context in
                let t = frozen ?? context.date.timeIntervalSince(start)
                layer(frame: reduceMotion ? LaunchChoreography.reducedFrame(at: t) : LaunchChoreography.frame(at: t), size: geo.size)
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { skip() }
        .task {
            guard frozen == nil else { return }
            while !Task.isCancelled {
                if Date().timeIntervalSince(start) >= total { visible = false; return }
                try? await Task.sleep(for: .milliseconds(40))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Echo")
    }

    private func layer(frame: LaunchFrame, size: CGSize) -> some View {
        let reach = hypot(size.width, size.height)
        return ZStack {
            // The screen the logo sits on. The app shows through a circle that grows from the logo's centre.
            ZStack {
                Palette.background
                AuroraBackground(calm: true)
                RadialGradient(colors: [Palette.teal.opacity(0.55), .clear], center: .center, startRadius: 0, endRadius: 260)
                    .scaleEffect(1 + 1.6 * frame.bloom)
                    .opacity(frame.bloom)
                EchoLogo(height: 108, frame: frame)
                    .scaleEffect(frame.logoScale)
                    .opacity(frame.logoOpacity)
            }
            .mask {
                Rectangle()
                    .overlay { Circle().frame(width: reach * frame.reveal, height: reach * frame.reveal).blendMode(.destinationOut) }
                    .compositingGroup()
            }
            // The ring of light at the edge of the opening.
            Circle()
                .strokeBorder(AngularGradient(colors: [.white, Palette.teal, Palette.blue, .white], center: .center), lineWidth: 5)
                .frame(width: reach * frame.reveal, height: reach * frame.reveal)
                .blur(radius: 1.5)
                .shadow(color: Palette.teal.opacity(0.8), radius: 14)
                .opacity(frame.reveal > 0.001 && frame.reveal < 0.999 ? 0.9 * (1 - frame.reveal) + 0.1 : 0)
        }
    }

    /// Jumps to the opening, so skipping still ends the way the animation does.
    private func skip() {
        let elapsed = Date().timeIntervalSince(start)
        if !reduceMotion, elapsed < LaunchChoreography.openStart { start = Date().addingTimeInterval(-LaunchChoreography.openStart) }
    }
}
