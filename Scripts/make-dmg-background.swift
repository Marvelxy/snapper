#!/usr/bin/env swift
//
// Renders the Snapper DMG install window background.
//
// Usage:
//   swift Scripts/make-dmg-background.swift <output.png> [scale]
//
// Coordinates are in window-content points with a top-left origin, matching the
// icon positions set by Scripts/build-dmg.sh.
//
import AppKit
import CoreGraphics

let width: CGFloat = 660
let height: CGFloat = 420

/// Must match the icon positions in build-dmg.sh.
let appIcon = CGPoint(x: 165, y: 200)
let applicationsIcon = CGPoint(x: 495, y: 200)

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write("usage: make-dmg-background.swift <output.png> [scale]\n".data(using: .utf8)!)
    exit(2)
}
let outputPath = arguments[1]
let scale = arguments.count >= 3 ? max(1, CGFloat(Double(arguments[2]) ?? 1)) : 1

let pixelWidth = Int(width * scale)
let pixelHeight = Int(height * scale)

guard
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
    let context = CGContext(
        data: nil,
        width: pixelWidth,
        height: pixelHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
else {
    FileHandle.standardError.write("error: could not create a bitmap context\n".data(using: .utf8)!)
    exit(1)
}

context.scaleBy(x: scale, y: scale)
// Flip to a top-left origin so the layout below reads like the Finder window.
context.translateBy(x: 0, y: height)
context.scaleBy(x: 1, y: -1)
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

// MARK: - Backdrop

let canvas = CGRect(x: 0, y: 0, width: width, height: height)
let backdrop = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(srgbRed: 0.16, green: 0.07, blue: 0.20, alpha: 1),
        CGColor(srgbRed: 0.08, green: 0.04, blue: 0.10, alpha: 1)
    ] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    backdrop,
    start: CGPoint(x: 0, y: 0),
    end: CGPoint(x: 0, y: height),
    options: []
)

// Soft violet glow behind the two drop targets.
let glow = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(srgbRed: 0.45, green: 0.15, blue: 0.60, alpha: 0.45),
        CGColor(srgbRed: 0.45, green: 0.15, blue: 0.60, alpha: 0)
    ] as CFArray,
    locations: [0, 1]
)!
context.drawRadialGradient(
    glow,
    startCenter: CGPoint(x: width / 2, y: applicationsIcon.y),
    startRadius: 0,
    endCenter: CGPoint(x: width / 2, y: applicationsIcon.y),
    endRadius: 240,
    options: []
)

// Hairline inset frame, so the window looks like a finished panel.
context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.08))
context.setLineWidth(1)
context.stroke(canvas.insetBy(dx: 0.5, dy: 0.5))

// MARK: - Arrow between the icons

let arrowStart = CGPoint(x: appIcon.x + 78, y: appIcon.y)
let arrowEnd = CGPoint(x: applicationsIcon.x - 86, y: applicationsIcon.y)

context.setStrokeColor(CGColor(srgbRed: 0.69, green: 0.42, blue: 1, alpha: 0.9))
context.setLineWidth(3)
context.setLineCap(.round)
context.move(to: arrowStart)
context.addLine(to: CGPoint(x: arrowEnd.x - 16, y: arrowEnd.y))
context.strokePath()

context.setFillColor(CGColor(srgbRed: 0.69, green: 0.42, blue: 1, alpha: 0.95))
context.move(to: arrowEnd)
context.addLine(to: CGPoint(x: arrowEnd.x - 20, y: arrowEnd.y - 9))
context.addLine(to: CGPoint(x: arrowEnd.x - 20, y: arrowEnd.y + 9))
context.closePath()
context.fillPath()

// MARK: - Text

let graphicsContext = NSGraphicsContext(cgContext: context, flipped: true)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphicsContext

func draw(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, centerY: CGFloat, tracking: CGFloat = 0) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: paragraph,
        .kern: tracking
    ]
    let string = NSAttributedString(string: text, attributes: attributes)
    let textHeight = string.size().height
    string.draw(in: CGRect(x: 24, y: centerY - textHeight / 2, width: width - 48, height: textHeight + 2))
}

draw(
    "Snapper",
    size: 30,
    weight: .bold,
    color: .white,
    centerY: 62,
    tracking: 0.5
)
draw(
    "Drag Snapper into Applications to install",
    size: 13,
    weight: .medium,
    color: NSColor(srgbRed: 0.80, green: 0.73, blue: 0.88, alpha: 1),
    centerY: 92
)
draw(
    "Fast screenshots with built-in annotations",
    size: 11,
    weight: .regular,
    color: NSColor(srgbRed: 0.62, green: 0.55, blue: 0.70, alpha: 1),
    centerY: 112
)
draw(
    "macOS 14 or later  ·  GPL-3.0",
    size: 10,
    weight: .regular,
    color: NSColor(srgbRed: 0.52, green: 0.45, blue: 0.60, alpha: 1),
    centerY: 340
)

NSGraphicsContext.restoreGraphicsState()

// MARK: - Write PNG

guard let image = context.makeImage() else {
    FileHandle.standardError.write("error: could not snapshot the context\n".data(using: .utf8)!)
    exit(1)
}

let representation = NSBitmapImageRep(cgImage: image)
guard let png = representation.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("error: could not encode PNG\n".data(using: .utf8)!)
    exit(1)
}

do {
    try png.write(to: URL(fileURLWithPath: outputPath))
} catch {
    FileHandle.standardError.write("error: \(error.localizedDescription)\n".data(using: .utf8)!)
    exit(1)
}
