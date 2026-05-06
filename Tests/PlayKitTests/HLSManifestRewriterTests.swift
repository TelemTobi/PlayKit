import Foundation
import Testing
@testable import PlayKit

@Suite struct HLSManifestRewriterTests {
    private static let twitterMaster = """
    #EXTM3U
    #EXT-X-VERSION:6
    #EXT-X-INDEPENDENT-SEGMENTS
    #EXT-X-MEDIA:NAME="Audio",TYPE=AUDIO,GROUP-ID="audio-32000",AUTOSELECT=YES,URI="/amplify_video/2050054622253920256/pl/mp4a/32000/9GY5AB5e1zRcSzDu.m3u8"
    #EXT-X-MEDIA:NAME="Audio",TYPE=AUDIO,GROUP-ID="audio-64000",AUTOSELECT=YES,URI="/amplify_video/2050054622253920256/pl/mp4a/64000/RlOl1DpQNje5DNYg.m3u8"
    #EXT-X-MEDIA:NAME="Audio",TYPE=AUDIO,GROUP-ID="audio-128000",AUTOSELECT=YES,URI="/amplify_video/2050054622253920256/pl/mp4a/128000/8ZEJuxJCOUlEZ6KH.m3u8"

    #EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=200359,BANDWIDTH=273034,RESOLUTION=480x270,CODECS="mp4a.40.2,avc1.4D401E",AUDIO="audio-32000"
    /amplify_video/2050054622253920256/pl/avc1/480x270/THhOP1n7e_7q0mue.m3u8
    #EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=643748,BANDWIDTH=899897,RESOLUTION=640x360,CODECS="mp4a.40.2,avc1.4D401F",AUDIO="audio-64000"
    /amplify_video/2050054622253920256/pl/avc1/640x360/LVJ2NYhqiCLq3T2i.m3u8
    #EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=1854959,BANDWIDTH=2447264,RESOLUTION=1280x720,CODECS="mp4a.40.2,avc1.640020",AUDIO="audio-128000"
    /amplify_video/2050054622253920256/pl/avc1/1280x720/xXi3jcx_QuTf2P0U.m3u8
    #EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=4084473,BANDWIDTH=6446457,RESOLUTION=1920x1080,CODECS="mp4a.40.2,avc1.640032",AUDIO="audio-128000"
    /amplify_video/2050054622253920256/pl/avc1/1920x1080/BzQJp9pqIcvzhnU-.m3u8
    """

    private let baseURL = URL(string: "https://video.twimg.com/amplify_video/2050054622253920256/pl/-WxByTLfMh2P8VZQ.m3u8?tag=27")!

    @Test func wifiFloorAndHighestFirstOrdering() throws {
        let rewritten = try #require(
            HLSManifestRewriter.rewrite(
                manifest: Self.twitterMaster,
                baseURL: baseURL,
                minimumHeight: 720,
                maximumHeight: nil,
                ordering: .highestFirst
            )
        )
        let variantURIs = streamInfURIs(in: rewritten)
        #expect(variantURIs.count == 2)
        #expect(variantURIs.first?.contains("1920x1080") == true)
        #expect(variantURIs.last?.contains("1280x720") == true)
        // Variants below floor are dropped.
        #expect(!rewritten.contains("480x270"))
        #expect(!rewritten.contains("640x360"))
    }

    @Test func cellularFloorAndLowestFirstOrdering() throws {
        let rewritten = try #require(
            HLSManifestRewriter.rewrite(
                manifest: Self.twitterMaster,
                baseURL: baseURL,
                minimumHeight: 480,
                maximumHeight: nil,
                ordering: .lowestFirst
            )
        )
        let variantURIs = streamInfURIs(in: rewritten)
        // 480x270 dropped (270 < 480), but 640x360 has height 360 which is < 480 — also dropped.
        // Kept: 720, 1080.
        #expect(variantURIs.count == 2)
        #expect(variantURIs.first?.contains("1280x720") == true)
        #expect(variantURIs.last?.contains("1920x1080") == true)
    }

    @Test func slowCellularFloorAt360() throws {
        let rewritten = try #require(
            HLSManifestRewriter.rewrite(
                manifest: Self.twitterMaster,
                baseURL: baseURL,
                minimumHeight: 360,
                maximumHeight: nil,
                ordering: .lowestFirst
            )
        )
        let variantURIs = streamInfURIs(in: rewritten)
        #expect(variantURIs.count == 3)
        #expect(variantURIs.first?.contains("640x360") == true)
        #expect(variantURIs.last?.contains("1920x1080") == true)
        #expect(!rewritten.contains("480x270"))
    }

    @Test func keepsHighestWhenAllVariantsBelowFloor() throws {
        // Source where all variants are below 720p
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
                minimumHeight: 720,
                maximumHeight: nil,
                ordering: .highestFirst
            )
        )
        let variantURIs = streamInfURIs(in: rewritten)
        #expect(variantURIs.count == 1)
        #expect(variantURIs.first?.contains("480x852") == true)
    }

    @Test func capsResolutionToCeiling() throws {
        let rewritten = try #require(
            HLSManifestRewriter.rewrite(
                manifest: Self.twitterMaster,
                baseURL: baseURL,
                minimumHeight: 480,
                maximumHeight: 720,
                ordering: .highestFirst
            )
        )
        let variantURIs = streamInfURIs(in: rewritten)
        // 270 dropped (cap), 360 dropped (cap excludes? no cap is 720 so 360 ≤ 720 fits cap)
        // Then floor 480: keeps only those ≥ 480. 360 dropped, 720 kept.
        #expect(variantURIs.count == 1)
        #expect(variantURIs.first?.contains("1280x720") == true)
    }

    @Test func expandsRelativeURIsInExtXMedia() throws {
        let rewritten = try #require(
            HLSManifestRewriter.rewrite(
                manifest: Self.twitterMaster,
                baseURL: baseURL,
                minimumHeight: nil,
                maximumHeight: nil,
                ordering: .lowestFirst
            )
        )
        // Audio URIs must become absolute https URLs.
        #expect(rewritten.contains("URI=\"https://video.twimg.com/amplify_video/2050054622253920256/pl/mp4a/32000/9GY5AB5e1zRcSzDu.m3u8\""))
        // Variant URIs must become absolute too.
        #expect(rewritten.contains("https://video.twimg.com/amplify_video/2050054622253920256/pl/avc1/"))
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
            minimumHeight: 720,
            maximumHeight: nil,
            ordering: .highestFirst
        )
        #expect(rewritten == nil)
    }

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
