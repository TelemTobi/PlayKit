//
//  PlaylistContentView.swift
//  PlayKit
//
//  Created by Telem Tobi on 14/12/2025.
//

import UIKit

protocol PlaylistContentView: UIView {
    func reloadData()
    func setContentCompression(height: CGFloat?, topInset: CGFloat, cornerRadius: CGFloat?)
}

extension PlaylistContentView {
    func reloadData() {}
    func setContentCompression(height: CGFloat?, topInset: CGFloat, cornerRadius: CGFloat?) {}
}
