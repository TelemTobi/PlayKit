//
//  AVPlayerItem+QualityPolicy.swift
//  PlayKit
//
//  Created by Telem Tobi on 05/05/2026.
//

import Foundation
import AVFoundation

extension AVPlayerItem {
    /// Builds an `AVPlayerItem` for a video URL that applies the host's
    /// ``PlaybackQualityPolicy`` and, for HLS streams, opts in to the
    /// manifest-rewriting strategy that forces a high-bandwidth first variant.
    ///
    /// The returned `loaderDelegate` must be retained for the lifetime of the
    /// player item — `AVURLAsset` holds its resource-loader delegate weakly.
    /// The caller stores it alongside the player item (e.g. on the player
    /// view) and discards it when the item is replaced.
    nonisolated static func makeConfigured(
        url: URL,
        policy: PlaybackQualityPolicy
    ) -> (item: AVPlayerItem, loaderDelegate: HLSManifestRewriter?) {
        let isHLS = isLikelyHLS(url: url)
        let shouldRewriteManifest = isHLS && policy.reordersMultivariantPlaylist

        let asset: AVURLAsset
        let rewriter: HLSManifestRewriter?
        if shouldRewriteManifest, let customURL = HLSManifestRewriter.customSchemeURL(for: url) {
            asset = AVURLAsset(url: customURL)
            let delegate = HLSManifestRewriter(originalURL: url)
            asset.resourceLoader.setDelegate(delegate, queue: .main)
            rewriter = delegate
        } else {
            asset = AVURLAsset(url: url)
            rewriter = nil
        }

        let item = AVPlayerItem(asset: asset)
        apply(policy: policy, to: item)
        return (item, rewriter)
    }

    /// Applies the mutable parts of a quality policy to an existing player
    /// item. Called both when the item is first created and when the host
    /// updates the policy mid-playback.
    nonisolated static func apply(policy: PlaybackQualityPolicy, to item: AVPlayerItem) {
        if policy.forcesFirstEligibleVariant {
            item.startsOnFirstEligibleVariant = true
        }

        item.preferredPeakBitRate = policy.preferredPeakBitRate ?? 0
        if #available(iOS 15.0, tvOS 15.0, macOS 12.0, watchOS 8.0, *) {
            item.preferredPeakBitRateForExpensiveNetworks =
                policy.preferredPeakBitRateForExpensiveNetworks ?? 0
        }

        item.preferredMaximumResolution = policy.preferredMaximumResolution ?? .zero
        if #available(iOS 15.0, tvOS 15.0, macOS 12.0, *) {
            item.preferredMaximumResolutionForExpensiveNetworks =
                policy.preferredMaximumResolutionForExpensiveNetworks ?? .zero
        }
    }

    nonisolated private static func isLikelyHLS(url: URL) -> Bool {
        if url.pathExtension.lowercased() == "m3u8" { return true }
        if url.path.lowercased().contains(".m3u8") { return true }
        return false
    }
}
