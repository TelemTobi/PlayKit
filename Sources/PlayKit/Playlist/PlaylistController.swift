//
//  PlaylistController.swift
//  PlayKit
//
//  Created by Telem Tobi on 06/11/2025.
//

import Foundation
import Combine
import AVKit

/// An observable controller that coordinates playlist playback and state.
///
/// Attach an instance to ``PlaylistView`` or ``UIPlaylistView`` (tap-through or
/// vertical feed) to drive media presentation. The controller buffers a window
/// of items around the current index to minimize transitions and exposes
/// playback state via ``Publisher`` properties for SwiftUI or UIKit consumers.
public final class PlaylistController: ObservableObject, Identifiable {
    /// A caller-provided identifier for correlating this controller instance.
    ///
    /// Use this to track or distinguish controllers when multiple playlists are
    /// active. Defaults to a generated UUID string.
    public let id: AnyHashable
    
    /// The items currently managed by the playlist.
    ///
    /// Updates publish changes and adjust the active index to stay in bounds.
    @Published public private(set) var items: [PlaylistItem]
    
    /// The index of the item currently in focus.
    ///
    /// Updates emit through the published property and drive which player view
    /// is considered the primary renderer.
    @Published public private(set) var currentIndex: Int
    
    /// The desired playback rate for the active item.
    ///
    /// A rate greater than zero implicitly turns on ``isPlaying``.
    @Published public private(set) var rate: Float = 1

    /// Load and readiness state for the current item.
    @Published public internal(set) var status: PlaylistItem.Status = .ready
    
    /// The elapsed playback time, in seconds, for the current item.
    @Published public internal(set) var progressInSeconds: TimeInterval = .zero
    
    /// The total duration, in seconds, of the current item when available.
    @Published public internal(set) var durationInSeconds: TimeInterval = .zero
    
    /// Publishes each time the current item finishes playing.
    ///
    /// Emitted on every item completion, not just when the playlist reaches its
    /// final item.
    public internal(set) var itemReachedEnd = PassthroughSubject<Void, Never>()

    /// Indicates whether the playlist currently has UI focus.
    ///
    /// When focus is gained, playback resumes; when focus is lost, it pauses.
    @Published public var isFocused: Bool = false
    
    /// Indicates whether playback should be active for the current item.
    @Published public var isPlaying: Bool = false

    internal var progressPublisher = PassthroughSubject<TimeInterval, Never>()
    internal let backwardBuffer: Int
    internal let forwardBuffer: Int
    var rangedItems: [PlaylistItem?] {
        ((currentIndex - backwardBuffer)...(currentIndex + forwardBuffer))
            .map { items[safe: $0] }
    }
    
    var currentItem: PlaylistItem? {
        rangedItems[safe: backwardBuffer] ?? nil
    }
    
    internal let players: [AVPlayer]
    internal var setIndexWithAnimation: Bool = false
    
    /// Creates a new controller.
    ///
    /// - Parameters:
    ///   - id: An identifier for correlating this controller instance. Defaults
    ///     to a generated UUID string.
    ///   - items: Initial playlist contents. Defaults to an empty list.
    ///   - initialIndex: The starting index. If the value is out of bounds, the
    ///     controller resets it to zero.
    ///   - backwardBuffer: The number of items to preload before the current
    ///     index.
    ///   - forwardBuffer: The number of items to preload after the current
    ///     index.
    ///   - isFocused: Whether the playlist starts focused. Focus determines
    ///     whether playback should commence automatically.
    public init(
        id: AnyHashable = UUID().uuidString,
        items: [PlaylistItem] = [],
        initialIndex: Int = .zero,
        backwardBuffer: Int = 2,
        forwardBuffer: Int = 5,
        isFocused: Bool = false,
        isPlaying: Bool = false
    ) {
        self.id = id
        self.items = items
        self.isFocused = isFocused
        self.isPlaying = isPlaying
        self.backwardBuffer = backwardBuffer
        self.forwardBuffer = forwardBuffer
        
        if items.indices.contains(initialIndex) || items.isEmpty {
            self.currentIndex = initialIndex
        } else {
            self.currentIndex = .zero
        }
        
        players = (0..<backwardBuffer + forwardBuffer + 1).map { _ in AVPlayer() }
        prepareInitialItemIfNeeded()
    }
    
    /// Updates whether the playlist should be considered in focus.
    ///
    /// Use this to reflect app lifecycle or navigation events.
    public func setFocus(_ newValue: Bool) {
        self.isFocused = newValue
    }
    
    /// Replaces the playlist contents while preserving a valid current index.
    ///
    /// If the provided items do not contain the current index, the controller
    /// resets the index to zero.
    public func setItems(_ newValue: [PlaylistItem]) {
        if !newValue.indices.contains(currentIndex) {
            currentIndex = .zero
        }
        
        let isInitialSetOfItems = items.isEmpty
        self.items = newValue
        
        if isInitialSetOfItems {
            for player in players {
                player.pause()
                player.replaceCurrentItem(with: nil)
            }
            
            prepareInitialItemIfNeeded()
        }
    }
    
    /// Advances to the next item, clamping to the end of the playlist.
    public func advanceToNext() {
        self.currentIndex = min(currentIndex + 1, items.count - 1)
    }
    
    /// Moves to the previous item, clamping to the start of the playlist.
    public func moveToPrevious() {
        self.currentIndex = max(currentIndex - 1, 0)
    }
    
    /// Sets the current index if it differs and is within bounds.
    ///
    /// - Parameters:
    ///   - newValue: The desired index within ``items``.
    ///   - animated: Whether UI surfaces that support animated jumps should
    ///     animate the scroll. Currently only used by `.verticalFeed`;
    ///     tap-through views ignore this flag and switch immediately.
    public func setCurrentIndex(_ newValue: Int, animated: Bool = false) {
        guard currentIndex != newValue else { return }
        
        if items.indices.contains(newValue) {
            self.setIndexWithAnimation = animated
            self.currentIndex = newValue
        }
    }
    
    /// Requests a new playback position, in seconds, for the current item.
    ///
    /// The request is forwarded to the active player view.
    public func setProgress(_ newValue: TimeInterval) {
        self.progressPublisher.send(newValue)
    }
    
    /// Sets the desired playback rate and implicitly resumes playback when
    /// positive.
    ///
    /// - Parameter newValue: The rate to use, where `1` is normal speed.
    public func setRate(_ newValue: Float) {
        self.rate = newValue
        
        if newValue > .zero {
            self.isPlaying = true
        }
    }
    
    /// Marks the playlist as playing.
    public func play() {
        self.isPlaying = true
    }
    
    /// Marks the playlist as paused.
    public func pause() {
        self.isPlaying = false
    }
}

extension PlaylistController {
    private func prepareInitialItemIfNeeded() {
        switch currentItem {
        case let .image(_, url, _):
            Task {
                await ImageProvider.shared.loadImage(from: url)
            }
            
        case let .video(_, url):
            guard let player = players[safe: backwardBuffer],
                player.currentItem == nil else { break }
            
            let item = AVPlayerItem(url: url)
            player.replaceCurrentItem(with: item)
            player.automaticallyWaitsToMinimizeStalling = true
            
        case .custom, .error, .none:
            break
        }
    }
}
