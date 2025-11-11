//
//  PlaylistController.swift
//  Tryout
//
//  Created by Telem Tobi on 06/11/2025.
//

import Foundation
import Combine

public final class PlaylistController: ObservableObject {
    public let items: [PlaylistItem]
    internal var backwardBuffer: Int = 1
    internal var forwardBuffer: Int = 1
    
    @Published public internal(set) var isPlaying: Bool = false
    @Published public private(set) var currentIndex: Int

    @Published public var status: PlaylistItem.Status = .loading
    @Published public internal(set) var progressInSeconds: TimeInterval = .zero
    @Published public internal(set) var durationInSeconds: TimeInterval = .zero

    public internal(set) var reachedEnd = PassthroughSubject<Void, Never>()
    internal var progressPublisher = PassthroughSubject<TimeInterval, Never>()
    
    var rangedItems: [PlaylistItem?] {
        ((currentIndex - backwardBuffer)...(currentIndex + forwardBuffer))
            .map { items[safe: $0] }
    }
    
    var currentItem: PlaylistItem? {
        rangedItems[safe: backwardBuffer] ?? nil
    }
    
    public init(items: [PlaylistItem], initialIndex: Int = .zero, isPlaying: Bool = false) {
        self.items = items
        self.isPlaying = isPlaying
        
        if items.indices.contains(initialIndex) {
            self.currentIndex = initialIndex
        } else {
            self.currentIndex = .zero
        }
    }
    
    public func advanceToNext() {
        currentIndex = min(currentIndex + 1, items.count - 1)
    }
    
    public func moveToPrevious() {
        currentIndex = max(currentIndex - 1, 0)
    }
    
    public func setCurrentIndex(_ newValue: Int) {
        if items.indices.contains(newValue) {
            currentIndex = newValue
        }
    }
    
    public func setProgress(_ newValue: TimeInterval) {
        self.progressPublisher.send(newValue)
    }
    
    public func play() {
        isPlaying = true
    }
    
    public func pause() {
        isPlaying = false
    }
}
