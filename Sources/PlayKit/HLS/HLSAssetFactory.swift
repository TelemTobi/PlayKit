//
//  HLSAssetFactory.swift
//  PlayKit
//
//  Created by Telem Tobi on 06/05/2026.
//

import Foundation
import AVFoundation
import ObjectiveC

/// Builds an `AVPlayerItem` for a video URL, applying an
/// ``HLSQualityPolicy`` when the URL refers to an HLS playlist.
///
/// Network-class branching:
/// - **Wi-Fi / wired**: rewrite path with the Wi-Fi floor (default
///   720p). Promotes a high variant to position 0 so AVPlayer's
///   "first eligible variant" pick lands on it.
/// - **Cellular**: rewrite path with the cellular floor (default 360p).
///   Earlier versions of this branch passed cellular through to
///   AVPlayer's native ABR. The problem: on a 10-second clip, ABR
///   doesn't have time to ramp from its default lowest-variant cold
///   start before the video ends — viewers watch the whole thing at the
///   lowest rung. A 360p floor is comfortably below any modern cellular
///   envelope (~310 Kbps actual) and since the rewriter no longer
///   *removes* variants, ABR can still drop further if it really needs
///   to. Earlier "locked at low quality" failures were at 720p on
///   borderline cellular; 360p does not reproduce that.
/// - **Constrained (Low Data Mode) / unknown**: passthrough. Low Data
///   Mode is the OS-level "save my bytes" signal and we honor it;
///   unknown means we have no idea what we're on and conservative is
///   safest.
internal enum HLSAssetFactory {
    /// Returns an `AVPlayerItem` configured for the given URL.
    ///
    /// - Parameters:
    ///   - url: The source URL (may be HLS or progressive).
    ///   - policy: The quality policy to apply.
    ///   - viewPixelSize: The render surface's size in pixels at the
    ///     time of preparation. Used to set `preferredMaximumResolution`
    ///     so AVPlayer doesn't decode higher than the surface it draws
    ///     into. Pass `nil` when the view size isn't yet known.
    ///   - networkClass: Override for the current network class, used
    ///     by tests to force either branch deterministically. Production
    ///     callers should accept the default.
    static func makePlayerItem(
        url: URL,
        policy: HLSQualityPolicy,
        viewPixelSize: CGSize?,
        networkClass: () -> HLSNetworkClass = { HLSNetworkClassifier.shared.current }
    ) -> AVPlayerItem {
        guard let configuration = policy.configuration, isHLS(url) else {
            return AVPlayerItem(url: url)
        }

        switch networkClass() {
        case .unconstrained:
            return makeRewrittenItem(
                url: url,
                targetHeight: configuration.wifiMinimumResolution,
                configuration: configuration,
                viewPixelSize: viewPixelSize
            )
        case .cellular:
            return makeRewrittenItem(
                url: url,
                targetHeight: configuration.cellularMinimumResolution,
                configuration: configuration,
                viewPixelSize: viewPixelSize
            )
        case .constrained, .unknown:
            return makePassthroughItem(
                url: url,
                configuration: configuration,
                viewPixelSize: viewPixelSize
            )
        }
    }

    // MARK: - Private

    /// Route the master through the rewriter so we can promote a
    /// higher-than-default initial variant. If `targetHeight` is `nil`
    /// the caller has opted out of promotion for this network class —
    /// fall through to passthrough rather than spend a master fetch on
    /// nothing.
    private static func makeRewrittenItem(
        url: URL,
        targetHeight: Int?,
        configuration: HLSQualityPolicy.Configuration,
        viewPixelSize: CGSize?
    ) -> AVPlayerItem {
        guard let targetHeight, let wrappedURL = wrap(url) else {
            return makePassthroughItem(
                url: url,
                configuration: configuration,
                viewPixelSize: viewPixelSize
            )
        }

        let asset = AVURLAsset(url: wrappedURL)
        let delegate = HLSAssetLoaderDelegate(
            targetHeight: targetHeight,
            removeBelowTarget: configuration.removesVariantsBelowFloor
        )
        asset.resourceLoader.setDelegate(delegate, queue: loaderQueue)

        let item = AVPlayerItem(asset: asset)
        // We control the initial pick via manifest order; AVPlayer should
        // honor it rather than running its own bandwidth heuristic.
        item.startsOnFirstEligibleVariant = true
        applyResolutionCap(item: item, configuration: configuration, viewPixelSize: viewPixelSize)

        // Tie the delegate's lifetime to the player item — when AVPlayer
        // releases the item, the delegate goes with it.
        objc_setAssociatedObject(
            item,
            loaderDelegateAssociationKey,
            delegate,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )

        return item
    }

    /// Constrained / unknown path: hand AVPlayer the original HTTPS URL
    /// untouched. AVPlayer's native HLS pipeline picks the initial
    /// variant from its own bandwidth measurements and adapts from
    /// there. `preferredMaximumResolution` still applies so we don't
    /// decode larger than the render surface.
    private static func makePassthroughItem(
        url: URL,
        configuration: HLSQualityPolicy.Configuration,
        viewPixelSize: CGSize?
    ) -> AVPlayerItem {
        let item = AVPlayerItem(url: url)
        item.startsOnFirstEligibleVariant = false
        applyResolutionCap(item: item, configuration: configuration, viewPixelSize: viewPixelSize)
        return item
    }

    private static func applyResolutionCap(
        item: AVPlayerItem,
        configuration: HLSQualityPolicy.Configuration,
        viewPixelSize: CGSize?
    ) {
        guard configuration.capsResolutionToViewSize,
              let size = viewPixelSize,
              size.width > 0, size.height > 0 else { return }
        item.preferredMaximumResolution = size
    }

    private static let loaderQueue = DispatchQueue(label: "PlayKit.HLSAssetLoader", qos: .userInitiated)

    /// Stable key for the player-item-associated loader delegate. A
    /// single byte is allocated for the lifetime of the process and used
    /// purely for its address. `nonisolated(unsafe)` is sound because
    /// the key is initialized once and never mutated.
    private nonisolated(unsafe) static let loaderDelegateAssociationKey: UnsafeRawPointer = {
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        buffer.initialize(to: 0)
        return UnsafeRawPointer(buffer)
    }()

    private static func isHLS(_ url: URL) -> Bool {
        if url.pathExtension.lowercased() == "m3u8" { return true }
        let lower = url.absoluteString.lowercased()
        return lower.contains(".m3u8")
    }

    private static func wrap(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        switch components.scheme?.lowercased() {
        case "http", "https":
            components.scheme = HLSAssetLoaderDelegate.scheme
            return components.url
        default:
            return nil
        }
    }
}
