//
//  NativeTextView+TaskCheckbox.swift
//  TaDaMarkdown
//
//  Created by Luca Chen on 16.03.26.
//
//  Hit-test for `[ ]` / `[x]` checkbox glyphs and toggle the underlying text
//  + `.taskCheckbox` attribute, then nudge the coordinator to restyle the
//  enclosing paragraph.
//
//  Ta Da fork: any `TaskMarker` character is a checkbox. A click follows
//  `TaskCheckboxStyle.clickTransitions`; a right-click on the box offers every
//  marker in `TaskCheckboxStyle.menuItems`, or goes to `onTaskMarkerMenu` for
//  the embedder to draw its own menu.
//

import AppKit

/// Ta Da fork: a right-click on a task box, delivered through
/// ``NativeTextViewWrapper/onTaskMarkerMenu``.
public struct TaskMarkerMenuRequest {
    /// The box's current marker.
    public let marker: Character
    /// The box in screen coordinates, to anchor the menu.
    public let anchorRect: CGRect
    /// Replaces the marker as one undoable edit. Does nothing once the box's text has changed.
    public let setMarker: @MainActor (Character) -> Void
}

extension NativeTextView {

    /// The drawn checkbox square under `containerPoint`, if any.
    ///
    /// The `[ ]` chars are collapsed to ~zero width, so their bounding rect sits
    /// at the content edge; reconstruct the DRAWN square from the shared
    /// `TaskCheckboxGeometry` (right-aligned to it). `baseFont`, not
    /// NSTextView.font (see the draw site). `searchRange` bounds the scan —
    /// the hovered line for cursor checks, nil (whole doc) for clicks.
    func taskCheckboxHit(at containerPoint: CGPoint, in searchRange: NSRange? = nil) -> (range: NSRange, marker: Character, rect: CGRect)? {
        guard let textContainer = textContainer,
              let bridge = layoutBridge,
              let storage = textStorage, storage.length > 0 else { return nil }
        let style = configuration.taskCheckbox
        let boxSize = TaskCheckboxGeometry.size(for: baseFont, style: style)
        let scan = searchRange ?? NSRange(location: 0, length: storage.length)
        var hit: (range: NSRange, marker: Character, rect: CGRect)?
        storage.enumerateAttribute(.taskCheckbox, in: scan, options: []) { value, attrRange, stop in
            guard let marker = (value as? String)?.first else { return }
            let anchor = bridge.boundingRect(forCharacterRange: attrRange, in: textContainer)
            let rect = CGRect(
                x: TaskCheckboxGeometry.boxX(contentX: anchor.minX, size: boxSize, style: style),
                y: anchor.minY,
                width: boxSize,
                height: max(anchor.height, boxSize)
            )
            if rect.contains(containerPoint) {
                hit = (attrRange, marker, rect)
                stop.pointee = true
            }
        }
        return hit
    }

    func taskCheckboxHit(for event: NSEvent) -> (range: NSRange, marker: Character, rect: CGRect)? {
        let localPoint = convert(event.locationInWindow, from: nil)
        let containerPoint = CGPoint(
            x: localPoint.x - textContainerOrigin.x,
            y: localPoint.y - textContainerOrigin.y
        )
        guard let hit = taskCheckboxHit(at: containerPoint),
              let storage = textStorage,
              (storage.string as NSString).substring(with: hit.range)
                .range(of: TaskMarker.boxPattern, options: .regularExpression) != nil else { return nil }
        return hit
    }

    /// Applies the click transition for the box under `event`. Returns true when
    /// the click landed on a box (consumed, even if its marker ignores clicks).
    func toggleTaskCheckboxIfHit(event: NSEvent) -> Bool? {
        guard let hit = taskCheckboxHit(for: event) else { return nil }
        if let next = configuration.taskCheckbox.clickTransitions[hit.marker] {
            setTaskMarker(next, boxRange: hit.range)
        }
        return true
    }

    /// The marker menu for a right-click on `hit`, or nil after handing the click to `onTaskMarkerMenu`.
    func taskMarkerMenu(for hit: (range: NSRange, marker: Character, rect: CGRect)) -> NSMenu? {
        if let onTaskMarkerMenu {
            let boxText = "[\(hit.marker)]"
            let viewRect = hit.rect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
            let anchor = window?.convertToScreen(convert(viewRect, to: nil)) ?? .zero
            onTaskMarkerMenu(TaskMarkerMenuRequest(marker: hit.marker, anchorRect: anchor) { [weak self] marker in
                guard let self, let storage = self.textStorage, NSMaxRange(hit.range) <= storage.length,
                      (storage.string as NSString).substring(with: hit.range) == boxText else { return }
                self.setTaskMarker(marker, boxRange: hit.range)
            })
            return nil
        }
        let style = configuration.taskCheckbox
        let menu = NSMenu()
        for entry in style.menuItems {
            let target = TaskMarkerMenuTarget(textView: self, boxRange: hit.range, marker: entry.marker)
            let item = NSMenuItem(title: entry.title, action: #selector(TaskMarkerMenuTarget.apply), keyEquivalent: "")
            item.target = target
            item.representedObject = target   // NSMenuItem.target is weak
            if let draw = style.draw {
                let tint = style.tints[entry.marker]
                    ?? (entry.marker == " " ? configuration.theme.mutedText : configuration.theme.bodyText)
                item.image = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { rect in
                    draw(entry.marker, rect, tint)
                    return true
                }
            } else {
                item.image = style.symbolNames[entry.marker].flatMap {
                    NSImage(systemSymbolName: $0, accessibilityDescription: entry.title)
                }
            }
            item.state = entry.marker == hit.marker ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    /// Replaces the marker character inside `[…]`, as one undoable edit.
    func setTaskMarker(_ marker: Character, boxRange: NSRange) {
        guard let storage = textStorage, let bridge = layoutBridge else { return }
        let replacement = "[\(marker)]"
        guard shouldChangeText(in: boxRange, replacementString: replacement) else { return }
        storage.replaceCharacters(in: boxRange, with: replacement)
        storage.addAttribute(.taskCheckbox, value: String(marker), range: boxRange)
        storage.addAttribute(.foregroundColor, value: NSColor.clear, range: boxRange)
        didChangeText()
        bridge.invalidateDisplay(forCharacterRange: boxRange)
        if let coord = delegate as? NativeTextViewCoordinator {
            let paragraph = (storage.string as NSString).paragraphRange(for: boxRange)
            coord.restyleParagraphs([paragraph], in: self)
        }
    }
}

private final class TaskMarkerMenuTarget: NSObject {
    weak var textView: NativeTextView?
    let boxRange: NSRange
    let marker: Character

    init(textView: NativeTextView, boxRange: NSRange, marker: Character) {
        self.textView = textView
        self.boxRange = boxRange
        self.marker = marker
    }

    @objc func apply() {
        textView?.setTaskMarker(marker, boxRange: boxRange)
    }
}
