import Foundation
import Testing
@testable import PlayKit

/// Unit tests on the rewriter. The rewriter runs on both networks
/// `HLSAssetFactory` rewrites (Wi-Fi at a 720 floor, cellular at 360),
/// so these tests exercise both production floors plus a couple of
/// edge-case targets to keep the rewriter robust against future
/// configuration knobs. The `removeBelowTarget` cases cover the opt-in
/// hard-floor path that strips sub-floor variants.
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

    /// Portrait masters encode `RESOLUTION=WIDTHxHEIGHT` with the *long*
    /// edge as height, so the floor must be measured against the shorter
    /// side. This production ladder ({320x568, 480x852, 720x1280,
    /// 1080x1920}) has a 480-wide rung (480x852) whose height (852)
    /// exceeds 720 — flooring on raw height would promote it and start a
    /// visibly sub-720p stream. The 720 floor must land on 720x1280.
    @Test func portraitFloorMeasuresShorterSide() throws {
        let portraitMaster = """
        #EXTM3U
        #EXT-X-VERSION:6
        #EXT-X-INDEPENDENT-SEGMENTS
        #EXT-X-STREAM-INF:BANDWIDTH=705575,RESOLUTION=320x568,CODECS="avc1.4D401F"
        /amplify_video/x/pl/avc1/320x568/a.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=1066580,RESOLUTION=480x852,CODECS="avc1.4D401F"
        /amplify_video/x/pl/avc1/480x852/b.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=2430012,RESOLUTION=720x1280,CODECS="avc1.640020"
        /amplify_video/x/pl/avc1/720x1280/c.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=10503867,RESOLUTION=1080x1920,CODECS="avc1.640032"
        /amplify_video/x/pl/avc1/1080x1920/d.m3u8
        """
        // Reorder path: 720x1280 is promoted, full ladder retained.
        let reordered = try #require(
            HLSManifestRewriter.rewrite(manifest: portraitMaster, baseURL: baseURL, targetHeight: 720)
        )
        let reorderedURIs = streamInfURIs(in: reordered)
        #expect(reorderedURIs.count == 4)
        #expect(reorderedURIs.first?.contains("720x1280") == true)

        // Hard floor: 320x568 (320 wide) and 480x852 (480 wide) are below
        // the floor and must be stripped; 720x1280 leads.
        let hardFloored = try #require(
            HLSManifestRewriter.rewrite(manifest: portraitMaster, baseURL: baseURL, targetHeight: 720, removeBelowTarget: true)
        )
        let hardURIs = streamInfURIs(in: hardFloored)
        #expect(hardURIs.count == 2)
        #expect(hardURIs.first?.contains("720x1280") == true)
        #expect(hardFloored.contains("480x852") == false)
        #expect(hardFloored.contains("320x568") == false)
    }

    // MARK: - Hard floor (removeBelowTarget)

    /// With `removeBelowTarget` the sub-floor rungs are stripped: the
    /// landscape ladder {270, 360, 720, 1080} at a 720 floor keeps only
    /// {720, 1080}, with 720 leading so the initial pick lands on the
    /// floor and 1080 left for ABR headroom.
    @Test func hardFloorRemovesVariantsBelowTarget() throws {
        let rewritten = try #require(
            HLSManifestRewriter.rewrite(
                manifest: Self.twitterLandscapeMaster,
                baseURL: baseURL,
                targetHeight: 720,
                removeBelowTarget: true
            )
        )
        let variantURIs = streamInfURIs(in: rewritten)
        #expect(variantURIs.count == 2)
        #expect(variantURIs.first?.contains("1280x720") == true)
        #expect(variantURIs.last?.contains("1920x1080") == true)
        // Sub-floor rungs are gone entirely.
        #expect(rewritten.contains("480x270") == false)
        #expect(rewritten.contains("640x360") == false)
    }

    /// When no variant meets the floor, `removeBelowTarget` must not strip
    /// the ladder to nothing — it falls back to promote-highest and keeps
    /// every rung, exactly like the reorder path. Here every rung (480p,
    /// 568p) sits below the 720 floor.
    @Test func hardFloorKeepsLadderWhenNoVariantMeetsFloor() throws {
        let lowLadderMaster = """
        #EXTM3U
        #EXT-X-VERSION:6
        #EXT-X-INDEPENDENT-SEGMENTS
        #EXT-X-STREAM-INF:BANDWIDTH=407633,RESOLUTION=270x480,CODECS="avc1.4D401E"
        /amplify_video/123/pl/avc1/270x480/a.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=823354,RESOLUTION=320x568,CODECS="avc1.4D401F"
        /amplify_video/123/pl/avc1/320x568/b.m3u8
        """
        let rewritten = try #require(
            HLSManifestRewriter.rewrite(
                manifest: lowLadderMaster,
                baseURL: baseURL,
                targetHeight: 720,
                removeBelowTarget: true
            )
        )
        let variantURIs = streamInfURIs(in: rewritten)
        #expect(variantURIs.count == 2)
        #expect(variantURIs.first?.contains("320x568") == true)
        #expect(rewritten.contains("270x480"))
    }

    /// `removeBelowTarget` defaults to `false`, so the default call keeps
    /// the full ladder — guards against the hard floor leaking into the
    /// standard reorder path.
    @Test func removeBelowTargetDefaultsToReorderOnly() throws {
        let rewritten = try #require(
            HLSManifestRewriter.rewrite(
                manifest: Self.twitterLandscapeMaster,
                baseURL: baseURL,
                targetHeight: 720
            )
        )
        #expect(streamInfURIs(in: rewritten).count == 4)
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
