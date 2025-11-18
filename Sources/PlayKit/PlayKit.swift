//
//  PlayKit.swift
//  PlayKit
//
//  Created by Telem Tobi on 16/11/2025.
//

import Foundation
import Combine
import AVKit

public final class PlayKit {
    
    @MainActor
    public static let shared = PlayKit()
    
    public var lastObservedBitrate: Double {
        _lastObservedBitrate.value
    }
    
    public var bitratePublisher: AnyPublisher<Double, Never> {
        _lastObservedBitrate.eraseToAnyPublisher()
    }
    
    private let _lastObservedBitrate = CurrentValueSubject<Double, Never>(.zero)
    private var accessLogSubscription: AnyCancellable?
    
    private init() {
        registerAccessLogSubscription()
    }
    
    private func registerAccessLogSubscription() {
        accessLogSubscription?.cancel()
        
        let subscription = NotificationCenter.default
            .publisher(for: AVPlayerItem.newAccessLogEntryNotification)
            .compactMap { notification -> Double? in
                guard let lastEvent = (notification.object as? AVPlayerItem)?.accessLog()?.events.last else { return nil }
                
                if lastEvent.transferDuration > 0, lastEvent.numberOfBytesTransferred > 0 {
                    return (Double(lastEvent.numberOfBytesTransferred) * 8.0) / lastEvent.transferDuration
                }
                
                return lastEvent.observedBitrate
            }
        
        let firstNonZero = subscription
            .first { $0 > .zero }
        
        let windowedMax = subscription
            .collect(.byTime(DispatchQueue.global(), .seconds(10)))
            .compactMap { $0.max() }
            .removeDuplicates()
        
        accessLogSubscription = firstNonZero
            .append(windowedMax)
            .removeDuplicates()
            .assign(to: \.value, on: _lastObservedBitrate)
    }
}
