//
//  PlayKit.swift
//  PlayKit
//
//  Created by Telem Tobi on 08/12/2025.
//

import Foundation

/// Shared namespace for PlayKit notifications and supporting types.
///
/// Use these notifications to observe playback lifecycle events emitted by
/// ``UIPlayerView`` instances that are managed by ``UIPlaylistView`` or
/// ``PlaylistView``.
public enum PlayKit {
    /// Posted when a video item was requested to start loading or playing.
    ///
    /// The notification `object` is a ``NotificationPayload`` describing the
    /// item that is about to start.
    public static let videoRequestedNotification = Notification.Name("PlayKit.videoRequested")
    
    /// Posted when the underlying ``AVPlayer`` begins rendering video frames.
    ///
    /// The notification `object` is a ``NotificationPayload`` describing the
    /// item that has started.
    public static let videoStartedNotification = Notification.Name("PlayKit.videoStarted")
    
    /// Posted when the player is waiting to resume playback because of stalling.
    ///
    /// The notification `object` is a ``NotificationPayload`` describing the
    /// item that stalled.
    public static let videoStalledNotification = Notification.Name("PlayKit.videoStalled")
    
    /// Posted when the player encounters a playback error.
    ///
    /// The notification `object` is a ``NotificationPayload`` describing the
    /// item that failed and, when available, the encountered error.
    public static let videoErrorNotification = Notification.Name("PlayKit.videoError")
    
    /// Payload attached to PlayKit playback notifications.
    ///
    /// This value is delivered as the notification `object` and includes the
    /// time the event was generated alongside the associated ``PlaylistItem``.
    public struct NotificationPayload {
        public let date = Date()
        public let url: URL
        public let error: Error?
        
        init(url: URL, error: Error? = nil) {
            self.url = url
            self.error = error
        }
    }
}
