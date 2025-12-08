//
//  PlaylistItem.swift
//  PlayKit
//
//  Created by Telem Tobi on 06/11/2025.
//

import Foundation

/// A single entry that can be rendered by PlayKit.
///
/// Items can be still images, videos, or custom placeholders that advance
/// after a specified duration. Instances are value types and equatable so they
/// can be diffed when playlist contents change.
public enum PlaylistItem: Equatable {
    /// A still image to display for a fixed duration.
    ///
    /// - Parameters:
    ///   - url: The remote or local URL of the image resource.
    ///   - duration: The number of seconds the image remains visible. Defaults
    ///     to 10 seconds.
    case image(URL, duration: TimeInterval = 10)
    
    /// A video to play using ``AVPlayer``.
    ///
    /// - Parameter url: The remote or local URL of the video asset.
    case video(URL)
    
    /// A custom placeholder that progresses on a timer instead of media
    /// playback.
    ///
    /// - Parameter duration: The number of seconds before the item is
    ///   considered finished.
    case custom(duration: TimeInterval)
    
    /// A sentinel item that represents a load or playback failure.
    ///
    /// - Parameter id: A stable identifier for distinguishing error items.
    case error(id: AnyHashable = UUID())
}

public extension PlaylistItem {
    /// Playback readiness for a playlist item.
    enum Status: Equatable {
        /// The item is preparing to play.
        case loading
        /// The item is ready to play or display.
        case ready
        /// The item failed to load or play.
        case error
    }
}
