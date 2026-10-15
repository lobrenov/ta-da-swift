// Format menu (⌘B, ⌘I, ⇧⌘H, ⇧⌘S): toggles an inline format on the Live editor's selection, or the word at the caret,
// or inserts its pair of markers with the caret between them.
#if os(macOS)
import SwiftUI

enum InlineFormat {
    case bold, italic, highlight, strikethrough
}

/// The Live editor, which publishes itself as a focused value while it has the keyboard.
protocol InlineFormatting: AnyObject {
    func apply(_ format: InlineFormat)
}

extension FocusedValues {
    /// The Live editor that has the keyboard. The Format menu is off while there's none, and in Source mode.
    @Entry var formatting: (any InlineFormatting)?
}
#endif
