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
/// retaining UIKit rendering performance. Choose a ``PlaylistType`` to render
/// either a tap-through experience or a vertical, feed-style layout.
public struct PlaylistView<Overlay>: UIViewRepresentable where Overlay : View {
    let playlistType: PlaylistType
    let controller: PlaylistController
    let gravity: AVLayerVideoGravity
    let overlayForItemAtIndex: ((Int) -> Overlay)?
    
    /// Creates a playlist view.
    ///
    /// - Parameters:
    ///   - type: The presentation style to use (tap-through or vertical feed).
    ///   - controller: The playlist controller that supplies items and state.
    ///   - gravity: The ``AVLayerVideoGravity`` to apply to rendered video and
    ///     images. Defaults to ``AVLayerVideoGravity/resizeAspect``.
    public init(
        type: PlaylistType,
        controller: PlaylistController,
        gravity: AVLayerVideoGravity = .resizeAspect
    ) where Overlay == EmptyView {
        self.playlistType = type
        self.controller = controller
        self.gravity = gravity
        self.overlayForItemAtIndex = nil
    }
    
    /// Creates a playlist view with per-item overlays.
    ///
    /// - Parameters:
    ///   - type: The presentation style to use (tap-through or vertical feed).
    ///   - controller: The playlist controller that supplies items and state.
    ///   - gravity: The ``AVLayerVideoGravity`` to apply to rendered video and
    ///     images. Defaults to ``AVLayerVideoGravity/resizeAspect``.
    ///   - overlayForItemAtIndex: A builder that returns an overlay for a given
    ///     playlist index. Return `nil` to omit an overlay for the item.
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
