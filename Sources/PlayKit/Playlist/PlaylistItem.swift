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
/// can be diffed when playlist contents change. Each item can be given a custom
/// `id` to disambiguate duplicates; if you omit it, a UUID is generated for you.
public enum PlaylistItem: Equatable, Hashable {
    /// A still image to display for a fixed duration.
    ///
    /// - Parameters:
    ///   - id: A stable identifier used to differentiate duplicate URLs.
    ///     Provide this when you need multiple image entries for the same URL;
    ///     otherwise a UUID is generated automatically.
    ///   - url: The remote or local URL of the image resource.
    ///   - duration: The number of seconds the image remains visible. Defaults
    ///     to 10 seconds.
    case image(id: AnyHashable = UUID(), URL, duration: TimeInterval = 10)
    
    /// A video to play using ``AVPlayer``.
    ///
    /// - Parameters:
    ///   - id: A stable identifier used to differentiate duplicate URLs.
    ///     Provide this when you need multiple video entries for the same URL;
    ///     otherwise a UUID is generated automatically.
    ///   - url: The remote or local URL of the video asset.
    case video(id: AnyHashable = UUID(), URL)
    
    /// A custom placeholder that progresses on a timer instead of media
    /// playback.
    ///
    /// - Parameters:
    ///   - id: A stable identifier for correlating or tracking the custom item.
    ///     Defaults to a generated UUID.
    ///   - duration: The number of seconds before the item is considered
    ///     finished.
    case custom(id: AnyHashable = UUID(), duration: TimeInterval)
    
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
