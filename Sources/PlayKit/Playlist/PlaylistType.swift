//
//  PlaylistType.swift
//  PlayKit
//
//  Created by Telem Tobi on 13/12/2025.
//

/// Presentation modes supported by ``PlaylistView`` and ``UIPlaylistView``.
///
/// Use these cases to pick how the playlist should transition between items.
/// `tapThrough` displays items stacked and advances via programmatic index
/// changes. `verticalFeed` renders items in a vertically scrolling feed, similar
/// to social short‑form video experiences.
public enum PlaylistType {
    /// Stacked players where only the active item is visible; ideal for paging
    /// or manual navigation via taps or buttons.
    case tapThrough
    
    /// A vertically scrolling feed where the item most visible on screen
    /// becomes the current playlist entry.
    case verticalFeed
}
