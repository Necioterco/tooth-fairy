#!/usr/bin/env swift
//
// Generates Tooth Fairy's app icon at every size macOS needs and writes the
// AppIcon.appiconset under Moonlit/Assets.xcassets. Run from the project
// root:
//
//     swift scripts/generate-icon.swift
//
// Re-run any time you tweak the design.
//

import AppKit
import Foundation

let outputRoot = "Moonlit/Assets.xcassets"
let iconsetDir = "\(outputRoot)/AppIcon.appiconset"

let fm = FileManager.default
try? fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let topContents = """
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""
try? topContents.write(toFile: "\(outputRoot)/Contents.json", atomically: true, encoding: .utf8)

let sizes: [Int] = [16, 32, 64, 128, 256, 512, 1024]

/// Draws a four-point sparkle/star centred on (cx, cy) with the given radius.
/// Two perpendicular tapered diamonds — the classic "fairy magic" sparkle.
func drawSparkle(at center: NSPoint, radius: CGFloat, color: NSColor) {
    color.setFill()
    let waist: CGFloat = radius * 0.18

    // Vertical diamond (top-bottom long axis).
    let v = NSBezierPath()
    v.move(to: NSPoint(x: center.x, y: center.y + radius))
    v.line(to: NSPoint(x: center.x + waist, y: center.y))
    v.line(to: NSPoint(x: center.x, y: center.y - radius))
    v.line(to: NSPoint(x: center.x - waist, y: center.y))
    v.close()
    v.fill()

    // Horizontal diamond.
    let h = NSBezierPath()
    h.move(to: NSPoint(x: center.x + radius, y: center.y))
    h.line(to: NSPoint(x: center.x + waist, y: center.y - waist))
    h.line(to: NSPoint(x: center.x - radius, y: center.y))
    h.line(to: NSPoint(x: center.x - waist, y: center.y + waist))
    h.close()
    h.fill()
}

func renderIcon(pixelSize: Int) -> Data? {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    let s = CGFloat(pixelSize)
    let rect = NSRect(x: 0, y: 0, width: s, height: s)

    // ── Background: rounded square with pink → purple gradient ──────────
    let cornerRadius = s * 0.22
    let bgPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)

    let topColor = NSColor(red: 0.98, green: 0.62, blue: 0.86, alpha: 1.0)    // soft pink
    let bottomColor = NSColor(red: 0.62, green: 0.36, blue: 0.94, alpha: 1.0) // lavender purple
    let gradient = NSGradient(starting: topColor, ending: bottomColor)

    NSGraphicsContext.current?.saveGraphicsState()
    bgPath.addClip()
    gradient?.draw(in: rect, angle: 270)

    // Soft top highlight for a glassy feel.
    let highlight = NSGradient(
        starting: NSColor.white.withAlphaComponent(0.20),
        ending: NSColor.white.withAlphaComponent(0)
    )
    highlight?.draw(in: rect, angle: 270)
    NSGraphicsContext.current?.restoreGraphicsState()

    // ── Big sparkle in the centre ─────────────────────────────────────────
    let bigCenter = NSPoint(x: s * 0.50, y: s * 0.50)
    let bigRadius = s * 0.32
    drawSparkle(at: bigCenter, radius: bigRadius, color: .white)

    // ── Smaller accompanying sparkles (skip at very small sizes) ─────────
    if pixelSize >= 64 {
        drawSparkle(
            at: NSPoint(x: s * 0.78, y: s * 0.78),
            radius: s * 0.10,
            color: NSColor.white.withAlphaComponent(0.95)
        )
        drawSparkle(
            at: NSPoint(x: s * 0.22, y: s * 0.22),
            radius: s * 0.08,
            color: NSColor.white.withAlphaComponent(0.85)
        )
    }
    if pixelSize >= 128 {
        drawSparkle(
            at: NSPoint(x: s * 0.18, y: s * 0.78),
            radius: s * 0.06,
            color: NSColor.white.withAlphaComponent(0.75)
        )
    }

    return bitmap.representation(using: .png, properties: [:])
}

print("→ Generating PNGs at \(sizes.count) sizes…")
for size in sizes {
    guard let data = renderIcon(pixelSize: size) else {
        print("✗ Failed to render \(size)")
        continue
    }
    let path = "\(iconsetDir)/icon_\(size).png"
    try? data.write(to: URL(fileURLWithPath: path))
    print("  ✓ icon_\(size).png")
}

let appIconContents = """
{
  "images" : [
    { "size" : "16x16",   "idiom" : "mac", "filename" : "icon_16.png",   "scale" : "1x" },
    { "size" : "16x16",   "idiom" : "mac", "filename" : "icon_32.png",   "scale" : "2x" },
    { "size" : "32x32",   "idiom" : "mac", "filename" : "icon_32.png",   "scale" : "1x" },
    { "size" : "32x32",   "idiom" : "mac", "filename" : "icon_64.png",   "scale" : "2x" },
    { "size" : "128x128", "idiom" : "mac", "filename" : "icon_128.png",  "scale" : "1x" },
    { "size" : "128x128", "idiom" : "mac", "filename" : "icon_256.png",  "scale" : "2x" },
    { "size" : "256x256", "idiom" : "mac", "filename" : "icon_256.png",  "scale" : "1x" },
    { "size" : "256x256", "idiom" : "mac", "filename" : "icon_512.png",  "scale" : "2x" },
    { "size" : "512x512", "idiom" : "mac", "filename" : "icon_512.png",  "scale" : "1x" },
    { "size" : "512x512", "idiom" : "mac", "filename" : "icon_1024.png", "scale" : "2x" }
  ],
  "info" : { "version" : 1, "author" : "xcode" }
}
"""
try? appIconContents.write(toFile: "\(iconsetDir)/Contents.json", atomically: true, encoding: .utf8)

print("✓ Wrote \(iconsetDir)/Contents.json")
print("✓ Done.")
