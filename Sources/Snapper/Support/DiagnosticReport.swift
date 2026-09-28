import AppKit
import Darwin
import ScreenCaptureKit
import UniformTypeIdentifiers

/// Non-GUI self test, reachable via `Snapper --diagnose`.
///
/// Exercises the same ScreenCaptureKit, cropping, encoding and persistence code
/// the menu bar actions use, and prints what happened. Used to verify a build on a
/// real machine, where capture cannot be covered by unit tests because the result
/// depends on TCC approval.
enum DiagnosticReport {
    static func run() async {
        print("Snapper diagnostics")
        print("------------------")
        printLine("bundle identifier", Bundle.main.bundleIdentifier ?? "<none>")
        printLine("executable arch", currentArchitecture())
        printLine("process arch", ProcessInfo.processInfo.processorCount > 0 ? hostArchitecture() : "unknown")
        printLine("macOS", ProcessInfo.processInfo.operatingSystemVersionString)
        printLine("screen recording", ScreenRecordingPermission.isGranted ? "GRANTED" : "NOT GRANTED")

        guard ScreenRecordingPermission.isGranted else {
            print("")
            print("Capture skipped. Grant access in System Settings >")
            print("Privacy & Security > Screen & System Audio Recording, then relaunch.")
            exit(1)
        }

        do {
            let content = try await ScreenCapturer.shareableContent()
            printLine("displays", "\(content.displays.count)")
            printLine("windows", "\(content.windows.count)")

            let display = try ScreenCapturer.displayUnderPointer(in: content)
            printLine(
                "target display",
                "id=\(display.displayID) \(Int(display.frame.width))x\(Int(display.frame.height))pt \(display.width)x\(display.height)px"
            )

            // Window capture uses a different SCContentFilter constructor, so it
            // gets its own end-to-end check.
            let candidates = ScreenCapturer.capturableWindows(from: content)
            if let target = candidates.first,
               let match = content.windows.first(where: { $0.windowID == target.id }) {
                let windowImage = try await ScreenCapturer.captureWindow(match)
                printLine(
                    "window capture",
                    "\(target.applicationName): \(windowImage.width)x\(windowImage.height)px"
                )
            } else {
                printLine("window capture", "no eligible window")
            }

            let snapshot = try await ScreenCapturer.captureDisplay(display)
            printLine("full capture", "\(snapshot.image.width)x\(snapshot.image.height)px scale=\(String(format: "%.2f", snapshot.pixelScale))")

            // A crop taken from the middle of the screen proves the region maths
            // lines up with what the overlay hands back.
            let cropRect = CGRect(
                x: Double(snapshot.image.width) * 0.25,
                y: Double(snapshot.image.height) * 0.25,
                width: Double(snapshot.image.width) * 0.5,
                height: Double(snapshot.image.height) * 0.5
            )

            guard let crop = ImageUtilities.cropped(snapshot.image, to: cropRect) else {
                printLine("region crop", "FAILED")
                exit(2)
            }
            printLine("region crop", "\(crop.width)x\(crop.height)px")

            let url = try ScreenshotStore.save(crop)
            printLine("written", url.path)

            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
            printLine("file size", "\(values.fileSize ?? 0) bytes")
            printLine("file type", values.contentType?.identifier ?? UTType.png.identifier)

            print("")
            print("All checks passed.")
        } catch {
            print("")
            print("FAILED: \(error.localizedDescription)")
            if let localized = error as? LocalizedError,
               let suggestion = localized.recoverySuggestion {
                print(suggestion)
            }
            exit(2)
        }
    }

    private static func printLine(_ label: String, _ value: String) {
        let padded = label.padding(toLength: 18, withPad: " ", startingAt: 0)
        print("\(padded) \(value)")
    }

    private static func currentArchitecture() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    private static func hostArchitecture() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }
}
