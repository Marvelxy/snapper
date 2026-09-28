import AppKit
import SwiftUI

/// Snapper-style capture editor: dimmed canvas, crosshair + magnifier while
/// selecting, a persistent 8-handle selection, in-place annotations and an
/// attached toolbar. Fills its host window exactly so selection rectangles in
/// top-left SwiftUI points map onto capture pixels by a single scale factor.
struct RegionSelectorView: View {
    let image: NSImage
    @ObservedObject var session: SnapperSession
    @FocusState private var textFieldFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack {
                canvasBackground(size: size)

                if let selection = session.selection {
                    dimming(except: selection, in: size)
                    annotationLayer(in: selection)
                    selectionChrome(for: selection, in: size)
                    dimensionBadge(for: selection, in: size)
                    editorChrome(for: selection, in: size)
                } else {
                    creatingChrome(in: size)
                }
            }
            .frame(width: size.width, height: size.height)
            .onAppear { session.canvasSize = size }
            .onChange(of: size) { _, newSize in session.canvasSize = newSize }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    session.hover(at: location)
                case .ended:
                    session.hoverEnded()
                }
            }
        }
    }

    // MARK: - Gestures

    /// The capture sits behind every overlay, so toolbar buttons and the text
    /// field stay clickable while everywhere else starts selections, moves,
    /// resizes and strokes. Double-click commits.
    private func canvasBackground(size: CGSize) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    session.commit(.copy)
                }
            )
            .gesture(dragGesture)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                // The first change event carries the press anchor.
                if !session.isDrawing {
                    session.pressBegan(at: value.startLocation)
                }
                session.pressChanged(to: value.location)
            }
            .onEnded { value in
                // A press without movement never fires onChanged.
                if !session.isDrawing {
                    session.pressBegan(at: value.startLocation)
                    session.pressChanged(to: value.location)
                }
                session.pressEnded(at: value.location)
            }
    }

    // MARK: - Dimming

    /// Four opaque bands around the selection, punching a clean hole without
    /// relying on blend modes.
    private func dimming(except rect: CGRect, in size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let bands = [
                CGRect(x: 0, y: 0, width: canvasSize.width, height: rect.minY),
                CGRect(
                    x: 0,
                    y: rect.maxY,
                    width: canvasSize.width,
                    height: canvasSize.height - rect.maxY
                ),
                CGRect(x: 0, y: rect.minY, width: rect.minX, height: rect.height),
                CGRect(
                    x: rect.maxX,
                    y: rect.minY,
                    width: canvasSize.width - rect.maxX,
                    height: rect.height
                )
            ]

            for band in bands where band.width > 0 && band.height > 0 {
                context.fill(Path(band), with: .color(.black.opacity(0.55)))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    // MARK: - Creating state (no selection yet)

    private func creatingChrome(in size: CGSize) -> some View {
        ZStack {
            // Snapper's full-screen crosshair lines follow the pointer.
            if session.isHovering {
                Path { path in
                    path.move(to: CGPoint(x: session.cursor.x, y: 0))
                    path.addLine(to: CGPoint(x: session.cursor.x, y: size.height))
                    path.move(to: CGPoint(x: 0, y: session.cursor.y))
                    path.addLine(to: CGPoint(x: size.width, y: session.cursor.y))
                }
                .stroke(Color.white.opacity(0.7), lineWidth: 1)
                .allowsHitTesting(false)

                magnifier(in: size)
            }

            hint
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private var hint: some View {
        VStack(spacing: 8) {
            Text("Drag to select a region")
                .font(.system(size: 15, weight: .medium))
            Text("Double-click or ⏎ copies · Esc quits · Space shows colors")
                .font(.system(size: 12))
                .opacity(0.8)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .allowsHitTesting(false)
    }

    /// Snapper's loupe: a zoomed view of the pixels under the cursor.
    private func magnifier(in size: CGSize) -> some View {
        let diameter: CGFloat = 120
        let radius = diameter / 2
        let zoom: CGFloat = 6
        let offset = CGPoint(
            x: session.cursor.x + 110,
            y: session.cursor.y - 110
        )
        let clamped = CGPoint(
            x: min(max(offset.x, radius + 4), size.width - radius - 4),
            y: min(max(offset.y, radius + 4), size.height - radius - 4)
        )

        return ZStack {
            Image(nsImage: image)
                .resizable()
                .interpolation(.none)
                .frame(width: size.width, height: size.height)
                .scaleEffect(zoom, anchor: .topLeading)
                .offset(
                    x: radius - session.cursor.x * zoom,
                    y: radius - session.cursor.y * zoom
                )
                .frame(width: diameter, height: diameter)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                .overlay(
                    Path { path in
                        path.move(to: CGPoint(x: radius - 8, y: radius))
                        path.addLine(to: CGPoint(x: radius + 8, y: radius))
                        path.move(to: CGPoint(x: radius, y: radius - 8))
                        path.addLine(to: CGPoint(x: radius, y: radius + 8))
                    }
                    .stroke(Color.red.opacity(0.9), lineWidth: 1)
                )
        }
        .position(x: clamped.x, y: clamped.y)
        .allowsHitTesting(false)
    }

    // MARK: - Selection chrome

    private func selectionChrome(for rect: CGRect, in size: CGSize) -> some View {
        _ = size
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .strokeBorder(.white, lineWidth: 1.5)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .shadow(color: .black.opacity(0.5), radius: 1)

            ForEach(SnapperHandle.allCases, id: \.self) { handle in
                let center = session.handlePoint(handle, in: rect)
                Rectangle()
                    .fill(.white)
                    .frame(width: 10, height: 10)
                    .overlay(Rectangle().strokeBorder(.black.opacity(0.7), lineWidth: 1))
                    .position(x: center.x, y: center.y)
            }
        }
        // Full-canvas frame so offsets/positions share the canvas space.
        .frame(
            width: session.canvasSize.width,
            height: session.canvasSize.height,
            alignment: .topLeading
        )
        .allowsHitTesting(false)
    }

    private func dimensionBadge(for rect: CGRect, in size: CGSize) -> some View {
        let label = String(
            format: "%d × %d",
            Int((rect.width * session.pixelScale).rounded()),
            Int((rect.height * session.pixelScale).rounded())
        )

        // Snapper pins the size readout above the selection's top edge,
        // falling back inside when there is no room.
        let y = rect.minY - 22 >= 12 ? rect.minY - 13 : rect.minY + 13
        let x = min(max(rect.midX, 60), size.width - 60)

        return Text(label)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color(hex: "#270032").opacity(0.9), in: RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color(hex: "#740096"), lineWidth: 1)
            )
            .fixedSize()
            .position(x: x, y: y)
            .allowsHitTesting(false)
    }

    // MARK: - Annotations

    private func annotationLayer(in selection: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(session.annotations) { annotation in
                annotationView(annotation, offset: CGPoint(x: selection.minX, y: selection.minY))
            }

            // Live stroke preview.
            if session.liveStroke.count >= 1 {
                strokePath(points: session.liveStroke, offset: CGPoint(x: selection.minX, y: selection.minY))
                    .stroke(
                        session.swatch.color.opacity(session.activeTool == .marker ? 0.4 : 1),
                        style: StrokeStyle(lineWidth: previewWidth, lineCap: .round, lineJoin: .round)
                    )
            }

            // Live shape preview.
            if let preview = session.dragPreview {
                shapePreview(preview)
            }

            // Live pixelate preview: a blurred patch over the region.
            if let pixelRect = session.livePixelateRect {
                pixelatePreview(rect: pixelRect, offset: CGPoint(x: selection.minX, y: selection.minY))
            }
        }
        // Full-canvas frame so every annotation shares one coordinate space.
        .frame(
            width: session.canvasSize.width,
            height: session.canvasSize.height,
            alignment: .topLeading
        )
        .allowsHitTesting(false)
        // Nothing drawn can spill outside the selection.
        .clipShape(SelectionClip(rect: selection))
    }

    private var previewWidth: CGFloat {
        session.activeTool == .marker ? session.thickness.rawValue * 3 : session.thickness.rawValue
    }

    private func annotationView(_ annotation: SnapperAnnotation, offset: CGPoint) -> some View {
        let color = Color(hex: annotation.hex)
        switch annotation.kind {
        case .stroke(let points, let opacity):
            return AnyView(
                strokePath(points: points, offset: offset)
                    .stroke(color.opacity(opacity), style: StrokeStyle(lineWidth: annotation.width, lineCap: .round, lineJoin: .round))
            )
        case .line(let from, let to):
            return AnyView(
                Path { path in
                    path.move(to: from + offset)
                    path.addLine(to: to + offset)
                }
                .stroke(color, style: StrokeStyle(lineWidth: annotation.width, lineCap: .round))
            )
        case .arrow(let from, let to):
            return AnyView(
                arrowPath(from: from + offset, to: to + offset, width: annotation.width)
                    .fill(color)
            )
        case .rectangle(let rect):
            return AnyView(
                Rectangle()
                    .strokeBorder(color, lineWidth: annotation.width)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX + offset.x, y: rect.minY + offset.y)
            )
        case .ellipse(let rect):
            return AnyView(
                Ellipse()
                    .strokeBorder(color, lineWidth: annotation.width)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX + offset.x, y: rect.minY + offset.y)
            )
        case .pixelate(let rect):
            return AnyView(pixelatePreview(rect: rect, offset: offset))
        case .text(let position, let string, let fontSize):
            return AnyView(
                Text(string)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(color)
                    .fixedSize()
                    .offset(x: position.x + offset.x, y: position.y + offset.y)
            )
        }
    }

    private func strokePath(points: [CGPoint], offset: CGPoint) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first + offset)
            for point in points.dropFirst() {
                path.addLine(to: point + offset)
            }
            // A single tap still leaves a visible dot.
            if points.count == 1 {
                path.addLine(to: CGPoint(x: first.x + offset.x + 0.5, y: first.y + offset.y + 0.5))
            }
        }
    }

    private func shapePreview(_ preview: SnapperSession.DrawPreview) -> some View {
        let color = session.swatch.color
        let width = session.thickness.rawValue
        switch preview.kind {
        case .line:
            return AnyView(
                Path { path in
                    path.move(to: preview.from)
                    path.addLine(to: preview.to)
                }
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
            )
        case .arrow:
            return AnyView(arrowPath(from: preview.from, to: preview.to, width: width).fill(color))
        case .rectangle:
            let rect = SnapperSession.rectangle(from: preview.from, to: preview.to, clampedTo: nil)
            return AnyView(
                Rectangle()
                    .strokeBorder(color, lineWidth: width)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            )
        case .ellipse:
            let rect = SnapperSession.rectangle(from: preview.from, to: preview.to, clampedTo: nil)
            return AnyView(
                Ellipse()
                    .strokeBorder(color, lineWidth: width)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            )
        }
    }

    private func pixelatePreview(rect: CGRect, offset: CGPoint) -> some View {
        let origin = CGPoint(x: rect.minX + offset.x, y: rect.minY + offset.y)
        let center = CGPoint(x: origin.x + rect.width / 2, y: origin.y + rect.height / 2)
        let canvas = session.canvasSize
        return ZStack {
            Image(nsImage: image)
                .resizable()
                .interpolation(.medium)
                .frame(width: canvas.width, height: canvas.height)
                .blur(radius: 14)
                .position(x: canvas.width / 2, y: canvas.height / 2)
                .mask(
                    Rectangle()
                        .frame(width: rect.width, height: rect.height)
                        .position(x: center.x, y: center.y)
                )
            Rectangle()
                .strokeBorder(.white.opacity(0.6), lineWidth: 1)
                .frame(width: rect.width, height: rect.height)
                .position(x: center.x, y: center.y)
        }
    }

    private func arrowPath(from: CGPoint, to: CGPoint, width: CGFloat) -> Path {
        Path { path in
            let direction = CGPoint(x: to.x - from.x, y: to.y - from.y)
            let length = hypot(direction.x, direction.y)
            guard length > 2 else { return }
            let unit = CGPoint(x: direction.x / length, y: direction.y / length)
            let normal = CGPoint(x: -unit.y, y: unit.x)
            let half = max(1.5, width / 2)
            let headLength = max(12, width * 3)
            let headHalf = max(6, width * 2)
            let base = CGPoint(x: to.x - unit.x * headLength, y: to.y - unit.y * headLength)

            path.move(to: CGPoint(x: from.x + normal.x * half, y: from.y + normal.y * half))
            path.addLine(to: CGPoint(x: base.x + normal.x * half, y: base.y + normal.y * half))
            path.addLine(to: CGPoint(x: base.x + normal.x * headHalf, y: base.y + normal.y * headHalf))
            path.addLine(to: to)
            path.addLine(to: CGPoint(x: base.x - normal.x * headHalf, y: base.y - normal.y * headHalf))
            path.addLine(to: CGPoint(x: base.x - normal.x * half, y: base.y - normal.y * half))
            path.addLine(to: CGPoint(x: from.x - normal.x * half, y: from.y - normal.y * half))
            path.closeSubpath()
        }
    }

    // MARK: - Toolbar + text editor

    private func editorChrome(for selection: CGRect, in size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            toolbarCluster(for: selection, in: size)

            if session.showSidePanel {
                sidePanelCluster(for: selection, in: size)
            }

            if let pending = session.pendingText {
                TextField("Type to annotate", text: binding(for: pending))
                    .textFieldStyle(.plain)
                    .font(.system(size: session.thickness.fontSize, weight: .semibold))
                    .foregroundStyle(session.swatch.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(session.swatch.color, lineWidth: 1)
                    )
                    .frame(width: 220)
                    .offset(x: selection.minX + pending.position.x, y: selection.minY + pending.position.y)
                    .focused($textFieldFocused)
                    .onAppear { textFieldFocused = true }
                    .onSubmit { session.commitPendingText() }
            }
        }
        // Full-canvas frame so the toolbar docks at absolute canvas coords.
        .frame(
            width: session.canvasSize.width,
            height: session.canvasSize.height,
            alignment: .topLeading
        )
    }

    private func binding(for pending: SnapperSession.PendingText) -> Binding<String> {
        Binding(
            get: { session.pendingText?.string ?? "" },
            set: { session.pendingText?.string = $0 }
        )
    }

    /// Snapper docks the toolbar under the selection, flipping above it when
    /// there is no room.
    private func toolbarCluster(for selection: CGRect, in size: CGSize) -> some View {
        let toolbarSize = CGSize(width: 560, height: 40)

        let belowY = selection.maxY + 10 + toolbarSize.height / 2
        let aboveY = selection.minY - 10 - toolbarSize.height / 2
        let fitsBelow = belowY + toolbarSize.height / 2 <= size.height - 8
        let fitsAbove = aboveY - toolbarSize.height / 2 >= 8
        let centerY: CGFloat
        if fitsBelow {
            centerY = belowY
        } else if fitsAbove {
            centerY = aboveY
        } else {
            centerY = min(max(selection.maxY - toolbarSize.height, toolbarSize.height / 2 + 8), size.height - toolbarSize.height / 2 - 8)
        }

        // Deliberately conservative: guarantees the real (narrower) toolbar
        // stays fully on screen.
        let centerX = min(
            max(selection.midX, toolbarSize.width / 2 + 8),
            size.width - toolbarSize.width / 2 - 8
        )

        return SnapperToolbarView(session: session)
            .position(x: centerX, y: centerY)
    }

    /// The color + thickness bar docks to the left side of the selection,
    /// mirroring how the toolbar sits at the bottom. Falls back to the right
    /// side, then inside the selection, when space is tight.
    private func sidePanelCluster(for selection: CGRect, in size: CGSize) -> some View {
        let panelSize = CGSize(width: 60, height: 330)

        let centerY = min(
            max(selection.midY, panelSize.height / 2 + 8),
            size.height - panelSize.height / 2 - 8
        )

        let leftX = selection.minX - 8 - panelSize.width / 2
        let rightX = selection.maxX + 8 + panelSize.width / 2
        let centerX: CGFloat
        if leftX - panelSize.width / 2 >= 8 {
            centerX = leftX
        } else if rightX + panelSize.width / 2 <= size.width - 8 {
            centerX = rightX
        } else {
            centerX = min(
                max(selection.midX, panelSize.width / 2 + 8),
                size.width - panelSize.width / 2 - 8
            )
        }

        return SnapperSidePanelView(session: session)
            .position(x: centerX, y: centerY)
    }
}

// MARK: - Helpers

/// Clips the annotation layer to the selection, in full-canvas coordinates.
private struct SelectionClip: Shape {
    let rect: CGRect

    func path(in _: CGRect) -> Path {
        Path(rect)
    }
}

private extension CGPoint {
    static func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }
}
