//
//  InlineBubble.swift
//  TaDaMarkdown
//
//  Ta Da fork: a rounded fill behind an inline span (inline code, a
//  highlight), drawn again on each line the span wraps onto. Set it on
//  `InlineCodeStyle.bubble`, or return it from `MarkdownExtension.bubble(theme:)`.
//

import AppKit

public struct InlineBubble: Sendable, Equatable {
    public var fill: NSColor
    /// A 1pt ring inside the bubble's edge; none when nil.
    public var ring: NSColor?
    /// The span's text colour; nil keeps the surrounding colour.
    public var text: NSColor?
    /// Space between the text and the bubble's left and right edges.
    public var horizontalPadding: CGFloat
    /// Space between the bubble and the text beside it; negative overlaps it.
    public var margin: CGFloat
    /// How far the bubble reaches above the ascender and below the descender.
    public var verticalPadding: CGFloat
    public var cornerRadius: CGFloat

    public init(fill: NSColor, ring: NSColor? = nil, text: NSColor? = nil, horizontalPadding: CGFloat,
                margin: CGFloat = 0, verticalPadding: CGFloat = 2, cornerRadius: CGFloat = 6) {
        self.fill = fill
        self.ring = ring
        self.text = text
        self.horizontalPadding = horizontalPadding
        self.margin = margin
        self.verticalPadding = verticalPadding
        self.cornerRadius = cornerRadius
    }

    /// The advance a hidden marker takes on each side, so the text clears the bubble's padding.
    var markerAdvance: CGFloat { horizontalPadding + margin }
}

/// The `.markdownInlineBubble` value: one object per span, so its runs join up when fonts split them.
final class InlineBubbleSpan: NSObject {
    let bubble: InlineBubble

    init(_ bubble: InlineBubble) {
        self.bubble = bubble
    }
}

extension NSAttributedString.Key {
    /// Ta Da fork: an `InlineBubbleSpan` over a whole span, its markers included.
    static let markdownInlineBubble = NSAttributedString.Key("MarkdownInlineBubble")
}
