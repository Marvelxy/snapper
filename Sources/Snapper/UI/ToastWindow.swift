import AppKit
import SwiftUI

/// Flameshot-style desktop notification: a small card bottom-right confirming
/// what happened to the capture. Replaces the old preview window, since the
/// editor already showed the result in place.
final class ToastWindow: FloatingPanel {
    private var dismissTask: Task<Void, Never>?

    func present(title: String, detail: String?, autoDismissAfter interval: TimeInterval = 3) {
        contentView = NSHostingView(
            rootView: ToastView(title: title, detail: detail)
        )
        presentCentered(size: NSSize(width: 320, height: detail == nil ? 52 : 68))
        setFrameOrigin(Self.bottomRightOrigin(for: NSSize(width: 320, height: detail == nil ? 52 : 68)))
        scheduleDismiss(after: interval)
    }

    override func close() {
        dismissTask?.cancel()
        dismissTask = nil
        super.close()
    }

    private static func bottomRightOrigin(for size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]

        let margin: CGFloat = 16
        return NSPoint(
            x: screen.frame.maxX - size.width - margin,
            y: screen.frame.minY + margin
        )
    }

    private func scheduleDismiss(after interval: TimeInterval) {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.close()
        }
    }
}

private struct ToastView: View {
    let title: String
    let detail: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }
}
