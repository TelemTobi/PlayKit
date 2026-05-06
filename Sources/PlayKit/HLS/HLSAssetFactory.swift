//
//  HLSAssetFactory.swift
//  PlayKit
//
//  Created by Telem Tobi on 06/05/2026.
//

import Foundation
import AVFoundation
import ObjectiveC
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

/// Builds an `AVPlayerItem` for a video URL, applying an
/// ``HLSQualityPolicy`` when the URL refers to an HLS playlist.
internal enum HLSAssetFactory {
    /// Returns an `AVPlayerItem` configured for the given URL.
    ///
    /// - Parameters:
    ///   - url: The source URL (may be HLS or progressive).
    ///   - policy: The quality policy to apply.
    ///   - viewPixelSize: The render surface's size in pixels at the time of
    ///     preparation, used to cap variant resolution. Pass `nil` if the
    ///     view size is not yet known; the cap will be skipped for this item.
    static func makePlayerItem(
        url: URL,
        policy: HLSQualityPolicy,
        viewPixelSize: CGSize?
    ) -> AVPlayerItem {
        guard let configuration = policy.configuration,
              isHLS(url),
              let wrappedURL = wrap(url) else {
            return AVPlayerItem(url: url)
        }

        let asset = AVURLAsset(url: wrappedURL)

        let viewPixelHeight: Int?
        if configuration.capsResolutionToViewSize, let size = viewPixelSize, size.height > 0 {
            viewPixelHeight = Int(size.height.rounded())
        } else {
            viewPixelHeight = nil
        }

        let delegate = HLSAssetLoaderDelegate(
            configuration: configuration,
            viewPixelHeight: { viewPixelHeight }
        )
        asset.resourceLoader.setDelegate(delegate, queue: loaderQueue)

        let item = AVPlayerItem(asset: asset)
        item.startsOnFirstEligibleVariant = true
        if let size = viewPixelSize,
           configuration.capsResolutionToViewSize,
           size.width > 0, size.height > 0 {
            item.preferredMaximumResolution = size
        }

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

    /// A square cap derived from the device screen's long edge in pixels,
    /// suitable to use when no view-bounds-derived size is available yet
    /// (e.g. during ``PlaylistController`` pre-warm before any view exists).
    /// Returns `nil` on platforms where the screen isn't reachable.
    static func estimatedScreenPixelSize() -> CGSize? {
        #if canImport(UIKit) && !os(watchOS)
        let bounds = UIScreen.main.nativeBounds
        let longEdge = max(bounds.width, bounds.height)
        return CGSize(width: longEdge, height: longEdge)
        #else
        return nil
        #endif
    }

    private static let loaderQueue = DispatchQueue(label: "PlayKit.HLSAssetLoader", qos: .userInitiated)

    /// Stable key for the player-item-associated loader delegate. A single
    /// byte is allocated for the lifetime of the process and used purely for
    /// its address. `nonisolated(unsafe)` is sound because the key is
    /// initialized once and never mutated.
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
