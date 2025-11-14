//
//  PlaylistView.swift
//  PlayKit
//
//  Created by Telem Tobi on 06/11/2025.
//

import SwiftUI
import AVKit

public struct PlaylistView: UIViewRepresentable {
    let controller: PlaylistController
    let gravity: AVLayerVideoGravity
    
    public init(controller: PlaylistController, gravity: AVLayerVideoGravity = .resizeAspect) {
        self.controller = controller
        self.gravity = gravity
    }
    
    public func makeUIView(context: Context) -> UIPlaylistView {
        let playlistView = UIPlaylistView()
        playlistView.controller = controller
        playlistView.gravity = gravity
        return playlistView
    }
    
    public func updateUIView(_ uiView: UIPlaylistView, context: Context) {
        
    }
}
