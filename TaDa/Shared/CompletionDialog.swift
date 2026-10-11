// Completing or cancelling a project that still has open tasks, or logging one with Log Now: completes or cancels the
// open tasks with it. A Mac sheet (ContentView shows it) and an iPhone confirmation dialog (PhoneRootView shows it), for
// `model.completionConfirmation`.
import SwiftUI
import TaDaCore

/// The question's words.
struct CompletionText {
    let request: AppModel.CompletionConfirmation

    private var count: Int { request.tasks.count }
    private var isCancelling: Bool { request.status == .cancelled }

    /// "Complete “Sell the Kombi”?" or "Cancel “Sell the Kombi”?"
    var title: String { "\(isCancelling ? "Cancel" : "Complete") “\(request.project.title)”?" }

    var message: String {
        let open = count == 1 ? "1 of its tasks is still open." : "\(count) of its tasks are still open."
        let when = request.logsAfter ? "now" : "tonight"
        return "\(open) Close \(count == 1 ? "it" : "them") with the project, and they all go to the Logbook \(when)."
    }

    /// "Complete 3 Tasks" or "Cancel 3 Tasks".
    func button(_ status: Status) -> String {
        "\(status == .cancelled ? "Cancel" : "Complete") \(count == 1 ? "1 Task" : "\(count) Tasks")"
    }

    /// The status the project's own is, first; the other second.
    var choices: (primary: Status, secondary: Status) { isCancelling ? (.cancelled, .done) : (.done, .cancelled) }
}

#if os(macOS)
/// The Mac's sheet: the open tasks, Cancel, and the two choices, the project's own status the default.
struct CompletionDialog: View {
    let model: AppModel
    let request: AppModel.CompletionConfirmation
    @Environment(\.theme) private var theme

    var body: some View {
        let text = CompletionText(request: request)
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(text.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(theme.color(\.strong))
                Text(text.message)
                    .foregroundStyle(theme.color(\.fg))
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(request.tasks) { task in
                        HStack(spacing: 10) {
                            let (marker, tint) = StatusCheckbox.box(for: task.properties.status, theme: theme)
                            InlineCheckboxView(marker: marker, tint: tint, background: theme.bg)
                                .frame(width: 14, height: 14)
                            Text(task.title).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(task.properties.status.rawValue)
                                .font(.system(size: 11.5))
                                .foregroundStyle(theme.color(\.muted))
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: min(CGFloat(request.tasks.count) * 32 + 8, 296))
            .background(theme.color(theme.isDark ? \.bg : \.side), in: .rect(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(theme.color(\.border)))
            HStack(spacing: 8) {
                Button("Cancel") { answer(nil) }
                    .buttonStyle(ActionButtonStyle(height: 28))
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(text.button(text.choices.secondary)) { answer(text.choices.secondary) }
                    .buttonStyle(ActionButtonStyle(height: 28))
                Button(text.button(text.choices.primary)) { answer(text.choices.primary) }
                    .buttonStyle(ActionButtonStyle(kind: .primary, height: 28))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .font(.system(size: 13))
        .padding(EdgeInsets(top: 20, leading: 22, bottom: 18, trailing: 22))
        .frame(width: 480)
    }

    /// Clears the question first, which closes the sheet, so it's answered once.
    private func answer(_ status: Status?) {
        model.completionConfirmation = nil
        Task { await model.answerCompletion(request, tasksAs: status) }
    }
}
#endif
