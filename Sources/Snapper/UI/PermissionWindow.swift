import AppKit
import SwiftUI

/// Explains the Screen Recording requirement and keeps the pending action queued
/// until the user grants access in System Settings (or dismisses the prompt).
final class PermissionWindow: FloatingPanel {
    private var pollTask: Task<Void, Never>?

    func present(
        onGranted: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        contentView = NSHostingView(
            rootView: PermissionView(
                onOpenSettings: { [weak self] in
                    self?.openSettingsAndPoll(onGranted: onGranted)
                },
                onCancel: { [weak self] in
                    self?.close()
                    onCancel()
                }
            )
        )

        presentCentered(size: NSSize(width: 420, height: 250))
        // Borderless card: let the user drag it aside while granting access.
        isMovableByWindowBackground = true
    }

    override func close() {
        pollTask?.cancel()
        pollTask = nil
        super.close()
    }

    /// TCC grants land asynchronously while Snapper is backgrounded, so poll
    /// instead of checking once and giving up.
    private func openSettingsAndPoll(onGranted: @escaping () -> Void) {
        ScreenRecordingPermission.openSystemSettings()
        close()

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard self != nil, !Task.isCancelled else { return }

                if ScreenRecordingPermission.isGranted {
                    onGranted()
                    return
                }
            }
        }
    }
}
