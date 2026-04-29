#!/usr/bin/env swift
//
// Generates Moonlit's app icon at every size macOS needs and writes the
// AppIcon.appiconset under Moonlit/Assets.xcassets. Run from the project root:
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

// Top-level Assets.xcassets/Contents.json
let topContents = """
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""
try? topContents.write(toFile: "\(outputRoot)/Contents.json", atomically: true, encoding: .utf8)

// Sizes we need (px). macOS app icons require 1x + 2x variants of each
// logical size — the Contents.json maps the same physical files to those.
let sizes: [Int] = [16, 32, 64, 128, 256, 512, 1024]

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

    // ── Background: rounded square with purple/indigo gradient ──────────
    let cornerRadius = s * 0.22 // macOS Big Sur+ icon radius
    let bgPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)

    let topColor = NSColor(red: 0.55, green: 0.36, blue: 0.96, alpha: 1.0)    // violet
    let bottomColor = NSColor(red: 0.31, green: 0.27, blue: 0.90, alpha: 1.0) // indigo
    let gradient = NSGradient(starting: topColor, ending: bottomColor)

    NSGraphicsContext.current?.saveGraphicsState()
    bgPath.addClip()
    gradient?.draw(in: rect, angle: 270)

    // Subtle highlight at the top to give the icon a soft, glassy feel.
    let highlight = NSGradient(
        starting: NSColor.white.withAlphaComponent(0.16),
        ending: NSColor.white.withAlphaComponent(0)
    )
    highlight?.draw(in: rect, angle: 270)
    NSGraphicsContext.current?.restoreGraphicsState()

    // ── Crescent moon ─────────────────────────────────────────────────────
    // Drawn as a white disc with a slightly offset gradient-coloured disc on
    // top to "carve out" the crescent shape.
    let moonScale: CGFloat = 0.58
    let moonSize = s * moonScale
    let moonRect = NSRect(
        x: (s - moonSize) / 2 - s * 0.02,
        y: (s - moonSize) / 2 - s * 0.02,
        width: moonSize,
        height: moonSize
    )
    NSColor.white.setFill()
    NSBezierPath(ovalIn: moonRect).fill()

    // Carve crescent
    let carveSize = moonSize * 1.0
    let carveRect = NSRect(
        x: moonRect.origin.x + moonSize * 0.28,
        y: moonRect.origin.y + moonSize * 0.22,
        width: carveSize,
        height: carveSize
    )
    // Use a colour matching the gradient near the moon's vertical position
    // so the carved-out region blends seamlessly.
    NSColor(red: 0.40, green: 0.31, blue: 0.93, alpha: 1.0).setFill()
    NSBezierPath(ovalIn: carveRect).fill()

    // ── Stars ────────────────────────────────────────────────────────────
    let starColor = NSColor.white
    starColor.setFill()
    // (x, y, size) all relative to icon size. Skip stars at very small sizes
    // to avoid muddy speckles.
    let stars: [(CGFloat, CGFloat, CGFloat)] = pixelSize >= 64
        ? [
            (0.18, 0.80, 0.045),
            (0.82, 0.30, 0.040),
            (0.88, 0.62, 0.028),
            (0.22, 0.42, 0.030),
        ]
        : [
            (0.20, 0.80, 0.06),
            (0.82, 0.30, 0.06),
        ]

    for (xRel, yRel, sizeRel) in stars {
        let dia = s * sizeRel
        let starRect = NSRect(
            x: s * xRel - dia / 2,
            y: s * yRel - dia / 2,
            width: dia,
            height: dia
        )
        NSBezierPath(ovalIn: starRect).fill()
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

// AppIcon.appiconset/Contents.json — maps the PNG files to the macOS slots.
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
