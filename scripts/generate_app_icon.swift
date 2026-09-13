#!/usr/bin/env swift
//
// Generates Sources/Ports/Resources/AppIcon.icns for the Ports app.
//
// Draws an anchor glyph on a rounded-rectangle background entirely from
// vector primitives, at each required pixel size, then packs the renders
// into an .iconset and shells out to `iconutil` to produce the .icns.
//
// Run with: swift scripts/generate_app_icon.swift

import AppKit

// MARK: - Palette

let bgTop = NSColor(srgbRed: 0.043, green: 0.118, blue: 0.176, alpha: 1)    // #0B1E2D deep navy
let bgBottom = NSColor(srgbRed: 0.078, green: 0.208, blue: 0.271, alpha: 1) // #143545 teal-navy
let glyphColor = NSColor(srgbRed: 0.949, green: 0.933, blue: 0.902, alpha: 1) // #F2EEE6 off-white

// MARK: - Shapes

/// macOS-style continuous rounded rect ("squircle-like") background shape.
func squirclePath(in rect: CGRect) -> NSBezierPath {
    let radius = rect.width * 0.2237
    return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

/// Anchor glyph, built from filled primitives (ring, stock, shank) plus one
/// thick stroked curve for the crown and flukes. The stock bar and the two
/// flukes give the silhouette strong horizontal mass at the top and bottom,
/// so no height band is dominated by a single thin vertical stroke -- that
/// was the failure mode of an earlier bollard design, which read as a
/// generic post/phallic shape once downsampled.
///
/// `compact` switches to a version tuned for tiny renders: no ring hole, a
/// thinner shank, and a wider fluke stance, all of which widen the notch
/// between shank and flukes. At 16-32px that notch is only a pixel or two
/// wide to begin with, and the detailed proportions below fill it in,
/// blurring the whole glyph into a featureless blob.
/// Defined directly in `rect`'s coordinate space via a unit-square mapping.
func anchorPaths(in rect: CGRect, compact: Bool) -> (filled: [NSBezierPath], stroked: [NSBezierPath]) {
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
    }

    var filled: [NSBezierPath] = []

    // Ring, at the top. A solid disc when compact; an annulus once there's
    // enough resolution for the hole to read instead of just filling in.
    let ringCenter = p(0.5, 0.885)
    let ringOuterRadius = rect.width * 0.16
    let ring = NSBezierPath()
    ring.appendOval(in: CGRect(x: ringCenter.x - ringOuterRadius, y: ringCenter.y - ringOuterRadius,
                                width: ringOuterRadius * 2, height: ringOuterRadius * 2))
    if !compact {
        let ringInnerRadius = ringOuterRadius * 0.52
        ring.appendOval(in: CGRect(x: ringCenter.x - ringInnerRadius, y: ringCenter.y - ringInnerRadius,
                                    width: ringInnerRadius * 2, height: ringInnerRadius * 2))
        ring.windingRule = .evenOdd
    }
    filled.append(ring)

    // Stock: the wide crossbar in the upper third.
    let stockRect = CGRect(x: rect.minX + rect.width * 0.16, y: rect.minY + rect.height * 0.655,
                            width: rect.width * 0.68, height: rect.height * 0.115)
    filled.append(NSBezierPath(roundedRect: stockRect, xRadius: stockRect.height / 2, yRadius: stockRect.height / 2))

    // Shank: connects the stock down to the crown. Thinner when compact, to
    // leave more room either side for the notch against the flukes.
    let shankWidthFraction: CGFloat = compact ? 0.11 : 0.14
    let shankRect = CGRect(x: rect.minX + rect.width * (0.5 - shankWidthFraction / 2), y: rect.minY + rect.height * 0.20,
                            width: rect.width * shankWidthFraction, height: rect.height * 0.50)
    filled.append(NSBezierPath(rect: shankRect))

    // Crown + flukes: one thick stroked curve sweeping from the left fluke
    // tip down through the crown and up to the right fluke tip. Round caps
    // give blunt, chunky tips instead of thin points. Wider stance when
    // compact opens up the shank/fluke notch for legibility at tiny sizes.
    let tipX: CGFloat = compact ? 0.08 : 0.15
    let waistX: CGFloat = compact ? 0.20 : 0.24
    let flukes = NSBezierPath()
    flukes.move(to: p(tipX, 0.50))
    flukes.curve(to: p(waistX, 0.24), controlPoint1: p(tipX, 0.35), controlPoint2: p(tipX + 0.02, 0.27))
    flukes.curve(to: p(0.50, 0.15), controlPoint1: p(waistX + 0.07, 0.21), controlPoint2: p(0.41, 0.15))
    flukes.curve(to: p(1 - waistX, 0.24), controlPoint1: p(0.59, 0.15), controlPoint2: p(1 - waistX - 0.07, 0.21))
    flukes.curve(to: p(1 - tipX, 0.50), controlPoint1: p(1 - tipX - 0.02, 0.27), controlPoint2: p(1 - tipX, 0.35))
    flukes.lineWidth = rect.width * (compact ? 0.145 : 0.155)
    flukes.lineCapStyle = .round
    flukes.lineJoinStyle = .round

    return (filled, [flukes])
}

// MARK: - Rendering

func renderIcon(size: Int) -> NSBitmapImageRep {
    let s = CGFloat(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Could not allocate bitmap for size \(size)")
    }
    rep.size = NSSize(width: s, height: s)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("Could not create graphics context for size \(size)")
    }
    NSGraphicsContext.current = ctx
    ctx.cgContext.clear(CGRect(x: 0, y: 0, width: s, height: s))
    ctx.cgContext.setShouldAntialias(true)

    // Background: rounded rect occupying the ~80% icon safe area.
    let margin = s * 0.10
    let squircleRect = CGRect(x: margin, y: margin, width: s - margin * 2, height: s - margin * 2)
    let squircle = squirclePath(in: squircleRect)

    ctx.cgContext.saveGState()
    squircle.addClip()
    NSGradient(starting: bgTop, ending: bgBottom)!.draw(in: squircleRect, angle: 90)
    ctx.cgContext.restoreGState()

    // Glyph: anchor, centered in the safe area with breathing room.
    let glyphWidth = squircleRect.width * 0.70
    let glyphHeight = squircleRect.height * 0.78
    let glyphRect = CGRect(
        x: squircleRect.midX - glyphWidth / 2,
        y: squircleRect.midY - glyphHeight / 2,
        width: glyphWidth,
        height: glyphHeight
    )
    let (filled, stroked) = anchorPaths(in: glyphRect, compact: size < 64)
    glyphColor.setFill()
    for path in filled {
        path.fill()
    }
    for path in stroked {
        glyphColor.setStroke()
        path.stroke()
    }

    ctx.flushGraphics()
    return rep
}

// MARK: - Iconset assembly

let specs: [(name: String, size: Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

let fm = FileManager.default
let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let projectRoot = scriptDir.deletingLastPathComponent()
let resourcesDir = projectRoot.appendingPathComponent("Sources/Ports/Resources")
let workDir = fm.temporaryDirectory.appendingPathComponent("PortsAppIconGen-\(UUID().uuidString)")
let iconsetDir = workDir.appendingPathComponent("AppIcon.iconset")

try fm.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

var cache: [Int: NSBitmapImageRep] = [:]
for spec in specs {
    let rep = cache[spec.size] ?? renderIcon(size: spec.size)
    cache[spec.size] = rep
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to encode PNG for \(spec.name)")
    }
    try data.write(to: iconsetDir.appendingPathComponent("\(spec.name).png"))
}

// Standalone previews for visual QA at the two legibility extremes, written
// outside the iconset so they survive its cleanup.
for previewSize in [16, 1024] {
    let rep = cache[previewSize]!
    let data = rep.representation(using: .png, properties: [:])!
    try data.write(to: URL(fileURLWithPath: "/tmp/AppIcon-preview-\(previewSize).png"))
}

let icnsURL = resourcesDir.appendingPathComponent("AppIcon.icns")
try? fm.removeItem(at: icnsURL)

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsURL.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    fatalError("iconutil failed with status \(process.terminationStatus)")
}

try? fm.removeItem(at: workDir)

print("Wrote \(icnsURL.path)")
print("Previews: /tmp/AppIcon-preview-16.png /tmp/AppIcon-preview-1024.png")
