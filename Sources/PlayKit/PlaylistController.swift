//
//  PlaylistController.swift
//  PlayKit
//
//  Created by Telem Tobi on 06/11/2025.
//

import Foundation
import Combine

public final class PlaylistController: ObservableObject {
    @Published public private(set) var items: [PlaylistItem]
    @Published public private(set) var currentIndex: Int
    @Published public private(set) var rate: Float = 1

    @Published public var isFocused: Bool = false
    @Published public internal(set) var isPlaying: Bool = false
    @Published public internal(set) var status: PlaylistItem.Status = .ready
    @Published public internal(set) var progressInSeconds: TimeInterval = .zero
    @Published public internal(set) var durationInSeconds: TimeInterval = .zero

    public internal(set) var reachedEnd = PassthroughSubject<Void, Never>()
    internal var progressPublisher = PassthroughSubject<TimeInterval, Never>()

    internal var backwardBuffer: Int = 1
    internal var forwardBuffer: Int = 1
    
    var rangedItems: [PlaylistItem?] {
        ((currentIndex - backwardBuffer)...(currentIndex + forwardBuffer))
            .map { items[safe: $0] }
    }
    
    var currentItem: PlaylistItem? {
        rangedItems[safe: backwardBuffer] ?? nil
    }
    
    public init(items: [PlaylistItem] = [], initialIndex: Int = .zero, isFocused: Bool = false) {
        self.items = items
        self.isFocused = isFocused
        
        if items.indices.contains(initialIndex) || items.isEmpty {
            self.currentIndex = initialIndex
        } else {
            self.currentIndex = .zero
        }
    }
    
    public func setIsFocused(_ newValue: Bool) {
        self.isFocused = newValue
    }
    
    public func setItems(_ newValue: [PlaylistItem]) {
        if !newValue.indices.contains(currentIndex) {
            currentIndex = .zero
        }
        self.items = newValue
    }
    
    public func advanceToNext() {
        self.currentIndex = min(currentIndex + 1, items.count - 1)
    }
    
    public func moveToPrevious() {
        self.currentIndex = max(currentIndex - 1, 0)
    }
    
    public func setCurrentIndex(_ newValue: Int) {
        guard currentIndex != newValue else { return }
        if items.indices.contains(newValue) {
            self.currentIndex = newValue
        }
    }
    
    public func setProgress(_ newValue: TimeInterval) {
        self.progressPublisher.send(newValue)
    }
    
    public func setRate(_ newValue: Float) {
        self.rate = newValue
        
        if newValue > .zero {
            self.isPlaying = true
        }
    }
    
    public func play() {
        self.isPlaying = true
    }
    
    public func pause() {
        self.isPlaying = false
    }
}
