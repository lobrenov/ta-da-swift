//
//  MenuRequests.swift
//  TaDaMarkdown
//
//  Ta Da fork: the menus the embedder draws for a task box or a callout title,
//  opened by a right-click on macOS and a press and hold on iOS.
//

import CoreGraphics

/// Ta Da fork: a right-click (or press and hold) on a task box, delivered through
/// ``NativeTextViewWrapper/onTaskMarkerMenu``.
public struct TaskMarkerMenuRequest {
    /// The box's current marker.
    public let marker: Character
    /// The box in screen coordinates, to anchor the menu.
    public let anchorRect: CGRect
    /// Replaces the marker as one undoable edit. Does nothing once the box's text has changed.
    public let setMarker: @MainActor (Character) -> Void
}

/// Ta Da fork: a right-click (or press and hold) on a callout's title line, delivered through
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
