import AppKit
import SwiftUI

/// Where the capture should go once the selection is accepted.
enum FlameshotCommitAction {
    case copy
    case save
}

/// Resize handles around the selection, in flameshot's 8-handle layout.
enum FlameshotHandle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
}

/// Owns all editor state for one flameshot-style capture session: the
/// selection rectangle, in-progress gestures, annotations with undo/redo, the
/// active tool, color and thickness. Coordinates are view points with a
/// top-left origin; the overlay maps them onto capture pixels at commit time.
@MainActor
final class FlameshotSession: ObservableObject {
    // MARK: - Canvas

    /// Full-canvas size in points (matches the captured image's point size).
    var canvasSize: CGSize = .zero
    let pixelScale: CGFloat

    // MARK: - Selection & gestures

    @Published var selection: CGRect?
    @Published var cursor: CGPoint = .zero
    @Published var isHovering = false

    private enum DragMode {
        case none
        case newSelection(anchor: CGPoint)
        case move(anchor: CGPoint, original: CGRect)
        case resize(handle: FlameshotHandle, original: CGRect)
        case drawShape(kind: ShapeKind, anchor: CGPoint, current: CGPoint)
        case stroke(points: [CGPoint])
        case pixelate(anchor: CGPoint, current: CGRect)
    }

    enum ShapeKind {
        case line, arrow, rectangle, ellipse
    }

    private var dragMode: DragMode = .none
    @Published private(set) var dragPreview: DrawPreview?
    @Published private(set) var liveStroke: [CGPoint] = []

    /// Transient shape preview while a shape gesture is active.
    struct DrawPreview {
        let kind: ShapeKind
        let from: CGPoint
        let to: CGPoint
    }

    // MARK: - Tools & style

    @Published var activeTool: FlameshotTool = .selection
    @Published var swatch: FlameshotSwatch = .red
    @Published var thickness: FlameshotThickness = .medium
    @Published var showSidePanel = false

    // MARK: - Annotations

    @Published private(set) var annotations: [FlameshotAnnotation] = []
    @Published private(set) var redoStack: [FlameshotAnnotation] = []
    var canUndo: Bool { !annotations.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: - Text editing

    struct PendingText: Identifiable {
        let id = UUID()
        var position: CGPoint
        var string: String
    }

    @Published var pendingText: PendingText?

    // MARK: - Commit

    /// Called with the selection (view coords), annotations
    /// (selection-local coords) and the requested action.
    var onAccept: ((CGRect, [FlameshotAnnotation], FlameshotCommitAction) -> Void)?
    var onCancel: (() -> Void)?

    private let minimumSide: CGFloat = 5
    private let handleRadius: CGFloat = 12

    init(pixelScale: CGFloat) {
        self.pixelScale = pixelScale
    }

    // MARK: - Selection-local mapping

    /// Converts a canvas point into selection-local coordinates.
    func toLocal(_ point: CGPoint) -> CGPoint {
        guard let selection else { return point }
        return CGPoint(x: point.x - selection.minX, y: point.y - selection.minY)
    }

    private func clampedToSelection(_ point: CGPoint) -> CGPoint {
        guard let selection else { return point }
        return CGPoint(
            x: min(max(point.x, selection.minX), selection.maxX),
            y: min(max(point.y, selection.minY), selection.maxY)
        )
    }

    // MARK: - Pointer

    func hover(at point: CGPoint) {
        cursor = point
        isHovering = true
    }

    func hoverEnded() {
        isHovering = false
    }

    // MARK: - Gesture entry

    func pressBegan(at point: CGPoint) {
        commitPendingText()
        guard canvasSize != .zero else { return }

        if activeTool == .selection {
            pressWithSelectionTool(at: point)
            return
        }

        // Drawing tools only operate inside an existing selection.
        guard let selection, selection.contains(point) else {
            // Without annotations yet, a click outside restarts the selection
            // instead of feeling dead.
            if !isSelectionLocked {
                dragMode = .newSelection(anchor: point)
                self.selection = CGRect(x: point.x, y: point.y, width: 0, height: 0)
            }
            return
        }

        let anchor = clampedToSelection(point)
        switch activeTool {
        case .pencil:
            dragMode = .stroke(points: [toLocal(anchor)])
            liveStroke = [toLocal(anchor)]
        case .marker:
            dragMode = .stroke(points: [toLocal(anchor)])
            liveStroke = [toLocal(anchor)]
        case .line:
            dragMode = .drawShape(kind: .line, anchor: anchor, current: anchor)
            dragPreview = DrawPreview(kind: .line, from: anchor, to: anchor)
        case .arrow:
            dragMode = .drawShape(kind: .arrow, anchor: anchor, current: anchor)
            dragPreview = DrawPreview(kind: .arrow, from: anchor, to: anchor)
        case .rectangle:
            dragMode = .drawShape(kind: .rectangle, anchor: anchor, current: anchor)
            dragPreview = DrawPreview(kind: .rectangle, from: anchor, to: anchor)
        case .circle:
            dragMode = .drawShape(kind: .ellipse, anchor: anchor, current: anchor)
            dragPreview = DrawPreview(kind: .ellipse, from: anchor, to: anchor)
        case .pixelate:
            let local = toLocal(anchor)
            dragMode = .pixelate(anchor: anchor, current: CGRect(origin: local, size: .zero))
        case .text:
            pendingText = PendingText(position: toLocal(anchor), string: "")
        case .selection:
            break
        }
    }

    private func pressWithSelectionTool(at point: CGPoint) {
        // Like flameshot, the selection locks once annotations exist so
        // selection-local strokes keep lining up with the pixels beneath them.
        if isSelectionLocked { return }
        if let selection {
            if let handle = handle(at: point, in: selection) {
                dragMode = .resize(handle: handle, original: selection)
                return
            }
            if selection.contains(point) {
                dragMode = .move(anchor: point, original: selection)
                return
            }
        }
        dragMode = .newSelection(anchor: point)
        self.selection = CGRect(x: point.x, y: point.y, width: 0, height: 0)
    }

    func pressChanged(to point: CGPoint) {
        cursor = point
        switch dragMode {
        case .none:
            break
        case .newSelection(let anchor):
            selection = Self.rectangle(from: anchor, to: point, clampedTo: canvasRect)
        case .move(let anchor, let original):
            let dx = point.x - anchor.x
            let dy = point.y - anchor.y
            selection = clampToCanvas(original.offsetBy(dx: dx, dy: dy))
        case .resize(let handle, let original):
            selection = clampedResized(original, handle: handle, to: point)
        case .drawShape(let kind, let anchor, _):
            let current = clampedToSelection(point)
            dragMode = .drawShape(kind: kind, anchor: anchor, current: current)
            dragPreview = DrawPreview(kind: kind, from: anchor, to: current)
        case .stroke(var points):
            let local = toLocal(clampedToSelection(point))
            if points.last != local {
                points.append(local)
                dragMode = .stroke(points: points)
                liveStroke = points
            }
        case .pixelate(let anchor, _):
            let current = clampedToSelection(point)
            let localRect = Self.rectangle(from: toLocal(anchor), to: toLocal(current), clampedTo: nil)
            dragMode = .pixelate(anchor: anchor, current: localRect)
            dragPreview = nil
        }
    }

    func pressEnded(at point: CGPoint) {
        switch dragMode {
        case .none:
            break
        case .newSelection:
            if let rect = selection, rect.width < minimumSide || rect.height < minimumSide {
                selection = nil
            }
        case .move, .resize:
            normalizeSelection()
        case .drawShape(let kind, let anchor, _):
            let current = clampedToSelection(point)
            pushShape(kind: kind, from: toLocal(anchor), to: toLocal(current))
            dragPreview = nil
        case .stroke(let points):
            pushStroke(points: points)
            liveStroke = []
        case .pixelate(_, let localRect):
            if localRect.width >= minimumSide, localRect.height >= minimumSide {
                push(FlameshotAnnotation(kind: .pixelate(rect: localRect), hex: swatch.rawValue, width: thickness.rawValue))
            }
        }
        dragMode = .none
    }

    var isDrawing: Bool {
        switch dragMode {
        case .none: return false
        case .newSelection: return true
        default: return true
        }
    }

    var livePixelateRect: CGRect? {
        if case .pixelate(_, let rect) = dragMode { return rect }
        return nil
    }

    // MARK: - Shapes

    private func pushShape(kind: ShapeKind, from: CGPoint, to: CGPoint) {
        let tooSmall: Bool
        switch kind {
        case .line, .arrow:
            tooSmall = hypot(to.x - from.x, to.y - from.y) < minimumSide
        case .rectangle, .ellipse:
            let rect = Self.rectangle(from: from, to: to, clampedTo: nil)
            tooSmall = rect.width < minimumSide || rect.height < minimumSide
        }
        guard !tooSmall else { return }

        let annotation: FlameshotAnnotation
        switch kind {
        case .line:
            annotation = FlameshotAnnotation(kind: .line(from: from, to: to), hex: swatch.rawValue, width: thickness.rawValue)
        case .arrow:
            annotation = FlameshotAnnotation(kind: .arrow(from: from, to: to), hex: swatch.rawValue, width: thickness.rawValue)
        case .rectangle:
            annotation = FlameshotAnnotation(
                kind: .rectangle(rect: Self.rectangle(from: from, to: to, clampedTo: nil)),
                hex: swatch.rawValue, width: thickness.rawValue
            )
        case .ellipse:
            annotation = FlameshotAnnotation(
                kind: .ellipse(rect: Self.rectangle(from: from, to: to, clampedTo: nil)),
                hex: swatch.rawValue, width: thickness.rawValue
            )
        }
        push(annotation)
    }

    private func pushStroke(points: [CGPoint]) {
        guard points.count >= 1 else { return }
        let isMarker = activeTool == .marker
        let width = isMarker ? thickness.rawValue * 3 : thickness.rawValue
        let kind = FlameshotAnnotation.Kind.stroke(points: points, opacity: isMarker ? 0.4 : 1)
        push(FlameshotAnnotation(kind: kind, hex: swatch.rawValue, width: width))
    }

    // MARK: - Undo / redo

    private func push(_ annotation: FlameshotAnnotation) {
        annotations.append(annotation)
        redoStack.removeAll()
    }

    func undo() {
        commitPendingText()
        guard let last = annotations.popLast() else { return }
        redoStack.append(last)
    }

    func redo() {
        commitPendingText()
        guard let next = redoStack.popLast() else { return }
        annotations.append(next)
    }

    // MARK: - Text

    func commitPendingText() {
        guard let pending = pendingText else { return }
        pendingText = nil
        let trimmed = pending.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        push(FlameshotAnnotation(
            kind: .text(position: pending.position, string: trimmed, fontSize: thickness.fontSize),
            hex: swatch.rawValue,
            width: thickness.rawValue
        ))
    }

    func cancelPendingText() {
        pendingText = nil
    }

    // MARK: - Selection commands

    func selectAll() {
        commitPendingText()
        guard !isSelectionLocked else { return }
        selection = canvasRect
        activeTool = .selection
    }

    func nudgeSelection(dx: CGFloat, dy: CGFloat, resize: Bool) {
        guard !isSelectionLocked else { return }
        guard var rect = selection else { return }
        if resize {
            rect.size.width = max(minimumSide, rect.width + dx)
            rect.size.height = max(minimumSide, rect.height + dy)
            selection = clampToCanvas(rect)
        } else {
            selection = clampToCanvas(rect.offsetBy(dx: dx, dy: dy))
        }
    }

    private func normalizeSelection() {
        guard let rect = selection else { return }
        var normalized = rect.standardized
        normalized.size.width = max(minimumSide, normalized.width)
        normalized.size.height = max(minimumSide, normalized.height)
        selection = clampToCanvas(normalized)
    }

    // MARK: - Handles

    func handle(at point: CGPoint, in rect: CGRect) -> FlameshotHandle? {
        for handle in FlameshotHandle.allCases {
            if hypot(point.x - handlePoint(handle, in: rect).x, point.y - handlePoint(handle, in: rect).y) <= handleRadius {
                return handle
            }
        }
        return nil
    }

    func handlePoint(_ handle: FlameshotHandle, in rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .top: return CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    private func clampedResized(_ original: CGRect, handle: FlameshotHandle, to point: CGPoint) -> CGRect {
        // Mirror flameshot defaults: Shift mirrors around the opposite edge,
        // Control preserves the aspect ratio.
        let flags = NSApp?.currentEvent?.modifierFlags ?? []
        let mirror = flags.contains(.shift)
        let keepAspect = flags.contains(.control)

        var rect = original
        let aspect = original.width / max(original.height, 1)

        switch handle {
        case .topLeft: rect = CGRect(x: point.x, y: point.y, width: original.maxX - point.x, height: original.maxY - point.y)
        case .top: rect = CGRect(x: original.minX, y: point.y, width: original.width, height: original.maxY - point.y)
        case .topRight: rect = CGRect(x: original.minX, y: point.y, width: point.x - original.minX, height: original.maxY - point.y)
        case .right: rect = CGRect(x: original.minX, y: original.minY, width: point.x - original.minX, height: original.height)
        case .bottomRight: rect = CGRect(x: original.minX, y: original.minY, width: point.x - original.minX, height: point.y - original.minY)
        case .bottom: rect = CGRect(x: original.minX, y: original.minY, width: original.width, height: point.y - original.minY)
        case .bottomLeft: rect = CGRect(x: point.x, y: original.minY, width: original.maxX - point.x, height: point.y - original.minY)
        case .left: rect = CGRect(x: point.x, y: original.minY, width: original.maxX - point.x, height: original.height)
        }

        if mirror {
            // Grow symmetrically around the original centre.
            let center = CGPoint(x: original.midX, y: original.midY)
            let half = CGSize(width: abs(rect.width) / 2, height: abs(rect.height) / 2)
            rect = CGRect(x: center.x - half.width, y: center.y - half.height, width: half.width * 2, height: half.height * 2)
        }

        if keepAspect {
            let w = max(abs(rect.width), abs(rect.height) * aspect)
            let h = w / aspect
            rect.size = CGSize(width: w, height: h)
        }

        rect = rect.standardized
        if rect.width < minimumSide { rect.size.width = minimumSide }
        if rect.height < minimumSide { rect.size.height = minimumSide }
        return clampToCanvas(rect)
    }

    // MARK: - Keyboard (flameshot bindings)

    /// Returns true when the event was consumed.
    func handleKey(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, !event.isARepeat else { return false }
        let flags = event.modifierFlags.intersection([.command, .control, .shift, .option])
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

        // Text editing takes over the keyboard, except for commit/cancel.
        if pendingText != nil {
            if event.keyCode == 53 { cancelPendingText(); return true }
            if event.keyCode == 36 { commitPendingText(); return true }
            return false
        }

        switch event.keyCode {
        case 53: // Escape
            onCancel?()
            return true
        case 36: // Return: flameshot uploads; here it copies like double-click.
            commit(.copy)
            return true
        case 123, 124, 125, 126: // Arrow keys
            let step: CGFloat = 1
            var dx: CGFloat = 0
            var dy: CGFloat = 0
            if event.keyCode == 123 { dx = -step }
            if event.keyCode == 124 { dx = step }
            if event.keyCode == 125 { dy = step } // top-left origin: down grows y
            if event.keyCode == 126 { dy = -step }
            nudgeSelection(dx: dx, dy: dy, resize: flags.contains(.shift))
            return true
        default:
            break
        }

        if flags.contains(.command) || flags.contains(.control) {
            switch chars {
            case "c": commit(.copy); return true
            case "s": commit(.save); return true
            case "z": flags.contains(.shift) ? redo() : undo(); return true
            case "m": activeTool = .selection; return true
            case "a": selectAll(); return true
            case "o": commit(.save); return true
            case "q": onCancel?(); return true
            default: return false
            }
        }

        if flags.isEmpty {
            switch chars {
            case " ": showSidePanel.toggle(); return true
            case "s": activeTool = .selection; return true
            case "p": activateDrawing(.pencil); return true
            case "d": activateDrawing(.line); return true
            case "a": activateDrawing(.arrow); return true
            case "r": activateDrawing(.rectangle); return true
            case "c": activateDrawing(.circle); return true
            case "m": activateDrawing(.marker); return true
            case "b": activateDrawing(.pixelate); return true
            case "t": activateDrawing(.text); return true
            case "g": return false
            default: return false
            }
        }

        return false
    }

    private func activateDrawing(_ tool: FlameshotTool) {
        activeTool = tool
        showSidePanel = true
    }

    // MARK: - Commit

    func commit(_ action: FlameshotCommitAction) {
        commitPendingText()
        guard let rect = selection,
              rect.width >= minimumSide, rect.height >= minimumSide else { return }
        // Annotations are stored selection-local already, so they can be
        // handed to the exporter unchanged.
        onAccept?(rect, annotations, action)
    }

    /// The selection locks once annotations exist, mirroring flameshot, so
    /// selection-local strokes keep lining up with the pixels beneath them.
    var isSelectionLocked: Bool { !annotations.isEmpty }

    // MARK: - Geometry helpers

    private var canvasRect: CGRect {
        CGRect(origin: .zero, size: canvasSize)
    }

    private func clampToCanvas(_ rect: CGRect) -> CGRect {
        var rect = rect
        if rect.width > canvasSize.width { rect.size.width = canvasSize.width }
        if rect.height > canvasSize.height { rect.size.height = canvasSize.height }
        if rect.minX < 0 { rect.origin.x = 0 }
        if rect.minY < 0 { rect.origin.y = 0 }
        if rect.maxX > canvasSize.width { rect.origin.x = canvasSize.width - rect.width }
        if rect.maxY > canvasSize.height { rect.origin.y = canvasSize.height - rect.height }
        return rect
    }

    static func rectangle(from start: CGPoint, to end: CGPoint, clampedTo bounds: CGRect?) -> CGRect {
        var rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
        if let bounds {
            rect = rect.intersection(bounds)
        }
        return rect
    }
}
