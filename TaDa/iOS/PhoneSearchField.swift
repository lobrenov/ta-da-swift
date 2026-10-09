// Pull to search: a list's search state, and the field each tab's navigation stack draws above its bar for the
// list on screen.
#if os(iOS)
import SwiftUI

/// A list's search: how far it's pulled past its top, whether search is open, and the query.
@Observable
final class ListSearch {
    /// How far past the top a list is pulled for search to open when the finger lifts.
    static let threshold: CGFloat = 60
    static let morph = Animation.spring(response: 0.42, dampingFraction: 0.84)

    var distance: CGFloat = 0
    /// Pulled past `threshold` while the finger is down; stays set while search is open.
    var isArmed = false
    var isOpen = false
    var isFocused = false
    var query = ""

    var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    func open() {
        // The keyboard comes once the field has landed: bringing it up holds the main thread for a moment.
        withAnimation(Self.morph) {
            isOpen = true
        } completion: { [self] in
            if isOpen { isFocused = true }
        }
    }

    func close() {
        isArmed = false
        query = ""
        isFocused = false
        withAnimation(Self.morph) { isOpen = false }
    }

    func reset() {
        isArmed = false
        query = ""
        isFocused = false
        isOpen = false
    }
}

/// The search of the list a navigation stack shows, which the stack draws.
@Observable
final class SearchHost {
    var search: ListSearch?
}

/// A tab's navigation stack, with the search field of its list drawn above the navigation bar, so the field and its
/// close button in the bar's row take taps.
struct PhoneSearchStack<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var host = SearchHost()

    var body: some View {
        let search = host.search
        content
            .environment(host)
            .overlay(alignment: .top) {
                if let search {
                    PullSearchField(search: search)
                        .id(ObjectIdentifier(search))
                        .ignoresSafeArea(.container, edges: .top)
                }
            }
    }
}

/// In the gap a pull opens above the title, a pill stretches with the pull and snaps into an accent dot at the
/// threshold; on release the dot grows into the search field in the navigation bar's row, with a close button where
/// the "…" was.
private struct PullSearchField: View {
    @Bindable var search: ListSearch
    @FocusState private var isFocused: Bool
    @Environment(\.theme) private var theme

    /// The navigation bar's row, under the status bar.
    private static let barRow: CGFloat = 44

    private var statusBar: CGFloat {
        let window = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        return window?.safeAreaInsets.top ?? 0
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let row = statusBar + Self.barRow / 2
            let gapTop = statusBar + Self.barRow
            let isDot = search.isArmed && !search.isOpen
            // At rest it waits as a dot in the bar's row, so closing shrinks the field in place.
            let isResting = !search.isOpen && !isDot && search.distance == 0
            let size = search.isOpen ? CGSize(width: width - 16 * 2 - 44 - 8, height: 40)
                : isDot || isResting ? CGSize(width: 40, height: 40)
                : CGSize(width: 36, height: max(36, search.distance - 12))
            let center = search.isOpen || isResting ? CGPoint(x: search.isOpen ? 16 + size.width / 2 : width / 2, y: row)
                : isDot ? CGPoint(x: width / 2, y: gapTop + search.distance / 2)
                : CGPoint(x: width / 2, y: gapTop + 6 + size.height / 2)
            ZStack {
                field(size: size, isDot: isDot)
                    .position(center)
                    .opacity(search.isOpen ? 1 : min(1, search.distance / 28))
                    .animation(.spring(response: 0.3, dampingFraction: 0.55), value: search.isArmed)
                Button("Cancel", systemImage: "xmark") { search.close() }
                    .labelStyle(.iconOnly)
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 44)
                    .contentShape(.circle)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .foregroundStyle(theme.color(\.strong))
                    .position(x: width - 16 - 22, y: row)
                    .opacity(search.isOpen ? 1 : 0)
                    .scaleEffect(search.isOpen ? 1 : 0.6)
                    .allowsHitTesting(search.isOpen)
            }
        }
        .onChange(of: search.isFocused) { isFocused = search.isFocused }
        .onChange(of: isFocused) { search.isFocused = isFocused }
    }

    private func field(size: CGSize, isDot: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.color(isDot ? \.bg : \.muted))
                .accessibilityHidden(true)
            if search.isOpen {
                TextField("Search", text: $search.query)
                    .focused($isFocused)
                    .submitLabel(.search)
                    .font(.system(size: 17))
                    .foregroundStyle(theme.color(\.fg))
                    .transition(.opacity.animation(.easeIn(duration: 0.15).delay(0.15)))
                if !search.query.isEmpty {
                    Button("Clear", systemImage: "xmark.circle.fill") { search.query = "" }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(theme.color(\.muted))
                }
            }
        }
        .padding(.horizontal, search.isOpen ? 12 : 0)
        .padding(.bottom, search.isOpen || isDot ? 0 : 9)
        .frame(width: size.width, height: size.height,
               alignment: search.isOpen ? .leading : isDot ? .center : .bottom)
        .background(isDot ? theme.color(\.accent) : theme.color(\.surface).opacity(0.5), in: .capsule)
        .clipShape(.capsule)
        .overlay {
            Circle()
                .strokeBorder(theme.color(\.accent), lineWidth: 2)
                .keyframeAnimator(initialValue: 0.0, trigger: search.isArmed) { ring, phase in
                    ring.scaleEffect(1 + (1 - phase) * 0.9).opacity(isDot ? phase * 0.6 : 0)
                } keyframes: { _ in
                    LinearKeyframe(1.0, duration: 0)
                    LinearKeyframe(0.0, duration: 0.38)
                }
                .frame(width: 40, height: 40)
                .allowsHitTesting(false)
        }
        .allowsHitTesting(search.isOpen)
    }
}
#endif
