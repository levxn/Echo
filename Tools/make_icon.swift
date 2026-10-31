// Draws the Echo app icon (aurora gradient + waveform) as 1024 px PNGs.
// Run:  swiftc -O Tools/make_icon.swift -o /tmp/make_icon && /tmp/make_icon <output_dir>
import AppKit
import CoreGraphics

let size = 1024
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [r, g, b, a])!
}

func blob(_ ctx: CGContext, center: CGPoint, radius: CGFloat, color c: CGColor) {
    let space = CGColorSpaceCreateDeviceRGB()
    let clear = c.copy(alpha: 0)!
    let gradient = CGGradient(colorsSpace: space, colors: [c, clear] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

/// variant: "any", "dark" or "tinted" (grayscale, for the system to tint).
func render(_ variant: String) -> Data {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let s = CGFloat(size)
    let tinted = variant == "tinted"
    let dim: CGFloat = variant == "dark" ? 0.7 : 1

    ctx.setFillColor(tinted ? color(0.04, 0.04, 0.05) : color(0.027, 0.035, 0.078))
    ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))

    if tinted {
        blob(ctx, center: CGPoint(x: s * 0.25, y: s * 0.2), radius: s * 0.8, color: color(0.45, 0.45, 0.47, 0.55))
        blob(ctx, center: CGPoint(x: s * 0.85, y: s * 0.85), radius: s * 0.7, color: color(0.3, 0.3, 0.32, 0.5))
    } else {
        blob(ctx, center: CGPoint(x: s * 0.22, y: s * 0.18), radius: s * 0.85, color: color(0.10, 0.80, 0.72, 0.62 * dim))   // teal
        blob(ctx, center: CGPoint(x: s * 0.88, y: s * 0.88), radius: s * 0.80, color: color(0.55, 0.36, 0.96, 0.62 * dim))   // violet
        blob(ctx, center: CGPoint(x: s * 0.62, y: s * 0.30), radius: s * 0.55, color: color(0.30, 0.50, 1.0, 0.45 * dim))    // blue
    }

    // Waveform: seven rounded bars, tallest in the middle.
    let heights: [CGFloat] = [0.16, 0.30, 0.50, 0.66, 0.46, 0.28, 0.15].map { $0 * s }
    let barWidth = s * 0.065, gap = s * 0.040
    let total = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
    var x = (s - total) / 2
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s * 0.05, color: tinted ? color(1, 1, 1, 0.5) : color(0.2, 0.9, 0.8, 0.85))
    ctx.setFillColor(color(1, 1, 1, 0.97))
    for h in heights {
        let rect = CGRect(x: x, y: (s - h) / 2, width: barWidth, height: h)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
        ctx.fillPath()
        x += barWidth + gap
    }
    ctx.restoreGState()

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

for variant in ["any", "dark", "tinted"] {
    try! render(variant).write(to: URL(fileURLWithPath: "\(outDir)/icon_\(variant).png"))
}
print("wrote icons to \(outDir)")
