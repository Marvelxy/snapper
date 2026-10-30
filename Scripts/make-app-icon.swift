#!/usr/bin/env swift
//
// Renders the Snapper app icon into an .iconset folder.
//
// Usage:
//   swift Scripts/make-app-icon.swift <output.iconset>
//
// Followed by:
//   iconutil -c icns -o Resources/AppIcon.icns <output.iconset>
//
// The palette matches Scripts/make-dmg-background.swift so the bundle and the
// install window look like the same product.
import AppKit
import CoreGraphics

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write("usage: make-app-icon.swift <output.iconset>\n".data(using: .utf8)!)
    exit(2)
}
let iconsetPath = arguments[1]

/// Every file `iconutil` expects, as points → pixels.
let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]

// MARK: - Shape

/// macOS-style squircle: a superellipse centred in `rect`.
func squircle(in rect: CGRect, exponent: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2
    let b = rect.height / 2
    let steps = 720
    for step in 0...steps {
        let angle = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let cosine = cos(angle)
        let sine = sin(angle)
        let x = rect.midX + a * copysign(pow(abs(cosine), 2 / exponent), cosine)
        let y = rect.midY + b * copysign(pow(abs(sine), 2 / exponent), sine)
        if step == 0 {
            path.move(to: CGPoint(x: x, y: y))
        } else {
            path.addLine(to: CGPoint(x: x, y: y))
        }
    }
    path.closeSubpath()
    return path
}

// MARK: - Drawing

/// Draws one icon at `size` × `size` pixels and returns the PNG bytes.
func renderIcon(size: Int) -> Data? {
    guard
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else { return nil }

    // Work in a 1024pt space and scale down, so every size shares one layout.
    let unit: CGFloat = 1024
    let scale = CGFloat(size) / unit
    context.scaleBy(x: scale, y: scale)
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    // Big Sur icon grid: 824 of 1024 occupied, centred.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(in: body)

    // Drop shadow so the icon sits on light and dark backgrounds alike.
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -12),
        blur: 34,
        color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.35)
    )
    context.addPath(shape)
    context.setFillColor(CGColor(srgbRed: 0.16, green: 0.07, blue: 0.20, alpha: 1))
    context.fillPath()
    context.restoreGState()

    // Violet gradient body: the DMG backdrop's colours, brighter at the top.
    context.saveGState()
    context.addPath(shape)
    context.clip()
    let bodyGradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(srgbRed: 0.58, green: 0.26, blue: 0.78, alpha: 1),
            CGColor(srgbRed: 0.36, green: 0.12, blue: 0.55, alpha: 1),
            CGColor(srgbRed: 0.13, green: 0.05, blue: 0.22, alpha: 1)
        ] as CFArray,
        locations: [0, 0.55, 1]
    )!
    context.drawLinearGradient(
        bodyGradient,
        start: CGPoint(x: body.midX, y: body.maxY),
        end: CGPoint(x: body.midX, y: body.minY),
        options: []
    )

    // Glow behind the glyph, echoing the install window's highlight.
    let glow = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(srgbRed: 0.69, green: 0.42, blue: 1, alpha: 0.55),
            CGColor(srgbRed: 0.69, green: 0.42, blue: 1, alpha: 0)
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawRadialGradient(
        glow,
        startCenter: CGPoint(x: unit / 2, y: unit / 2),
        startRadius: 0,
        endCenter: CGPoint(x: unit / 2, y: unit / 2),
        endRadius: 430,
        options: []
    )
    context.restoreGState()

    // MARK: Glyph — a screenshot selection frame with a shutter dot inside.

    let frameSide: CGFloat = 452
    let frame = CGRect(
        x: (unit - frameSide) / 2,
        y: (unit - frameSide) / 2,
        width: frameSide,
        height: frameSide
    )
    let lineWidth: CGFloat = 62
    let arm: CGFloat = 148
    let inset = lineWidth / 2
    let left = frame.minX + inset
    let right = frame.maxX - inset
    let bottom = frame.minY + inset
    let top = frame.maxY - inset

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -6),
        blur: 18,
        color: CGColor(srgbRed: 0.05, green: 0.0, blue: 0.10, alpha: 0.45)
    )
    context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    context.setLineWidth(lineWidth)
    context.setLineCap(.round)
    context.setLineJoin(.round)

    // Four corners, each an L with a rounded elbow.
    let corners: [(CGPoint, CGPoint, CGPoint)] = [
        (CGPoint(x: left, y: top - arm), CGPoint(x: left, y: top), CGPoint(x: left + arm, y: top)),
        (CGPoint(x: right - arm, y: top), CGPoint(x: right, y: top), CGPoint(x: right, y: top - arm)),
        (CGPoint(x: right, y: bottom + arm), CGPoint(x: right, y: bottom), CGPoint(x: right - arm, y: bottom)),
        (CGPoint(x: left + arm, y: bottom), CGPoint(x: left, y: bottom), CGPoint(x: left, y: bottom + arm))
    ]
    for (start, elbow, end) in corners {
        context.move(to: start)
        context.addLine(to: elbow)
        context.addLine(to: end)
        context.strokePath()
    }

    // Shutter dot in the middle of the frame.
    let dotRadius: CGFloat = 74
    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    context.fillEllipse(in: CGRect(
        x: unit / 2 - dotRadius,
        y: unit / 2 - dotRadius,
        width: dotRadius * 2,
        height: dotRadius * 2
    ))
    context.restoreGState()

    // Hairline rim, so the edge reads against the same-coloured backgrounds.
    context.addPath(shape)
    context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.14))
    context.setLineWidth(4)
    context.strokePath()

    guard let image = context.makeImage() else { return nil }
    let representation = NSBitmapImageRep(cgImage: image)
    return representation.representation(using: .png, properties: [:])
}

// MARK: - Write

try FileManager.default.createDirectory(
    atPath: iconsetPath,
    withIntermediateDirectories: true
)

for variant in variants {
    guard let png = renderIcon(size: variant.pixels) else {
        FileHandle.standardError.write("error: could not render \(variant.name)\n".data(using: .utf8)!)
        exit(1)
    }
    let url = URL(fileURLWithPath: iconsetPath).appendingPathComponent("\(variant.name).png")
    try png.write(to: url)
}

print("wrote \(variants.count) images to \(iconsetPath)")
