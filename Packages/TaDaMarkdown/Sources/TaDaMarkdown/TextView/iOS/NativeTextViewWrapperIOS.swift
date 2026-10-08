//
//  NativeTextViewWrapperIOS.swift
//  TaDaMarkdown
//
//  The SwiftUI entry point on iOS, with the macOS wrapper's API where iOS
//  has an equivalent.
//

#if os(iOS)
import SwiftUI
import UIKit

public struct NativeTextViewWrapper: UIViewRepresentable {
    public typealias Coordinator = NativeTextViewCoordinator
    public typealias UIViewType = UITextView

    @Binding public var text: String
    public var configuration: MarkdownEditorConfiguration
    public var fontName: String
    public var fontSize: CGFloat
    public var documentId: String
    public var onLinkClick: ((String) -> Void)?
    public var onSlashCommandChange: ((SlashCommandState?) -> Void)?
    public var onSlashCommandKey: ((InlinePreviewKey) -> Bool)?
    public var slashCommandProxy: SlashCommandProxy?
    public var onTaskMarkerMenu: ((TaskMarkerMenuRequest) -> Void)?
    public var onCalloutMenu: ((CalloutMenuRequest) -> Void)?

    public init(
        text: Binding<String>,
        configuration: MarkdownEditorConfiguration = .default,
        fontName: String,
        fontSize: CGFloat,
        documentId: String,
        onLinkClick: ((String) -> Void)? = nil,
        onSlashCommandChange: ((SlashCommandState?) -> Void)? = nil,
        onSlashCommandKey: ((InlinePreviewKey) -> Bool)? = nil,
        slashCommandProxy: SlashCommandProxy? = nil,
        onTaskMarkerMenu: ((TaskMarkerMenuRequest) -> Void)? = nil,
        onCalloutMenu: ((CalloutMenuRequest) -> Void)? = nil
    ) {
        self._text = text
        self.configuration = configuration
        self.fontName = fontName
        self.fontSize = fontSize
        self.documentId = documentId
        self.onLinkClick = onLinkClick
        self.onSlashCommandChange = onSlashCommandChange
        self.onSlashCommandKey = onSlashCommandKey
        self.slashCommandProxy = slashCommandProxy
        self.onTaskMarkerMenu = onTaskMarkerMenu
        self.onCalloutMenu = onCalloutMenu
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, fontName: fontName, fontSize: fontSize, isWikiLinkActive: .constant(false),
                    onLinkClick: onLinkClick, onInlineSelectionChange: nil)
    }

    public func makeUIView(context: Context) -> UITextView {
        NativeTextView()
    }

    public func updateUIView(_ textView: UITextView, context: Context) {}
}
#endif
