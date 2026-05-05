//
//  PlaybackQualityPolicy.swift
//  PlayKit
//
//  Created by Telem Tobi on 05/05/2026.
//

import Foundation
import CoreGraphics

/// Configures how PlayKit chooses HLS variants when an `AVPlayer` first starts
/// rendering an item, and how it caps quality during playback.
///
/// AVPlayer's built-in algorithm (since iOS 13) optimizes for fast startup by
/// picking a low-bitrate variant first and upgrading later, even on fast
/// networks. It also serves cached low-quality segments when the user seeks
/// back. ``PlaybackQualityPolicy`` lets the host override that behavior so
/// playback starts at the highest reasonable quality for the current network.
public struct PlaybackQualityPolicy: Sendable, Equatable {
    /// Whether to ask AVPlayer to start on the first variant it finds in the
    /// HLS master playlist (`AVPlayerItem.startsOnFirstEligibleVariant`).
    ///
    /// When combined with ``reordersMultivariantPlaylist`` this produces a
    /// deterministic high-quality startup regardless of how the source orders
    /// its variants.
    public var forcesFirstEligibleVariant: Bool

    /// Whether PlayKit should intercept the HLS master playlist and reorder
    /// `#EXT-X-STREAM-INF` entries so the highest-bandwidth variant appears
    /// first.
    ///
    /// Some servers (e.g. Twitter/X) order variants from low to high. With
    /// this option enabled PlayKit rewrites the manifest in-flight, so AVPlayer
    /// always sees a high-first playlist when it makes its initial selection.
    public var reordersMultivariantPlaylist: Bool

    /// A ceiling, in bits per second, applied via
    /// `AVPlayerItem.preferredPeakBitRate`. `nil` leaves the default (no cap).
    public var preferredPeakBitRate: Double?

    /// A ceiling for "expensive" networks (cellular, hotspots, Low Data Mode)
    /// applied via `AVPlayerItem.preferredPeakBitRateForExpensiveNetworks`.
    /// `nil` leaves the default (matches ``preferredPeakBitRate``).
    public var preferredPeakBitRateForExpensiveNetworks: Double?

    /// A ceiling on resolution applied via
    /// `AVPlayerItem.preferredMaximumResolution`. `nil` leaves the default.
    public var preferredMaximumResolution: CGSize?

    /// A ceiling on resolution for "expensive" networks applied via
    /// `AVPlayerItem.preferredMaximumResolutionForExpensiveNetworks`. `nil`
    /// leaves the default.
    public var preferredMaximumResolutionForExpensiveNetworks: CGSize?

    public init(
        forcesFirstEligibleVariant: Bool,
        reordersMultivariantPlaylist: Bool,
        preferredPeakBitRate: Double? = nil,
        preferredPeakBitRateForExpensiveNetworks: Double? = nil,
        preferredMaximumResolution: CGSize? = nil,
        preferredMaximumResolutionForExpensiveNetworks: CGSize? = nil
    ) {
        self.forcesFirstEligibleVariant = forcesFirstEligibleVariant
        self.reordersMultivariantPlaylist = reordersMultivariantPlaylist
        self.preferredPeakBitRate = preferredPeakBitRate
        self.preferredPeakBitRateForExpensiveNetworks = preferredPeakBitRateForExpensiveNetworks
        self.preferredMaximumResolution = preferredMaximumResolution
        self.preferredMaximumResolutionForExpensiveNetworks = preferredMaximumResolutionForExpensiveNetworks
    }

    /// Restores AVPlayer's stock behavior. Variant selection is left entirely
    /// to AVFoundation's startup-optimized heuristic.
    public static let automatic = PlaybackQualityPolicy(
        forcesFirstEligibleVariant: false,
        reordersMultivariantPlaylist: false
    )

    /// Aggressively prefers the highest available variant on startup, on every
    /// network. Recommended when the host's network is generally good and the
    /// product surface (short-form vertical feeds, story players) can't afford
    /// the visible "low quality first" hop.
    public static let highestQuality = PlaybackQualityPolicy(
        forcesFirstEligibleVariant: true,
        reordersMultivariantPlaylist: true
    )
}
