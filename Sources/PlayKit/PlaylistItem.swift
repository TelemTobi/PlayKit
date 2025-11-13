//
//  PlaylistItem.swift
//  Tryout
//
//  Created by Telem Tobi on 06/11/2025.
//

import Foundation

public enum PlaylistItem: Equatable {
    case image(URL)
    case video(URL)
    case custom
}

public extension PlaylistItem {
    enum Status: Equatable {
        case loading
        case ready
        case error
    }
}
