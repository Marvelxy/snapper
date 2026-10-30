import AppKit
import Foundation

/// Installs a downloaded update: mounts the DMG and swaps the running bundle
/// for the new one. A process cannot replace the app it is running from, so the
/// swap happens in a small shell helper that waits for Snapper to quit.
enum UpdateInstaller {
    enum Outcome {
        /// The helper takes over as soon as the app quits; call `NSApp.terminate`.
        case installing
        /// The image was opened so the user can drag the app across themselves.
        case manualInstall
    }

    enum InstallError: LocalizedError {
        case mountFailed
        case noAppInImage
        case wrongApp

        var errorDescription: String? {
            switch self {
            case .mountFailed:
                "Couldn't open the downloaded disk image."
            case .noAppInImage:
                "The downloaded disk image doesn't contain Snapper."
            case .wrongApp:
                "The downloaded disk image contains a different app."
            }
        }
    }

    @discardableResult
    static func install(dmg: URL) throws -> Outcome {
        // Translocation, a mounted DMG or an unwritable folder: hand the image
        // to Finder instead of guessing where the app should live.
        guard let bundle = installableBundle else {
            NSWorkspace.shared.open(dmg)
            return .manualInstall
        }

        let mountPoint = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapperMount-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)

        let attach = run(
            "/usr/bin/hdiutil",
            ["attach", "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", mountPoint.path, dmg.path]
        )
        guard attach == 0 else {
            try? FileManager.default.removeItem(at: mountPoint)
            throw InstallError.mountFailed
        }

        guard let newBundle = try FileManager.default
            .contentsOfDirectory(at: mountPoint, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" }) else {
            detach(mountPoint)
            throw InstallError.noAppInImage
        }

        let newID = Bundle(url: newBundle)?.bundleIdentifier
        guard newID == Bundle.main.bundleIdentifier else {
            detach(mountPoint)
            throw InstallError.wrongApp
        }

        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        #!/bin/sh
        # Wait for the running copy to exit, then swap the bundle in place.
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        rm -rf '\(bundle.path)' || exit 1
        ditto '\(newBundle.path)' '\(bundle.path)' || exit 1
        xattr -dr com.apple.quarantine '\(bundle.path)' 2>/dev/null
        hdiutil detach '\(mountPoint.path)' -force >/dev/null 2>&1
        open '\(bundle.path)'
        """

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapper-update-\(UUID().uuidString).sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )

        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = [scriptURL.path]
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        try helper.run()

        return .installing
    }

    /// The bundle to replace, or nil when it can't be written to.
    private static var installableBundle: URL? {
        let bundle = Bundle.main.bundleURL
        guard bundle.pathExtension == "app" else { return nil }

        let path = bundle.path
        // Launched from a DMG (possibly translocated) — read-only either way.
        guard !path.hasPrefix("/Volumes/"), !path.contains("/AppTranslocation/") else {
            return nil
        }
        // Both the folder and the old bundle have to be replaceable, otherwise
        // the swap script would half-finish after the app has already quit.
        let fileManager = FileManager.default
        guard fileManager.isWritableFile(atPath: bundle.deletingLastPathComponent().path),
              fileManager.isWritableFile(atPath: path) else {
            return nil
        }
        return bundle
    }

    private static func detach(_ mountPoint: URL) {
        _ = run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"])
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return -1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
