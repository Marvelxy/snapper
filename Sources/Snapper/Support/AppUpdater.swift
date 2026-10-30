import AppKit
import Foundation

/// Checks the GitHub releases API for a newer Snapper build and downloads the
/// matching DMG. No dependencies; installing the download is `UpdateInstaller`.
enum AppUpdater {
    private static let latestURL = URL(
        string: "https://api.github.com/repos/Marvelxy/snapper/releases/latest"
    )!

    private struct Release: Decodable {
        var tagName: String
        var htmlURL: URL
        var assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case assets
        }
    }

    private struct Asset: Decodable {
        var name: String
        var downloadURL: URL
        var byteCount: Int

        enum CodingKeys: String, CodingKey {
            case name
            case downloadURL = "browser_download_url"
            case byteCount = "size"
        }
    }

    /// A release asset the app can fetch without a browser.
    struct Download {
        var url: URL
        var fileName: String
        var byteCount: Int
    }

    enum CheckResult {
        case upToDate(current: String)
        case available(version: String, releaseURL: URL, download: Download?)
        case noReleases
        case failed(Error)
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "1.0"
    }

    static func check() async -> CheckResult {
        var request = URLRequest(url: latestURL, timeoutInterval: 20)
        request.setValue("Snapper-macOS", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            // No published release yet — not an error, just nothing to offer.
            if status == 404 {
                return .noReleases
            }
            guard status == 200 else {
                throw URLError(.badServerResponse)
            }

            let release = try JSONDecoder().decode(Release.self, from: data)
            let latest = release.tagName.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            let current = currentVersion

            if compareVersions(latest, current) == .orderedDescending {
                return .available(
                    version: release.tagName,
                    releaseURL: release.htmlURL,
                    download: download(for: release)
                )
            }
            return .upToDate(current: current)
        } catch {
            return .failed(error)
        }
    }

    /// Streams the release DMG into a temp folder, reporting 0...1 progress as it
    /// goes, and returns where it landed.
    static func download(
        _ download: Download,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        var request = URLRequest(url: download.url, timeoutInterval: 120)
        request.setValue("Snapper-macOS", forHTTPHeaderField: "User-Agent")

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapperUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(download.fileName)

        do {
            return try await DownloadTask(destination: destination, progress: progress)
                .start(request)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    /// Picks the build for this Mac, falling back to any DMG in the release.
    private static func download(for release: Release) -> Download? {
        let images = release.assets.filter { $0.name.hasSuffix(".dmg") }
        let preferred = images.first { $0.name.contains(architectureHint) } ?? images.first
        guard let preferred else { return nil }

        return Download(
            url: preferred.downloadURL,
            fileName: preferred.name,
            byteCount: preferred.byteCount
        )
    }

    private static var architectureHint: String {
        #if arch(arm64)
        "Apple-Silicon"
        #else
        "Intel"
        #endif
    }

    /// Numeric dot-separated comparison ("1.0.10" > "1.0.2").
    private static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").compactMap { Int($0) }
        let right = rhs.split(separator: ".").compactMap { Int($0) }
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r {
                return l < r ? .orderedAscending : .orderedDescending
            }
        }
        return .orderedSame
    }
}

/// One download, wired to a delegate session so progress and cancellation come
/// from the download task itself. Owns the session that owns it, so it lives
/// until the transfer finishes.
private final class DownloadTask: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let progress: @Sendable (Double) -> Void
    private let lock = NSLock()

    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession?
    private var moveError: Error?

    init(destination: URL, progress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        self.progress = progress
    }

    func start(_ request: URLRequest) async throws -> URL {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session.downloadTask(with: request)
        setSession(session)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                adopt(continuation)
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            moveError = URLError(.badServerResponse)
            return
        }

        do {
            try FileManager.default.moveItem(at: location, to: destination)
            progress(1)
        } catch {
            moveError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish(with: error ?? moveError)
    }

    // Synchronous helpers keep NSLock out of the async function bodies.
    @discardableResult
    private func setSession(_ session: URLSession?) -> URLSession? {
        lock.lock()
        let previous = self.session
        self.session = session
        lock.unlock()
        return previous
    }

    private func adopt(_ continuation: CheckedContinuation<URL, Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    private func takeContinuation() -> CheckedContinuation<URL, Error>? {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        return continuation
    }

    private func finish(with error: Error?) {
        let continuation = takeContinuation()
        setSession(nil)?.finishTasksAndInvalidate()

        if let error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume(returning: destination)
        }
    }
}
