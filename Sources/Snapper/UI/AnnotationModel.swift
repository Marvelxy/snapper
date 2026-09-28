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

/// Bakes annotations onto a cropped capture using only AppKit drawing
/// primitives — the same path the overlay uses to display the screenshot —
/// so the file matches the screen exactly: the photo is copied with
/// interpolation disabled (no resampling softness, no flips) and vectors are
/// drawn in matching coordinates. Geometry arrives in selection-local points
/// (top-left origin); `scale` maps points onto pixels.
enum SnapperRenderer {
    @MainActor
    static func composite(
        base: CGImage,
        annotations: [SnapperAnnotation],
        scale: CGFloat
    ) -> CGImage? {
        guard !annotations.isEmpty else { return base }
        let pixelWidth = base.width
        let pixelHeight = base.height
        guard pixelWidth > 0, pixelHeight > 0 else { return base }

        // 1 unit = 1 pixel, AppKit bottom-left origin.
        let canvasSize = NSSize(width: pixelWidth, height: pixelHeight)
        let canvas = NSImage(size: canvasSize)
        canvas.lockFocus()

        // Pixel-identical copy of the photo: no interpolation, no resampling.
        NSGraphicsContext.current?.imageInterpolation = .none
        NSImage(cgImage: base, size: canvasSize)
            .draw(in: NSRect(origin: .zero, size: canvasSize))
        NSGraphicsContext.current?.imageInterpolation = .default

        let canvasHeight = CGFloat(pixelHeight)
        for annotation in annotations {
            draw(annotation, base: base, canvasHeight: canvasHeight, scale: scale)
        }
        canvas.unlockFocus()

        // Re-render through AppKit so orientation matches what was drawn.
        guard let tiff = canvas.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let output = rep.cgImage else { return nil }
        return output
    }

    private static func draw(
        _ annotation: SnapperAnnotation,
        base: CGImage,
        canvasHeight: CGFloat,
        scale: CGFloat
    ) {
        let color = NSColor(hex: annotation.hex)
        let lineWidth = max(1, annotation.width * scale)

        func point(_ p: CGPoint) -> NSPoint {
            NSPoint(x: p.x * scale, y: canvasHeight - p.y * scale)
        }
        func rect(_ r: CGRect) -> NSRect {
            NSRect(
                x: r.minX * scale,
                y: canvasHeight - r.maxY * scale,
                width: r.width * scale,
                height: r.height * scale
            )
        }
        func stroke(_ path: NSBezierPath) {
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }

        switch annotation.kind {
        case .stroke(let points, let opacity):
            guard let first = points.first else { return }
            color.withAlphaComponent(opacity).setStroke()
            let path = NSBezierPath()
            let start = point(first)
            path.move(to: start)
            if points.count == 1 {
                path.line(to: NSPoint(x: start.x + 0.5, y: start.y))
            } else {
                for p in points.dropFirst() {
                    path.line(to: point(p))
                }
            }
            stroke(path)

        case .line(let from, let to):
            color.setStroke()
            let path = NSBezierPath()
            path.move(to: point(from))
            path.line(to: point(to))
            stroke(path)

        case .arrow(let from, let to):
            let a = point(from)
            let b = point(to)
            color.setStroke()
            let shaft = NSBezierPath()
            shaft.move(to: a)
            shaft.line(to: b)
            stroke(shaft)

            let direction = NSPoint(x: b.x - a.x, y: b.y - a.y)
            let length = hypot(direction.x, direction.y)
            guard length > 4 else { return }
            let unit = NSPoint(x: direction.x / length, y: direction.y / length)
            let normal = NSPoint(x: -unit.y, y: unit.x)
            let half = max(1.5, lineWidth / 2)
            let headLength = max(12, lineWidth * 3)
            let headHalf = max(6, lineWidth * 2)
            let neck = NSPoint(x: b.x - unit.x * headLength, y: b.y - unit.y * headLength)

            let head = NSBezierPath()
            head.move(to: NSPoint(x: a.x + normal.x * half, y: a.y + normal.y * half))
            head.line(to: NSPoint(x: neck.x + normal.x * half, y: neck.y + normal.y * half))
            head.line(to: NSPoint(x: neck.x + normal.x * headHalf, y: neck.y + normal.y * headHalf))
            head.line(to: b)
            head.line(to: NSPoint(x: neck.x - normal.x * headHalf, y: neck.y - normal.y * headHalf))
            head.line(to: NSPoint(x: neck.x - normal.x * half, y: neck.y - normal.y * half))
            head.line(to: NSPoint(x: a.x - normal.x * half, y: a.y - normal.y * half))
            head.close()
            color.setFill()
            head.fill()

        case .rectangle(let r):
            color.setStroke()
            stroke(NSBezierPath(rect: rect(r)))

        case .ellipse(let r):
            color.setStroke()
            stroke(NSBezierPath(ovalIn: rect(r)))

        case .pixelate(let r):
            // Crop from the original capture (top-left origin, same convention
            // as ImageUtilities.cropped) so the region lines up exactly.
            let pixelRect = scaled(r, by: scale)
            guard let pixellated = pixellated(base: base, rect: pixelRect) else { return }
            NSImage(
                cgImage: pixellated,
                size: NSSize(width: pixelRect.width, height: pixelRect.height)
            ).draw(in: rect(r))

        case .text(let position, let string, let fontSize):
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize * scale, weight: .semibold),
                .foregroundColor: color
            ]
            let text = NSAttributedString(string: trimmed, attributes: attributes)
            let textSize = text.size()
            let anchor = point(position)
            // draw(in:) lays out from the rect's top in any context, matching
            // the top-left anchored preview.
            text.draw(in: NSRect(
                x: anchor.x,
                y: anchor.y - ceil(textSize.height),
                width: ceil(textSize.width),
                height: ceil(textSize.height)
            ))
        }
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
