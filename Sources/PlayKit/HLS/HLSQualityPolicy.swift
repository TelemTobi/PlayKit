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
/// AVPlayer's default behavior cold-starts at the lowest variant in the
/// master playlist before adapting upward, which produces a visible
/// "starts blurry" experience. For short-form clips (10–15s) ABR doesn't
/// get enough runway to ramp before the video ends, so the viewer
/// watches the whole thing at the lowest rung.
///
/// PlayKit intervenes on Wi-Fi/wired *and* cellular by rewriting the
/// master playlist to promote a higher variant to the first position so
/// `AVPlayerItem.startsOnFirstEligibleVariant=true` picks it. The floors
/// differ by network class: Wi-Fi gets a 720p floor, cellular gets a
/// 360p floor (low enough that any modern cellular link sustains it, but
/// high enough to be watchable). Past attempts to push cellular to 720p
/// produced "slow load → locked at low quality"; 360p sits well below
/// any cellular envelope and the rewriter no longer removes variants, so
/// ABR can still drop further if the link genuinely can't sustain even
/// that.
///
/// Low Data Mode (`.constrained`) and `.unknown` always stay on
/// passthrough — Low Data Mode is the user telling the OS to conserve
/// bandwidth and we honor that.
public enum HLSQualityPolicy: Sendable, Equatable {
    /// Sensible defaults:
    /// - Wi-Fi / wired Ethernet: bias the initial variant up to ≥720p
    ///   via manifest reorder.
    /// - Cellular: bias the initial variant up to ≥360p via manifest
    ///   reorder.
    /// - Low Data Mode / unknown: AVPlayer's native HLS pipeline, no
    ///   interception.
    /// ABR is unaffected on every path and still has every variant to
    /// adapt across. All cases additionally set
    /// `preferredMaximumResolution` so the player doesn't decode higher
    /// than the surface it draws into.
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
        /// Set to `nil` to skip the Wi-Fi rewrite (passthrough to native
        /// ABR).
        public var wifiMinimumHeight: Int?

        /// Minimum video pixel height to promote on cellular.
        ///
        /// Same promotion rule as `wifiMinimumHeight`. Defaults to 360 —
        /// the lowest height that's still watchable on a phone screen.
        /// Set to `nil` to skip the cellular rewrite and let AVPlayer's
        /// native ABR pick the initial variant.
        public var cellularMinimumHeight: Int?

        /// When `true`, `AVPlayerItem.preferredMaximumResolution` is set
        /// to the player view's pixel size so AVPlayer doesn't decode
        /// higher than it renders. Applies on every network.
        public var capsResolutionToViewSize: Bool

        public init(
            wifiMinimumHeight: Int? = 720,
            cellularMinimumHeight: Int? = 360,
            capsResolutionToViewSize: Bool = true
        ) {
            self.wifiMinimumHeight = wifiMinimumHeight
            self.cellularMinimumHeight = cellularMinimumHeight
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
