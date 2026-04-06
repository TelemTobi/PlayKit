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
    ///   - loopMode: The playback behavior for this item. Defaults to
    ///     ``PlaybackBehavior/playOnce``.
    case image(id: AnyHashable = UUID(), URL, duration: TimeInterval = 10, behavior: PlaybackBehavior = .playOnce)
    
    /// A video to play using ``AVPlayer``.
    ///
    /// - Parameters:
    ///   - id: A stable identifier used to differentiate duplicate URLs.
    ///     Provide this when you need multiple video entries for the same URL;
    ///     otherwise a UUID is generated automatically.
    ///   - url: The remote or local URL of the video asset.
    ///   - loopMode: The playback behavior for this item. Defaults to
    ///     ``PlaybackBehavior/playOnce``.
    case video(id: AnyHashable = UUID(), URL, behavior: PlaybackBehavior = .playOnce)
    
    /// A custom placeholder that progresses on a timer instead of media
    /// playback.
    ///
    /// - Parameters:
    ///   - id: A stable identifier for correlating or tracking the custom item.
    ///     Defaults to a generated UUID.
    ///   - duration: The number of seconds before the item is considered
    ///     finished.
    ///   - loopMode: The playback behavior for this item. Defaults to
    ///     ``PlaybackBehavior/playOnce``.
    case custom(id: AnyHashable = UUID(), duration: TimeInterval, behavior: PlaybackBehavior = .playOnce)
    
    /// A sentinel item that represents a load or playback failure.
    ///
    /// - Parameters:
    ///   - id: A stable identifier for distinguishing error items.
    ///   - loopMode: The playback behavior for this item. Defaults to
    ///     ``PlaybackBehavior/playOnce``.
    case error(id: AnyHashable = UUID(), behavior: PlaybackBehavior = .playOnce)
    
    internal var playbackBehavior: PlaybackBehavior {
        switch self {
        case let.image(_, _, _, behavior): behavior
        case let .video(_, _, behavior): behavior
        case let .custom(_, _, behavior): behavior
        case let .error(_, behavior): behavior
        }
    }
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
    
    /// Playback repetition behavior for a playlist item.
    enum PlaybackBehavior: Hashable {
        /// The item plays once and then advances to the next item.
        case playOnce
        /// The item repeats indefinitely until manually advanced.
        case loop
        /// The item repeats a specific number of times before advancing.
        ///
        /// - Parameter count: The number of times the item should repeat.
        case `repeat`(count: Int)
    }
}
