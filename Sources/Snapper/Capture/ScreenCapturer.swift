import AppKit
import CoreGraphics
import ScreenCaptureKit

/// Thin async wrapper over ScreenCaptureKit's one-shot screenshot API.
enum ScreenCapturer {
    /// Upper bound on the long edge of a display capture, in pixels. Guards against
    /// absurd memory use on very high resolution displays while staying above the
    /// native resolution of every shipping Mac.
    private static let maxPixelDimension = 8192

    // MARK: - Content

    static func shareableContent() async throws -> SCShareableContent {
        do {
            return try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
        } catch {
            // ScreenCaptureKit reports permission failures as an opaque error code.
            if !ScreenRecordingPermission.isGranted {
                throw ScreenCaptureError.permissionNotGranted
            }
            throw error
        }
    }

    // MARK: - Displays

    /// The display the pointer is currently over, falling back to the main display.
    static func displayUnderPointer(in content: SCShareableContent) throws -> SCDisplay {
        let mouseLocation = NSEvent.mouseLocation
        let screens = NSScreen.screens

        let targetScreen = screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        } ?? NSScreen.main

        if let targetScreen,
           let number = targetScreen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
           ] as? NSNumber {
            let displayID = CGDirectDisplayID(number.uint32Value)
            if let match = content.displays.first(where: { $0.displayID == displayID }) {
                return match
            }
        }

        guard let fallback = content.displays.first else {
            throw ScreenCaptureError.noDisplays
        }
        return fallback
    }

    static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber else { return false }
            return CGDirectDisplayID(number.uint32Value) == displayID
        }
    }

    /// Captures an entire display at full backing-store resolution
    /// (capped at `maxPixelDimension`).
    static func captureDisplay(
        _ display: SCDisplay,
        excludingWindows excludedWindows: [SCWindow] = []
    ) async throws -> DisplaySnapshot {
        guard display.width > 0, display.height > 0 else {
            throw ScreenCaptureError.displayNotFound
        }
        guard let screen = screen(for: display.displayID) else {
            throw ScreenCaptureError.displayNotFound
        }

        // Request full backing-store resolution as a floor: if the display
        // buffer reports fewer pixels than the screen's backing store (scaled
        // modes report points), capturing at the buffer size would upscale
        // and blur. Never request fewer pixels than the buffer offers.
        let backing = max(screen.backingScaleFactor, 1)
        let rawWidth = max(
            CGFloat(display.width),
            (screen.frame.width * backing).rounded()
        )
        let rawHeight = max(
            CGFloat(display.height),
            (screen.frame.height * backing).rounded()
        )
        let scale = min(1, CGFloat(maxPixelDimension) / max(rawWidth, rawHeight))

        let configuration = SCStreamConfiguration()
        configuration.width = Int((rawWidth * scale).rounded())
        configuration.height = Int((rawHeight * scale).rounded())
        configuration.showsCursor = false
        configuration.scalesToFit = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA

        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
        let image = try await captureImage(filter: filter, configuration: configuration)

        return DisplaySnapshot(displayID: display.displayID, screen: screen, image: image)
    }

    // MARK: - Windows

    static func capturableWindows(from content: SCShareableContent) -> [CapturableWindow] {
        let ownBundleIdentifier = Bundle.main.bundleIdentifier

        return content.windows
            .filter { window in
                guard window.isOnScreen else { return false }
                // Layer 0 is the normal application window layer; skip docks,
                // status items, tooltips and the like.
                guard window.windowLayer == 0 else { return false }
                guard let application = window.owningApplication else { return false }
                guard application.bundleIdentifier != ownBundleIdentifier else { return false }
                // SCRunningApplication exposes no "is system app" flag, so match
                // on Apple's own bundle identifiers.
                guard !application.bundleIdentifier.hasPrefix("com.apple.") else { return false }
                guard window.frame.width >= 120, window.frame.height >= 80 else { return false }
                return true
            }
            .sorted { lhs, rhs in
                let leftFront = lhs.frame.maxY
                let rightFront = rhs.frame.maxY
                if abs(leftFront - rightFront) > 1 { return leftFront > rightFront }
                return (lhs.owningApplication?.applicationName ?? "")
                    < (rhs.owningApplication?.applicationName ?? "")
            }
            .map(CapturableWindow.init(window:))
    }

    static func captureWindow(_ window: SCWindow) async throws -> CGImage {
        let configuration = SCStreamConfiguration()
        configuration.showsCursor = false
        // Leaving width/height at zero lets ScreenCaptureKit pick the window's
        // native pixel size, which is what we want for a 1:1 capture.
        configuration.scalesToFit = true
        configuration.pixelFormat = kCVPixelFormatType_32BGRA

        let filter = SCContentFilter(desktopIndependentWindow: window)
        return try await captureImage(filter: filter, configuration: configuration)
    }

    // MARK: - Core

    private static func captureImage(
        filter: SCContentFilter,
        configuration: SCStreamConfiguration
    ) async throws -> CGImage {
        if !ScreenRecordingPermission.isGranted {
            throw ScreenCaptureError.permissionNotGranted
        }

        return try await withCheckedThrowingContinuation { continuation in
            SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            ) { image, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: ScreenCaptureError.emptyResult)
                }
            }
        }
    }
}
