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
    let compressedContentHeight: CGFloat?
    let contentTopInset: CGFloat
    let compressedCornerRadius: CGFloat?
    let overlayForItemAtIndex: ((Int) -> Overlay)?

    /// Creates a playlist view.
    ///
    /// - Parameters:
    ///   - type: The presentation style to use (tap-through or vertical feed).
    ///   - controller: The playlist controller that supplies items and state.
    ///   - gravity: The ``AVLayerVideoGravity`` to apply to rendered video and images. Defaults to ``AVLayerVideoGravity/resizeAspect``.
    ///   - compressedContentHeight: When non-nil, pins each feed cell's player view to a top-anchored region of this height (in points) instead of filling the cell, so a partially covering sheet can shrink the video above it. `nil` restores the full-bleed layout. Only affects `.verticalFeed`.
    ///   - contentTopInset: The offset, in points, from the top of each cell at which compressed content begins. Ignored when `compressedContentHeight` is `nil`. Defaults to `0`.
    ///   - compressedCornerRadius: The corner radius applied to the player view while compressed. `nil` (or `0`) leaves the video square. Ignored when `compressedContentHeight` is `nil`. Only affects `.verticalFeed`. Defaults to `nil`.
    public init(
        type: PlaylistType,
        controller: PlaylistController,
        gravity: AVLayerVideoGravity = .resizeAspect,
        compressedContentHeight: CGFloat? = nil,
        contentTopInset: CGFloat = 0,
        compressedCornerRadius: CGFloat? = nil
    ) where Overlay == EmptyView {
        self.playlistType = type
        self.controller = controller
        self.gravity = gravity
        self.compressedContentHeight = compressedContentHeight
        self.contentTopInset = contentTopInset
        self.compressedCornerRadius = compressedCornerRadius
        self.overlayForItemAtIndex = nil
    }

    /// Creates a playlist view with per-item overlays.
    ///
    /// - Parameters:
    ///   - type: The presentation style to use (tap-through or vertical feed).
    ///   - controller: The playlist controller that supplies items and state.
    ///   - gravity: The ``AVLayerVideoGravity`` to apply to rendered video and images. Defaults to ``AVLayerVideoGravity/resizeAspect``.
    ///   - compressedContentHeight: When non-nil, pins each feed cell's player view to a top-anchored region of this height (in points) instead of filling the cell, so a partially covering sheet can shrink the video above it. `nil` restores the full-bleed layout. Only affects `.verticalFeed`.
    ///   - contentTopInset: The offset, in points, from the top of each cell at which compressed content begins. Ignored when `compressedContentHeight` is `nil`. Defaults to `0`.
    ///   - compressedCornerRadius: The corner radius applied to the player view while compressed. `nil` (or `0`) leaves the video square. Ignored when `compressedContentHeight` is `nil`. Only affects `.verticalFeed`. Defaults to `nil`.
    ///   - overlayForItemAtIndex: A builder that returns an overlay for a given playlist index. Return `nil` to omit an overlay for the item.
    public init(
        type: PlaylistType,
        controller: PlaylistController,
        gravity: AVLayerVideoGravity = .resizeAspect,
        compressedContentHeight: CGFloat? = nil,
        contentTopInset: CGFloat = 0,
        compressedCornerRadius: CGFloat? = nil,
        @ViewBuilder overlayForItemAtIndex: @escaping (Int) -> Overlay
    ) {
        self.playlistType = type
        self.controller = controller
        self.gravity = gravity
        self.compressedContentHeight = compressedContentHeight
        self.contentTopInset = contentTopInset
        self.compressedCornerRadius = compressedCornerRadius
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
        playlistView.setContentCompression(height: compressedContentHeight, topInset: contentTopInset, cornerRadius: compressedCornerRadius)
        return playlistView
    }

    public func updateUIView(_ uiView: UIPlaylistView, context: Context) {
        uiView.setContentCompression(height: compressedContentHeight, topInset: contentTopInset, cornerRadius: compressedCornerRadius)
    }
}
