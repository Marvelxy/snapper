import AppKit
import CoreGraphics

/// Persists captures into ~/Pictures/Snapper, creating the folder on demand.
enum ScreenshotStore {
    static var directory: URL {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Pictures", isDirectory: true)

        return pictures.appendingPathComponent("Snapper", isDirectory: true)
    }

    @discardableResult
    static func save(_ image: CGImage, date: Date = Date()) throws -> URL {
        let folder = directory
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )

        let url = uniqueDestination(in: folder, date: date)
        try ImageUtilities.pngData(from: image).write(to: url, options: .atomic)
        return url
    }

    private static func uniqueDestination(in folder: URL, date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"

        let base = "Snapper \(formatter.string(from: date))"
        var candidate = folder.appendingPathComponent("\(base).png")

        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(suffix).png")
            suffix += 1
        }
        return candidate
    }

    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
