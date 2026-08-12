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
///
/// Every notification carries a ``NotificationPayload`` whose
/// ``NotificationPayload/playbackId`` identifies one item lifecycle — from
/// `prepare` to teardown. Correlate events by that id rather than by URL: a
/// buffered playlist prepares several players at once, and the same URL can
/// legitimately play on two surfaces simultaneously.
///
/// The lifecycle, in order: ``videoPrepareStartedNotification`` →
/// ``videoReadyNotification`` → ``videoRequestedNotification`` →
/// ``videoStartedNotification`` → ``videoFinishedNotification``, with
/// ``videoStalledNotification``, ``videoVariantChangedNotification`` and
/// ``videoErrorNotification`` interleaved as they occur. Only
/// `prepareStarted` and `finished` are guaranteed to be paired.
public enum PlayKit {
    /// Posted when a video item begins loading — the player item was created
    /// and handed to `AVPlayer`.
    ///
    /// This marks the start of the *load*, as opposed to
    /// ``videoRequestedNotification`` which marks play *intent*. Buffered
    /// look-ahead items are prepared long before they're requested, so the
    /// gap between the two measures prefetch benefit rather than latency.
    /// The payload's ``NotificationPayload/context`` describes how PlayKit
    /// resolved variant selection for this item.
    public static let videoPrepareStartedNotification = Notification.Name("PlayKit.videoPrepareStarted")

    /// Posted when the player item reaches `readyToPlay` — enough of the
    /// stream is loaded for playback to begin.
    public static let videoReadyNotification = Notification.Name("PlayKit.videoReady")

    /// Posted when a video item was requested to start loading or playing.
    ///
    /// The notification `object` is a ``NotificationPayload`` describing the
    /// item that is about to start. Posted on every play intent, including a
    /// resume after pause — dedupe by ``NotificationPayload/playbackId`` when
    /// measuring startup, or a resume will register as an instant load.
    public static let videoRequestedNotification = Notification.Name("PlayKit.videoRequested")

    /// Posted when the underlying ``AVPlayer`` begins rendering video frames.
    ///
    /// The notification `object` is a ``NotificationPayload`` describing the
    /// item that has started. Also posted when playback resumes.
    public static let videoStartedNotification = Notification.Name("PlayKit.videoStarted")

    /// Posted when the player is waiting to resume playback because of stalling.
    ///
    /// The notification `object` is a ``NotificationPayload`` describing the
    /// item that stalled. Check ``NotificationPayload/isRebuffer`` to tell a
    /// mid-playback rebuffer from the initial buffering every cold start goes
    /// through — conflating the two makes stall rate read as ~100%.
    public static let videoStalledNotification = Notification.Name("PlayKit.videoStalled")

    /// Posted when the resolution `AVPlayer` renders changes — the initial
    /// variant pick, and every ABR switch after it.
    ///
    /// The payload's ``NotificationPayload/variant`` carries the new
    /// presentation size and the variant's declared bitrate.
    public static let videoVariantChangedNotification = Notification.Name("PlayKit.videoVariantChanged")

    /// Posted when the player encounters a terminal playback error — the item
    /// failed and will not play.
    ///
    /// The notification `object` is a ``NotificationPayload`` describing the
    /// item that failed and, when available, the encountered error. This is
    /// deliberately narrow: the transient entries `AVPlayerItem` writes to its
    /// error log (a retried segment, a redirect, a 404 on one rendition) are
    /// usually invisible to the viewer, so they are *not* posted as events.
    /// They arrive aggregated in ``PlaybackMetrics`` on
    /// ``videoFinishedNotification`` instead.
    public static let videoErrorNotification = Notification.Name("PlayKit.videoError")

    /// Posted when a video item is torn down — replaced, cancelled, or
    /// released after playing to the end.
    ///
    /// The payload's ``NotificationPayload/outcome`` says how it ended, and
    /// ``NotificationPayload/metrics`` carries the item's aggregated access
    /// and error logs (bitrates, stalls, bytes, dropped frames, error
    /// entries). This is the only place those numbers are available —
    /// `AVPlayer` releases the item immediately after.
    ///
    /// An item that never started playing produces a `finished` with no
    /// preceding `started`: that pairing is how a load abandoned before first
    /// frame is detected.
    public static let videoFinishedNotification = Notification.Name("PlayKit.videoFinished")

    /// Payload attached to PlayKit playback notifications.
    ///
    /// This value is delivered as the notification `object` and includes the
    /// time the event was generated alongside the associated ``PlaylistItem``.
    /// Fields beyond `date`, `url`, `playbackId` and `surface` are populated
    /// only for the events that describe them.
    public struct NotificationPayload {
        /// How a playback ended, reported with ``videoFinishedNotification``.
        public enum Outcome: String {
            /// Played through to the end at least once.
            case completed
            /// Torn down before finishing — scrolled past, replaced, or
            /// dropped out of the buffer window.
            case interrupted
            /// Ended on a terminal player error.
            case failed
        }

        public let date = Date()
        public let url: URL

        /// Identifies one item lifecycle, from `prepare` to teardown.
        ///
        /// Stable across every event for that playback, and unique per
        /// prepare — re-preparing the same URL yields a new id.
        public let playbackId: String

        /// The caller-provided label of the surface this item plays on,
        /// forwarded from ``PlaylistController/surface``.
        public let surface: String?

        public let error: Error?

        /// How variant selection was resolved. Set on
        /// ``videoPrepareStartedNotification``.
        public let context: PlaybackContext?

        /// The resolution currently being rendered. Set on
        /// ``videoVariantChangedNotification``.
        public let variant: PlaybackVariant?

        /// The item's aggregated access and error logs. Set on
        /// ``videoFinishedNotification``.
        public let metrics: PlaybackMetrics?

        /// `true` when the stall interrupted playback that had already
        /// started, `false` while the first frame is still buffering. Only
        /// meaningful on ``videoStalledNotification``.
        public let isRebuffer: Bool

        /// How the playback ended. Set on ``videoFinishedNotification``.
        public let outcome: Outcome?

        init(
            url: URL,
            playbackId: String,
            surface: String? = nil,
            error: Error? = nil,
            context: PlaybackContext? = nil,
            variant: PlaybackVariant? = nil,
            metrics: PlaybackMetrics? = nil,
            isRebuffer: Bool = false,
            outcome: Outcome? = nil
        ) {
            self.url = url
            self.playbackId = playbackId
            self.surface = surface
            self.error = error
            self.context = context
            self.variant = variant
            self.metrics = metrics
            self.isRebuffer = isRebuffer
            self.outcome = outcome
        }
    }
}
