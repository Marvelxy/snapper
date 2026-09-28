import AppKit
import SwiftUI

final class WindowPickerWindow: FloatingPanel {
    static let contentSize = NSSize(width: 360, height: 440)

    func present(
        windows: [CapturableWindow],
        onSelect: @escaping (CapturableWindow) -> Void,
        onCancel: @escaping () -> Void
    ) {
        contentView = NSHostingView(
            rootView: WindowPickerView(
                windows: windows,
                onSelect: onSelect,
                onCancel: onCancel
            )
        )

        presentCentered(size: Self.contentSize)
        // Borderless card: draggable so it never blocks the window you want.
        isMovableByWindowBackground = true
    }
}
