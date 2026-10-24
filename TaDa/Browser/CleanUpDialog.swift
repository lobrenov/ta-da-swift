// The Clean Up dialog (a sheet on the Attachments list): the images no open file embeds, grouped by why, each ticked to
// move to Trash. While markdown files are still downloading from iCloud Drive, nothing starts ticked.
#if os(macOS)
import SwiftUI
import TaDaCore

struct CleanUpDialog: View {
    let model: AppModel
    @State private var ticks = CleanUpTicks()
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    private var groups: AttachmentGroups { model.attachmentGroups }

    var body: some View {
        let candidates = groups.candidates
        let ticked = ticks.ticked(in: candidates)
        let sections = CleanUpSection.sections(of: candidates)
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(CleanUpText.title(count: candidates.count))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(theme.color(\.strong))
                Text(CleanUpText.explanation)
                    .foregroundStyle(theme.color(\.fg))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !groups.pendingFiles.isEmpty { pending(groups.pendingFiles.count) }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { offset, entry in
                        if offset > 0 { Hairline() }
                        section(entry)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 420)
            .background(theme.color(theme.isDark ? \.bg : \.side), in: .rect(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(theme.color(\.border)))
            HStack(spacing: 10) {
                Text(CleanUpText.summary(ticked: ticked, of: candidates.count))
                    .font(.system(size: 12))
                    .foregroundStyle(theme.color(\.muted))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Cancel") { dismiss() }
                    .buttonStyle(ActionButtonStyle(height: 28))
                    .keyboardShortcut(.cancelAction)
                Button("Move \(ticked.count) to Trash") {
                    let paths = ticked.map(\.id)
                    dismiss()
                    Task { await model.trashAttachments(paths) }
                }
                .buttonStyle(ActionButtonStyle(kind: .danger, height: 28))
                .keyboardShortcut(.defaultAction)
                .disabled(ticked.isEmpty)
            }
        }
        .font(.system(size: 13))
        .padding(EdgeInsets(top: 20, leading: 22, bottom: 18, trailing: 22))
        .frame(width: 560)
        .onAppear { ticks.start(groups) }
        .onChange(of: candidates.isEmpty) { _, isEmpty in if isEmpty { dismiss() } }
    }

    private func pending(_ count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "icloud.and.arrow.down")
                .foregroundStyle(theme.color(\.due))
                .accessibilityHidden(true)
            Text(CleanUpText.pending(count: count))
                .foregroundStyle(theme.color(\.fg))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.color(\.code), in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.color(\.due)))
    }

    private func section(_ section: CleanUpSection) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(theme.color(section.tint)).frame(width: 7, height: 7)
                Text(section.title).fontWeight(.semibold).foregroundStyle(theme.color(\.strong))
                Spacer()
                Text("\(section.uses.count)").font(.system(size: 11.5, weight: .medium)).foregroundStyle(theme.color(\.muted))
            }
            .font(.system(size: 12.5))
            .padding(.horizontal, 12)
            .frame(height: 30)
            .accessibilityAddTraits(.isHeader)
            ForEach(section.uses) { row($0) }
        }
    }

    private func row(_ use: AttachmentUse) -> some View {
        let image = use.attachment
        let isOn = ticks.isTicked(use)
        return Button {
            ticks.toggle(use)
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(isOn ? theme.color(\.accent) : .clear)
                    .strokeBorder(theme.color(\.muted), lineWidth: isOn ? 0 : 1.5)
                    .frame(width: 16, height: 16)
                    .overlay {
                        if isOn { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(theme.color(\.bg)) }
                    }
                ImageThumbnail(url: image.isDownloaded ? model.vault?.url(for: image.path) : nil, side: 34, cornerRadius: 5)
                    .opacity(isOn ? 1 : 0.55)
                VStack(alignment: .leading, spacing: 1) {
                    Text(image.name).foregroundStyle(theme.color(isOn ? \.strong : \.fg))
                    Group {
                        if use.closedTitles.isEmpty {
                            Text(image.addedText.map { "Added \($0)" } ?? "")
                        } else {
                            Text("Embedded in \(Text(use.closedTitles).foregroundStyle(theme.color(\.link)))")
                        }
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.color(\.muted))
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                Text(image.sizeText).font(.system(size: 11.5)).foregroundStyle(theme.color(\.muted))
            }
            .padding(.leading, 28)
            .padding(.trailing, 12)
            .frame(height: 50)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

#Preview {
    CleanUpDialog(model: AppModel())
}
#endif
