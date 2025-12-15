//
//  TapThroughView.swift
//  PlayKit
//
//  Created by Telem Tobi on 13/12/2025.
//

import UIKit

final class TapThroughView: UIView, PlaylistContentView {
    convenience init(players: [UIPlayerView]) {
        self.init(frame: .zero)
        
        for playerView in players {
            playerView.alpha = .zero
            addSubview(playerView)
            playerView.anchorToSuperview()
        }
    }
}
