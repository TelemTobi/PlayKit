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
    ///
    /// - Parameter defaultMaximumPixelSize: A view-derived ceiling, in pixels,
    ///   used as the fallback for `preferredMaximumResolution` when the policy
    ///   itself doesn't specify one. Lets PlayKit avoid downloading variants
    ///   bigger than the player will ever render.
    nonisolated static func makeConfigured(
        url: URL,
        policy: PlaybackQualityPolicy,
        defaultMaximumPixelSize: CGSize? = nil
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
        apply(policy: policy, to: item, defaultMaximumPixelSize: defaultMaximumPixelSize)
        return (item, rewriter)
    }

    /// Applies the mutable parts of a quality policy to an existing player
    /// item. Called both when the item is first created and when the host
    /// updates the policy mid-playback.
    ///
    /// - Parameter defaultMaximumPixelSize: A view-derived ceiling, in pixels.
    ///   Used as the fallback resolution cap when ``PlaybackQualityPolicy/preferredMaximumResolution``
    ///   is `nil`. Pass the player view's `bounds.size × displayScale` so AVPlayer
    ///   skips variants larger than the surface that will render them.
    nonisolated static func apply(
        policy: PlaybackQualityPolicy,
        to item: AVPlayerItem,
        defaultMaximumPixelSize: CGSize? = nil
    ) {
        if policy.forcesFirstEligibleVariant {
            item.startsOnFirstEligibleVariant = true
        }

        item.preferredPeakBitRate = policy.preferredPeakBitRate ?? 0
        if #available(iOS 15.0, tvOS 15.0, macOS 12.0, watchOS 8.0, *) {
            item.preferredPeakBitRateForExpensiveNetworks =
                policy.preferredPeakBitRateForExpensiveNetworks ?? 0
        }

        let resolution = policy.preferredMaximumResolution
            ?? defaultMaximumPixelSize
            ?? .zero
        item.preferredMaximumResolution = resolution

        if #available(iOS 15.0, tvOS 15.0, macOS 12.0, *) {
            let expensiveResolution = policy.preferredMaximumResolutionForExpensiveNetworks
                ?? policy.preferredMaximumResolution
                ?? defaultMaximumPixelSize
                ?? .zero
            item.preferredMaximumResolutionForExpensiveNetworks = expensiveResolution
        }
    }

    nonisolated private static func isLikelyHLS(url: URL) -> Bool {
        if url.pathExtension.lowercased() == "m3u8" { return true }
        if url.path.lowercased().contains(".m3u8") { return true }
        return false
    }
}
