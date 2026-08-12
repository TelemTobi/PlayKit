//
//  PlaybackTelemetry.swift
//  PlayKit
//
//  Created by Telem Tobi on 12/08/2026.
//

import AVFoundation

public extension PlayKit {
    /// How PlayKit resolved variant selection for one prepared item.
    ///
    /// Reported with ``PlayKit/videoPrepareStartedNotification`` so playback
    /// metrics can be segmented by the policy that actually applied. Without
    /// it, a quality floor that silently fell through to passthrough (Low Data
    /// Mode, an unsettled path) looks identical to one that took effect.
    struct PlaybackContext: Equatable, Sendable {
        /// The class PlayKit assigned to the network path at prepare time.
        public enum NetworkClass: String, Sendable {
            case unconstrained
            case cellular
            case constrained
            case unknown
        }

        public let networkClass: NetworkClass

        /// `true` when the master playlist was routed through the rewriter to
        /// bias the initial variant; `false` on the passthrough path, where
        /// `AVPlayer` makes its own cold-start choice.
        public let isManifestRewritten: Bool

        /// The resolution floor the rewrite aimed for, as a "p" tier, or `nil`
        /// on the passthrough path.
        public let resolutionFloor: Int?

        /// The `preferredMaximumResolution` applied for the render surface, or
        /// `nil` when uncapped.
        public let maximumResolution: CGSize?

        init(
            networkClass: NetworkClass,
            isManifestRewritten: Bool,
            resolutionFloor: Int? = nil,
            maximumResolution: CGSize? = nil
        ) {
            self.networkClass = networkClass
            self.isManifestRewritten = isManifestRewritten
            self.resolutionFloor = resolutionFloor
            self.maximumResolution = maximumResolution
        }
    }

    /// The variant `AVPlayer` is rendering at a point in time.
    struct PlaybackVariant: Equatable, Sendable {
        /// The decoded frame size, in pixels.
        public let presentationSize: CGSize

        /// The variant's declared peak bitrate in bits per second, when the
        /// access log has reported one yet.
        public let indicatedBitrate: Double?

        /// The standard "p" tier of ``presentationSize``'s shorter edge — 360
        /// for both `640x360` and a portrait `360x640`, so the value means the
        /// same quality in any orientation.
        public var resolutionTier: Int {
            Int(min(presentationSize.width, presentationSize.height).rounded())
        }

        init(presentationSize: CGSize, indicatedBitrate: Double?) {
            self.presentationSize = presentationSize
            self.indicatedBitrate = indicatedBitrate
        }
    }

    /// An item's access and error logs, aggregated at teardown.
    ///
    /// `AVPlayer` releases a player item as soon as playback ends, taking both
    /// logs with it — this snapshot is taken while the item is still alive.
    /// Values `AVFoundation` reports as negative ("unknown") are normalized to
    /// `nil` or excluded from sums.
    struct PlaybackMetrics: Equatable, Sendable {
        /// Declared bitrate of the last variant played, in bits per second.
        public let indicatedBitrate: Double?

        /// Empirical throughput the player measured, in bits per second.
        public let observedBitrate: Double?

        /// Average bitrate of the video track actually played.
        public let averageVideoBitrate: Double?

        /// The decoded frame size at teardown.
        public let presentationSize: CGSize?

        /// Stalls `AVFoundation` counted for this item across its access log.
        public let stallCount: Int

        /// `AVFoundation`'s own time-to-first-frame measurement, in seconds.
        public let startupTime: TimeInterval?

        /// Seconds of media actually played.
        public let durationWatched: TimeInterval

        public let bytesTransferred: Int64
        public let transferDuration: TimeInterval
        public let mediaRequestCount: Int

        /// Media requests served over cellular. Confirms whether the bytes
        /// really came down a WWAN path, independently of the interface the
        /// app believes it is on.
        public let cellularMediaRequestCount: Int

        public let droppedFrameCount: Int

        /// The address that served the media — the CDN PoP, in practice.
        public let serverAddress: String?

        /// `AVFoundation`'s own playback session id, for joining these numbers
        /// against CDN-side logs.
        public let playbackSessionId: String?

        /// How many entries `AVPlayerItem` wrote to its error log.
        ///
        /// These are mostly *not* user-visible: a retried segment or a 404 on
        /// one rendition lands here while playback carries on. Reported as a
        /// count rather than as events precisely because a single underlying
        /// fault can produce several entries. A playback with a healthy
        /// ``durationWatched`` and a non-zero count had errors the viewer
        /// never saw.
        public let errorEntryCount: Int

        /// Distinct HTTP status codes across the error log, sorted. A 4xx here
        /// usually means an expired token or a rotated asset URL.
        public let errorStatusCodes: [Int]

        /// Domain and comment of the most recent error-log entry, for
        /// drill-down.
        public let lastErrorDomain: String?
        public let lastErrorComment: String?
    }
}

internal extension PlayKit.PlaybackMetrics {
    /// Aggregates `item`'s access and error logs.
    ///
    /// Additive counters are summed across access-log entries —
    /// `AVFoundation` opens a new entry per server or variant change — while
    /// point-in-time values take the most recent usable reading.
    init(item: AVPlayerItem) {
        let events = item.accessLog()?.events ?? []
        let errors = item.errorLog()?.events ?? []

        func latest(_ keyPath: KeyPath<AVPlayerItemAccessLogEvent, Double>) -> Double? {
            events.reversed()
                .lazy
                .map { $0[keyPath: keyPath] }
                .first { $0 > 0 }
        }

        func sum(_ keyPath: KeyPath<AVPlayerItemAccessLogEvent, Int>) -> Int {
            events.reduce(0) { $0 + max($1[keyPath: keyPath], 0) }
        }

        func sum(_ keyPath: KeyPath<AVPlayerItemAccessLogEvent, Double>) -> Double {
            events.reduce(0) { $0 + max($1[keyPath: keyPath], 0) }
        }

        self.init(
            indicatedBitrate: latest(\.indicatedBitrate),
            observedBitrate: latest(\.observedBitrate),
            averageVideoBitrate: latest(\.averageVideoBitrate),
            presentationSize: item.presentationSize == .zero ? nil : item.presentationSize,
            stallCount: sum(\.numberOfStalls),
            // Only the entry covering the initial load reports a startup time;
            // later entries report -1.
            startupTime: events.lazy.map(\.startupTime).first { $0 > 0 },
            durationWatched: sum(\.durationWatched),
            bytesTransferred: events.reduce(0) { $0 + max($1.numberOfBytesTransferred, 0) },
            transferDuration: sum(\.transferDuration),
            mediaRequestCount: sum(\.numberOfMediaRequests),
            cellularMediaRequestCount: sum(\.mediaRequestsWWAN),
            droppedFrameCount: sum(\.numberOfDroppedVideoFrames),
            serverAddress: events.reversed().compactMap(\.serverAddress).first,
            playbackSessionId: events.compactMap(\.playbackSessionID).first,
            errorEntryCount: errors.count,
            errorStatusCodes: Set(errors.map(\.errorStatusCode)).sorted(),
            lastErrorDomain: errors.last?.errorDomain,
            lastErrorComment: errors.last?.errorComment
        )
    }
}

internal extension HLSNetworkClass {
    var telemetryValue: PlayKit.PlaybackContext.NetworkClass {
        switch self {
        case .unconstrained: .unconstrained
        case .cellular: .cellular
        case .constrained: .constrained
        case .unknown: .unknown
        }
    }
}
