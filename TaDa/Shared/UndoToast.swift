// The toast after completing, moving or deleting: what happened and Undo, for 6 seconds or until another change.
import SwiftUI

struct UndoToastView: View {
    let model: AppModel
    let toast: AppModel.UndoToast
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Text(toast.message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.color(\.strong))
                .lineLimit(1)
                .truncationMode(.middle)
            Button("Undo") {
                model.undoToast = nil
                model.undoManager?.undo()
            }
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(theme.color(\.accent))
            .buttonStyle(.plain)
            .disabled(model.undoManager?.undoActionName != toast.actionName)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(theme.color(theme.isDark ? \.side : \.bg), in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.color(\.surface)))
        .shadow(color: .black.opacity(theme.isDark ? 0.4 : 0.15), radius: 16, y: 8)
        .padding(16)
        .accessibilityElement(children: .contain)
        .task(id: toast.id) {
            AccessibilityNotification.Announcement(toast.message).post()
            try? await Task.sleep(for: .seconds(6))
            if model.undoToast?.id == toast.id { model.undoToast = nil }
        }
    }
}

extension View {
    /// Shows the model's undo toast at the bottom, `inset` above it, and gives the model the window's undo manager.
    func undoToast(_ model: AppModel, inset: CGFloat = 0) -> some View {
        modifier(UndoToastHost(model: model, inset: inset))
    }
}

private struct UndoToastHost: ViewModifier {
    let model: AppModel
    let inset: CGFloat
    @Environment(\.undoManager) private var undoManager

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let toast = model.undoToast {
                    UndoToastView(model: model, toast: toast)
                        .padding(.bottom, inset)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: model.undoToast)
            .onChange(of: undoManager, initial: true) { model.undoManager = undoManager }
    }
}
