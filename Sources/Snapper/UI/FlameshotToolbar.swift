import SwiftUI

/// Flameshot's dark attached toolbar: drawing tools, undo/redo and the final
/// copy / save / exit actions. Styled after flameshot's charcoal bar with a
/// purple highlight for the active tool.
struct FlameshotToolbarView: View {
    @ObservedObject var session: FlameshotSession

    var body: some View {
        HStack(spacing: 2) {
            ForEach(FlameshotTool.allCases) { tool in
                toolButton(tool)
            }

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 4)

            Button {
                session.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(FlameshotToolButtonStyle(isActive: false))
            .disabled(!session.canUndo)
            .opacity(session.canUndo ? 1 : 0.35)
            .help("Undo (Ctrl+Z)")

            Button {
                session.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(FlameshotToolButtonStyle(isActive: false))
            .disabled(!session.canRedo)
            .opacity(session.canRedo ? 1 : 0.35)
            .help("Redo (Ctrl+Shift+Z)")

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 4)

            Button {
                session.commit(.copy)
            } label: {
                Image(systemName: "doc.on.doc")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(FlameshotToolButtonStyle(isActive: false))
            .help("Copy (Ctrl+C)")

            Button {
                session.commit(.save)
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(FlameshotToolButtonStyle(isActive: false))
            .help("Save (Ctrl+S)")

            Button {
                session.onCancel?()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(FlameshotToolButtonStyle(isActive: false))
            .help("Exit (Esc)")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
    }

    private func toolButton(_ tool: FlameshotTool) -> some View {
        Button {
            session.activeTool = tool
            if tool != .selection {
                session.showSidePanel = true
            }
        } label: {
            Image(systemName: tool.symbolName)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(FlameshotToolButtonStyle(isActive: session.activeTool == tool))
        .help(tool.help)
    }
}

struct FlameshotToolButtonStyle: ButtonStyle {
    var isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(
                        isActive ? Color(hex: "#740096")
                            : configuration.isPressed ? Color.white.opacity(0.25)
                            : Color.clear
                    )
            )
    }
}

/// Color + thickness panel: a vertical strip in the same card style as the
/// toolbar, docked to the left side of the selection. Toggled with Space,
/// like flameshot's toggle-panel shortcut.
struct FlameshotSidePanelView: View {
    @ObservedObject var session: FlameshotSession

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 6) {
                ForEach(FlameshotSwatch.allCases) { swatch in
                    Button {
                        session.swatch = swatch
                    } label: {
                        Circle()
                            .fill(swatch.color)
                            .frame(width: 20, height: 20)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        session.swatch == swatch ? Color.white : Color.white.opacity(0.25),
                                        lineWidth: session.swatch == swatch ? 2 : 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .help(swatch.rawValue)
                }
            }

            Divider()

            VStack(spacing: 4) {
                ForEach(FlameshotThickness.allCases) { thickness in
                    Button {
                        session.thickness = thickness
                    } label: {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(session.thickness == thickness ? Color.white : Color.white.opacity(0.5))
                            .frame(width: 34, height: max(2, thickness.rawValue))
                            .frame(height: 14)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(session.thickness == thickness ? Color(hex: "#740096") : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(thickness.label)
                }
            }
        }
        .fixedSize()
        .padding(8)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
    }
}
