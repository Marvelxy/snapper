import AppKit
import SwiftUI

/// About window: app identity, author info and open-source license note.
final class AboutWindow: FloatingPanel {
    func present(onClose: @escaping () -> Void) {
        contentView = NSHostingView(
            rootView: AboutView(onClose: onClose)
        )
        presentCentered(size: NSSize(width: 360, height: 330))
    }
}

private struct AboutView: View {
    let onClose: () -> Void

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tint)
                .padding(.top, 18)

            VStack(spacing: 2) {
                Text("Snapper")
                    .font(.system(size: 20, weight: .bold))
                Text("Version \(version)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Text("Flameshot-style screenshots for macOS.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text("by Marvelous Akpotu")
                    .font(.system(size: 12, weight: .semibold))

                Link(
                    "github.com/Marvelxy", destination: URL(string: "https://github.com/Marvelxy")!
                )
                .font(.system(size: 12))

                Link(
                    "still4marvelous@gmail.com",
                    destination: URL(string: "mailto:still4marvelous@gmail.com")!
                )
                .font(.system(size: 12))
            }

            Text("Free and open-source software licensed under GPL-3.0.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("OK", action: onClose)
                .keyboardShortcut(.defaultAction)
                .padding(.bottom, 16)
        }
        .frame(width: 360, height: 330)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }
}
