// Attachments beside its detail pane: the images in `Ta Da/attachments/` in two groups, "Not in open files" (what Clean
// Up moves to Trash) and "In open files", each by name. A click picks a row; ⌘-click, ⇧-click and ⌘A pick several. The
// detail pane shows the picked image with the files that embed it, or the picked images stacked. Clean Up… opens its dialog.
#if os(macOS)
import SwiftUI
import TaDaCore

struct AttachmentsBrowser: View {
    let model: AppModel
    @State private var isCleaningUp = false
    @Environment(\.theme) private var theme

    var body: some View {
        let groups = model.attachmentGroups
        let all = groups.candidates + groups.inUse
        BrowserColumn(model: model, paths: all.map(\.id), spacing: 22,
                      empty: all.isEmpty ? empty : nil) {
            header(groups, count: all.count)
        } content: {
            if !groups.candidates.isEmpty {
                group("Not in open files", uses: groups.candidates,
                      note: "\(Attachment.countText(groups.candidates.count)) · \(Attachment.sizeText(groups.candidatesSize))")
            }
            if !groups.inUse.isEmpty {
                group("In open files", uses: groups.inUse, note: Attachment.countText(groups.inUse.count))
            }
            if let note = model.attachmentNote { toast(note) }
        }
        .sheet(isPresented: $isCleaningUp) {
            CleanUpDialog(model: model)
                .presentationBackground(theme.color(theme.isDark ? \.side : \.bg))
        }
    }

    private var empty: EmptyState {
        EmptyState(systemImage: AppModel.Domain.attachments.systemImage, title: "No attachments",
                   message: "Images you paste or drop into a file are saved in `\(Vault.attachmentFolder)`.")
    }

    private func header(_ groups: AttachmentGroups, count total: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            DomainHeader(.attachments) {
                Button("Clean Up…") {
                    model.attachmentNote = nil
                    isCleaningUp = true
                }
                .buttonStyle(ActionButtonStyle(kind: .primary, height: 28))
                .disabled(groups.candidates.isEmpty)
            }
            if total > 0 {
                Text("\(Attachment.countText(total)) · \(Attachment.sizeText(groups.totalSize)) · "
                     + (groups.candidates.isEmpty ? "every one is in an open file" : "\(groups.candidates.count) not in any open file"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.color(\.muted))
            }
        }
    }

    private func group(_ title: String, uses: [AttachmentUse], note: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            GroupTitle(title: title, note: note)
            ForEach(uses) { AttachmentRow(model: model, use: $0) }
        }
    }

    private func toast(_ note: String) -> some View {
        Text(note)
            .font(.system(size: 12))
            .foregroundStyle(theme.color(\.fg))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.color(\.code), in: .rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.color(\.border)))
            .padding(.horizontal, 10)
            .accessibilityAddTraits(.updatesFrequently)
    }

}

/// A row: thumbnail, filename (with a cloud when iCloud Drive hasn't downloaded it), where it's embedded and its size.
private struct AttachmentRow: View {
    let model: AppModel
    let use: AttachmentUse
    @Environment(\.theme) private var theme

    var body: some View {
        let image = use.attachment
        let isPicked = model.isSelected(use.id)
        Button {
            model.click(use.id)
            model.attachmentNote = nil
        } label: {
            HStack(spacing: 12) {
                ImageThumbnail(url: image.isDownloaded ? model.vault?.url(for: image.path) : nil, side: 34, cornerRadius: 5)
                    .opacity(image.isDownloaded ? 1 : 0.45)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(image.name)
                            .font(.system(size: 13.5))
                            .foregroundStyle(theme.color(isPicked ? \.strong : \.fg))
                        if !image.isDownloaded {
                            Image(systemName: "icloud")
                                .font(.system(size: 11))
                                .foregroundStyle(theme.color(\.muted))
                                .help("In iCloud Drive, not downloaded")
                        }
                    }
                    AttachmentWhereText(line: use.whereLine, linkTint: use.isInUse ? \.link : \.fg)
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.color(\.muted))
                }
                .lineLimit(1)
                Spacer(minLength: 12)
                Text(image.sizeText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.color(\.muted))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isPicked ? theme.color(\.surface) : .clear, in: .rect(cornerRadius: 7))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isPicked ? .isSelected : [])
    }
}

/// The detail pane: nothing picked, one image with its embeds, or several stacked.
struct AttachmentDetail: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        let groups = model.attachmentGroups
        let picked = (groups.candidates + groups.inUse).filter { model.attachmentSelection.contains($0.id) }
        VStack(spacing: 0) {
            crumb(picked.count == 1 ? picked[0].attachment.name : picked.count > 1 ? "\(picked.count) images" : nil)
            Hairline()
            if picked.count == 1 {
                SingleAttachment(model: model, use: picked[0]).id(picked[0].id)
            } else if picked.count > 1 {
                SeveralAttachments(model: model, uses: picked)
            } else {
                EmptyState(systemImage: AppModel.Domain.attachments.systemImage, title: "No image selected")
            }
        }
    }

    /// "Ta Da / attachments / name", as the document pane shows a file's place.
    private func crumb(_ name: String?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "folder").font(.system(size: 12))
            ForEach(Vault.attachmentFolder.split(separator: "/").map(String.init), id: \.self) { Text($0); Text("/") }
            if let name { Text(name).foregroundStyle(theme.color(\.fg)) }
            Spacer(minLength: 12)
        }
        .font(.system(size: 11.5, design: .monospaced))
        .foregroundStyle(theme.color(\.muted))
        .lineLimit(1)
        .padding(.horizontal, 20)
        .frame(height: 46)
    }
}

/// One image: a large preview (with Download when iCloud Drive hasn't sent it), its details, actions and embeds.
private struct SingleAttachment: View {
    let model: AppModel
    let use: AttachmentUse
    @State private var dimensions: String?
    @State private var search = LinkMenuSearch()
    @Environment(\.theme) private var theme

    var body: some View {
        let image = use.attachment
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                preview(image)
                VStack(alignment: .leading, spacing: 4) {
                    Text(image.name)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(theme.color(\.strong))
                        .textSelection(.enabled)
                    Text(image.metaText(dimensions: dimensions))
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.color(\.muted))
                }
                HStack(spacing: 6) {
                    Button("Show in Finder") { model.revealInFinder([image.path]) }
                        .buttonStyle(ActionButtonStyle(height: 28))
                    Button("Rename…") { model.imageDialog = .rename(image.path) }
                        .buttonStyle(ActionButtonStyle(height: 28))
                    Button { Task { await model.moveAttachmentsToTrash([image.path]) } } label: {
                        Text("Move to Trash").foregroundStyle(theme.color(\.deadline))
                    }
                    .buttonStyle(ActionButtonStyle(height: 28))
                }
                Hairline().padding(.top, 4)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Embedded in").fontWeight(.semibold).foregroundStyle(theme.color(\.strong))
                    let embeds = use.live.count + use.logged.count + use.trashed.count
                    if embeds > 0 { Text("\(embeds)").font(.system(size: 11.5)).foregroundStyle(theme.color(\.muted)) }
                }
                if use.live.isEmpty && use.logged.isEmpty && use.trashed.isEmpty {
                    Text("No file embeds it. Clean Up moves it to Trash.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.color(\.muted))
                }
                VStack(spacing: 2) {
                    ForEach(use.live) { embedRow($0, state: .live) }
                    ForEach(use.logged) { embedRow($0, state: .logged) }
                    ForEach(use.trashed) { embedRow($0.item, state: .trashed, trashedID: $0.id) }
                }
            }
            .padding(EdgeInsets(top: 28, leading: 40, bottom: 40, trailing: 40))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: image.path) {
            dimensions = nil
            guard image.isDownloaded, let url = model.vault?.url(for: image.path), let size = await ImageMetadata.pixelSize(of: url) else { return }
            dimensions = "\(size.width) × \(size.height)"
        }
    }

    private func preview(_ image: Attachment) -> some View {
        AttachmentPreview(url: image.isDownloaded ? model.vault?.url(for: image.path) : nil)
            .overlay {
                if !image.isDownloaded {
                    VStack(spacing: 10) {
                        Image(systemName: "icloud.and.arrow.down").font(.system(size: 26, weight: .light))
                        Text("In iCloud Drive, not downloaded").font(.system(size: 12.5))
                        Button("Download") { Task { await model.downloadAttachment(image.path) } }
                            .buttonStyle(ActionButtonStyle(kind: .primary, height: 28))
                    }
                    .foregroundStyle(theme.color(\.strong))
                }
            }
    }

    private enum EmbedState { case live, logged, trashed }

    /// A file that embeds the image: the title, and where the file is.
    private func embedRow(_ item: Item, state: EmbedState, trashedID: String? = nil) -> some View {
        let place = switch state {
        case .live: AttachmentUse.livePlace(item)
        case .logged: AttachmentUse.loggedPlace(item)
        case .trashed: "Trash"
        }
        return Button {
            if let trashedID {
                model.show(.trash)
                model.trashSelection = [trashedID]
            } else {
                model.openLink(to: item.path)
            }
        } label: {
            HStack(spacing: 10) {
                LinkChoiceIcon(icon: model.linkIcon(of: item), search: search, theme: theme, size: 15)
                Text(item.title)
                    .foregroundStyle(theme.color(state == .live ? \.link : \.muted))
                    .strikethrough(state == .logged)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 5) {
                    Circle()
                        .fill(theme.color(state == .logged ? \.done : state == .trashed ? \.muted : \.accent))
                        .frame(width: 6, height: 6)
                    Text(place)
                }
                .font(.system(size: 11.5))
                .foregroundStyle(theme.color(\.muted))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(theme.color(\.code), in: .rect(cornerRadius: 7))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// Several images: up to three stacked, their count, size and names, and the actions on all of them.
private struct SeveralAttachments: View {
    let model: AppModel
    let uses: [AttachmentUse]
    @Environment(\.theme) private var theme

    var body: some View {
        let images = uses.map(\.attachment)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ZStack(alignment: .topLeading) {
                    ForEach(Array(images.prefix(3).enumerated()), id: \.offset) { offset, image in
                        ImageThumbnail(url: image.isDownloaded ? model.vault?.url(for: image.path) : nil, side: 150, cornerRadius: 10)
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.color(\.bg), lineWidth: 2))
                            .shadow(color: .black.opacity(0.25), radius: 9, y: 3)
                            .rotationEffect(.degrees(Double(offset - 1) * 4))
                            .offset(x: CGFloat(offset) * 60, y: CGFloat(offset) * 12)
                    }
                }
                .frame(height: 200, alignment: .topLeading)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(images.count) images")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(theme.color(\.strong))
                    Text(Attachment.sizeText(Attachment.totalSize(of: images)) + " · " + images.map(\.name).joined(separator: ", "))
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.color(\.muted))
                }
                HStack(spacing: 6) {
                    Button("Show in Finder") { model.revealInFinder(images.map(\.path)) }
                        .buttonStyle(ActionButtonStyle(height: 28))
                    Button { Task { await model.moveAttachmentsToTrash(model.attachmentSelection) } } label: {
                        Text("Move \(images.count) to Trash").foregroundStyle(theme.color(\.deadline))
                    }
                    .buttonStyle(ActionButtonStyle(height: 28))
                }
                Hairline().padding(.top, 4)
                Text("⌘-click picks or unpicks an image, ⇧-click picks a run, ⌘A picks every image. ⌫ moves the picked images to Trash, asking first when an open file embeds one.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.color(\.muted))
            }
            .padding(EdgeInsets(top: 28, leading: 40, bottom: 40, trailing: 40))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    AttachmentsBrowser(model: AppModel())
        .frame(width: 460, height: 500)
}
#endif
