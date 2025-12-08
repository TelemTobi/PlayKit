//
//  PlaylistItem.swift
//  PlayKit
//
//  Created by Telem Tobi on 06/11/2025.
//

import Foundation

public enum PlaylistItem: Equatable {
    case image(URL, duration: TimeInterval = 10)
    case video(URL)
    case custom(duration: TimeInterval)
    case error(id: AnyHashable = UUID())
}

public extension PlaylistItem {
    enum Status: Equatable {
        case loading
        case ready
        case error
    }
}
