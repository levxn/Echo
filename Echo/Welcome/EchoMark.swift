import SwiftUI

/// A band that follows an ellipse (half-axes `a` and `b`) and changes thickness along it. With `b` at 0 it is a flat streak.
struct OrbitBand: Shape {
    var a: CGFloat
    var b: CGFloat
    var thetaRange: ClosedRange<Double> = 0...(2 * .pi)
    var width: (Double) -> CGFloat

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let steps = 140
        var outer: [CGPoint] = [], inner: [CGPoint] = []
        for k in 0...steps {
            let theta = thetaRange.lowerBound + (thetaRange.upperBound - thetaRange.lowerBound) * Double(k) / Double(steps)
            let p = CGPoint(x: a * CGFloat(cos(theta)), y: b * CGFloat(sin(theta)))
            var n = CGPoint(x: b * CGFloat(cos(theta)), y: a * CGFloat(sin(theta)))     // the ellipse's outward direction
            let length = hypot(n.x, n.y)
            n = length < 0.0001 ? CGPoint(x: 0, y: 1) : CGPoint(x: n.x / length, y: n.y / length)
            let half = width(theta) / 2
            outer.append(CGPoint(x: c.x + p.x + n.x * half, y: c.y + p.y + n.y * half))
            inner.append(CGPoint(x: c.x + p.x - n.x * half, y: c.y + p.y - n.y * half))
        }
        // One connected outline: out along the outer edge, back along the inner edge. (Two `addLines` calls would be two
        // separate shapes, each closed with a straight chord.)
        var path = Path()
        guard let first = outer.first else { return path }
        path.move(to: first)
        for point in outer.dropFirst() { path.addLine(to: point) }
        for point in inner.reversed() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }
}

/// The Echo logo: uneven sound bars inside a glossy orbit tilted 45 degrees. The orbit is a hairline behind the bars and swells into a
/// bright, thick sweep where it passes in front of them. `frame` says how it looks right now, so the same view is the finished
/// logo, the idling one and every moment of the launch animation.
struct EchoLogo: View {
    var height: CGFloat = 120
    var frame: LaunchFrame = LaunchChoreography.idle(at: 0)

    private var barWidth: CGFloat { height * LogoGeometry.barWidth }
    private var gap: CGFloat { height * LogoGeometry.gap }

    private var gradient: AngularGradient {
        AngularGradient(colors: [Palette.teal, .white, Palette.violet, Palette.teal], center: .center, angle: .degrees(360 * frame.shine))
    }

    /// The glint: a point on the front of the orbit that travels once round each cycle.
    private func glintOffset(a: CGFloat, b: CGFloat) -> CGSize {
        let theta = Double.pi * frame.shine
        let x = Double(a) * cos(theta), y = Double(b) * sin(theta)
        let r = frame.ringDegrees * .pi / 180
        return CGSize(width: x * cos(r) - y * sin(r), height: x * sin(r) + y * cos(r))
    }

    var body: some View {
        let box = height * 2.1
        let a = height * frame.ringHalfWidth, b = height * LogoGeometry.ringB * frame.ringOpen
        let glintStrength = frame.ringOpen > 0.9 ? sin(.pi * frame.shine) : 0
        func band(range: ClosedRange<Double> = 0...(2 * .pi), _ w: @escaping (Double) -> Double) -> some View {
            OrbitBand(a: a, b: b, thetaRange: range) { CGFloat(w($0)) * height }
                .fill(gradient)
                .frame(width: box, height: box)
                .rotationEffect(.degrees(frame.ringDegrees))
        }
        return ZStack {
            // The whole orbit, dim, behind the bars.
            band { LogoGeometry.width(at: $0) }
                .opacity(0.5 * frame.ringOpacity)
            HStack(spacing: gap) {
                ForEach(frame.levels.indices, id: \.self) { i in
                    Capsule()
                        .fill(LinearGradient(colors: [.white, Color(red: 0.80, green: 0.97, blue: 0.96)], startPoint: .top, endPoint: .bottom))
                        .frame(width: barWidth, height: max(barWidth, height * frame.levels[i]))
                }
            }
            .shadow(color: Palette.teal.opacity(0.75 * frame.glow), radius: height * 0.09)
            // The bright front of the orbit, across the bars, thinning into the back at both ends.
            band(range: 0...Double.pi) { LogoGeometry.frontWidth(at: $0) }
                .shadow(color: Palette.teal.opacity(0.8 * frame.glow), radius: height * 0.06)
                .opacity(frame.ringOpacity)
            // A thin white highlight down the middle of the front gives it a polished, glassy look.
            OrbitBand(a: a, b: b, thetaRange: 0.25...(Double.pi - 0.25)) { CGFloat(LogoGeometry.frontWidth(at: $0)) * height * 0.22 }
                .fill(.white.opacity(0.9))
                .frame(width: box, height: box)
                .rotationEffect(.degrees(frame.ringDegrees))
                .opacity(frame.ringOpacity * frame.ringOpen)
            Circle()
                .fill(.white)
                .frame(width: height * 0.07, height: height * 0.07)
                .blur(radius: height * 0.012)
                .shadow(color: .white, radius: height * 0.05)
                .offset(glintOffset(a: a, b: b))
                .opacity(glintStrength * frame.ringOpacity)
        }
        .frame(width: box, height: box)
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
                AuroraBackground(calm: true, fps: 15)
                RadialGradient(colors: [Palette.teal.opacity(0.55), .clear], center: .center, startRadius: 0, endRadius: 260)
                    .scaleEffect(1 + 1.6 * frame.bloom)
                    .opacity(frame.bloom)
                EchoLogo(height: 96, frame: frame)
                    .scaleEffect(frame.logoScale)
                    .opacity(frame.logoOpacity)
            }
            .overlay(alignment: .bottom) {
                // The name, in the same capitals as the header, low on the screen. It goes with the logo as the app opens.
                Text("ECHO")
                    .font(.custom("AvenirNext-DemiBold", size: 26, relativeTo: .title2))
                    .tracking(9)
                    .padding(.leading, 9)
                    .foregroundStyle(.white)
                    .opacity(frame.logoOpacity)
                    .padding(.bottom, 96)
                    .accessibilityHidden(true)
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
