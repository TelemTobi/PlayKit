import Foundation
import Testing
import AVFoundation
@testable import PlayKit

/// End-to-end checks that exercise the full HLS pipeline against real
/// public streams — `AVAssetResourceLoaderDelegate` callbacks, manifest
/// rewrite, AVPlayer parsing the rewritten manifest, and the AVPlayerItem
/// reaching `.readyToPlay`.
///
/// Plus deterministic checks that the factory routes Wi-Fi and cellular
/// traffic through the rewriter (with different floors) and routes
/// Low Data Mode / unknown traffic straight through to AVPlayer's
/// native pipeline. The factory branch is the single most consequential
/// decision in this module — an inversion here is what produced the
/// "stuck at 270p on cellular short clips" failure mode — so it gets
/// its own pinned tests.
@Suite struct HLSAssetFactoryIntegrationTests {
    /// Apple's reference HLS multivariant stream — long-lived and
    /// publicly documented; used in many WWDC samples.
    private let appleBipBop = URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8")!

    /// Real Twitter HLS samples shipped in production. Twitter rotates
    /// URLs over time, so a 4xx here is a signal to refresh the fixture
    /// rather than evidence of a regression.
    private let twitterSamples: [URL] = [
        URL(string: "https://video.twimg.com/amplify_video/2052598697494822912/pl/RlXt3Dc9rvJiaHsP.m3u8?tag=14")!,
        URL(string: "https://video.twimg.com/amplify_video/2052600700958380037/pl/8sv_B4I6g7I6ay4r.m3u8")!,
        URL(string: "https://video.twimg.com/amplify_video/2052602909603348486/pl/c4vgX97muaW78MBl.m3u8")!,
        URL(string: "https://video.twimg.com/amplify_video/2052603114822283268/pl/t73rEuDhtldPiGA6.m3u8")!,
        URL(string: "https://video.twimg.com/amplify_video/2052608087077359618/pl/ywHR2xUIRY2K-lFQ.m3u8")!,
        URL(string: "https://video.twimg.com/amplify_video/2052891591317110789/pl/kVvWMesbVImv0hUH.m3u8")!
    ]

    // MARK: - Branching invariants (no network)

    /// Wi-Fi / wired networks must run through the rewriter — that's how
    /// we promote a higher initial variant on Wi-Fi. The wrapped URL
    /// identifies the rewrite path: it carries the `pkhls` scheme so
    /// AVPlayer dispatches the master fetch to our resource loader.
    @Test func unconstrainedNetworkUsesRewritePath() {
        let item = HLSAssetFactory.makePlayerItem(
            url: twitterSamples[0],
            policy: .automatic,
            viewPixelSize: CGSize(width: 1290, height: 2796),
            networkClass: { .unconstrained }
        )
        let asset = item.asset as? AVURLAsset
        #expect(asset?.url.scheme == HLSAssetLoaderDelegate.scheme)
        #expect(item.startsOnFirstEligibleVariant == true)
    }

    /// Cellular runs through the rewriter too, with a lower floor
    /// (360p by default) so short-form clips don't pin to AVPlayer's
    /// lowest-variant cold start. The `pkhls` scheme on the asset's URL
    /// is the contract that says "resource-loader interception engaged."
    @Test func cellularUsesRewritePath() {
        let item = HLSAssetFactory.makePlayerItem(
            url: twitterSamples[0],
            policy: .automatic,
            viewPixelSize: CGSize(width: 1290, height: 2796),
            networkClass: { .cellular }
        )
        let asset = item.asset as? AVURLAsset
        #expect(asset?.url.scheme == HLSAssetLoaderDelegate.scheme)
        #expect(item.startsOnFirstEligibleVariant == true)
    }

    /// Opting out of cellular promotion (`cellularMinimumResolution = nil`)
    /// falls back to passthrough — the factory shouldn't spend a master
    /// fetch on a no-op rewrite.
    @Test func cellularWithNilFloorUsesPassthroughPath() {
        let policy = HLSQualityPolicy.custom(
            HLSQualityPolicy.Configuration(
                wifiMinimumResolution: 720,
                cellularMinimumResolution: nil
            )
        )
        let item = HLSAssetFactory.makePlayerItem(
            url: twitterSamples[0],
            policy: policy,
            viewPixelSize: nil,
            networkClass: { .cellular }
        )
        let asset = item.asset as? AVURLAsset
        #expect(asset?.url.scheme == "https")
        #expect(item.startsOnFirstEligibleVariant == false)
    }

    /// Low Data Mode and unknown classifications fall onto the
    /// passthrough path — Low Data Mode is the OS-level "save my bytes"
    /// signal we honor, and unknown means we don't have enough info to
    /// safely intervene.
    @Test func constrainedAndUnknownUsePassthroughPath() {
        for networkClass in [HLSNetworkClass.constrained, .unknown] {
            let item = HLSAssetFactory.makePlayerItem(
                url: twitterSamples[0],
                policy: .automatic,
                viewPixelSize: nil,
                networkClass: { networkClass }
            )
            let asset = item.asset as? AVURLAsset
            #expect(asset?.url.scheme == "https", "expected passthrough for \(networkClass)")
            #expect(item.startsOnFirstEligibleVariant == false)
        }
    }

    /// `.unrestricted` opts the entire asset out of PlayKit's HLS
    /// handling on every network class — useful when the caller wants
    /// AVPlayer's defaults end to end.
    @Test func unrestrictedPolicyAlwaysUsesPassthroughPath() {
        for networkClass in [HLSNetworkClass.unconstrained, .cellular, .constrained] {
            let item = HLSAssetFactory.makePlayerItem(
                url: twitterSamples[0],
                policy: .unrestricted,
                viewPixelSize: nil,
                networkClass: { networkClass }
            )
            let asset = item.asset as? AVURLAsset
            #expect(asset?.url.scheme == "https", "expected passthrough for \(networkClass) under .unrestricted")
        }
    }

    @Test func nonHLSURLsAreNeverRewritten() {
        let mp4 = URL(string: "https://example.com/clip.mp4")!
        let item = HLSAssetFactory.makePlayerItem(
            url: mp4,
            policy: .automatic,
            viewPixelSize: nil,
            networkClass: { .unconstrained }
        )
        let asset = item.asset as? AVURLAsset
        #expect(asset?.url.scheme == "https")
    }

    // MARK: - End-to-end reachability (live network)

    @Test func unconstrainedReachesReadyToPlayThroughRewriter() async throws {
        let item = HLSAssetFactory.makePlayerItem(
            url: appleBipBop,
            policy: .automatic,
            viewPixelSize: CGSize(width: 2400, height: 2400),
            networkClass: { .unconstrained }
        )
        let player = AVPlayer(playerItem: item)
        defer { player.replaceCurrentItem(with: nil) }
        try await awaitReadyToPlay(item, timeout: 30)
    }

    @Test func cellularReachesReadyToPlayThroughRewriter() async throws {
        let item = HLSAssetFactory.makePlayerItem(
            url: appleBipBop,
            policy: .automatic,
            viewPixelSize: CGSize(width: 2400, height: 2400),
            networkClass: { .cellular }
        )
        let player = AVPlayer(playerItem: item)
        defer { player.replaceCurrentItem(with: nil) }
        try await awaitReadyToPlay(item, timeout: 30)
    }

    /// Sweep the production Twitter fleet through both rewrite branches.
    /// The live-CDN assertion is just `.readyToPlay`; deeper invariants
    /// (variant counts, ordering) belong in the rewriter unit tests.
    @Test func sweepProductionSamplesAcrossBothBranches() async throws {
        for url in twitterSamples {
            for networkClass in [HLSNetworkClass.unconstrained, .cellular] {
                let item = HLSAssetFactory.makePlayerItem(
                    url: url,
                    policy: .automatic,
                    viewPixelSize: CGSize(width: 2400, height: 2400),
                    networkClass: { networkClass }
                )
                let player = AVPlayer(playerItem: item)
                do {
                    try await awaitReadyToPlay(item, timeout: 30)
                } catch {
                    Issue.record("\(url.lastPathComponent) failed under \(networkClass): \(error)")
                }
                player.replaceCurrentItem(with: nil)
            }
        }
    }

    /// Fetches each live master and asserts the rewriter — at the
    /// production wifi target — preserves every variant in the source.
    /// The original cellular bug was *dropping* low rungs, which is what
    /// this invariant exists to catch in the Wi-Fi branch as well.
    @Test func wifiRewriterPreservesEveryVariant() async throws {
        let baseConfig = HLSQualityPolicy.Configuration()
        let target = baseConfig.wifiMinimumResolution

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
            let rewritten = HLSManifestRewriter.rewrite(
                manifest: manifest,
                baseURL: url,
                targetHeight: target
            ) ?? manifest
            #expect(
                countStreamInf(in: rewritten) == sourceCount,
                "\(url.lastPathComponent) wifi rewrite emitted \(countStreamInf(in: rewritten))/\(sourceCount) variants — ABR cannot adapt with rungs missing"
            )
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
