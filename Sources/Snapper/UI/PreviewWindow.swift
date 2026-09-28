import AppKit
import SwiftUI

/// Transient card showing the capture that was just taken, with reveal/save actions.
final class PreviewWindow: FloatingPanel {
    private static let cardWidth: CGFloat = 420
    private static let maxImageHeight: CGFloat = 280
    private static let minImageHeight: CGFloat = 80

    private var dismissTask: Task<Void, Never>?

    func present(
        image: NSImage,
        fileURL: URL?,
        autoDismissAfter interval: TimeInterval = 8,
        onSaveAs: @escaping () -> Void,
        onReveal: @escaping () -> Void,
        onDiscard: @escaping () -> Void
    ) {
        contentView = NSHostingView(
            rootView: PreviewView(
                image: image,
                fileName: fileURL?.lastPathComponent,
                onSave: onSaveAs,
                onReveal: onReveal,
                onClose: onDiscard
            )
        )

        let size = Self.cardSize(for: image)
        presentCentered(size: size)
        setFrameOrigin(Self.bottomRightOrigin(for: size))

        scheduleDismiss(after: interval)
    }

    override func close() {
        dismissTask?.cancel()
        dismissTask = nil
        super.close()
    }

    // MARK: - Layout

    private static func cardSize(for image: NSImage) -> NSSize {
        let aspect = image.size.height / max(image.size.width, 1)
        let imageHeight = min(
            max(cardWidth / max(aspect, 0.01), minImageHeight),
            maxImageHeight
        )

        // 20pt of image padding, 1pt divider, 40pt action bar.
        return NSSize(width: cardWidth, height: imageHeight + 61)
    }

    private static func bottomRightOrigin(for size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]

        let margin: CGFloat = 16
        return NSPoint(
            x: screen.frame.maxX - size.width - margin,
            y: screen.frame.minY + margin
        )
    }

    // MARK: - Auto dismiss

    private func scheduleDismiss(after interval: TimeInterval) {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.close()
        }
    }
}
