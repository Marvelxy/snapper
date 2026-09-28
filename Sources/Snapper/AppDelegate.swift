import AppKit
import ScreenCaptureKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var regionOverlay: RegionOverlayWindow?
    private var windowPicker: WindowPickerWindow?
    private var toastWindow: ToastWindow?
    private var permissionWindow: PermissionWindow?
    private var aboutWindow: AboutWindow?

    /// The capture the user asked for before we knew whether permission was granted.
    private var pendingAction: CaptureAction?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusBarController = StatusBarController(
            onCapture: { [weak self] action in
                self?.beginCapture(action)
            },
            onOpenFolder: {
                let folder = ScreenshotStore.directory
                try? FileManager.default.createDirectory(
                    at: folder,
                    withIntermediateDirectories: true
                )
                NSWorkspace.shared.activateFileViewerSelecting([folder])
            },
            onPermissionSettings: { [weak self] in
                ScreenRecordingPermission.openSystemSettings()
                self?.pollForPermissionAndResume()
            },
            onAbout: { [weak self] in
                self?.presentAbout()
            },
            onCheckUpdates: { [weak self] in
                self?.checkForUpdates()
            }
        )
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: - Capture entry points

    private func beginCapture(_ action: CaptureAction) {
        if ScreenRecordingPermission.isGranted {
            perform(action)
        } else {
            pendingAction = action
            requestPermission()
        }
    }

    private func requestPermission() {
        closePermissionWindow()

        // Triggers the one-time system prompt, then explain what happens next.
        ScreenRecordingPermission.request()

        let window = PermissionWindow()
        permissionWindow = window
        window.present(
            onGranted: { [weak self] in
                guard let self else { return }
                self.closePermissionWindow()
                let action = self.pendingAction ?? .screen
                self.pendingAction = nil
                self.perform(action)
            },
            onCancel: { [weak self] in
                self?.pendingAction = nil
            }
        )
    }

    private func pollForPermissionAndResume() {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { return }

                if ScreenRecordingPermission.isGranted {
                    self.closePermissionWindow()
                    let action = self.pendingAction ?? .screen
                    self.pendingAction = nil
                    self.perform(action)
                    return
                }
            }
        }
    }

    private func perform(_ action: CaptureAction) {
        switch action {
        case .gui, .region:
            captureRegion()
        case .screen:
            captureFullScreen()
        case .window:
            captureWindow()
        }
    }

    // MARK: - Full screen

    private func captureFullScreen() {
        runCapture {
            let content = try await ScreenCapturer.shareableContent()
            let display = try ScreenCapturer.displayUnderPointer(in: content)
            return try await ScreenCapturer.captureDisplay(display)
        } onSuccess: { [weak self] snapshot in
            self?.finish(snapshot.image)
        }
    }

    // MARK: - Region

    private func captureRegion() {
        runCapture {
            let content = try await ScreenCapturer.shareableContent()
            let display = try ScreenCapturer.displayUnderPointer(in: content)
            return try await ScreenCapturer.captureDisplay(display)
        } onSuccess: { [weak self] snapshot in
            self?.presentRegionOverlay(with: snapshot)
        }
    }

    private func presentRegionOverlay(with snapshot: DisplaySnapshot) {
        closeRegionOverlay()

        let overlay = RegionOverlayWindow()
        regionOverlay = overlay

        overlay.present(
            snapshot: snapshot,
            onAccept: { [weak self] rect, annotations, action in
                guard let self else { return }
                self.closeRegionOverlay()
                self.finishEditorSelection(rect, annotations: annotations, snapshot: snapshot, action: action)
            },
            onCancel: { [weak self] in
                self?.closeRegionOverlay()
            }
        )
    }

    /// Snapper's commit: crop the selection, bake annotations in, then copy
    /// and/or save like the toolbar action asked — no intermediate preview.
    private func finishEditorSelection(
        _ rect: CGRect,
        annotations: [SnapperAnnotation],
        snapshot: DisplaySnapshot,
        action: SnapperCommitAction
    ) {
        let pixelRect = CGRect(
            x: rect.minX * snapshot.pixelScale,
            y: rect.minY * snapshot.pixelScale,
            width: rect.width * snapshot.pixelScale,
            height: rect.height * snapshot.pixelScale
        )

        guard var cropped = ImageUtilities.cropped(snapshot.image, to: pixelRect),
              cropped.width >= 2,
              cropped.height >= 2 else {
            return
        }

        if !annotations.isEmpty {
            guard let composited = SnapperRenderer.composite(
                base: cropped,
                annotations: annotations,
                scale: snapshot.pixelScale
            ) else { return }
            cropped = composited
        }

        var savedURL: URL?
        if let url = try? ScreenshotStore.save(cropped) {
            savedURL = url
        }

        switch action {
        case .copy:
            ImageUtilities.copyToClipboard(cropped)
            presentToast(title: "Copied to clipboard", detail: savedURL?.lastPathComponent)
        case .save:
            presentToast(title: "Screenshot saved", detail: savedURL?.lastPathComponent)
        }
    }

    private func closeRegionOverlay() {
        regionOverlay?.close()
        regionOverlay = nil
    }

    // MARK: - Window

    private func captureWindow() {
        runCapture {
            let content = try await ScreenCapturer.shareableContent()
            let windows = ScreenCapturer.capturableWindows(from: content)
            guard !windows.isEmpty else { throw ScreenCaptureError.noWindows }
            return windows
        } onSuccess: { [weak self] windows in
            self?.presentWindowPicker(with: windows)
        }
    }

    private func presentWindowPicker(with windows: [CapturableWindow]) {
        closeWindowPicker()

        let picker = WindowPickerWindow()
        windowPicker = picker

        picker.present(
            windows: windows,
            onSelect: { [weak self] selected in
                guard let self else { return }
                self.closeWindowPicker()
                self.captureWindowContent(for: selected)
            },
            onCancel: { [weak self] in
                self?.closeWindowPicker()
            }
        )
    }

    private func captureWindowContent(for window: CapturableWindow) {
        runCapture {
            let content = try await ScreenCapturer.shareableContent()
            guard let match = content.windows.first(where: { $0.windowID == window.id }) else {
                throw ScreenCaptureError.noWindows
            }
            return try await ScreenCapturer.captureWindow(match)
        } onSuccess: { [weak self] image in
            self?.finish(image)
        }
    }

    private func closeWindowPicker() {
        windowPicker?.close()
        windowPicker = nil
    }

    // MARK: - Result handling

    /// Headless captures (full screen / window): clipboard + file + toast,
    /// matching what the editor's Copy button does.
    private func finish(_ image: CGImage) {
        ImageUtilities.copyToClipboard(image)

        var savedURL: URL?
        if let url = try? ScreenshotStore.save(image) {
            savedURL = url
        }

        presentToast(title: "Copied to clipboard", detail: savedURL?.lastPathComponent)
    }

    private func presentToast(title: String, detail: String?) {
        toastWindow?.close()

        let toast = ToastWindow()
        toastWindow = toast
        toast.present(title: title, detail: detail)
    }

    private func closePermissionWindow() {
        permissionWindow?.close()
        permissionWindow = nil
    }

    // MARK: - About

    private func presentAbout() {
        aboutWindow?.close()

        let window = AboutWindow()
        aboutWindow = window
        window.present { [weak self] in
            self?.aboutWindow?.close()
            self?.aboutWindow = nil
        }
    }

    // MARK: - Updates

    private var updateCheckTask: Task<Void, Never>?

    private func checkForUpdates() {
        guard updateCheckTask == nil else { return }

        updateCheckTask = Task { [weak self] in
            let result = await AppUpdater.check()
            guard let self else { return }
            self.updateCheckTask = nil

            switch result {
            case .upToDate(let version):
                self.presentToast(title: "Snapper is up to date", detail: "Version \(version)")
            case .available(let version, let url):
                self.presentUpdateAlert(version: version, url: url)
            case .noReleases:
                self.presentToast(title: "No updates found", detail: "No releases published yet — check back later.")
            case .failed(let error):
                self.presentToast(title: "Couldn't check for updates", detail: error.localizedDescription)
            }
        }
    }

    private func presentUpdateAlert(version: String, url: URL) {
        let alert = NSAlert()
        alert.messageText = "Update available"
        alert.informativeText =
            "Snapper \(version) is available (you have \(AppUpdater.currentVersion)). Download it from GitHub to update."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")

        // Same activation dance as presentModally, but capturing the response.
        let previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        NSApp.setActivationPolicy(previousPolicy)
        NSApp.hide(nil)

        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Plumbing

    /// Shared entry point for the async capture pipeline: dismisses the menu,
    /// waits for the status menu to disappear so it is not captured, then runs
    /// `work` and routes the result or error.
    private func runCapture<T>(
        _ work: @escaping () async throws -> T,
        onSuccess: @escaping (T) -> Void
    ) {
        closeAllTransientWindows()

        Task { [weak self] in
            // Let the status item menu finish dismissing before the screen is read.
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard self != nil else { return }

            do {
                let result = try await work()
                onSuccess(result)
            } catch {
                self?.presentError(error)
            }
        }
    }

    private func closeAllTransientWindows() {
        closeRegionOverlay()
        closeWindowPicker()
        toastWindow?.close()
        toastWindow = nil
    }

    private func presentError(_ error: Error) {
        if case ScreenCaptureError.permissionNotGranted = error {
            pendingAction = .screen
            requestPermission()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Capture Failed"
        alert.informativeText = (error as? LocalizedError)?.errorDescription
            ?? error.localizedDescription
        alert.alertStyle = .warning

        presentModally(alert.window)
    }

    /// Snapper runs as an accessory app, so it has to activate itself before a
    /// modal dialog or save panel will come forward.
    private func presentModally(_ window: NSWindow) {
        let previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: window)

        NSApp.setActivationPolicy(previousPolicy)
        NSApp.hide(nil)
    }
}
