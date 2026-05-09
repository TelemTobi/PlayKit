//
//  HLSQualityPolicy.swift
//  PlayKit
//
//  Created by Telem Tobi on 06/05/2026.
//

import Foundation

/// Controls how PlayKit selects an initial HLS variant when a `.video`
/// item is played.
///
/// AVPlayer's default behavior on Wi-Fi starts at the lowest variant in
/// the master playlist before adapting upward, which produces a visible
/// "starts blurry" experience. PlayKit intervenes on Wi-Fi/wired networks
/// only — it rewrites the master playlist to promote a higher variant to
/// the first position so `AVPlayerItem.startsOnFirstEligibleVariant=true`
/// picks it.
///
/// On cellular and constrained networks, PlayKit deliberately *does not*
/// intervene: it hands AVPlayer the original URL untouched and lets
/// AVPlayer's native ABR pick the initial variant. AVPlayer's heuristic
/// is bandwidth-aware and tuned for cellular — past attempts to bias the
/// initial pick upward on cellular caused the player to commit to a
/// variant the link couldn't sustain, producing exactly the "long load
/// then locked at low quality" failure mode this branch was originally
/// trying to fix.
public enum HLSQualityPolicy: Sendable, Equatable {
    /// Sensible defaults:
    /// - Wi-Fi / wired Ethernet: bias the initial variant up to ≥720p
    ///   via manifest reorder. ABR is unaffected and still has every
    ///   variant to adapt across.
    /// - Cellular / constrained / unknown: AVPlayer's native HLS
    ///   pipeline. No master-playlist interception, no variant promotion.
    /// All cases additionally set `preferredMaximumResolution` so the
    /// player doesn't decode higher than the surface it draws into.
    case automatic

    /// Disables PlayKit's HLS interception entirely on every network.
    /// AVPlayer makes its own initial-variant choice everywhere.
    case unrestricted

    /// Caller-supplied configuration.
    case custom(Configuration)

    public struct Configuration: Sendable, Equatable, Hashable {
        /// Minimum video pixel height to promote on Wi-Fi or wired
        /// Ethernet.
        ///
        /// The rewriter promotes the smallest variant whose height is
        /// `>= wifiMinimumHeight` to the first position in the master
        /// playlist; if no variant clears the bar (e.g. a low-ladder
        /// portrait source) the highest variant is promoted instead.
        /// Set to `nil` to skip the Wi-Fi rewrite.
        public var wifiMinimumHeight: Int?

        /// When `true`, `AVPlayerItem.preferredMaximumResolution` is set
        /// to the player view's pixel size so AVPlayer doesn't decode
        /// higher than it renders. Applies on every network.
        public var capsResolutionToViewSize: Bool

        public init(
            wifiMinimumHeight: Int? = 720,
            capsResolutionToViewSize: Bool = true
        ) {
            self.wifiMinimumHeight = wifiMinimumHeight
            self.capsResolutionToViewSize = capsResolutionToViewSize
        }
    }

    /// The configuration this policy applies, or `nil` when no
    /// manipulation should occur on any network.
    internal var configuration: Configuration? {
        switch self {
        case .automatic: return Configuration()
        case .unrestricted: return nil
        case let .custom(config): return config
        }
    }
}
