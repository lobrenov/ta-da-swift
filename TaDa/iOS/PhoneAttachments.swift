// Attachments, pushed from the Other tab: the images in `Ta Da/attachments/` in two groups, "Not in open files" (what
// Clean Up moves to Trash) and "In open files". A tap opens an image, "…" ▸ Select or a swipe picks several, and the
// bar at the bottom holds Clean Up… or Move to Trash. One image shows its preview, details and the files that embed it.
#if os(iOS)
import SwiftUI
import TaDaCore

struct PhoneAttachmentsScreen: View {
    let model: AppModel
    @State private var isCleaningUp = false
    @State private var isFirstAppearance = true
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    var body: some View {
        let groups = model.attachmentGroups
        let all = groups.candidates + groups.inUse
        PhoneList(model: model, title: "Attachments", subtitle: subtitle(groups, all: all), icon: AnyView(icon),
                  pickable: all.map(\.id), pickingActions: AnyView(AttachmentsPickingBar(model: model)),
                  searchResults: { query in AnyView(results(groups, query: query)) },
                  menu: {}, content: {
            if let note = model.attachmentNote {
                Text(note)
                    .scaledFont(size: 13)
                    .foregroundStyle(theme.color(\.done))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            list(groups)
        })
        .overlay {
            if all.isEmpty {
                ContentUnavailableView("No attachments", systemImage: AppModel.Domain.attachments.systemImage,
                                       description: Text("Images you paste or drop into a file are saved in `\(Vault.attachmentFolder)`."))
            }
        }
        .overlay(alignment: .bottom) {
            if !nav.isPicking { browsingBar(groups) }
        }
        .background { TabBarHiddenOnTop() }
        .sheet(isPresented: $isCleaningUp) { PhoneCleanUpSheet(model: model) }
        .onAppear {
            guard isFirstAppearance else { return }
            isFirstAppearance = false
            model.attachmentNote = nil
        }
    }

    private var icon: some View {
        Image(systemName: AppModel.Domain.attachments.systemImage)
            .scaledFont(size: 28)
            .foregroundStyle(theme.color(\.link))
            .accessibilityHidden(true)
    }

    /// "12 images · 16.2 MB", or the picked images' count and size while picking.
    private func subtitle(_ groups: AttachmentGroups, all: [AttachmentUse]) -> String {
        if nav.isPicking {
            let picked = all.filter { nav.picked.contains($0.id) }.map(\.attachment)
            return "\(picked.count) selected · \(Attachment.sizeText(Attachment.totalSize(of: picked)))"
        }
        return all.isEmpty ? "" : "\(Attachment.countText(all.count)) · \(Attachment.sizeText(groups.totalSize))"
    }

    @ViewBuilder private func list(_ groups: AttachmentGroups) -> some View {
        if !groups.candidates.isEmpty {
            header("Not in open files", note: "\(Attachment.countText(groups.candidates.count)) · \(Attachment.sizeText(groups.candidatesSize))")
            ForEach(groups.candidates) { AttachmentRow(model: model, use: $0) }
        }
        if !groups.inUse.isEmpty {
            header("In open files", note: Attachment.countText(groups.inUse.count))
            ForEach(groups.inUse) { AttachmentRow(model: model, use: $0) }
        }
    }

    /// The images whose name or embedding files contain what's typed, in their groups.
    private func results(_ groups: AttachmentGroups, query: String) -> some View {
        func matches(_ use: AttachmentUse) -> Bool {
            use.attachment.name.localizedStandardContains(query)
                || (use.live + use.logged + use.trashed.map(\.item)).contains { $0.title.localizedStandardContains(query) }
        }
        let found = AttachmentGroups(groups.candidates.filter(matches) + groups.inUse.filter(matches))
        return LazyVStack(alignment: .leading, spacing: 0) {
            if found.candidates.isEmpty, found.inUse.isEmpty {
                ContentUnavailableView.search(text: query).padding(.top, 60)
            }
            list(found)
            PickingBarClearance()
        }
    }

    private func header(_ title: String, note: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title.uppercased())
                .scaledFont(size: 13, weight: .semibold)
                .tracking(0.3)
            Spacer()
            Text(note).scaledFont(size: 13)
        }
        .foregroundStyle(theme.color(\.muted))
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// How many images no open file embeds, and Clean Up….
    private func browsingBar(_ groups: AttachmentGroups) -> some View {
        let unused = groups.candidates.count
        return PhoneBottomBar {
            HStack(spacing: 8) {
                Text(unused == 0 ? "Every image is in an open file" : "\(unused) not in open files")
                    .scaledFont(size: 15)
                    .foregroundStyle(theme.color(\.muted))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Button("Clean Up…") {
                    model.attachmentNote = nil
                    isCleaningUp = true
                }
                .buttonStyle(.glassProminent)
                .tint(theme.color(\.accent))
                .disabled(unused == 0)
            }
            .padding(.leading, 18)
            .padding(.trailing, 8)
        }
    }
}

/// While images are picked: how many, and Move to Trash, which asks first when an open file embeds one.
private struct AttachmentsPickingBar: View {
    let model: AppModel
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    var body: some View {
        let paths = nav.picked
        HStack(spacing: 8) {
            Text("\(paths.count) selected")
                .scaledFont(size: 15)
                .foregroundStyle(theme.color(\.muted))
            Spacer(minLength: 0)
            Button("Move \(paths.count) to Trash") {
                let asks = paths.contains { model.attachmentUse(at: $0)?.isInUse == true }
                if !asks {
                    nav.play(.trash)
                    nav.endPicking()
                }
                Task { await model.moveAttachmentsToTrash(Set(paths)) }
            }
            .buttonStyle(.glassProminent)
            .tint(theme.color(\.deadline))
            .disabled(paths.isEmpty)
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
    }
}

/// A row: the thumbnail, filename (with a cloud when iCloud Drive hasn't downloaded it), where it's embedded and its size.
private struct AttachmentRow: View {
    let model: AppModel
    let use: AttachmentUse
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    var body: some View {
        let image = use.attachment
        let isPicked = nav.picked.contains(use.id)
        VStack(spacing: 0) {
            Button {
                if nav.isPicking { nav.togglePicked(use.id) } else { nav.push(.attachment(use.id)) }
            } label: {
                HStack(spacing: 12) {
                    if nav.isPicking {
                        Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                            .scaledFont(size: 22)
                            .foregroundStyle(isPicked ? theme.color(\.accent) : theme.color(\.border))
                            .transition(.opacity.animation(PhoneNavigation.pickFade))
                            .accessibilityHidden(true)
                    }
                    ImageThumbnail(url: image.isDownloaded ? model.vault?.url(for: image.path) : nil, side: 44, cornerRadius: 8)
                        .opacity(image.isDownloaded ? 1 : 0.45)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(image.name)
                                .scaledFont(size: 17)
                                .foregroundStyle(theme.color(\.fg))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if !image.isDownloaded {
                                Image(systemName: "icloud.and.arrow.down")
                                    .scaledFont(size: 14)
                                    .foregroundStyle(theme.color(\.muted))
                                    .accessibilityLabel("Not downloaded")
                            }
                        }
                        AttachmentWhereText(line: use.whereLine, linkTint: use.isInUse ? \.link : \.fg)
                            .scaledFont(size: 13)
                            .foregroundStyle(theme.color(\.muted))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(image.sizeText).scaledFont(size: 13).foregroundStyle(theme.color(\.muted))
                    if !nav.isPicking {
                        Image(systemName: "chevron.right")
                            .scaledFont(size: 13, weight: .semibold)
                            .foregroundStyle(theme.color(\.muted))
                            .accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isPicked ? .isSelected : [])
        }
        .background {
            // An opaque base under the highlight, so the swipe's pill stays hidden behind the row.
            ZStack {
                theme.color(\.bg)
                theme.color(\.accent).opacity(isPicked ? (theme.isDark ? 0.16 : 0.1) : 0)
                    .animation(PhoneNavigation.pickFade, value: isPicked)
            }
        }
        .swipeToPick(use.id)
    }
}

// MARK: One image

/// One image: a large preview, its details, the files that embed it, and Share, Rename and Move to Trash. An image
/// iCloud Drive hasn't sent is asked for on open, and shows a placeholder until it arrives.
struct PhoneAttachmentScreen: View {
    let model: AppModel
    let path: String
    @State private var dimensions: String?
    @State private var downloadFailed = false
    /// Bumped by Try Again to restart the download.
    @State private var downloadAttempt = 0
    @State private var search = LinkMenuSearch()
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            theme.color(\.bg).ignoresSafeArea()
            if let use = model.attachmentUse(at: path) { content(use) }
        }
        .navigationBarTitleDisplayMode(.inline)
        .background { TabBarHiddenOnTop() }
        .toolbar { actions }
        .onChange(of: model.renamedAttachment) { _, rename in followRename(rename) }
        .onChange(of: model.attachments) { _, new in if !new.contains(path), model.renamedAttachment?.from != path { nav.dropAttachment(path) } }
    }

    private func content(_ use: AttachmentUse) -> some View {
        let image = use.attachment
        let url = model.vault?.url(for: image.path)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    AttachmentPreview(url: image.isDownloaded ? url : nil, cornerRadius: 16)
                        .overlay { if !image.isDownloaded { downloading } }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(image.name)
                            .scaledFont(size: 24, weight: .bold)
                            .foregroundStyle(theme.color(\.strong))
                            .textSelection(.enabled)
                        Text(image.metaText(dimensions: dimensions))
                            .scaledFont(size: 15)
                            .foregroundStyle(theme.color(\.muted))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                embeds(use)
                PickingBarClearance()
            }
        }
        .task(id: "\(image.path) \(image.isDownloaded) \(downloadAttempt)") {
            dimensions = nil
            downloadFailed = false
            if image.isDownloaded {
                guard let url, let size = await ImageMetadata.pixelSize(of: url) else { return }
                dimensions = "\(size.width) × \(size.height)"
            } else {
                await download(image)
            }
        }
    }

    /// Asks iCloud Drive for the image, then re-reads the folder once it's there.
    private func download(_ image: Attachment) async {
        await model.downloadAttachment(image.path)
        guard let url = model.vault?.url(for: image.path) else { return }
        for _ in 0..<60 {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return }
            if FileManager.default.fileExists(atPath: url.path) {
                await model.refresh()
                return
            }
        }
        downloadFailed = true
    }

    private var downloading: some View {
        VStack(spacing: 10) {
            if downloadFailed {
                Image(systemName: "icloud.slash").scaledFont(size: 26)
                Text("Couldn’t download from iCloud Drive").scaledFont(size: 15)
                Button("Try Again") { downloadAttempt += 1 }
                    .buttonStyle(.glassProminent)
                    .tint(theme.color(\.accent))
            } else {
                ProgressView()
                Text("Downloading from iCloud Drive…").scaledFont(size: 15)
            }
        }
        .foregroundStyle(theme.color(\.strong))
    }

    @ViewBuilder private func embeds(_ use: AttachmentUse) -> some View {
        let count = use.live.count + use.logged.count + use.trashed.count
        Text(count == 0 ? "Embedded in" : "Embedded in · \(count)")
            .scaledFont(size: 13)
            .foregroundStyle(theme.color(\.muted))
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 7)
            .accessibilityAddTraits(.isHeader)
        if count == 0 {
            Text("No file embeds it. Clean Up moves it to Trash.")
                .scaledFont(size: 15)
                .foregroundStyle(theme.color(\.muted))
                .padding(.horizontal, 32)
        } else {
            VStack(spacing: 0) {
                let rows = use.live.map { Embed(item: $0, place: AttachmentUse.livePlace($0), state: .live) }
                    + use.logged.map { Embed(item: $0, place: AttachmentUse.loggedPlace($0), state: .logged) }
                    + use.trashed.map { Embed(item: $0.item, place: "Trash", state: .trashed) }
                ForEach(Array(rows.enumerated()), id: \.offset) { offset, embed in
                    if offset > 0 { Divider().overlay(theme.color(\.border)).padding(.leading, 50) }
                    row(embed)
                }
            }
            .background(theme.color(theme.isDark ? \.code : \.side), in: .rect(cornerRadius: 14))
            .padding(.horizontal, 16)
        }
    }

    private struct Embed {
        enum State { case live, logged, trashed }
        let item: Item
        let place: String
        let state: State
    }

    /// A file that embeds the image: its title and where it is. A live or logged file opens; a trashed one opens Trash.
    private func row(_ embed: Embed) -> some View {
        Button {
            nav.push(embed.state == .trashed ? .trash : .file(embed.item.path))
        } label: {
            HStack(spacing: 12) {
                LinkChoiceIcon(icon: model.linkIcon(of: embed.item), search: search, theme: theme, size: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(embed.item.title)
                        .scaledFont(size: 17)
                        .foregroundStyle(theme.color(embed.state == .live ? \.fg : \.muted))
                        .strikethrough(embed.state == .logged)
                        .lineLimit(1)
                    Text(embed.place).scaledFont(size: 13).foregroundStyle(theme.color(\.muted)).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .scaledFont(size: 13, weight: .semibold)
                    .foregroundStyle(theme.color(\.muted))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .scaledMinHeight(56)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    @ToolbarContentBuilder private var actions: some ToolbarContent {
        let use = model.attachmentUse(at: path)
        ToolbarItem(placement: .bottomBar) {
            if let url = model.vault?.url(for: path), use?.attachment.isDownloaded == true {
                ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
            }
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
            Button("Rename") { model.imageDialog = .rename(path) }
                .disabled(use == nil)
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
            Button {
                if use?.isInUse != true { nav.play(.trash) }
                Task { await model.moveAttachmentsToTrash([path]) }
            } label: {
                Label("Move to Trash", systemImage: "trash").labelStyle(.titleAndIcon)
            }
            .tint(theme.color(\.deadline))
            .disabled(use == nil)
        }
    }

    /// Points the screen at the new path when this image is renamed.
    private func followRename(_ rename: AppModel.AttachmentRename?) {
        guard let rename, rename.from == path else { return }
        nav.replace(.attachment(rename.from), with: .attachment(rename.to))
    }
}

// MARK: Clean Up

/// The Clean Up sheet: the images no open file embeds, grouped by why, each ticked to move to Trash. While files are
/// still downloading from iCloud Drive, nothing starts ticked.
private struct PhoneCleanUpSheet: View {
    let model: AppModel
    @State private var ticks = CleanUpTicks()
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let groups = model.attachmentGroups
        let candidates = groups.candidates
        let ticked = ticks.ticked(in: candidates)
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.glass)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(CleanUpText.title(count: candidates.count))
                            .scaledFont(size: 22, weight: .bold)
                            .foregroundStyle(theme.color(\.strong))
                        Text(CleanUpText.explanation)
                            .scaledFont(size: 15)
                            .foregroundStyle(theme.color(\.fg))
                    }
                    .padding(.horizontal, 4)
                    if !groups.pendingFiles.isEmpty { pending(groups.pendingFiles.count) }
                    ForEach(CleanUpSection.sections(of: candidates), id: \.title) { section($0) }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            VStack(spacing: 8) {
                Text(CleanUpText.summary(ticked: ticked, of: candidates.count))
                    .scaledFont(size: 13)
                    .foregroundStyle(theme.color(\.muted))
                Button {
                    let paths = ticked.map(\.id)
                    nav.play(.trash)
                    dismiss()
                    Task { await model.trashAttachments(paths) }
                } label: {
                    Text("Move \(ticked.count) to Trash")
                        .scaledFont(size: 17, weight: .semibold)
                        .foregroundStyle(theme.color(ticked.isEmpty ? \.muted : \.bg))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(theme.color(ticked.isEmpty ? \.surface : \.deadline), in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(ticked.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .overlay(alignment: .top) { Hairline() }
        }
        .background(theme.color(theme.isDark ? \.side : \.bg))
        .presentationDetents([.large])
        .onAppear { ticks.start(groups) }
        .onChange(of: candidates.isEmpty) { _, isEmpty in if isEmpty { dismiss() } }
    }

    private func pending(_ count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "icloud.and.arrow.down")
                .foregroundStyle(theme.color(\.due))
                .accessibilityHidden(true)
            Text(CleanUpText.pending(count: count))
                .scaledFont(size: 15)
                .foregroundStyle(theme.color(\.fg))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.color(theme.isDark ? \.code : \.side), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.color(\.due)))
    }

    private func section(_ section: CleanUpSection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle().fill(theme.color(section.tint)).frame(width: 7, height: 7)
                Text(section.title)
            }
            .scaledFont(size: 13, weight: .semibold)
            .foregroundStyle(theme.color(\.muted))
            .padding(.horizontal, 4)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(section.uses.enumerated()), id: \.element.id) { offset, use in
                    if offset > 0 { Divider().overlay(theme.color(\.border)) }
                    row(use)
                }
            }
            .background(theme.color(theme.isDark ? \.code : \.side), in: .rect(cornerRadius: 14))
        }
    }

    private func row(_ use: AttachmentUse) -> some View {
        let image = use.attachment
        let isOn = ticks.isTicked(use)
        return Button {
            ticks.toggle(use)
            nav.play(.pick)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .scaledFont(size: 24)
                    .foregroundStyle(isOn ? theme.color(\.accent) : theme.color(\.muted))
                    .accessibilityHidden(true)
                ImageThumbnail(url: image.isDownloaded ? model.vault?.url(for: image.path) : nil, side: 44, cornerRadius: 8)
                    .opacity(isOn ? 1 : 0.55)
                VStack(alignment: .leading, spacing: 2) {
                    Text(image.name)
                        .scaledFont(size: 17)
                        .foregroundStyle(theme.color(isOn ? \.strong : \.fg))
                    Group {
                        if use.closedTitles.isEmpty {
                            Text(image.addedText.map { "Added \($0)" } ?? "")
                        } else {
                            Text("Embedded in \(Text(use.closedTitles).foregroundStyle(theme.color(\.link)))")
                        }
                    }
                    .scaledFont(size: 13)
                    .foregroundStyle(theme.color(\.muted))
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .scaledMinHeight(60)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

#Preview {
    NavigationStack {
        PhoneAttachmentsScreen(model: AppModel())
    }
    .environment(PhoneNavigation())
    .environment(SearchHost())
}
#endif
