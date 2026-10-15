// Format menu (⌘B, ⌘I, ⇧⌘H, ⇧⌘S): toggles an inline format on the Live editor's selection, or the word at the caret
// (not for highlight), or inserts its pair of markers with the caret between them.
#if os(macOS)
import SwiftUI

enum InlineFormat {
    case bold, italic, highlight, strikethrough
}

/// The Live editor's `editor` focused value. The Format menu is off while there's none, and in Source mode.
protocol InlineFormatting: TextViewHolder {
    func apply(_ format: InlineFormat)
}
#endif
