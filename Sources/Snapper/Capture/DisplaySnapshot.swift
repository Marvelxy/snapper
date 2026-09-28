import AppKit
import CoreGraphics
import ScreenCaptureKit

/// A full-resolution capture of one display, plus everything needed to map
/// screen-space rectangles back onto the captured pixels.
struct DisplaySnapshot {
    let displayID: CGDirectDisplayID
    let screen: NSScreen
    let image: CGImage

    var frameWidthInPoints: CGFloat {
        screen.frame.width
    }

    var frameHeightInPoints: CGFloat {
        screen.frame.height
    }

    /// Native capture pixels per point. Retina displays yield 2.0; if the capture
    /// was capped at `maxPixelDimension` this will be lower than the real scale.
    var pixelScale: CGFloat {
        guard frameWidthInPoints > 0 else { return 1 }
        return CGFloat(image.width) / frameWidthInPoints
    }

    var nativeImage: NSImage {
        NSImage(
            cgImage: image,
            size: NSSize(width: frameWidthInPoints, height: frameHeightInPoints)
        )
    }
}

/// A window that is eligible to be captured on its own.
struct CapturableWindow: Identifiable, Hashable {
    let id: CGWindowID
    let title: String
    let applicationName: String
    let processIdentifier: pid_t

    init(window: SCWindow) {
        let application = window.owningApplication
        id = window.windowID
        title = window.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled Window"
        applicationName = application?.applicationName ?? "Unknown App"
        processIdentifier = application?.processID ?? 0
    }

    /// Falls back to the generic app icon while the process is not resolvable.
    var icon: NSImage {
        NSRunningApplication(processIdentifier: processIdentifier)?.icon
            ?? NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)!
    }
}
