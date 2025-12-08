//
//  PlayKit.swift
//  PlayKit
//
//  Created by Telem Tobi on 08/12/2025.
//

import Foundation

public enum PlayKit {
    /// Video was request to start playing
    public static let videoRequestedNotification = Notification.Name("PlayKit.videoRequested")
    
    /// Video stated playing
    public static let videoStartedNotification = Notification.Name("PlayKit.videoStarted")
    
    /// Video stated playing
    public static let videoStalledNotification = Notification.Name("PlayKit.videoStalled")
    
    public struct NotificationPayload {
        let date = Date()
        let item: PlaylistItem
    }
}
