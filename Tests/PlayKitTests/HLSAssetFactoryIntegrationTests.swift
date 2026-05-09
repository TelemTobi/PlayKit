import Foundation
import Testing
import AVFoundation
@testable import PlayKit

/// End-to-end checks that exercise the full HLS pipeline against real
/// public streams — `AVAssetResourceLoaderDelegate` callbacks, manifest
/// rewrite, AVPlayer parsing the rewritten manifest, and the AVPlayerItem
/// reaching `.readyToPlay`.
///
/// Unit tests on the rewriter alone cannot catch contract violations
/// against AVPlayer (e.g. capturing `loadingRequest` weakly so
/// `finishLoading` is never called), and they can't catch the production
/// bug where dropping variants below the floor stripped ABR's downshift
/// path on Twitter's portrait ladders. These integration tests require
/// network access.
@Suite struct HLSAssetFactoryIntegrationTests {
    /// Apple's reference HLS multivariant stream — long-lived and
    /// publicly documented; used in many WWDC samples.
    private let appleBipBop = URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8")!

    /// Real Twitter HLS samples the team ships in production. Twitter
    /// rotates URLs over time, so a 4xx here is a signal to refresh the
    /// fixture rather than evidence of a regression.
    private let twitterSamples: [URL] = [
        URL(string: "https://video.twimg.com/amplify_video/2052598697494822912/pl/RlXt3Dc9rvJiaHsP.m3u8?tag=14")!,
        URL(string: "https://video.twimg.com/amplify_video/2052600700958380037/pl/8sv_B4I6g7I6ay4r.m3u8")!,
        URL(string: "https://video.twimg.com/amplify_video/2052602909603348486/pl/c4vgX97muaW78MBl.m3u8")!,
        URL(string: "https://video.twimg.com/amplify_video/2052603114822283268/pl/t73rEuDhtldPiGA6.m3u8")!,
        URL(string: "https://video.twimg.com/amplify_video/2052608087077359618/pl/ywHR2xUIRY2K-lFQ.m3u8")!,
        URL(string: "https://video.twimg.com/amplify_video/2052632039837331458/pl/R9WFh3euPZxCOjeQ.m3u8")!
    ]

    // MARK: - End-to-end reachability

    @Test func automaticPolicyReachesReadyToPlay() async throws {
        let item = HLSAssetFactory.makePlayerItem(
            url: appleBipBop,
            policy: .automatic,
            viewPixelSize: CGSize(width: 2400, height: 2400)
        )
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

    /// Sweep the production fleet under `.automatic`. The classifier picks
    /// whatever interface the test host is on; the assertion is just that
    /// AVPlayer reaches readyToPlay through the full pipeline. This is the
    /// regression sentinel for the "loadingRequest captured weakly" class
    /// of bug — `finishLoading` either fires or AVPlayer hangs.
    @Test func sweepProductionSamplesUnderAutomaticPolicy() async throws {
        for url in twitterSamples {
            let item = HLSAssetFactory.makePlayerItem(
                url: url,
                policy: .automatic,
                viewPixelSize: CGSize(width: 2400, height: 2400)
            )
            let player = AVPlayer(playerItem: item)
            do {
                try await awaitReadyToPlay(item, timeout: 30)
            } catch {
                Issue.record("\(url.lastPathComponent) failed under .automatic: \(error)")
            }
            player.replaceCurrentItem(with: nil)
        }
    }

    // MARK: - ABR invariants on real masters

    /// The bug: dropping variants below the policy floor left Twitter's
    /// `{404, 608, 912}` portrait ladders with one variant on Wi-Fi (only
    /// 912 cleared the 720 floor) and two on cellular (only 608 + 912
    /// cleared the 480 floor). ABR couldn't downshift on weak networks
    /// → stalls. This test fetches the live masters and asserts the
    /// rewriter — across every target height the production policy uses,
    /// including the `unconstrained` 720 case — preserves the source
    /// variant count.
    @Test func rewriterPreservesVariantCountAcrossAllTargets() async throws {
        let baseConfig = HLSQualityPolicy.Configuration()
        let targets: [(label: String, value: Int?)] = [
            ("wifi/wired", baseConfig.wifiMinimumHeight),
            ("fast cellular", baseConfig.fastCellularMinimumHeight),
            ("slow cellular", baseConfig.slowCellularMinimumHeight),
            ("constrained/unknown", nil)
        ]

        for url in twitterSamples {
            let manifest: String
            do {
                manifest = try await fetchManifest(url: url)
            } catch {
                Issue.record("Couldn't fetch \(url.lastPathComponent): \(error). Refresh the fixture.")
                continue
            }
            let sourceCount = countStreamInf(in: manifest)
            guard sourceCount > 0 else {
                Issue.record("\(url.lastPathComponent) is not a multivariant master.")
                continue
            }

            for target in targets {
                let rewritten = HLSManifestRewriter.rewrite(
                    manifest: manifest,
                    baseURL: url,
                    targetHeight: target.value
                ) ?? manifest
                let rewrittenCount = countStreamInf(in: rewritten)
                #expect(
                    rewrittenCount == sourceCount,
                    "\(url.lastPathComponent) under \(target.label) target: rewriter emitted \(rewrittenCount)/\(sourceCount) variants — ABR cannot adapt with rungs missing"
                )
            }
        }
    }

    // MARK: - Helpers

    private func fetchManifest(url: URL) async throws -> String {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw IntegrationError.nonUTF8Manifest
        }
        return text
    }

    private func countStreamInf(in manifest: String) -> Int {
        manifest
            .components(separatedBy: .newlines)
            .filter { $0.hasPrefix("#EXT-X-STREAM-INF") }
            .count
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
        case nonUTF8Manifest
        var description: String {
            switch self {
            case .timedOut: return "AVPlayerItem did not reach .readyToPlay within the timeout"
            case .failedWithoutError: return "AVPlayerItem.status went to .failed without an attached error"
            case .nonUTF8Manifest: return "manifest was not UTF-8"
            }
        }
    }
}
