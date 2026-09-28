import AppKit
import SwiftUI

struct PermissionView: View {
    let onOpenSettings: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Screen Recording Access")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Required to capture screenshots")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Text("macOS only lets apps capture the screen once you approve them. Open System Settings, then turn on Snapper under Privacy & Security › Screen & System Audio Recording.")
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.primary)

            HStack {
                Text("Snapper will continue as soon as you grant access.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Button("Not Now", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Button("Open Settings", action: onOpenSettings)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }
}
