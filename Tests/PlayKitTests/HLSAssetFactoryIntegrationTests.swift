import Foundation
import Testing
import AVFoundation
@testable import PlayKit

/// End-to-end checks that exercise the full HLS pipeline against a real
/// public stream — `AVAssetResourceLoaderDelegate` callbacks, manifest
/// rewrite, AVPlayer parsing the rewritten manifest, and the AVPlayerItem
/// reaching `.readyToPlay`.
///
/// Unit tests on the rewriter alone cannot catch contract violations
/// against AVPlayer (e.g. capturing `loadingRequest` weakly so
/// `finishLoading` is never called). These integration tests require
/// network access.
@Suite struct HLSAssetFactoryIntegrationTests {
    /// Apple's reference HLS multivariant stream — long-lived and
    /// publicly documented; used in many WWDC samples.
    private let appleBipBop = URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8")!

    @Test func automaticPolicyReachesReadyToPlay() async throws {
        let item = HLSAssetFactory.makePlayerItem(
            url: appleBipBop,
            policy: .automatic,
            viewPixelSize: CGSize(width: 2400, height: 2400)
        )
        // AVPlayerItem.status only progresses while a player is observing it.
        let player = AVPlayer(playerItem: item)
        defer { player.replaceCurrentItem(with: nil) }

        try await awaitReadyToPlay(item, timeout: 30)
    }

    @Test func unrestrictedPolicyReachesReadyToPlay() async throws {
        // Verifies the non-rewritten path (no resource-loader interception)
        // still works — guards against regressions on plain pass-through.
        let item = HLSAssetFactory.makePlayerItem(
            url: appleBipBop,
            policy: .unrestricted,
            viewPixelSize: nil
        )
        let player = AVPlayer(playerItem: item)
        defer { player.replaceCurrentItem(with: nil) }

        try await awaitReadyToPlay(item, timeout: 30)
    }

    /// Polls `AVPlayerItem.status` until it reaches `.readyToPlay`, throws
    /// on `.failed`, throws on timeout. Polling at 100 ms is plenty given
    /// readyToPlay latency for a public stream is hundreds of ms at most.
    private func awaitReadyToPlay(_ item: AVPlayerItem, timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            switch item.status {
            case .readyToPlay:
                return
            case .failed:
                throw item.error ?? IntegrationError.failedWithoutError
            case .unknown:
                break
            @unknown default:
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw IntegrationError.timedOut
    }

    private enum IntegrationError: Error, CustomStringConvertible {
        case timedOut
        case failedWithoutError
        var description: String {
            switch self {
            case .timedOut: return "AVPlayerItem did not reach .readyToPlay within the timeout"
            case .failedWithoutError: return "AVPlayerItem.status went to .failed without an attached error"
            }
        }
    }
}
