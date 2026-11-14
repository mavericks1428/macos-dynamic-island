import Cocoa

guard CommandLine.arguments.count > 1 else {
    fputs("Usage: generate_icon.swift <output.iconset>\n", stderr)
    exit(1)
}

let outDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let specs: [(name: String, px: Int)] = [
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

func renderIcon(pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        return nil
    }
    rep.size = NSSize(width: pixels, height: pixels)

    guard let nsCtx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx
    defer { NSGraphicsContext.restoreGraphicsState() }

    let cg = nsCtx.cgContext
    let s = CGFloat(pixels)
    let scale = s / 1024.0

    cg.setAllowsAntialiasing(true)
    cg.setShouldAntialias(true)
    cg.interpolationQuality = .high

    // macOS Big Sur / Monterey squircle bounds (standard 100px inset on 1024 canvas)
    let pad = 100.0 * scale
    let tileRect = CGRect(x: pad, y: pad, width: s - pad * 2.0, height: s - pad * 2.0)
    let tileRadius = 186.0 * scale
    let tilePath = CGPath(roundedRect: tileRect, cornerWidth: tileRadius, cornerHeight: tileRadius, transform: nil)

    // Subtle drop shadow under tile
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -18.0 * scale), blur: 32.0 * scale, color: NSColor(calibratedWhite: 0, alpha: 0.42).cgColor)
    cg.addPath(tilePath)
    cg.setFillColor(NSColor(srgbRed: 0.08, green: 0.09, blue: 0.14, alpha: 1.0).cgColor)
    cg.fillPath()
    cg.restoreGState()

    // Clip to squircle for internal background + ambient glow
    cg.saveGState()
    cg.addPath(tilePath)
    cg.clip()

    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let bgColors = [
        NSColor(srgbRed: 0.14, green: 0.16, blue: 0.25, alpha: 1.0).cgColor,
        NSColor(srgbRed: 0.06, green: 0.07, blue: 0.12, alpha: 1.0).cgColor
    ] as CFArray
    if let grad = CGGradient(colorsSpace: cs, colors: bgColors, locations: [0.0, 1.0]) {
        cg.drawLinearGradient(
            grad,
            start: CGPoint(x: s * 0.5, y: tileRect.maxY),
            end: CGPoint(x: s * 0.5, y: tileRect.minY),
            options: []
        )
    }

    // Soft cyan-violet ambient glow behind Dynamic Island capsule
    let glowColors = [
        NSColor(srgbRed: 0.28, green: 0.72, blue: 1.0, alpha: 0.34).cgColor,
        NSColor(srgbRed: 0.54, green: 0.34, blue: 1.0, alpha: 0.14).cgColor,
        NSColor(srgbRed: 0.0, green: 0.0, blue: 0.0, alpha: 0.0).cgColor
    ] as CFArray
    if let glow = CGGradient(colorsSpace: cs, colors: glowColors, locations: [0.0, 0.5, 1.0]) {
        cg.drawRadialGradient(
            glow,
            startCenter: CGPoint(x: s * 0.5, y: s * 0.5),
            startRadius: 0,
            endCenter: CGPoint(x: s * 0.5, y: s * 0.5),
            endRadius: 360.0 * scale,
            options: []
        )
    }
    cg.restoreGState()

    // Subtle specular glass border on squircle
    cg.saveGState()
    cg.addPath(tilePath)
    cg.setLineWidth(max(1.0, 6.0 * scale))
    cg.setStrokeColor(NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.18).cgColor)
    cg.strokePath()
    cg.restoreGState()

    // Centered Dynamic Island Pill
    let pillW = 620.0 * scale
    let pillH = 220.0 * scale
    let pillRect = CGRect(
        x: (s - pillW) * 0.5,
        y: (s - pillH) * 0.5,
        width: pillW,
        height: pillH
    )
    let pillPath = CGPath(roundedRect: pillRect, cornerWidth: pillH * 0.5, cornerHeight: pillH * 0.5, transform: nil)

    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -10.0 * scale), blur: 26.0 * scale, color: NSColor(calibratedWhite: 0, alpha: 0.55).cgColor)
    cg.addPath(pillPath)
    cg.setFillColor(NSColor(srgbRed: 0.02, green: 0.02, blue: 0.04, alpha: 1.0).cgColor)
    cg.fillPath()
    cg.restoreGState()

    cg.saveGState()
    cg.addPath(pillPath)
    cg.setLineWidth(max(1.0, 4.5 * scale))
    cg.setStrokeColor(NSColor(srgbRed: 0.45, green: 0.80, blue: 1.0, alpha: 0.45).cgColor)
    cg.strokePath()
    cg.restoreGState()

    // Left mini album/orb badge inside the pill
    let orbSize = 112.0 * scale
    let orbRect = CGRect(
        x: pillRect.minX + 54.0 * scale,
        y: pillRect.midY - orbSize * 0.5,
        width: orbSize,
        height: orbSize
    )
    let orbRadius = 28.0 * scale
    let orbPath = CGPath(roundedRect: orbRect, cornerWidth: orbRadius, cornerHeight: orbRadius, transform: nil)
    cg.saveGState()
    cg.addPath(orbPath)
    cg.clip()
    let orbColors = [
        NSColor(srgbRed: 0.25, green: 0.80, blue: 1.0, alpha: 1.0).cgColor,
        NSColor(srgbRed: 0.58, green: 0.36, blue: 1.0, alpha: 1.0).cgColor
    ] as CFArray
    if let orbGrad = CGGradient(colorsSpace: cs, colors: orbColors, locations: [0.0, 1.0]) {
        cg.drawLinearGradient(
            orbGrad,
            start: CGPoint(x: orbRect.minX, y: orbRect.maxY),
            end: CGPoint(x: orbRect.maxX, y: orbRect.minY),
            options: []
        )
    }
    cg.restoreGState()

    // Center subtle title bars inside pill
    let titleW = 164.0 * scale
    let titleH = 22.0 * scale
    let titleRect = CGRect(
        x: orbRect.maxX + 34.0 * scale,
        y: pillRect.midY + 12.0 * scale,
        width: titleW,
        height: titleH
    )
    let subRect = CGRect(
        x: orbRect.maxX + 34.0 * scale,
        y: pillRect.midY - 26.0 * scale,
        width: 112.0 * scale,
        height: 16.0 * scale
    )
    cg.setFillColor(NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.90).cgColor)
    cg.addPath(CGPath(roundedRect: titleRect, cornerWidth: titleH * 0.5, cornerHeight: titleH * 0.5, transform: nil))
    cg.fillPath()
    cg.setFillColor(NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.40).cgColor)
    cg.addPath(CGPath(roundedRect: subRect, cornerWidth: 8.0 * scale, cornerHeight: 8.0 * scale, transform: nil))
    cg.fillPath()

    // Right 5-bar waveform spectrum inside pill
    let barHeights: [CGFloat] = [44, 92, 114, 72, 48]
    let barW = 16.0 * scale
    let barGap = 14.0 * scale
    let totalBarsW = CGFloat(barHeights.count) * barW + CGFloat(barHeights.count - 1) * barGap
    let barsStartX = pillRect.maxX - 56.0 * scale - totalBarsW
    for (idx, h) in barHeights.enumerated() {
        let bh = h * scale
        let bx = barsStartX + CGFloat(idx) * (barW + barGap)
        let by = pillRect.midY - bh * 0.5
        let barRect = CGRect(x: bx, y: by, width: barW, height: bh)
        let barPath = CGPath(roundedRect: barRect, cornerWidth: barW * 0.5, cornerHeight: barW * 0.5, transform: nil)
        cg.saveGState()
        cg.addPath(barPath)
        cg.clip()
        if let orbGrad = CGGradient(colorsSpace: cs, colors: orbColors, locations: [0.0, 1.0]) {
            cg.drawLinearGradient(
                orbGrad,
                start: CGPoint(x: barRect.midX, y: barRect.maxY),
                end: CGPoint(x: barRect.midX, y: barRect.minY),
                options: []
            )
        }
        cg.restoreGState()
    }

    return rep.representation(using: .png, properties: [:])
}

for spec in specs {
    guard let pngData = renderIcon(pixels: spec.px) else {
        fputs("Failed rendering \(spec.name)\n", stderr)
        exit(1)
    }
    try pngData.write(to: outDir.appendingPathComponent(spec.name))
}
print("Generated iconset in \(outDir.path)")
