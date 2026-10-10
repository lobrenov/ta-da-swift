// Deleting files that embed images: the images each file embeds, ticked to go to Trash with it. An image another file
// still embeds starts unticked. A Mac sheet (ContentView shows it) and an iPhone sheet (PhoneRootView shows it), for
// `model.trashConfirmation` when it lists images; an area that embeds none asks with an alert instead.
import SwiftUI
import TaDaCore

/// The ticks: each image starts ticked unless another file still embeds it, and `toggled` holds the ones flipped.
private struct ImageTicks {
    let request: AppModel.TrashConfirmation
    var toggled: Set<String>

    func isTicked(_ image: AppModel.TrashImage) -> Bool { image.keptIn.isEmpty != toggled.contains(image.path) }

    var ticked: [String] { request.images.flatMap(\.images).filter(isTicked).map(\.path) }

    mutating func toggle(_ image: AppModel.TrashImage) {
        if toggled.remove(image.path) == nil { toggled.insert(image.path) }
    }
}

/// An image's tick, thumbnail, name and what else embeds it, as one toggle.
private struct ImageTickRow: View {
    let model: AppModel
    let image: AppModel.TrashImage
    let isTicked: Bool
    let phone: Bool
    let toggle: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        let note = TrashConfirmationText.note(for: image, ticked: isTicked, phone: phone)
        Button(action: toggle) {
            HStack(spacing: 12) {
                tick
                ImageThumbnail(url: model.vault?.url(for: image.path), side: phone ? 44 : 34, cornerRadius: phone ? 8 : 5)
                    .opacity(isTicked ? 1 : 0.55)
                VStack(alignment: .leading, spacing: phone ? 2 : 1) {
                    Text(Item.title(ofPath: image.path))
                        .font(.system(size: phone ? 17 : 13))
                        .foregroundStyle(theme.color(isTicked ? \.strong : \.fg))
                    Text("\(note.before)\(Text(note.titles).foregroundStyle(theme.color(\.link)))\(note.after)")
                        .font(.system(size: phone ? 13 : 11.5))
                        .foregroundStyle(theme.color(\.muted))
                }
                .lineLimit(1)
                .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isTicked ? "Goes to Trash" : "Stays")
    }

    /// A rounded square on the Mac, a circle on iPhone.
    private var tick: some View {
        let side: CGFloat = phone ? 24 : 16
        let shape = RoundedRectangle(cornerRadius: phone ? side / 2 : 4)
        return ZStack {
            if isTicked {
                shape.fill(theme.color(\.accent))
                Image(systemName: "checkmark")
                    .font(.system(size: phone ? 12 : 9, weight: .heavy))
                    .foregroundStyle(theme.color(\.bg))
            } else {
                shape.strokeBorder(theme.color(\.muted), lineWidth: phone ? 1.75 : 1.5)
            }
        }
        .frame(width: side, height: side)
    }
}

/// A file's icon and title above its images, when the dialog lists more than one file.
private struct GroupHeader: View {
    let model: AppModel
    let item: Item
    let search: LinkMenuSearch
    let phone: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            LinkChoiceIcon(icon: model.linkIcon(of: item), search: search, theme: theme, size: 14)
            Text(item.title)
                .font(.system(size: phone ? 13 : 12.5, weight: .semibold))
                .foregroundStyle(theme.color(phone ? \.muted : \.strong))
                .lineLimit(1)
            Spacer(minLength: 8)
            if !phone {
                Text(item.properties.kind.rawValue)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(theme.color(\.muted))
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

#if os(macOS)
/// The Mac's sheet: the files' images under each file, the count, Cancel and Delete.
struct DeleteFilesDialog: View {
    let model: AppModel
    let request: AppModel.TrashConfirmation
    @State private var toggled: Set<String> = []
    @State private var search = LinkMenuSearch()
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let text = TrashConfirmationText(model: model, request: request)
        let ticks = ImageTicks(request: request, toggled: toggled)
        let isGrouped = request.count > 1
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Delete \(text.subject)?")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(theme.color(\.strong))
                Text(text.imagesMessage(phone: false))
                    .foregroundStyle(theme.color(\.fg))
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(request.images.enumerated()), id: \.element.item.path) { offset, group in
                        if offset > 0 { Hairline() }
                        if isGrouped {
                            GroupHeader(model: model, item: group.item, search: search, phone: false)
                                .padding(.horizontal, 12)
                                .frame(height: 30)
                        }
                        ForEach(group.images, id: \.path) { image in
                            ImageTickRow(model: model, image: image, isTicked: ticks.isTicked(image), phone: false) {
                                var ticks = ticks
                                ticks.toggle(image)
                                toggled = ticks.toggled
                            }
                            .padding(.leading, isGrouped ? 34 : 12)
                            .padding(.trailing, 12)
                            .frame(height: 50)
                        }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: min(listHeight(grouped: isGrouped), 388))
            .background(theme.color(theme.isDark ? \.bg : \.side), in: .rect(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(theme.color(\.border)))
            HStack(spacing: 10) {
                Text(text.imagesSummary(ticked: ticks.ticked.count, phone: false))
                    .font(.system(size: 12))
                    .foregroundStyle(theme.color(\.muted))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Cancel") { dismiss() }
                    .buttonStyle(ActionButtonStyle(height: 28))
                    .keyboardShortcut(.cancelAction)
                Button("Delete") {
                    let images = ticks.ticked
                    dismiss()
                    Task { await model.confirmTrash(request, images: images) }
                }
                .buttonStyle(ActionButtonStyle(kind: .danger, height: 28))
                .keyboardShortcut(.defaultAction)
            }
        }
        .font(.system(size: 13))
        .padding(EdgeInsets(top: 20, leading: 22, bottom: 18, trailing: 22))
        .frame(width: 540)
    }

    private func listHeight(grouped: Bool) -> CGFloat {
        request.images.reduce(0) { $0 + (grouped ? 30 : 0) + CGFloat($1.images.count) * 50 }
    }
}
#else
/// The iPhone's sheet: Cancel, the files' images under each file, the count and Move to Trash, which hands `confirm` the
/// ticked images.
struct PhoneDeleteFilesSheet: View {
    let model: AppModel
    let request: AppModel.TrashConfirmation
    let confirm: (_ images: [String]) -> Void
    @State private var toggled: Set<String> = []
    @State private var search = LinkMenuSearch()
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let text = TrashConfirmationText(model: model, request: request)
        let ticks = ImageTicks(request: request, toggled: toggled)
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.glass)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            VStack(alignment: .leading, spacing: 6) {
                Text("Move \(text.subject) to Trash?")
                    .scaledFont(size: 22, weight: .bold)
                    .foregroundStyle(theme.color(\.strong))
                Text(text.imagesMessage(phone: true))
                    .scaledFont(size: 15)
                    .foregroundStyle(theme.color(\.fg))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 10, leading: 20, bottom: 14, trailing: 20))
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(request.images, id: \.item.path) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            if request.count > 1 {
                                GroupHeader(model: model, item: group.item, search: search, phone: true)
                                    .padding(.horizontal, 4)
                            }
                            VStack(spacing: 0) {
                                ForEach(Array(group.images.enumerated()), id: \.element.path) { offset, image in
                                    if offset > 0 { Divider().overlay(theme.color(\.border)) }
                                    ImageTickRow(model: model, image: image, isTicked: ticks.isTicked(image), phone: true) {
                                        var ticks = ticks
                                        ticks.toggle(image)
                                        toggled = ticks.toggled
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .frame(minHeight: 60)
                                }
                            }
                            .background(theme.color(theme.isDark ? \.code : \.side), in: .rect(cornerRadius: 14))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            VStack(spacing: 8) {
                Text(text.imagesSummary(ticked: ticks.ticked.count, phone: true))
                    .scaledFont(size: 13)
                    .foregroundStyle(theme.color(\.muted))
                    .multilineTextAlignment(.center)
                Button {
                    let images = ticks.ticked
                    dismiss()
                    confirm(images)
                } label: {
                    Text(request.count == 1 ? "Move to Trash" : "Move \(request.count) Files to Trash")
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
            .overlay(alignment: .top) { Divider().overlay(theme.color(\.border)) }
        }
        .background(theme.color(theme.isDark ? \.side : \.bg))
        .presentationDetents(request.count > 1 ? [.large] : [.medium, .large])
    }
}
#endif
