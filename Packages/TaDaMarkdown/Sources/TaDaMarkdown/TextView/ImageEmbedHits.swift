//
//  ImageEmbedHits.swift
//  TaDaMarkdown
//
//  Ta Da fork: the drawn image embed under a point. The Mac's source button
//  (`NativeTextView+ImageSourceButton.swift`) uses it.
//

#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

extension NativeTextView {
    /// The drawn image under a point in the text view's coordinates: its `![[ ]]` range and the image's rect in
    /// view coordinates.
    func imageEmbedHit(atViewPoint viewPoint: CGPoint) -> (range: NSRange, rect: CGRect)? {
        guard let coordinator = delegate as? NativeTextViewCoordinator, let textContainer = optionalTextContainer,
              let bridge = layoutBridge, let storage = optionalTextStorage, storage.length > 0 else { return nil }
        let containerPoint = CGPoint(x: viewPoint.x - textContainerOrigin.x, y: viewPoint.y - textContainerOrigin.y)
        for token in coordinator.parsedDocument(for: string).imageEmbedTokens
            where NSMaxRange(token.range) <= storage.length && token.range.location != coordinator.revealedImageEmbed {
            var hit: CGRect?
            storage.enumerateAttribute(.latexImage, in: token.range) { value, attrRange, stop in
                guard value != nil, let bounds = (storage.attribute(.latexBounds, at: attrRange.location, effectiveRange: nil)
                    as? NSValue)?.rectValue else { return }
                let anchor = bridge.boundingRect(forCharacterRange: NSRange(location: attrRange.location, length: 1), in: textContainer)
                let rect = CGRect(x: anchor.minX, y: anchor.minY, width: bounds.width, height: bounds.height)
                if rect.contains(containerPoint) { hit = rect }
                stop.pointee = true
            }
            if let hit { return (token.range, hit.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)) }
        }
        return nil
    }
}
