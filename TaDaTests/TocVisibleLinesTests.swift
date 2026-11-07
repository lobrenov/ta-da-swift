#if os(macOS)
import AppKit
import SwiftUI
import Testing
import TaDaCore
import MarkdownEngine
@testable import TaDa

/// The page's visible lines at the top and after scrolling, in the real document layout: the editor in `fitsContent` inside the
/// page's `ScrollView`, as `LiveDocumentView` builds it.
@MainActor
struct TocVisibleLinesTests {
    /// 40 headings spread over about 300 lines.
    static let body: String = (0..<40).map { section in
        "## Heading \(section)\n" + (0..<6).map { "Line \(section)-\($0) of the section with some words in it." }.joined(separator: "\n") + "\n"
    }.joined(separator: "\n")

    private struct Page: View {
        let model: AppModel
        let document: OpenDocument
        let toc: TocState

        var body: some View {
            GeometryReader { viewport in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        TitleField(model: model, document: document, size: 23)
                        if let item = document.item { PropertyChips(model: model, item: item) }
                        Hairline()
                        BodyEditor(model: model, document: document, toc: toc)
                        Spacer(minLength: 0)
                        DocumentFooter(document: document)
                    }
                    .padding(.horizontal, 44)
                    .padding(.top, 30)
                    .padding(.bottom, 40)
                    .frame(minHeight: viewport.size.height, alignment: .top)
                }
            }
            .tocPanel(model: model, document: document, state: toc)
        }
    }

    private func findTextView(_ view: NSView) -> NSTextView? {
        if String(describing: type(of: view)) == "NativeTextView" { return view as? NSTextView }
        for sub in view.subviews { if let found = findTextView(sub) { return found } }
        return nil
    }

    @Test func visibleLinesFollowThePageViewport() async throws {
        let folder = try TestFolder(["tasks/Long.md": "---\ntype: task\n---\n" + Self.body])
        let model = await folder.model(selecting: "tasks/Long.md")
        let document = try #require(model.document)
        let toc = TocState()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: Page(model: model, document: document, toc: toc).themed(by: model))
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(800))
        let content = try #require(window.contentView)
        let textView = try #require(findTextView(content))
        let lineCount = Self.body.split(separator: "\n", omittingEmptySubsequences: false).count
        #expect(toc.visibleLines.lowerBound == 0)
        #expect(toc.visibleLines.upperBound > 5 && toc.visibleLines.upperBound < 60, "top \(toc.visibleLines)")

        var scroller: NSView? = textView
        while let view = scroller, !(view is NSScrollView && view !== textView.enclosingScrollView) { scroller = view.superview }
        let page = try #require(scroller as? NSScrollView)
        func scroll(to y: CGFloat) async throws {
            page.contentView.scroll(to: NSPoint(x: 0, y: y))
            page.reflectScrolledClipView(page.contentView)
            try await Task.sleep(for: .milliseconds(200))
        }
        try await scroll(to: 4000)
        let middle = toc.visibleLines
        #expect(middle.lowerBound > 100 && middle.upperBound - middle.lowerBound > 5 && middle.upperBound - middle.lowerBound < 60, "middle \(middle)")
        try await scroll(to: try #require(page.documentView).frame.height - page.contentView.bounds.height + page.contentInsets.bottom)
        #expect(toc.visibleLines.upperBound >= lineCount - 3 && toc.visibleLines.lowerBound > 250, "bottom \(toc.visibleLines)")
        try await scroll(to: -32)
        #expect(toc.visibleLines.lowerBound == 0 && toc.visibleLines.upperBound < 60, "back at the top \(toc.visibleLines)")
        window.orderOut(nil)
    }
}
#endif
