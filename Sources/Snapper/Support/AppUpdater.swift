import AppKit
import Foundation

/// Checks the GitHub releases API for a newer Snapper build. No dependencies,
/// no auto-install — just notifies and opens the release page.
enum AppUpdater {
    private static let latestURL = URL(
        string: "https://api.github.com/Marvelxy/snapper/releases/latest"
    )!

    private struct Release: Decodable {
        var tagName: String
        var htmlURL: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    enum CheckResult {
        case upToDate(current: String)
        case available(version: String, url: URL)
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
                return .available(version: release.tagName, url: release.htmlURL)
            }
            return .upToDate(current: current)
        } catch {
            return .failed(error)
        }
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
