import AppKit
import SwiftUI

struct PreviewView: View {
    let image: NSImage
    let fileName: String?
    let onSave: () -> Void
    let onReveal: () -> Void
    let onClose: () -> Void

    private let maxImageSize = NSSize(width: 420, height: 280)

    var body: some View {
        VStack(spacing: 0) {
            imageArea
            Divider()
            actionBar
        }
        .frame(width: maxImageSize.width)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }

    private var imageArea: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.medium)
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: maxImageSize.width, maxHeight: maxImageSize.height)
            .padding(10)
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Saved to clipboard")
                    .font(.system(size: 11, weight: .medium))
                if let fileName {
                    Text(fileName)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)

            iconButton("trash", help: "Discard file", action: onClose)
            iconButton("folder", help: "Reveal in Finder", action: onReveal)
            iconButton("square.and.arrow.down", help: "Save a copy…", action: onSave)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func iconButton(
        _ symbol: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .frame(width: 24, height: 22)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        )
        .help(help)
    }
}
