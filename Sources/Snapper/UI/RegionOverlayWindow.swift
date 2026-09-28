import AppKit
import SwiftUI

/// `NSHostingView` that paints the crosshair cursor over its whole area, which
/// `NSWindow` alone cannot do (`addCursorRect(_:cursor:)` lives on `NSView`).
final class CrosshairHostingView<Content: View>: NSHostingView<Content> {
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .crosshair)
    }
}

/// Borderless full-display overlay hosting the capture editor.
/// Forwards every key event to the session, since a non-activating panel never
/// gets the SwiftUI responder chain.
final class RegionOverlayWindow: FloatingPanel {
    private var keyMonitor: Any?
    private var session: SnapperSession?

    func present(
        snapshot: DisplaySnapshot,
        onAccept: @escaping (CGRect, [SnapperAnnotation], SnapperCommitAction) -> Void,
        onCancel: @escaping () -> Void
    ) {
        let session = SnapperSession(pixelScale: snapshot.pixelScale)
        self.session = session
        session.onAccept = { [weak self] rect, annotations, action in
            guard self != nil else { return }
            onAccept(rect, annotations, action)
        }
        session.onCancel = { [weak self] in
            guard self != nil else { return }
            onCancel()
        }

        contentView = CrosshairHostingView(
            rootView: RegionSelectorView(
                image: snapshot.nativeImage,
                session: session
            )
        )

        present(covering: snapshot.screen)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak session] event in
            guard let session else { return event }
            // Swallow events the editor consumes so they never reach the
            // system (e.g. arrow-key nudges, tool hotkeys).
            return session.handleKey(event) ? nil : event
        }
    }

    override func close() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        session?.onAccept = nil
        session?.onCancel = nil
        session = nil
        super.close()
    }
}
