import AppKit
import CoreGraphics

/// Wraps the macOS Screen Recording (TCC) privacy gate that every capture path must clear.
enum ScreenRecordingPermission {
    private static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )!

    /// `true` when Snapper is already listed as an authorised screen recorder.
    static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Triggers the one-time system prompt. Returns the state *after* the prompt is shown.
    @discardableResult
    static func request() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func openSystemSettings() {
        NSWorkspace.shared.open(settingsURL)
    }
}
