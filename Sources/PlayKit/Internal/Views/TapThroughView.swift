//
//  TapThroughView.swift
//  PlayKit
//
//  Created by Telem Tobi on 13/12/2025.
//

import UIKit

// TODO: Consider removing if that's all it does ⚠️
final class TapThroughView: UIView {
    
    convenience init(players: [UIPlayerView]) {
        self.init(frame: .zero)
        
        for playerView in players {
            playerView.alpha = .zero
            addSubview(playerView)
            playerView.anchorToSuperview()
        }
    }
}
