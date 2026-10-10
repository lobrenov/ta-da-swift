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

/// Ta Da fork: a drawn image's `![[ ]]`, for the embedder's image actions: ``NativeTextViewWrapper/onImageEmbed`` on
/// macOS, ``NativeTextViewWrapper/imageEmbedMenu`` on iOS.
public struct ImageEmbedRequest {
    public enum Action: Sendable {
        /// A right-click (or press and hold) on the image: the embedder shows its menu.
        case menu
        /// ⌘C, ⌘X or ⌘⌫ while the image is selected.
        case copy, cut, delete
    }

    public let action: Action
    /// The text between `![[` and `]]`.
    public let name: String
    /// Where a right-click landed, else the image; in screen coordinates on macOS and window coordinates on iOS.
    public let anchorRect: CGRect
    /// Removes the `![[ ]]` as one undoable edit with this action name. Does nothing once its text has changed.
    public let remove: @MainActor (_ actionName: String) -> Void
    /// Shows the `![[ ]]` with the caret after it, until the caret leaves its line.
    public let revealSource: @MainActor () -> Void
    /// Call when the menu closes: the image drops its ring unless it's selected.
    public let close: @MainActor () -> Void
}
