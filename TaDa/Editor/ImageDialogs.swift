// The image dialogs the embed menu opens through `model.imageDialog`. Rename changes the image's name (its extension
// stays) and every `![[ ]]` that shows it. Delete lists the files that embed the image and moves it to Trash; their
// embeds show as missing until it's restored. On the Mac both are sheets; on iPhone, Rename is an alert and Delete a
// sheet.
import SwiftUI
import ImageIO
import TaDaCore

extension View {
    /// Shows `model.imageDialog`.
    func imageDialogs(_ model: AppModel) -> some View {
        modifier(ImageDialogPresenter(model: model))
    }
}

/// What the dialogs say about an image's embeds.
struct ImageDialogText {
    let model: AppModel
    let path: String

    var name: String { Item.title(ofPath: path) }
    var embedders: [(item: Item, count: Int)] { model.embedders(ofAttachment: path) }

    /// "Updates 3 embeds in 2 files."
    var renameSummary: String {
        let files = embedders, embeds = files.reduce(0) { $0 + $1.count }
        switch files.count {
        case 0: return "No file embeds it."
        case 1: return "Updates \(count(embeds, "embed")) in \(isOpen(files[0].item) ? "this file" : "“\(files[0].item.title)”")."
        default: return "Updates \(count(embeds, "embed")) in \(files.count) files."
        }
    }

    /// Whether `newPath`'s filename is another image's.
    func isTaken(_ newPath: String) -> Bool {
        Vault.attachmentName(of: newPath, isTakenBesides: path, in: model.attachments)
    }

    /// What deleting does to the embeds, in one sentence or (`sentences`) two.
    func deleteSummary(sentences: Bool = false) -> String {
        let files = embedders
        let who = switch files.count {
        case 0: "No file embeds it"
        case 1 where isOpen(files[0].item): "Only this file embeds it"
        case 1: "“\(files[0].item.title)” embeds it"
        default: "These \(files.count) files embed it"
        }
        guard !files.isEmpty else { return who + "." }
        let missing = files.count == 1 ? (sentences ? "The embed shows" : "its embed shows") : (sentences ? "Their embeds show" : "their embeds show")
        return who + (sentences ? ". " : "; ") + missing + " as missing until you restore the image."
    }

    func isOpen(_ item: Item) -> Bool { item.path == model.document?.path }

    /// A task's project or area, or Loose task; Project; Area.
    func place(of item: Item) -> String {
        switch item.properties.kind {
        case .task: model.index.parent(of: item)?.title ?? "Loose task"
        case .project: "Project"
        case .area: "Area"
        }
    }

    func icon(of item: Item) -> LinkChoice.Icon { model.linkIcon(of: item) }

    func count(_ n: Int, _ noun: String) -> String { n == 1 ? "1 \(noun)" : "\(n) \(noun)s" }
}

extension AppModel {
    /// The link menu's icon for `item`: its status box, progress ring or area icon.
    func linkIcon(of item: Item) -> LinkChoice.Icon {
        switch item.properties.kind {
        case .task: .task(item.properties.status)
        case .project: .project(index.progress(of: item).fraction)
        case .area: .area
        }
    }
}

/// An image file, scaled down to fill a rounded square.
struct ImageThumbnail: View {
    let url: URL?
    let side: CGFloat
    var cornerRadius: CGFloat = 8
    @Environment(\.theme) private var theme
    @Environment(\.displayScale) private var scale

    var body: some View {
        Color.clear
            .frame(width: side, height: side)
            .overlay {
                if let url, let image = Self.load(url, pixels: side * scale * 2) {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo").font(.system(size: side * 0.4)).foregroundStyle(theme.color(\.muted))
                }
            }
            .background(theme.color(\.code))
        .clipShape(.rect(cornerRadius: cornerRadius))
        .accessibilityHidden(true)
    }

    private static func load(_ url: URL, pixels: CGFloat) -> CGImage? {
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                       kCGImageSourceThumbnailMaxPixelSize: pixels] as CFDictionary
        return CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateThumbnailAtIndex($0, 0, options) }
    }
}

private struct ImageDialogPresenter: ViewModifier {
    @Bindable var model: AppModel
    #if os(iOS)
    @State private var newName = ""
    #endif

    func body(content: Content) -> some View {
        #if os(macOS)
        content.sheet(item: $model.imageDialog) { dialog in
            Group {
                switch dialog {
                case .rename(let path): RenameImageDialog(model: model, path: path)
                case .delete(let path): DeleteImageDialog(model: model, path: path)
                }
            }
            .presentationBackground(model.theme.color(model.theme.isDark ? \.side : \.bg))
        }
        #else
        let text = ImageDialogText(model: model, path: model.imageDialog?.path ?? "")
        let newPath = Vault.renamedAttachment(text.path, to: newName)
        content
            .sheet(item: Binding { model.imageDialog.flatMap { if case .delete = $0 { $0 } else { nil } } }
                         set: { if $0 == nil { model.imageDialog = nil } }) { dialog in
                PhoneDeleteImageSheet(model: model, path: dialog.path)
            }
            .alert("Rename Image", isPresented: Binding { if case .rename = model.imageDialog { true } else { false } }
                                                     set: { if !$0 { model.imageDialog = nil } }) {
                TextField("Name", text: $newName)
                Button("Rename") {
                    let path = text.path, name = newName
                    Task { await model.renameAttachment(path, to: name) }
                }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || newPath == text.path || text.isTaken(newPath))
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(text.isTaken(newPath) ? "An image named “\(Item.title(ofPath: newPath))” is already in the folder."
                     : "Keeps .\(FileNaming.split(text.name).ext). \(text.renameSummary)")
            }
            .onChange(of: model.imageDialog) {
                if case .rename(let path) = model.imageDialog { newName = FileNaming.split(Item.title(ofPath: path)).base }
            }
        #endif
    }
}

#if os(macOS)
/// The Mac's rename sheet: the name without its extension, and what it updates.
private struct RenameImageDialog: View {
    let model: AppModel
    let path: String
    @State private var name = ""
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let text = ImageDialogText(model: model, path: path)
        let ext = FileNaming.split(text.name).ext
        let newPath = Vault.renamedAttachment(path, to: name)
        let isTaken = text.isTaken(newPath)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ImageThumbnail(url: model.vault?.url(for: path), side: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rename “\(text.name)”")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(theme.color(\.strong))
                    Text("The file is renamed, and every embed of it follows.")
                        .foregroundStyle(theme.color(\.fg))
                    Text(path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.color(\.muted))
                }
            }
            HStack(spacing: 4) {
                TextField("Name", text: $name)
                    .textFieldStyle(.plain)
                    .foregroundStyle(theme.color(\.strong))
                    .onSubmit(rename)
                if !ext.isEmpty { Text(".\(ext)").foregroundStyle(theme.color(\.muted)) }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(theme.color(theme.isDark ? \.bg : \.side), in: .rect(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.color(isTaken ? \.deadline : \.border)))
            HStack(spacing: 10) {
                Text(isTaken ? "An image named “\(Item.title(ofPath: newPath))” is already in the folder." : text.renameSummary)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.color(isTaken ? \.deadline : \.muted))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Cancel") { dismiss() }
                    .buttonStyle(ActionButtonStyle(height: 28))
                    .keyboardShortcut(.cancelAction)
                Button("Rename", action: rename)
                    .buttonStyle(ActionButtonStyle(kind: .primary, height: 28))
                    .disabled(!canRename(newPath, isTaken: isTaken))
            }
        }
        .font(.system(size: 13))
        .padding(EdgeInsets(top: 20, leading: 22, bottom: 18, trailing: 22))
        .frame(width: 500)
        .onAppear { name = FileNaming.split(text.name).base }
    }

    private func canRename(_ newPath: String, isTaken: Bool) -> Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && newPath != path && !isTaken
    }

    private func rename() {
        let newPath = Vault.renamedAttachment(path, to: name)
        guard canRename(newPath, isTaken: ImageDialogText(model: model, path: path).isTaken(newPath)) else { return }
        let name = name
        dismiss()
        Task { await model.renameAttachment(path, to: name) }
    }
}

/// The Mac's delete sheet: the image, the files that embed it, and Delete.
private struct DeleteImageDialog: View {
    let model: AppModel
    let path: String
    @State private var search = LinkMenuSearch()
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let text = ImageDialogText(model: model, path: path)
        let files = text.embedders
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ImageThumbnail(url: model.vault?.url(for: path), side: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Delete “\(text.name)”?")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(theme.color(\.strong))
                    Text("The image goes to Trash. \(text.deleteSummary())")
                        .foregroundStyle(theme.color(\.fg))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(path + (size.map { " · \($0)" } ?? ""))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.color(\.muted))
                }
            }
            if !files.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("EMBEDDED IN")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(theme.color(\.muted))
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(files.enumerated()), id: \.element.item.path) { offset, file in
                                if offset > 0 { Hairline() }
                                row(file.item, count: file.count, text: text)
                            }
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(maxHeight: min(CGFloat(files.count) * 45, 300))
                    .background(theme.color(theme.isDark ? \.bg : \.side), in: .rect(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(theme.color(\.border)))
                }
            }
            HStack(spacing: 10) {
                Text("Restore in Trash brings it back to every embed.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.color(\.muted))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Cancel") { dismiss() }
                    .buttonStyle(ActionButtonStyle(height: 28))
                    .keyboardShortcut(.cancelAction)
                Button("Delete") {
                    dismiss()
                    Task { await model.trashAttachment(path) }
                }
                .buttonStyle(ActionButtonStyle(kind: .danger, height: 28))
                .keyboardShortcut(.defaultAction)
            }
        }
        .font(.system(size: 13))
        .padding(EdgeInsets(top: 20, leading: 22, bottom: 18, trailing: 22))
        .frame(width: 500)
    }

    /// The file's size, as Finder shows it.
    private var size: String? {
        guard let url = model.vault?.url(for: path),
              let bytes = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func row(_ item: Item, count: Int, text: ImageDialogText) -> some View {
        HStack(spacing: 10) {
            LinkChoiceIcon(icon: text.icon(of: item), search: search, theme: theme, size: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .foregroundStyle(theme.color(item.properties.status == .done ? \.muted : \.strong))
                Text(text.place(of: item))
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.color(\.muted))
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            if text.isOpen(item) {
                Text("This file")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.color(\.muted))
                    .padding(.horizontal, 6)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(theme.color(\.border)))
            }
            if count > 1 {
                Text(text.count(count, "embed")).font(.system(size: 11.5)).foregroundStyle(theme.color(\.muted))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }
}
#else
/// The iPhone's delete sheet: the image, the files that embed it, and Move to Trash.
private struct PhoneDeleteImageSheet: View {
    let model: AppModel
    let path: String
    @State private var search = LinkMenuSearch()
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let text = ImageDialogText(model: model, path: path)
        let files = text.embedders
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.glass)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 10) {
                        ImageThumbnail(url: model.vault?.url(for: path), side: 88, cornerRadius: 14)
                        Text("Move “\(text.name)” to Trash?")
                            .scaledFont(size: 22, weight: .bold)
                            .foregroundStyle(theme.color(\.strong))
                        Text(text.deleteSummary(sentences: true))
                            .scaledFont(size: 15)
                            .foregroundStyle(theme.color(\.fg))
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
                    if !files.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Embedded in")
                                .scaledFont(size: 13, weight: .semibold)
                                .foregroundStyle(theme.color(\.muted))
                                .padding(.horizontal, 4)
                            VStack(spacing: 0) {
                                ForEach(Array(files.enumerated()), id: \.element.item.path) { offset, file in
                                    if offset > 0 { Divider().overlay(theme.color(\.border)) }
                                    row(file.item, count: file.count, text: text)
                                }
                            }
                            .background(theme.color(theme.isDark ? \.code : \.side), in: .rect(cornerRadius: 14))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            VStack(spacing: 8) {
                Text("Restore in Trash brings it back to every embed.")
                    .scaledFont(size: 13)
                    .foregroundStyle(theme.color(\.muted))
                Button {
                    dismiss()
                    Task { await model.trashAttachment(path) }
                } label: {
                    Text("Move to Trash")
                        .scaledFont(size: 17, weight: .semibold)
                        .foregroundStyle(theme.color(\.bg))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(theme.color(\.deadline), in: .capsule)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .background(theme.color(theme.isDark ? \.side : \.bg))
        .presentationDetents([.medium, .large])
    }

    private func row(_ item: Item, count: Int, text: ImageDialogText) -> some View {
        let meta = [text.isOpen(item) ? "This file" : nil, text.place(of: item), count > 1 ? text.count(count, "embed") : nil]
        return HStack(spacing: 12) {
            LinkChoiceIcon(icon: text.icon(of: item), search: search, theme: theme, size: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .scaledFont(size: 17)
                    .foregroundStyle(theme.color(item.properties.status == .done ? \.muted : \.strong))
                Text(meta.compactMap { $0 }.joined(separator: " · "))
                    .scaledFont(size: 13)
                    .foregroundStyle(theme.color(\.muted))
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 56)
    }
}
#endif
