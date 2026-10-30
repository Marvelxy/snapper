import AppKit
import SwiftUI

/// Update prompt: shows what's changing, downloads the DMG in place and hands it
/// to `UpdateInstaller`. Replaces the old "open GitHub in your browser" alert.
final class UpdateWindow: FloatingPanel {
    private var model: UpdateModel?

    func present(
        version: String,
        download: AppUpdater.Download?,
        releaseURL: URL,
        onClose: @escaping () -> Void,
        onInstall: @escaping (URL) -> Void
    ) {
        let model = UpdateModel(download: download, onInstall: onInstall)
        self.model = model

        contentView = NSHostingView(
            rootView: UpdateView(
                version: version,
                currentVersion: AppUpdater.currentVersion,
                releaseURL: releaseURL,
                model: model,
                onClose: onClose
            )
        )
        presentCentered(size: UpdateView.size)
        // Borderless card: draggable.
        isMovableByWindowBackground = true
    }

    override func close() {
        // Closing mid-download should stop it, not let it finish in the dark.
        model?.cancel()
        model = nil
        super.close()
    }
}

/// Download state machine for the prompt.
@MainActor
final class UpdateModel: ObservableObject {
    enum Phase: Equatable {
        case ready
        case downloading(progress: Double)
        case downloaded(URL)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .ready

    let download: AppUpdater.Download?
    private let onInstall: (URL) -> Void
    private var task: Task<Void, Never>?

    init(download: AppUpdater.Download?, onInstall: @escaping (URL) -> Void) {
        self.download = download
        self.onInstall = onInstall
    }

    var canDownload: Bool { download != nil }

    func startDownload() {
        guard let download, task == nil else { return }
        phase = .downloading(progress: 0)

        task = Task { [weak self] in
            guard let self else { return }

            let outcome: Result<URL, Error>
            do {
                let url = try await AppUpdater.download(download) { fraction in
                    Task { @MainActor in
                        guard case .downloading = self.phase else { return }
                        self.phase = .downloading(progress: fraction)
                    }
                }
                outcome = .success(url)
            } catch {
                outcome = .failure(error)
            }

            self.task = nil
            // Cancelling closes the prompt; don't report a failure for it.
            guard !Task.isCancelled else { return }

            switch outcome {
            case .success(let url):
                self.phase = .downloaded(url)
            case .failure(let error):
                self.phase = .failed(Self.message(for: error))
            }
        }
    }

    /// `localizedDescription` for URLSession errors is a bare error number, so
    /// say what actually happened.
    private static func message(for error: Error) -> String {
        // URLSession errors arrive as NSError, which does not always bridge to
        // URLError, so match on the domain and code instead.
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return error.localizedDescription }
        switch URLError.Code(rawValue: nsError.code) {
        case .notConnectedToInternet:
            return "You appear to be offline."
        case .timedOut:
            return "The download timed out."
        case .badServerResponse, .fileDoesNotExist, .resourceUnavailable:
            return "That download isn't available right now."
        case .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .dnsLookupFailed:
            return "Couldn't reach GitHub."
        default:
            return "The download didn't finish."
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    func install() {
        guard case .downloaded(let url) = phase else { return }
        onInstall(url)
    }
}

// MARK: - Palette

/// Violet drawn from the app icon and the DMG install window.
private enum Brand {
    static let accent = Color(red: 0.62, green: 0.36, blue: 0.94)
    static let accentDeep = Color(red: 0.40, green: 0.17, blue: 0.68)
}

// MARK: - View

private struct UpdateView: View {
    static let size = NSSize(width: 420, height: 280)

    let version: String
    let currentVersion: String
    let releaseURL: URL
    @ObservedObject var model: UpdateModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 16)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 20)

            rule
            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
        .animation(.easeOut(duration: 0.22), value: model.phase)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.28), radius: 7, y: 3)

            VStack(alignment: .leading, spacing: 3) {
                Text("Update available")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.1)
                    .textCase(.uppercase)
                    .foregroundStyle(Brand.accent)

                Text("Snapper \(version)")
                    .font(.system(size: 19, weight: .bold))

                Text("You're on \(currentVersion)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .ready:
            VStack(spacing: 14) {
                Spacer(minLength: 0)
                versionPath
                if let download = model.download {
                    Text(details(for: download))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    Text("This release has no installer attached.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

        case .downloading(let progress):
            VStack(spacing: 10) {
                Spacer(minLength: 0)
                ProgressBar(progress: progress)
                HStack {
                    Text("Downloading update…")
                    Spacer()
                    Text("\(Int((progress * 100).rounded()))%")
                        .monospacedDigit()
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

        case .downloaded:
            VStack(spacing: 6) {
                Spacer(minLength: 0)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(Brand.accent)
                Text("Ready to install")
                    .font(.system(size: 13, weight: .semibold))
                Text("Snapper restarts to finish the update.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

        case .failed(let message):
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Download failed")
                        .font(.system(size: 12, weight: .semibold))
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 14)
        }
    }

    private var versionPath: some View {
        HStack(spacing: 10) {
            VersionPill(text: currentVersion)
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
            VersionPill(text: version, emphasized: true)
        }
    }

    private func details(for download: AppUpdater.Download) -> String {
        var parts: [String] = []
        if download.fileName.contains("Apple-Silicon") {
            parts.append("Apple Silicon build")
        } else if download.fileName.contains("Intel") {
            parts.append("Intel build")
        }
        if download.byteCount > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(download.byteCount), countStyle: .file))
        }
        return parts.isEmpty ? download.fileName : parts.joined(separator: " · ")
    }

    private var releaseLink: some View {
        Link(destination: releaseURL) {
            HStack(spacing: 4) {
                Text("Release Notes")
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8, weight: .bold))
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Brand.accent)
        }
        .buttonStyle(.plain)
    }

    // MARK: Footer

    private var rule: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 0.5)
    }

    @ViewBuilder
    private var footer: some View {
        switch model.phase {
        case .ready:
            HStack(spacing: 10) {
                releaseLink

                Spacer()

                Button("Not Now", action: onClose)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction)

                if model.canDownload {
                    Button("Download", action: model.startDownload)
                        .buttonStyle(.borderedProminent)
                        .tint(Brand.accent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Open Release Page") {
                        NSWorkspace.shared.open(releaseURL)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.accent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .font(.system(size: 12))

        case .downloading:
            HStack {
                Spacer()
                Button("Cancel") {
                    model.cancel()
                    onClose()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)
            }

        case .downloaded:
            HStack(spacing: 10) {
                Spacer()
                Button("Later", action: onClose)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Button("Install and Relaunch", action: model.install)
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.accent)
                    .keyboardShortcut(.defaultAction)
            }

        case .failed:
            HStack(spacing: 10) {
                releaseLink

                Spacer()

                Button("Close", action: onClose)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
                Button("Try Again", action: model.startDownload)
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.accent)
                    .keyboardShortcut(.defaultAction)
            }
            .font(.system(size: 12))
        }
    }

    // MARK: Card

    private var cardBackground: some View {
        ZStack {
            Rectangle().fill(.regularMaterial)
            // Faint violet wash from the top-left, like the install window.
            RadialGradient(
                colors: [Brand.accent.opacity(0.16), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 420
            )
        }
    }
}

// MARK: - Pieces

private struct VersionPill: View {
    let text: String
    var emphasized = false

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(emphasized ? Brand.accent : Color.primary.opacity(0.65))
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(
                    emphasized
                        ? Brand.accent.opacity(0.16)
                        : Color.primary.opacity(0.06)
                )
            )
            .overlay(
                Capsule().strokeBorder(
                    emphasized ? Brand.accent.opacity(0.45) : Color.primary.opacity(0.10),
                    lineWidth: 0.5
                )
            )
    }
}

private struct ProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Brand.accent, Brand.accentDeep],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(7, geometry.size.width * min(max(progress, 0), 1)))
                    .animation(.easeOut(duration: 0.25), value: progress)
            }
        }
        .frame(height: 7)
    }
}
