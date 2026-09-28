import AppKit

enum CaptureAction: String {
    case gui
    case screen
    case region
    case window
}

/// Routes every menu item selection back to Swift closures, so the status item
/// controller does not have to subclass `NSObject` for each action.
private final class MenuActionProxy: NSObject {
    var onCapture: ((CaptureAction) -> Void)?
    var onOpenFolder: (() -> Void)?
    var onPermissionSettings: (() -> Void)?
    var onAbout: (() -> Void)?

    @objc func handleCapture(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
            let action = CaptureAction(rawValue: raw)
        else { return }
        onCapture?(action)
    }

    @objc func handleOpenFolder() {
        onOpenFolder?()
    }

    @objc func handlePermissionSettings() {
        onPermissionSettings?()
    }

    @objc func handleAbout() {
        onAbout?()
    }
}

/// Owns the NSStatusItem and its menu. Snapper runs as an accessory app, so this
/// is the app's only persistent UI.
final class StatusBarController {
    private let proxy = MenuActionProxy()
    private var statusItem: NSStatusItem?

    init(
        onCapture: @escaping (CaptureAction) -> Void,
        onOpenFolder: @escaping () -> Void,
        onPermissionSettings: @escaping () -> Void,
        onAbout: @escaping () -> Void
    ) {
        proxy.onCapture = onCapture
        proxy.onOpenFolder = onOpenFolder
        proxy.onPermissionSettings = onPermissionSettings
        proxy.onAbout = onAbout
        install()
    }

    private func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = item.button {
            let image = NSImage(
                systemSymbolName: "camera.viewfinder",
                accessibilityDescription: "Snapper"
            )
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Snapper"
        }

        item.menu = makeMenu()
        statusItem = item
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        // Snapper's primary entry point: one GUI for select + annotate.
        menu.addItem(captureItem("Take Screenshot", action: .gui))

        menu.addItem(.separator())

        menu.addItem(captureItem("Capture Full Screen", action: .screen))
        menu.addItem(captureItem("Capture Window…", action: .window))

        menu.addItem(.separator())

        menu.addItem(
            plainItem(
                "Open Screenshots Folder", action: #selector(MenuActionProxy.handleOpenFolder))
        )
        menu.addItem(
            plainItem(
                "Screen Recording Settings…",
                action: #selector(MenuActionProxy.handlePermissionSettings)
            )
        )

        menu.addItem(.separator())

        menu.addItem(
            plainItem("About Snapper", action: #selector(MenuActionProxy.handleAbout))
        )

        menu.addItem(.separator())

        menu.addItem(
            NSMenuItem(
                title: "Quit Snapper",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )

        return menu
    }

    private func captureItem(_ title: String, action: CaptureAction) -> NSMenuItem {
        let item = plainItem(title, action: #selector(MenuActionProxy.handleCapture(_:)))
        item.representedObject = action.rawValue
        return item
    }

    private func plainItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = proxy
        return item
    }
}
