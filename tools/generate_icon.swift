#!/usr/bin/env swift
// One-off icon generator. Renders the PhotoProof app icon at all 10 macOS
// sizes using a green→cyan squircle + a white SF Symbol "checkmark.shield.fill".
// Re-run any time the design needs updating:
//
//     swift tools/generate_icon.swift
//
// Outputs PNGs into PhotoProof/Assets.xcassets/AppIcon.appiconset/.
//
// Renders via CGBitmapContext so it works headless (no NSApp needed).

import AppKit
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

let outputDir = "PhotoProof/Assets.xcassets/AppIcon.appiconset"

// macOS app icon sizes: (pixel size, filename).
let sizes: [(CGFloat, String)] = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

func makeContext(size: CGFloat) -> CGContext {
    let pixels = Int(size)
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    return ctx
}

func renderIcon(size: CGFloat) -> Data {
    let ctx = makeContext(size: size)
    let rect = CGRect(x: 0, y: 0, width: size, height: size)

    // Clip to a squircle. macOS clips icons to this shape automatically.
    let cornerRadius = size * 0.225
    let bgPath = CGPath(
        roundedRect: rect,
        cornerWidth: cornerRadius,
        cornerHeight: cornerRadius,
        transform: nil
    )
    ctx.addPath(bgPath)
    ctx.clip()

    // Green → cyan gradient.
    let cs = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(
        colorsSpace: cs,
        colors: [
            CGColor(srgbRed: 0.18, green: 0.74, blue: 0.42, alpha: 1.0),
            CGColor(srgbRed: 0.06, green: 0.45, blue: 0.65, alpha: 1.0),
        ] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: size / 2, y: size),
        end: CGPoint(x: size / 2, y: 0),
        options: []
    )

    // Subtle top highlight so the icon doesn't read as flat.
    let highlight = CGGradient(
        colorsSpace: cs,
        colors: [
            CGColor(gray: 1.0, alpha: 0.25),
            CGColor(gray: 1.0, alpha: 0.0),
        ] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawLinearGradient(
        highlight,
        start: CGPoint(x: size / 2, y: size),
        end: CGPoint(x: size / 2, y: size * 0.55),
        options: []
    )

    // Centred shield-with-check, drawn as a path so we don't depend on
    // SF Symbols rendering pipeline (which needs an NSApp). The shape is a
    // bog-standard rounded shield outline + check.
    let shieldHeight = size * 0.62
    let shieldWidth = size * 0.52
    let shieldRect = CGRect(
        x: (size - shieldWidth) / 2,
        y: (size - shieldHeight) / 2,
        width: shieldWidth,
        height: shieldHeight
    )
    let shieldPath = makeShieldPath(in: shieldRect)
    ctx.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
    ctx.addPath(shieldPath)
    ctx.fillPath()

    // Check mark inside the shield.
    let checkRect = shieldRect.insetBy(dx: shieldRect.width * 0.22, dy: shieldRect.height * 0.30)
    let checkPath = makeCheckPath(in: checkRect)
    ctx.setStrokeColor(CGColor(srgbRed: 0.10, green: 0.55, blue: 0.40, alpha: 1.0))
    ctx.setLineWidth(size * 0.07)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.addPath(checkPath)
    ctx.strokePath()

    guard let cgImage = ctx.makeImage() else {
        fatalError("Couldn't snapshot context")
    }
    let dest = CFDataCreateMutable(nil, 0)!
    let writer = CGImageDestinationCreateWithData(dest, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(writer, cgImage, nil)
    CGImageDestinationFinalize(writer)
    return dest as Data
}

/// A simple shield outline: rounded top, tapered to a point at the bottom.
func makeShieldPath(in rect: CGRect) -> CGPath {
    let p = CGMutablePath()
    let topRadius = rect.width * 0.20

    // Top-left rounded corner
    p.move(to: CGPoint(x: rect.minX, y: rect.maxY - topRadius))
    p.addArc(
        tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
        tangent2End: CGPoint(x: rect.minX + topRadius, y: rect.maxY),
        radius: topRadius
    )
    // Top edge
    p.addLine(to: CGPoint(x: rect.maxX - topRadius, y: rect.maxY))
    // Top-right rounded corner
    p.addArc(
        tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
        tangent2End: CGPoint(x: rect.maxX, y: rect.maxY - topRadius),
        radius: topRadius
    )
    // Right edge down to about 35% from bottom
    let curveStartY = rect.minY + rect.height * 0.35
    p.addLine(to: CGPoint(x: rect.maxX, y: curveStartY))
    // Curve to point at the bottom centre
    p.addQuadCurve(
        to: CGPoint(x: rect.midX, y: rect.minY),
        control: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.05)
    )
    // Curve back up to the left edge
    p.addQuadCurve(
        to: CGPoint(x: rect.minX, y: curveStartY),
        control: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.05)
    )
    p.closeSubpath()
    return p
}

/// A check mark within `rect`. Three-point stroke.
func makeCheckPath(in rect: CGRect) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.55))
    p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.minY + rect.height * 0.18))
    p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    return p
}

for (size, filename) in sizes {
    let data = renderIcon(size: size)
    let url = URL(fileURLWithPath: "\(outputDir)/\(filename)")
    do {
        try data.write(to: url)
        print("wrote \(filename) at \(Int(size))x\(Int(size))")
    } catch {
        print("FAILED to write \(filename): \(error)")
        exit(1)
    }
}
