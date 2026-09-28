import AppKit

/// A click-through-until-used, borderless panel that floats above full-screen apps
/// and joins every Space. Base class for the region overlay, window picker,
/// preview and permission prompts.
class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func configureCommon() {
        styleMask = [.borderless, .nonactivatingPanel]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    /// Covers an entire display, used by the region selector.
    func present(covering screen: NSScreen) {
        configureCommon()
        setFrame(screen.frame, display: true)
        makeKeyAndOrderFront(nil)
    }

    /// Fixed-size panel centred on the screen holding the pointer.
    func presentCentered(size: NSSize) {
        configureCommon()

        let frame = NSRect(origin: .zero, size: size)
        setContentSize(size)
        setFrameOrigin(Self.centeredOrigin(for: frame, preferredScreen: nil))
        makeKeyAndOrderFront(nil)
    }

    private static func centeredOrigin(
        for frame: NSRect,
        preferredScreen: NSScreen?
    ) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = preferredScreen
            ?? NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main

        guard let screen else { return .zero }
        return NSPoint(
            x: screen.frame.midX - frame.width / 2,
            y: screen.frame.midY - frame.height / 2
        )
    }
}
