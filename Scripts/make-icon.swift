import CoreGraphics
import Foundation
import ImageIO

// Renders the MacPulse app icon at every iconset size. All artwork is
// expressed on a 1024x1024 design grid and scaled per pixel size.

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func pulsePath(in rect: CGRect, offsetY: CGFloat, amp: CGFloat) -> CGPath {
    let midY = rect.midY + offsetY
    let x = { (fraction: CGFloat) in rect.minX + rect.width * fraction }
    let path = CGMutablePath()
    path.move(to: CGPoint(x: x(0.10), y: midY))
    path.addLine(to: CGPoint(x: x(0.29), y: midY))
    path.addCurve(
        to: CGPoint(x: x(0.37), y: midY),
        control1: CGPoint(x: x(0.32), y: midY - amp * 0.22),
        control2: CGPoint(x: x(0.34), y: midY - amp * 0.22)
    )
    path.addLine(to: CGPoint(x: x(0.44), y: midY - amp))
    path.addLine(to: CGPoint(x: x(0.52), y: midY + amp * 0.58))
    path.addLine(to: CGPoint(x: x(0.58), y: midY))
    path.addLine(to: CGPoint(x: x(0.90), y: midY))
    return path
}

func drawIcon(size: CGFloat) -> CGImage? {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil,
        width: Int(size),
        height: Int(size),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    // Work in top-left-origin coordinates.
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1)

    let s = size / 1024
    let inset = 100 * s
    let radius = 185 * s
    let rect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Background gradient.
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let background = CGGradient(
        colorsSpace: space,
        colors: [color(0x272F52), color(0x151A2E), color(0x0C0F1D)] as CFArray,
        locations: [0, 0.55, 1]
    )!
    ctx.drawLinearGradient(
        background,
        start: CGPoint(x: rect.minX, y: rect.minY),
        end: CGPoint(x: rect.maxX, y: rect.maxY),
        options: []
    )

    // Faint monitor grid.
    ctx.setLineWidth(2 * s)
    ctx.setStrokeColor(color(0xFFFFFF, 0.045))
    let gridStep = rect.height / 8
    for row in 1..<8 {
        let y = rect.minY + gridStep * CGFloat(row)
        ctx.move(to: CGPoint(x: rect.minX, y: y))
        ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
        ctx.strokePath()
    }

    // Soft highlight from the top-left corner.
    let highlight = CGGradient(
        colorsSpace: space,
        colors: [color(0xFFFFFF, 0.12), color(0xFFFFFF, 0)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawRadialGradient(
        highlight,
        startCenter: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.minY + rect.height * 0.12),
        startRadius: 0,
        endCenter: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.minY + rect.height * 0.12),
        endRadius: rect.width * 0.85,
        options: []
    )

    // Blue companion pulse, lower and fainter.
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    let companion = pulsePath(in: rect, offsetY: 96 * s, amp: 132 * s)
    ctx.setShadow(offset: .zero, blur: 34 * s, color: color(0x0A84FF, 0.85))
    ctx.setStrokeColor(color(0x0A84FF, 0.5))
    ctx.setLineWidth(14 * s)
    ctx.addPath(companion)
    ctx.strokePath()

    // Main green pulse with glow.
    let amplitude = 236 * s
    let pulse = pulsePath(in: rect, offsetY: -14 * s, amp: amplitude)
    ctx.setShadow(offset: .zero, blur: 30 * s, color: color(0x30D158, 0.95))
    ctx.setStrokeColor(color(0x5BE384))
    ctx.setLineWidth(30 * s)
    ctx.addPath(pulse)
    ctx.strokePath()

    // Glowing sensor dot on the spike tip.
    let peak = CGPoint(x: rect.minX + rect.width * 0.44, y: rect.midY - 14 * s - amplitude)
    ctx.setShadow(offset: .zero, blur: 46 * s, color: color(0x30D158, 1))
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillEllipse(in: CGRect(x: peak.x - 17 * s, y: peak.y - 17 * s, width: 34 * s, height: 34 * s))
    ctx.restoreGState()

    // Inner hairline for a crisp edge.
    ctx.addPath(squircle)
    ctx.setStrokeColor(color(0xFFFFFF, 0.10))
    ctx.setLineWidth(6 * s)
    ctx.strokePath()

    return ctx.makeImage()
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw NSError(domain: "MacPulseIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "cannot create destination \(url.lastPathComponent)"])
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "MacPulseIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "failed to write \(url.lastPathComponent)"])
    }
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    fputs("usage: make-icon.swift <iconset-dir>\n", stderr)
    exit(2)
}

let iconsetURL = URL(fileURLWithPath: arguments[1])
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let entries: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (fileName, pixels) in entries {
    guard let image = drawIcon(size: pixels) else {
        fputs("failed to render \(fileName)\n", stderr)
        exit(1)
    }
    try writePNG(image, to: iconsetURL.appendingPathComponent(fileName))
}
print("iconset written to \(iconsetURL.path)")
