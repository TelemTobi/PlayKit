//
//  HLSQualityPolicy.swift
//  PlayKit
//
//  Created by Telem Tobi on 06/05/2026.
//

import Foundation

/// Controls how PlayKit selects an initial HLS variant when a `.video` item is
/// played.
///
/// AVPlayer's default initial-variant heuristic is conservative and frequently
/// starts at the lowest available variant before adapting upward, which causes
/// a visible "starts blurry" experience on multivariant playlists. Apply a
/// policy to bias the initial pick toward a quality floor that respects the
/// user's network class.
public enum HLSQualityPolicy: Sendable, Equatable {
    /// Sensible defaults driven by the user's current network:
    /// - Wi-Fi / wired Ethernet: floor at 720p; if every variant is below
    ///   720p, the highest available variant is used.
    /// - Fast cellular (5G or LTE): floor at 480p.
    /// - Slow cellular (3G or older): floor at 360p.
    /// - Low Data Mode or otherwise constrained networks: no manipulation.
    /// All cases additionally cap the maximum resolution to the player view's
    /// rendered pixel size so the player doesn't decode higher than the
    /// surface it draws into.
    case automatic

    /// Disables PlayKit's HLS interception entirely. AVPlayer makes its own
    /// choices.
    case unrestricted

    /// Caller-supplied configuration.
    case custom(Configuration)

    /// Concrete thresholds applied by ``HLSQualityPolicy/automatic`` and
    /// ``HLSQualityPolicy/custom(_:)``.
    public struct Configuration: Sendable, Equatable, Hashable {
        /// Minimum video pixel height to use on Wi-Fi or wired Ethernet.
        ///
        /// If every variant in the manifest falls below this value, the
        /// highest available variant is used as a fallback.
        public var wifiMinimumHeight: Int?

        /// Minimum video pixel height to use on fast cellular (5G / LTE).
        public var fastCellularMinimumHeight: Int?

        /// Minimum video pixel height to use on slow cellular (3G or older).
        public var slowCellularMinimumHeight: Int?

        /// When `true`, the variant selection is also capped to the player
        /// view's pixel size so the player doesn't decode higher than it
        /// renders.
        public var capsResolutionToViewSize: Bool

        public init(
            wifiMinimumHeight: Int? = 720,
            fastCellularMinimumHeight: Int? = 480,
            slowCellularMinimumHeight: Int? = 360,
            capsResolutionToViewSize: Bool = true
        ) {
            self.wifiMinimumHeight = wifiMinimumHeight
            self.fastCellularMinimumHeight = fastCellularMinimumHeight
            self.slowCellularMinimumHeight = slowCellularMinimumHeight
            self.capsResolutionToViewSize = capsResolutionToViewSize
        }
    }

    /// The configuration this policy applies, or `nil` when no manipulation
    /// should occur.
    internal var configuration: Configuration? {
        switch self {
        case .automatic: return Configuration()
        case .unrestricted: return nil
        case let .custom(config): return config
        }
    }
}
