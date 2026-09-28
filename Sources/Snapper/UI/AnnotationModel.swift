import AppKit
import CoreGraphics
import CoreImage
import SwiftUI

// MARK: - Tools

/// Snapper's toolbar toolset, in toolbar order.
enum SnapperTool: String, CaseIterable, Identifiable {
    case selection
    case pencil
    case line
    case arrow
    case rectangle
    case circle
    case marker
    case pixelate
    case text

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .selection: return "cursorarrow"
        case .pencil: return "pencil"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .circle: return "circle"
        case .marker: return "highlighter"
        case .pixelate: return "square.grid.3x3.fill"
        case .text: return "textformat"
        }
    }

    /// Snapper single-key shortcut for each tool.
    var hotkey: String {
        switch self {
        case .selection: return "S"
        case .pencil: return "P"
        case .line: return "D"
        case .arrow: return "A"
        case .rectangle: return "R"
        case .circle: return "C"
        case .marker: return "M"
        case .pixelate: return "B"
        case .text: return "T"
        }
    }

    var help: String {
        switch self {
        case .selection: return "Selection (S)"
        case .pencil: return "Pencil (P)"
        case .line: return "Line (D)"
        case .arrow: return "Arrow (A)"
        case .rectangle: return "Rectangle (R)"
        case .circle: return "Circle (C)"
        case .marker: return "Marker (M)"
        case .pixelate: return "Pixelate (B)"
        case .text: return "Text (T)"
        }
    }
}

// MARK: - Color / thickness

/// Snapper's default draw-color choices.
enum SnapperSwatch: String, CaseIterable, Identifiable {
    case red = "#FF0000"
    case orange = "#FF8000"
    case yellow = "#FFE400"
    case green = "#00FF00"
    case blue = "#0080FF"
    case purple = "#740096"
    case white = "#FFFFFF"
    case black = "#000000"

    var id: String { rawValue }

    var color: Color { Color(hex: rawValue) }
    var nsColor: NSColor { NSColor(hex: rawValue) }
}

enum SnapperThickness: CGFloat, CaseIterable, Identifiable {
    case thin = 2
    case medium = 4
    case thick = 8

    var id: CGFloat { rawValue }

    var label: String {
        switch self {
        case .thin: return "Thin"
        case .medium: return "Medium"
        case .thick: return "Thick"
        }
    }

    /// Font size used by the text tool for each thickness step.
    var fontSize: CGFloat {
        switch self {
        case .thin: return 14
        case .medium: return 18
        case .thick: return 26
        }
    }
}

extension Color {
    init(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: value).scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

extension NSColor {
    convenience init(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: value).scanHexInt64(&rgb)
        self.init(
            calibratedRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Annotations

/// A single annotation stroke. All geometry is in selection-local points with a
/// top-left origin (SwiftUI space), scaled by `pixelScale` at export time.
struct SnapperAnnotation: Identifiable, Equatable {
    enum Kind: Equatable {
        case stroke(points: [CGPoint], opacity: Double)
        case line(from: CGPoint, to: CGPoint)
        case arrow(from: CGPoint, to: CGPoint)
        case rectangle(rect: CGRect)
        case ellipse(rect: CGRect)
        case pixelate(rect: CGRect)
        case text(position: CGPoint, string: String, fontSize: CGFloat)
    }

    let id: UUID
    var kind: Kind
    var hex: String
    var width: CGFloat

    init(id: UUID = UUID(), kind: Kind, hex: String, width: CGFloat) {
        self.id = id
        self.kind = kind
        self.hex = hex
        self.width = width
    }
}

// MARK: - Export renderer

/// Bakes annotations onto a cropped capture. Coordinates arrive in
/// selection-local points (top-left origin) and are scaled to pixels.
enum SnapperRenderer {
    static func composite(
        base: CGImage,
        annotations: [SnapperAnnotation],
        scale: CGFloat
    ) -> CGImage? {
        guard !annotations.isEmpty else { return base }
        let width = base.width
        let height = base.height
        guard width > 0, height > 0 else { return base }

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Work in top-left origin space so annotation geometry maps 1:1.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(base, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.setLineCap(.round)
        context.setLineJoin(.round)

        for annotation in annotations {
            draw(
                annotation,
                in: context,
                imageSize: CGSize(width: width, height: height),
                scale: scale,
                originalBase: base
            )
        }

        return context.makeImage()
    }

    private static func draw(
        _ annotation: SnapperAnnotation,
        in context: CGContext,
        imageSize: CGSize,
        scale: CGFloat,
        originalBase: CGImage
    ) {
        let px = { (value: CGFloat) in value * scale }
        let color = NSColor(hex: annotation.hex)
        let lineWidth = max(1, px(annotation.width))

        switch annotation.kind {
        case .stroke(let points, let opacity):
            guard points.count >= 1 else { return }
            context.setStrokeColor(color.withAlphaComponent(CGFloat(opacity)).cgColor)
            context.setLineWidth(lineWidth)
            context.beginPath()
            if points.count == 1 {
                let p = scaled(points[0], by: scale)
                context.move(to: p)
                context.addLine(to: CGPoint(x: p.x + 0.5, y: p.y + 0.5))
            } else {
                context.move(to: scaled(points[0], by: scale))
                for point in points.dropFirst() {
                    context.addLine(to: scaled(point, by: scale))
                }
            }
            context.strokePath()

        case .line(let from, let to):
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(lineWidth)
            context.beginPath()
            context.move(to: scaled(from, by: scale))
            context.addLine(to: scaled(to, by: scale))
            context.strokePath()

        case .arrow(let from, let to):
            let a = scaled(from, by: scale)
            let b = scaled(to, by: scale)
            context.setStrokeColor(color.cgColor)
            context.setFillColor(color.cgColor)
            context.setLineWidth(lineWidth)
            context.beginPath()
            context.move(to: a)
            context.addLine(to: b)
            context.strokePath()

            let direction = CGPoint(x: b.x - a.x, y: b.y - a.y)
            let length = hypot(direction.x, direction.y)
            guard length > 4 else { return }
            let unit = CGPoint(x: direction.x / length, y: direction.y / length)
            let headLength = max(10 * scale, lineWidth * 3)
            let angle: CGFloat = .pi / 7
            let left = CGPoint(
                x: b.x - headLength * (unit.x * cos(angle) - unit.y * sin(angle)),
                y: b.y - headLength * (unit.x * sin(angle) + unit.y * cos(angle))
            )
            let right = CGPoint(
                x: b.x - headLength * (unit.x * cos(angle) + unit.y * sin(angle)),
                y: b.y - headLength * (-unit.x * sin(angle) + unit.y * cos(angle))
            )
            context.beginPath()
            context.move(to: b)
            context.addLine(to: left)
            context.addLine(to: right)
            context.closePath()
            context.fillPath()

        case .rectangle(let rect):
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(lineWidth)
            context.stroke(scaled(rect, by: scale))

        case .ellipse(let rect):
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(lineWidth)
            context.beginPath()
            context.addEllipse(in: scaled(rect, by: scale))
            context.strokePath()

        case .pixelate(let rect):
            // Crop from the original capture (top-left origin, same convention
            // as ImageUtilities.cropped) so the region lines up exactly.
            guard let pixellated = pixellated(base: originalBase, rect: scaled(rect, by: scale)) else { return }
            context.saveGState()
            context.clip(to: scaled(rect, by: scale))
            context.draw(pixellated, in: scaled(rect, by: scale))
            context.restoreGState()

        case .text(let position, let string, let fontSize):
            guard !string.isEmpty else { return }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: px(fontSize), weight: .semibold),
                .foregroundColor: color
            ]
            let attributed = NSAttributedString(string: string, attributes: attributes)
            let textSize = attributed.size()
            let size = NSSize(width: ceil(textSize.width) + 8, height: ceil(textSize.height) + 8)
            let raster = NSImage(size: size)
            raster.lockFocus()
            NSColor.clear.set()
            NSRect(origin: .zero, size: size).fill()
            attributed.draw(at: NSPoint(x: 4, y: 4))
            raster.unlockFocus()
            guard let textImage = raster.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
            let origin = scaled(position, by: scale)
            context.draw(textImage, in: CGRect(origin: origin, size: size))
        }

        // Silence unused warning for imageSize when no branch needs it.
        _ = imageSize
    }

    private static func scaled(_ point: CGPoint, by scale: CGFloat) -> CGPoint {
        CGPoint(x: point.x * scale, y: point.y * scale)
    }

    private static func scaled(_ rect: CGRect, by scale: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX * scale,
            y: rect.minY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    private static func pixellated(base: CGImage?, rect: CGRect) -> CGImage? {
        guard let base, rect.width >= 4, rect.height >= 4 else { return nil }
        let clipped = rect.integral.intersection(CGRect(x: 0, y: 0, width: base.width, height: base.height))
        guard clipped.width >= 4, clipped.height >= 4,
              let cropped = base.cropping(to: clipped) else { return nil }
        let input = CIImage(cgImage: cropped)
        guard let filter = CIFilter(name: "CIPixellate") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(max(8, min(clipped.width, clipped.height) / 24), forKey: kCIInputScaleKey)
        guard let output = filter.outputImage else { return nil }
        let context = CIContext(options: [.useSoftwareRenderer: false])
        // Render at the cropped size, anchored at the output's origin.
        let renderRect = CGRect(origin: output.extent.origin, size: clipped.size)
        return context.createCGImage(output, from: renderRect)
    }
}
