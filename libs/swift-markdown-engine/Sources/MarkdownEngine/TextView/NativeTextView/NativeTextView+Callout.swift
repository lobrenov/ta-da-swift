//
//  NativeTextView+Callout.swift
//  MarkdownEngine
//
//  Ta Da fork: a click on a foldable callout's title row (its icon, chevron
//  or the space past its title) folds or opens it on screen; the file keeps
//  its `+` or `-`. A right-click on a title line goes to `onCalloutMenu`,
//  which can change the type and the fold sign.
//

import AppKit

/// Ta Da fork: a right-click on a callout's title line, delivered through
/// ``NativeTextViewWrapper/onCalloutMenu``.
public struct CalloutMenuRequest {
    /// The type as written, between `[!` and `]`.
    public let type: String
    /// `+`, `-` or nil.
    public let fold: Character?
    /// The icon in screen coordinates, to anchor the menu.
    public let anchorRect: CGRect
    /// Replaces the type as one undoable edit. Does nothing once the title line has changed.
    public let setType: @MainActor (String) -> Void
    /// Sets, changes or removes the fold sign as one undoable edit. Does nothing once the title line has changed.
    public let setFold: @MainActor (Character?) -> Void
    /// Call when the menu closes: the callout drops its ring.
    public let close: @MainActor () -> Void
}

extension NativeTextView {

    struct CalloutTitleHit {
        let line: QuoteLine
        let header: CalloutHeader
        let info: CalloutLine
        /// The click, in text-container coordinates.
        let point: CGPoint
    }

    /// The callout title line under `event`, if any.
    func calloutTitleHit(for event: NSEvent) -> CalloutTitleHit? {
        guard configuration.callouts != nil, let storage = textStorage, storage.length > 0,
              let container = textContainer, let bridge = layoutBridge else { return nil }
        let viewPoint = convert(event.locationInWindow, from: nil)
        let point = CGPoint(x: viewPoint.x - textContainerOrigin.x, y: viewPoint.y - textContainerOrigin.y)
        let ns = storage.string as NSString
        let index = min(characterIndexForInsertion(at: viewPoint), ns.length - 1)
        guard index >= 0 else { return nil }
        let line = QuoteLine.parse(ns.lineRange(for: NSRange(location: index, length: 0)), of: ns)
        guard line.level > 0, line.text.length > 0,
              let info = storage.attribute(.calloutLine, at: line.text.location, effectiveRange: nil) as? CalloutLine,
              info.isTitle, let header = CalloutHeader.parse(ns, content: line.content) else { return nil }
        let rect = bridge.boundingRect(forCharacterRange: line.text, in: container)
        guard point.y >= rect.minY, point.y < rect.maxY else { return nil }
        return CalloutTitleHit(line: line, header: header, info: info, point: point)
    }

    /// Folds or opens the callout when `event` lands on its title row outside the title text. Returns true when
    /// it did.
    func toggleCalloutFoldIfHit(event: NSEvent) -> Bool {
        guard event.clickCount == 1, event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock).isEmpty,
              let hit = calloutTitleHit(for: event), hit.header.fold.length == 1, let title = hit.info.title,
              let storage = textStorage, let container = textContainer, let bridge = layoutBridge,
              let coordinator = delegate as? NativeTextViewCoordinator else { return false }
        // The title text places the caret; the rest of the row folds.
        if hit.header.title.length > 0 {
            let titleRect = bridge.boundingRect(forCharacterRange: hit.header.title, in: container)
            let chevronX = container.size.width - title.chevronRightInset - title.chevronSize - 4
            // A wrapped title runs to the chevron.
            let titleEnd = titleRect.height > title.font.pointSize * 2.5 ? chevronX : titleRect.maxX
            if hit.point.x >= title.nameX, hit.point.x <= titleEnd { return false }
        }
        let ns = storage.string as NSString
        let key = ns.substring(with: hit.line.text)
        let folding = !hit.info.isFolded
        let fileFolds = ns.character(at: hit.header.fold.location) == 0x2D /* - */
        coordinator.configuration.calloutFoldOverrides[key] = folding == fileFolds ? nil : folding
        // A caret in the body keeps it open.
        let callout = calloutRange(titledBy: hit.line, in: ns)
        if folding, NSLocationInRange(selectedRange().location, callout),
           selectedRange().location > NSMaxRange(hit.line.text) {
            setSelectedRange(NSRange(location: NSMaxRange(hit.line.text), length: 0))
        }
        coordinator.restyleParagraphs([callout], in: self)
        return true
    }

    /// Hands a right-click on a title line to `onCalloutMenu`, ringing the callout until the menu closes.
    func showCalloutMenu(for hit: CalloutTitleHit, _ onCalloutMenu: (CalloutMenuRequest) -> Void) {
        guard let storage = textStorage, let container = textContainer, let bridge = layoutBridge else { return }
        let ns = storage.string as NSString
        let titleLine = hit.line.text
        let lineText = ns.substring(with: titleLine)
        let callout = calloutRange(titledBy: hit.line, in: ns)
        let lineRect = bridge.boundingRect(forCharacterRange: titleLine, in: container)
        let iconX = hit.info.title?.iconX ?? bridge.boundingRect(forCharacterRange: hit.header.syntax, in: container).minX
        let iconSize = hit.info.title?.iconSize ?? lineRect.height
        let viewRect = CGRect(x: iconX, y: lineRect.minY, width: iconSize, height: lineRect.height)
            .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        let anchor = window?.convertToScreen(convert(viewRect, to: nil)) ?? .zero

        calloutMenuTarget = titleLine.location
        bridge.invalidateDisplay(forCharacterRange: callout)
        let header = hit.header
        let fold = header.fold.length == 1 ? Character(ns.substring(with: header.fold)) : nil
        // Edits apply only while the title line still reads as it did.
        let edit: @MainActor (NSRange, String) -> Void = { [weak self] range, text in
            guard let self, let storage = self.textStorage, NSMaxRange(titleLine) <= storage.length,
                  (storage.string as NSString).substring(with: titleLine) == lineText,
                  (storage.string as NSString).substring(with: range) != text else { return }
            self.breakUndoCoalescing()
            guard self.shouldChangeText(in: range, replacementString: text) else { return }
            storage.replaceCharacters(in: range, with: text)
            self.didChangeText()
        }
        onCalloutMenu(CalloutMenuRequest(
            type: ns.substring(with: header.type), fold: fold, anchorRect: anchor,
            setType: { edit(header.type, $0) },
            setFold: { edit(header.fold, $0.map { String($0) } ?? "") },
            close: { [weak self] in
                guard let self, self.calloutMenuTarget == titleLine.location else { return }
                self.calloutMenuTarget = nil
                let length = self.textStorage?.length ?? 0
                self.layoutBridge?.invalidateDisplay(forCharacterRange: NSIntersectionRange(callout, NSRange(location: 0, length: length)))
            }))
    }

    /// The title line and the lines after it at its level or deeper.
    private func calloutRange(titledBy title: QuoteLine, in ns: NSString) -> NSRange {
        var end = NSMaxRange(title.line)
        while end < ns.length {
            let next = QuoteLine.parse(ns.lineRange(for: NSRange(location: end, length: 0)), of: ns)
            guard next.level >= title.level else { break }
            end = NSMaxRange(next.line)
        }
        return NSRange(location: title.line.location, length: end - title.line.location)
    }
}
