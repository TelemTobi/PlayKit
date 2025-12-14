//
//  PlaylistView.swift
//  PlayKit
//
//  Created by Telem Tobi on 06/11/2025.
//

import SwiftUI
import AVKit

/// A SwiftUI wrapper that hosts a ``UIPlaylistView``.
///
/// Use this view to embed PlayKit playback inside SwiftUI hierarchies while
/// retaining UIKit rendering performance.
public struct PlaylistView<Overlay>: UIViewRepresentable where Overlay : View {
    let playlistType: PlaylistType
    let controller: PlaylistController
    let gravity: AVLayerVideoGravity
    let overlayForItemAtIndex: ((Int) -> Overlay)?
    
    /// Creates a playlist view.
    ///
    /// - Parameters:
    ///   - controller: The playlist controller that supplies items and state.
    ///   - gravity: The ``AVLayerVideoGravity`` to apply to rendered video and
    ///     images. Defaults to ``AVLayerVideoGravity/resizeAspect``.
    public init(
        type: PlaylistType,
        controller: PlaylistController,
        gravity: AVLayerVideoGravity = .resizeAspect
    ) {
        self.playlistType = type
        self.controller = controller
        self.gravity = gravity
        self.overlayForItemAtIndex = nil
    }
    
    public init(
        type: PlaylistType,
        controller: PlaylistController,
        gravity: AVLayerVideoGravity = .resizeAspect,
        @ViewBuilder overlayForItemAtIndex: @escaping (Int) -> Overlay
    ) {
        self.playlistType = type
        self.controller = controller
        self.gravity = gravity
        self.overlayForItemAtIndex = overlayForItemAtIndex
    }
    
    public func makeUIView(context: Context) -> UIPlaylistView {
        let playlistView = UIPlaylistView()
        playlistView.initialize(type: playlistType, controller: controller)
        playlistView.gravity = gravity
        playlistView.overlayForItemAtIndex = { index in
            guard let overlay = overlayForItemAtIndex?(index) else { return nil }
            return UIHostingController(rootView: overlay).view
        }
        return playlistView
    }
    
    public func updateUIView(_ uiView: UIPlaylistView, context: Context) {
        
    }
}
