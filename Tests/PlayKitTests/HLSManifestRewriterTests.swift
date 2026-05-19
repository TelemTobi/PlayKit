import Foundation
import Testing
@testable import PlayKit

/// Unit tests on the rewriter. The rewriter is the Wi-Fi-only branch of
/// `HLSAssetFactory` — cellular paths bypass it entirely — so these tests
/// exercise the wifi target heights the production policy ships with
/// (720 by default) plus a couple of edge-case targets to keep the
/// rewriter robust against future configuration knobs.
@Suite struct HLSManifestRewriterTests {
    /// Twitter portrait ladder shape — heights {404, 608, 912}. Every
    /// production sample we've seen has a similar shape.
    private static let twitterPortraitMaster = """
    #EXTM3U
    #EXT-X-VERSION:6
    #EXT-X-INDEPENDENT-SEGMENTS
    #EXT-X-MEDIA:NAME="Audio",TYPE=AUDIO,GROUP-ID="audio-32000",AUTOSELECT=YES,URI="/amplify_video/2052598697494822912/pl/mp4a/32000/L9XT-p2lcCA5G3qQ.m3u8"
    #EXT-X-MEDIA:NAME="Audio",TYPE=AUDIO,GROUP-ID="audio-64000",AUTOSELECT=YES,URI="/amplify_video/2052598697494822912/pl/mp4a/64000/_0vi17ybs5-we72k.m3u8"
    #EXT-X-MEDIA:NAME="Audio",TYPE=AUDIO,GROUP-ID="audio-128000",AUTOSELECT=YES,URI="/amplify_video/2052598697494822912/pl/mp4a/128000/Qaq3nlTQkwaUhVay.m3u8"

    #EXT-X-STREAM-INF:BANDWIDTH=402929,RESOLUTION=320x404,CODECS="mp4a.40.2,avc1.4D401E",AUDIO="audio-32000"
    /amplify_video/2052598697494822912/pl/avc1/320x404/a.m3u8
    #EXT-X-STREAM-INF:BANDWIDTH=703922,RESOLUTION=480x608,CODECS="mp4a.40.2,avc1.4D401F",AUDIO="audio-64000"
    /amplify_video/2052598697494822912/pl/avc1/480x608/b.m3u8
    #EXT-X-STREAM-INF:BANDWIDTH=1402792,RESOLUTION=720x912,CODECS="mp4a.40.2,avc1.640020",AUDIO="audio-128000"
    /amplify_video/2052598697494822912/pl/avc1/720x912/c.m3u8
    """

    private static let twitterLandscapeMaster = """
    #EXTM3U
    #EXT-X-VERSION:6
    #EXT-X-INDEPENDENT-SEGMENTS
    #EXT-X-MEDIA:NAME="Audio",TYPE=AUDIO,GROUP-ID="audio-32000",AUTOSELECT=YES,URI="/amplify_video/x/pl/mp4a/32000/a.m3u8"

    #EXT-X-STREAM-INF:BANDWIDTH=273034,RESOLUTION=480x270,CODECS="mp4a.40.2,avc1.4D401E",AUDIO="audio-32000"
    /amplify_video/x/pl/avc1/480x270/a.m3u8
    #EXT-X-STREAM-INF:BANDWIDTH=899897,RESOLUTION=640x360,CODECS="mp4a.40.2,avc1.4D401F",AUDIO="audio-32000"
    /amplify_video/x/pl/avc1/640x360/b.m3u8
    #EXT-X-STREAM-INF:BANDWIDTH=2447264,RESOLUTION=1280x720,CODECS="mp4a.40.2,avc1.640020",AUDIO="audio-32000"
    /amplify_video/x/pl/avc1/1280x720/c.m3u8
    #EXT-X-STREAM-INF:BANDWIDTH=6446457,RESOLUTION=1920x1080,CODECS="mp4a.40.2,avc1.640032",AUDIO="audio-32000"
    /amplify_video/x/pl/avc1/1920x1080/d.m3u8
    """

    private let baseURL = URL(string: "https://video.twimg.com/amplify_video/2052598697494822912/pl/master.m3u8")!

    // MARK: - Promotion + retention

    @Test func promotesSmallestVariantAtOrAbove720Target() throws {
        let rewritten = try #require(
            HLSManifestRewriter.rewrite(
                manifest: Self.twitterLandscapeMaster,
                baseURL: baseURL,
                targetHeight: 720
            )
        )
        let variantURIs = streamInfURIs(in: rewritten)
        // All four source variants must remain — ABR needs every rung.
        #expect(variantURIs.count == 4)
        // Lowest variant >= 720 is 720 itself; promoted to position 0.
        #expect(variantURIs.first?.contains("1280x720") == true)
    }

    /// Twitter portrait masters at the production wifi target (720): the
    /// lowest variant clearing the floor is 912p, and every rung below
    /// must still be present in the manifest so ABR can downgrade if the
    /// link weakens mid-playback.
    @Test func twitterPortraitWifiTargetKeepsAllVariants() throws {
        let rewritten = try #require(
            HLSManifestRewriter.rewrite(
                manifest: Self.twitterPortraitMaster,
                baseURL: baseURL,
                targetHeight: 720
            )
        )
        let variantURIs = streamInfURIs(in: rewritten)
        #expect(variantURIs.count == 3)
        #expect(variantURIs.first?.contains("720x912") == true)
        #expect(rewritten.contains("320x404"))
        #expect(rewritten.contains("480x608"))
    }

    /// The cellular floor (360p). On Twitter's standard landscape ladder
    /// the smallest variant clearing 360 is exactly 360, and every rung
    /// below (270p) must still be present so ABR can drop if the link
    /// actually struggles.
    @Test func promotesSmallestVariantAtOrAbove360Target() throws {
        let rewritten = try #require(
            HLSManifestRewriter.rewrite(
                manifest: Self.twitterLandscapeMaster,
                baseURL: baseURL,
                targetHeight: 360
            )
        )
        let variantURIs = streamInfURIs(in: rewritten)
        #expect(variantURIs.count == 4)
        #expect(variantURIs.first?.contains("640x360") == true)
        #expect(rewritten.contains("480x270"))
    }

    @Test func promotesHighestVariantWhenAllBelowTarget() throws {
        // Source where all variants are below 720p — the rewriter falls
        // back to the highest variant the source provides instead of
        // refusing to promote.
        let portraitMaster = """
        #EXTM3U
        #EXT-X-VERSION:6
        #EXT-X-INDEPENDENT-SEGMENTS
        #EXT-X-STREAM-INF:BANDWIDTH=407633,RESOLUTION=320x568,CODECS="avc1.4D401E"
        /amplify_video/123/pl/avc1/320x568/a.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=823354,RESOLUTION=480x852,CODECS="avc1.4D401F"
        /amplify_video/123/pl/avc1/480x852/b.m3u8
        """
        let rewritten = try #require(
            HLSManifestRewriter.rewrite(
                manifest: portraitMaster,
                baseURL: baseURL,
                targetHeight: 720
            )
        )
        let variantURIs = streamInfURIs(in: rewritten)
        #expect(variantURIs.count == 2)
        #expect(variantURIs.first?.contains("480x852") == true)
        // The smaller rung must still be present for ABR.
        #expect(rewritten.contains("320x568"))
    }

    @Test func nilTargetPreservesOriginalOrderAndAllVariants() throws {
        let rewritten = try #require(
            HLSManifestRewriter.rewrite(
                manifest: Self.twitterPortraitMaster,
                baseURL: baseURL,
                targetHeight: nil
            )
        )
        let variantURIs = streamInfURIs(in: rewritten)
        #expect(variantURIs.count == 3)
        // Source order: 404, 608, 912.
        #expect(variantURIs[0].contains("320x404"))
        #expect(variantURIs[1].contains("480x608"))
        #expect(variantURIs[2].contains("720x912"))
    }

    // MARK: - URL handling

    @Test func expandsRelativeURIsInExtXMedia() throws {
        let rewritten = try #require(
            HLSManifestRewriter.rewrite(
                manifest: Self.twitterPortraitMaster,
                baseURL: baseURL,
                targetHeight: nil
            )
        )
        // Audio URIs become absolute.
        #expect(rewritten.contains("URI=\"https://video.twimg.com/amplify_video/2052598697494822912/pl/mp4a/32000/L9XT-p2lcCA5G3qQ.m3u8\""))
        // Variant URIs become absolute.
        #expect(rewritten.contains("https://video.twimg.com/amplify_video/2052598697494822912/pl/avc1/"))
    }

    /// I-FRAME-STREAM-INF lines (used by AVPlayer for trick play / scrub
    /// preview) carry their URI as an attribute on the line itself. If we
    /// leave them relative, AVPlayer resolves them against the `pkhls://`
    /// loader URL and routes the fetch back through `HLSAssetLoaderDelegate`
    /// — which only knows how to serve the master and breaks everything
    /// else. Same hazard applies to SESSION-KEY and SESSION-DATA.
    @Test func expandsRelativeURIsOnIFrameStreamInf() throws {
        let master = """
        #EXTM3U
        #EXT-X-VERSION:6
        #EXT-X-STREAM-INF:BANDWIDTH=2227464,RESOLUTION=960x540,CODECS="avc1.640020,mp4a.40.2"
        v5/prog_index.m3u8
        #EXT-X-I-FRAME-STREAM-INF:BANDWIDTH=186522,RESOLUTION=1920x1080,CODECS="avc1.64002a",URI="v7/iframe_index.m3u8"
        #EXT-X-I-FRAME-STREAM-INF:BANDWIDTH=98136,RESOLUTION=960x540,CODECS="avc1.640020",URI="v5/iframe_index.m3u8"
        """
        let rewritten = try #require(
            HLSManifestRewriter.rewrite(
                manifest: master,
                baseURL: baseURL,
                targetHeight: nil
            )
        )
        #expect(rewritten.contains("URI=\"https://video.twimg.com/amplify_video/2052598697494822912/pl/v7/iframe_index.m3u8\""))
        #expect(rewritten.contains("URI=\"https://video.twimg.com/amplify_video/2052598697494822912/pl/v5/iframe_index.m3u8\""))
        // The relative form must be gone entirely — no straggler that
        // would resolve against `pkhls://`.
        #expect(rewritten.contains("URI=\"v7/iframe_index.m3u8\"") == false)
        #expect(rewritten.contains("URI=\"v5/iframe_index.m3u8\"") == false)
    }

    @Test func returnsNilForNonMultivariantPlaylist() {
        let mediaPlaylist = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-TARGETDURATION:6
        #EXTINF:6.0,
        segment0.ts
        #EXT-X-ENDLIST
        """
        let rewritten = HLSManifestRewriter.rewrite(
            manifest: mediaPlaylist,
            baseURL: baseURL,
            targetHeight: 720
        )
        #expect(rewritten == nil)
    }

    // MARK: - Helpers

    private func streamInfURIs(in manifest: String) -> [String] {
        var result: [String] = []
        var pending = false
        for raw in manifest.components(separatedBy: .newlines) {
            if raw.hasPrefix("#EXT-X-STREAM-INF") {
                pending = true
                continue
            }
            if pending {
                let trimmed = raw.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    result.append(trimmed)
                    pending = false
                }
            }
        }
        return result
    }
}
