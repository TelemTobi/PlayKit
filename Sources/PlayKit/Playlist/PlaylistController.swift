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
/// Attach an instance to ``PlaylistView`` or ``UIPlaylistView`` to drive media
/// presentation. The controller buffers a window of items around the current
/// index to minimize transitions and exposes playback state via ``Publisher``
/// properties for SwiftUI or UIKit consumers.
public final class PlaylistController: ObservableObject {
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
    
    /// Publishes when the playlist reaches the final item and finishes playing.
    public internal(set) var reachedEnd = PassthroughSubject<Void, Never>()

    /// Indicates whether the playlist currently has UI focus.
    ///
    /// When focus is gained, playback resumes; when focus is lost, it pauses.
    @Published public var isFocused: Bool = false
    
    /// Indicates whether playback should be active for the current item.
    @Published public var isPlaying: Bool = false

    internal var progressPublisher = PassthroughSubject<TimeInterval, Never>()
    internal var backwardBuffer: Int = 2
    internal var forwardBuffer: Int = 5
    
    var rangedItems: [PlaylistItem?] {
        ((currentIndex - backwardBuffer)...(currentIndex + forwardBuffer))
            .map { items[safe: $0] }
    }
    
    var currentItem: PlaylistItem? {
        rangedItems[safe: backwardBuffer] ?? nil
    }
    
    internal let players: [AVPlayer]
    
    /// Creates a new controller.
    ///
    /// - Parameters:
    ///   - items: Initial playlist contents. Defaults to an empty list.
    ///   - initialIndex: The starting index. If the value is out of bounds, the
    ///     controller resets it to zero.
    ///   - isFocused: Whether the playlist starts focused. Focus determines
    ///     whether playback should commence automatically.
    public init(items: [PlaylistItem] = [], initialIndex: Int = .zero, isFocused: Bool = false) {
        self.items = items
        self.isFocused = isFocused
        
        if items.indices.contains(initialIndex) || items.isEmpty {
            self.currentIndex = initialIndex
        } else {
            self.currentIndex = .zero
        }
        
        var newPlayer: AVPlayer { AVPlayer() }
        players = Array(
            repeating: newPlayer,
            count: backwardBuffer + forwardBuffer + 1
        )
        
        
        prepareInitialItemIfNeeded()
    }
    
    /// Updates whether the playlist should be considered in focus.
    ///
    /// Use this to reflect app lifecycle or navigation events.
    public func setIsFocused(_ newValue: Bool) {
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
        self.items = newValue
        
        for player in players {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
        
        prepareInitialItemIfNeeded()
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
    /// - Parameter newValue: The desired index within ``items``.
    public func setCurrentIndex(_ newValue: Int) {
        guard currentIndex != newValue else { return }
        if items.indices.contains(newValue) {
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
        case let .image(url, _):
            Task {
                await ImageProvider.shared.loadImage(from: url)
            }
            
        case let .video(url):
            guard let player = players[safe: backwardBuffer] else { break }
            
            let item = AVPlayerItem(url: url)
            item.preferredForwardBufferDuration = 2.5
            player.replaceCurrentItem(with: item)
            player.automaticallyWaitsToMinimizeStalling = true
            
        case .custom, .error, .none:
            break
        }
    }
}
