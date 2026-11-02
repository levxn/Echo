import SwiftUI

/// The Echo logo: uneven sound bars inside a shiny ring tilted 45 degrees, its back half behind the bars and its front half in front.
/// `frame` says how it looks right now, so the same view is the finished logo, the idling one and every moment of the launch animation.
struct EchoLogo: View {
    var height: CGFloat = 120
    var frame: LaunchFrame = LaunchChoreography.idle(at: 0)

    private var barWidth: CGFloat { height * LogoGeometry.barWidth }
    private var gap: CGFloat { height * LogoGeometry.gap }

    private var gradient: AngularGradient {
        AngularGradient(colors: [Palette.teal, .white, Palette.violet, Palette.teal], center: .center, angle: .degrees(360 * frame.shine))
    }

    private func arc(from: CGFloat, to: CGFloat, width: CGFloat, size: CGSize) -> some View {
        Ellipse()
            .trim(from: from, to: to)
            .stroke(gradient, style: StrokeStyle(lineWidth: width, lineCap: .butt))
            .frame(width: size.width, height: size.height)
            .rotationEffect(.degrees(frame.ringDegrees))
    }

    /// The glint: a point on the front half of the ring that travels once round each cycle.
    private func glintOffset(a: CGFloat, b: CGFloat) -> CGSize {
        let theta = Double.pi * frame.shine
        let x = Double(a) * cos(theta), y = Double(b) * sin(theta)
        let r = frame.ringDegrees * .pi / 180
        return CGSize(width: x * cos(r) - y * sin(r), height: x * sin(r) + y * cos(r))
    }

    var body: some View {
        let a = height * frame.ringHalfWidth, b = height * LogoGeometry.ringB * frame.ringOpen
        let size = CGSize(width: max(1, 2 * a), height: max(0.5, 2 * b))
        let stroke = height * LogoGeometry.ringWidth
        let glintStrength = frame.ringOpen > 0.9 ? sin(.pi * frame.shine) : 0
        ZStack {
            arc(from: 0.5, to: 1, width: stroke * 0.8, size: size)          // the back of the ring, behind the bars
                .opacity(0.45 * frame.ringOpacity)
            HStack(spacing: gap) {
                ForEach(frame.levels.indices, id: \.self) { i in
                    Capsule()
                        .fill(LinearGradient(colors: [.white, Color(red: 0.80, green: 0.97, blue: 0.96)], startPoint: .top, endPoint: .bottom))
                        .frame(width: barWidth, height: max(barWidth, height * frame.levels[i]))
                }
            }
            .shadow(color: Palette.teal.opacity(0.75 * frame.glow), radius: height * 0.09)
            arc(from: 0, to: 0.5, width: stroke, size: size)                 // the front of the ring, across the bars
                .shadow(color: Palette.teal.opacity(0.8 * frame.glow), radius: height * 0.06)
                .opacity(frame.ringOpacity)
            Circle()
                .fill(.white)
                .frame(width: height * 0.07, height: height * 0.07)
                .blur(radius: height * 0.012)
                .shadow(color: .white, radius: height * 0.05)
                .offset(glintOffset(a: a, b: b))
                .opacity(glintStrength * frame.ringOpacity)
        }
        .frame(width: height * 2.1, height: height * 2.1)
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

/// The launch animation: a line becomes bars that play like live audio, falls back to a line, opens into a ring around the bars, and a ring of light
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
                EchoLogo(height: 96, frame: frame)
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
