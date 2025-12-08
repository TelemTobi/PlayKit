//
//  PlayKit.swift
//  PlayKit
//
//  Created by Telem Tobi on 08/12/2025.
//

import Foundation

public enum PlayKit {
    public static let videoRequestedNotification = Notification.Name("PlayKit.videoRequested")
    public static let videoStartedNotification = Notification.Name("PlayKit.videoStarted")
    
    public struct NotificationPayload {
        let date = Date()
        let item: PlaylistItem
    }
}
