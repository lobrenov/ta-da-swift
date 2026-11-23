// The vault menu: the folders opened on this Mac in a popup menu above the sidebar's folder line (⇧⌘O), then Open
// Another Vault…. A right-click on a vault opens the file menu with Reveal in Finder and Remove from List. File ▸ Open
// Vault lists the same vaults.
#if os(macOS)
import SwiftUI
import AppKit

/// A row of the vault menu.
enum VaultMenuItem: PopupMenuItem {
    case vault(RememberedVault)
    case openAnother

    var title: String {
        switch self {
        case .vault(let vault): vault.name
        case .openAnother: "Open Another Vault…"
        }
    }

    var accessibilityValue: String {
        guard case .vault(let vault) = self else { return "" }
        return [vault.isOpen ? "Current" : "", vault.isMissing ? "Not found" : vault.location]
            .filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// Vaults on this Mac under their label, then Open Another Vault… after a divider.
    static func sections(for vaults: [RememberedVault]) -> [PopupMenuSection<VaultMenuItem>] {
        [PopupMenuSection(label: "Vaults on this Mac", items: vaults.map { .vault($0) }),
         PopupMenuSection(items: [.openAnother])]
    }
}

/// Shows the vault menu and acts on its picks. Owned as a singleton, as the file menu is.
@Observable
final class VaultMenu {
    static let shared = VaultMenu()

    /// Bumped by ⇧⌘O and File ▸ Open Vault ▸ Show Vaults, for the sidebar to open the menu.
    var request = 0
    /// The folder picker is open for Open Another Vault… or a missing vault.
    var isChoosingFolder = false
    private(set) var isOpen = false

    @ObservationIgnored private lazy var menu = makeMenu()
    @ObservationIgnored private var context: (model: AppModel, window: NSWindow)?
    /// The folder line, in screen coordinates.
    @ObservationIgnored private var anchorRect = CGRect.zero
    /// When a mouse-down on the folder line closed the menu, so the click's own action doesn't reopen it.
    @ObservationIgnored private var closedByClick: TimeInterval?

    init() {
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    /// Opens the menu above `anchor`, or closes it when it's open, or when this click just closed it.
    func toggle(model: AppModel, anchor: ScreenAnchor) {
        guard let window = anchor.window else { return }
        let closedByThisClick = closedByClick.map { (NSApp.currentEvent?.timestamp ?? .infinity) - $0 < NSEvent.doubleClickInterval } ?? false
        closedByClick = nil
        let wasOpen = isOpen
        close()
        guard !wasOpen, !closedByThisClick else { return }
        model.reloadVaults()
        context = (model, window)
        anchorRect = anchor.rect
        isOpen = true
        menu.show(VaultMenuItem.sections(for: model.vaults), highlight: nil, theme: model.theme, below: anchorRect,
                  inset: 0, gap: 6, above: true, in: window) { [weak self] item in
            self?.close()
            self?.pick(item, model: model)
        }
    }

    func close() {
        menu.hide()
        context = nil
        isOpen = false
    }

    /// Switches to a vault, or opens the folder picker for a missing one and for Open Another Vault….
    func pick(_ item: VaultMenuItem, model: AppModel) {
        switch item {
        case .vault(let vault) where !vault.isMissing: Task { await model.switchVault(to: vault) }
        case .vault, .openAnother: isChoosingFolder = true
        }
    }

    /// Reveal in Finder (not for a missing vault) and Remove from List (not for the open vault).
    static func actions(for vault: RememberedVault, model: AppModel) -> [FileMenuAction] {
        let reveal = FileMenuAction(title: "Reveal in Finder", systemImage: "arrow.up.forward.square", shortcut: "",
                                    isEnabled: !vault.isMissing) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: vault.path)])
        }
        let remove = FileMenuAction(title: "Remove from List", systemImage: "xmark", shortcut: "") { model.forget(vault) }
        return vault.isOpen ? [reveal] : [reveal, remove]
    }

    /// A right-click on a vault row: the file menu at `point` (screen coordinates), where the vault menu was.
    fileprivate func showActions(for item: VaultMenuItem, at point: CGPoint) {
        guard case .vault(let vault) = item, let context else { return }
        let (model, window) = context
        close()
        FileMenu.shared.show(Self.actions(for: vault, model: model), at: point, in: window, theme: model.theme)
    }

    /// A click on the folder line closes the menu and notes it; any other click, a scroll or esc just closes it.
    private func dismiss() {
        if isOpen, let event = NSApp.currentEvent, event.type == .leftMouseDown, let window = event.window,
           window === context?.window, anchorRect.contains(window.convertPoint(toScreen: event.locationInWindow)) {
            closedByClick = event.timestamp
        }
        close()
    }

    private func makeMenu() -> PopupMenu<VaultMenuItem, VaultMenuRow> {
        var style = PopupMenuStyle.full(confirm: "Open", maxListHeight: 360)
        style.width = 320
        let menu = PopupMenu(style: style, takesKeys: true) { item, isHighlighted, theme in
            VaultMenuRow(item: item, isHighlighted: isHighlighted, theme: theme) { point in
                VaultMenu.shared.showActions(for: item, at: point)
            }
        }
        menu.onDismiss = { [weak self] in self?.dismiss() }
        return menu
    }
}

private struct VaultMenuRow: View {
    let item: VaultMenuItem
    let isHighlighted: Bool
    let theme: Theme
    let rightClick: (CGPoint) -> Void

    var body: some View {
        switch item {
        case .vault(let vault):
            HStack(spacing: 8) {
                Image(systemName: vault.isInICloud ? "icloud" : "folder")
                    .font(.system(size: 12))
                    .frame(width: 14)
                    .foregroundStyle(theme.color(isHighlighted ? \.accent : \.muted))
                Text(vault.name)
                    .foregroundStyle(theme.color(isHighlighted ? \.strong : \.fg))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(vault.isMissing ? "Not found" : vault.location)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.color(\.muted))
                    .lineLimit(1)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.color(\.accent))
                    .frame(width: 12)
                    .opacity(vault.isOpen ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
            .opacity(vault.isMissing ? 0.55 : 1)
            .overlay {
                RightClickReader { point, _ in rightClick(point) }
                    .accessibilityHidden(true)
            }
        case .openAnother:
            HStack(spacing: 8) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 12))
                    .frame(width: 14)
                    .foregroundStyle(theme.color(isHighlighted ? \.accent : \.muted))
                Text(item.title)
                    .foregroundStyle(theme.color(isHighlighted ? \.strong : \.fg))
                    .lineLimit(1)
                Spacer(minLength: 8)
            }
        }
    }
}
#endif
