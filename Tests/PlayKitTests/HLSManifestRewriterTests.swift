import Foundation
import Testing
@testable import PlayKit

@Suite struct HLSManifestRewriterTests {
    private let twitterMaster = """
        #EXTM3U
        #EXT-X-VERSION:6
        #EXT-X-INDEPENDENT-SEGMENTS
        #EXT-X-MEDIA:NAME="Audio",TYPE=AUDIO,GROUP-ID="audio-32000",AUTOSELECT=YES,URI="/amplify_video/123/pl/mp4a/32000/a.m3u8"
        #EXT-X-MEDIA:NAME="Audio",TYPE=AUDIO,GROUP-ID="audio-128000",AUTOSELECT=YES,URI="/amplify_video/123/pl/mp4a/128000/c.m3u8"

        #EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=200359,BANDWIDTH=273034,RESOLUTION=480x270,CODECS="mp4a.40.2,avc1.4D401E",AUDIO="audio-32000"
        /amplify_video/123/pl/avc1/480x270/v.m3u8
        #EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=4084473,BANDWIDTH=6446457,RESOLUTION=1920x1080,CODECS="mp4a.40.2,avc1.640032",AUDIO="audio-128000"
        /amplify_video/123/pl/avc1/1920x1080/v.m3u8
        #EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=1854959,BANDWIDTH=2447264,RESOLUTION=1280x720,CODECS="mp4a.40.2,avc1.640020",AUDIO="audio-128000"
        /amplify_video/123/pl/avc1/1280x720/v.m3u8
        """

    private let twitterBaseURL = URL(string: "https://video.twimg.com/amplify_video/123/pl/master.m3u8")!

    @Test func reordersVariantsByBandwidthDescending() {
        let rewritten = HLSManifestRewriter.rewriteMultivariantPlaylist(twitterMaster, baseURL: twitterBaseURL)
        let lines = rewritten.components(separatedBy: "\n")
        let streamInfIndices = lines.enumerated()
            .compactMap { $0.element.hasPrefix("#EXT-X-STREAM-INF") ? $0.offset : nil }

        #expect(streamInfIndices.count == 3)

        // First STREAM-INF block should now be 6446457 bps (1080p), then 2447264 bps (720p),
        // then 273034 bps (480p).
        #expect(lines[streamInfIndices[0]].contains("BANDWIDTH=6446457"))
        #expect(lines[streamInfIndices[1]].contains("BANDWIDTH=2447264"))
        #expect(lines[streamInfIndices[2]].contains("BANDWIDTH=273034"))
    }

    @Test func absolutizesRelativeVariantURIs() {
        let rewritten = HLSManifestRewriter.rewriteMultivariantPlaylist(twitterMaster, baseURL: twitterBaseURL)
        // No naked relative URIs should remain.
        #expect(!rewritten.contains("\n/amplify_video/123/pl/avc1/"))
        #expect(rewritten.contains("https://video.twimg.com/amplify_video/123/pl/avc1/1920x1080/v.m3u8"))
        #expect(rewritten.contains("https://video.twimg.com/amplify_video/123/pl/avc1/1280x720/v.m3u8"))
    }

    @Test func absolutizesURIAttributesOnAudioRenditions() {
        let rewritten = HLSManifestRewriter.rewriteMultivariantPlaylist(twitterMaster, baseURL: twitterBaseURL)
        #expect(rewritten.contains("URI=\"https://video.twimg.com/amplify_video/123/pl/mp4a/32000/a.m3u8\""))
        #expect(rewritten.contains("URI=\"https://video.twimg.com/amplify_video/123/pl/mp4a/128000/c.m3u8\""))
    }

    @Test func preservesNonVariantLinesAndPlaylistHeader() {
        let rewritten = HLSManifestRewriter.rewriteMultivariantPlaylist(twitterMaster, baseURL: twitterBaseURL)
        let lines = rewritten.components(separatedBy: "\n")
        #expect(lines.first == "#EXTM3U")
        #expect(lines.contains("#EXT-X-VERSION:6"))
        #expect(lines.contains("#EXT-X-INDEPENDENT-SEGMENTS"))
    }

    @Test func leavesAlreadyHighFirstPlaylistsValid() {
        let highFirst = """
            #EXTM3U
            #EXT-X-VERSION:3
            #EXT-X-STREAM-INF:BANDWIDTH=2145080,RESOLUTION=1280x720
            720p.m3u8
            #EXT-X-STREAM-INF:BANDWIDTH=541816,RESOLUTION=400x226
            225p.m3u8
            """
        let baseURL = URL(string: "https://example.com/video/master.m3u8")!
        let rewritten = HLSManifestRewriter.rewriteMultivariantPlaylist(highFirst, baseURL: baseURL)
        let lines = rewritten.components(separatedBy: "\n")
        let streamInfIndices = lines.enumerated()
            .compactMap { $0.element.hasPrefix("#EXT-X-STREAM-INF") ? $0.offset : nil }
        #expect(lines[streamInfIndices[0]].contains("BANDWIDTH=2145080"))
        #expect(lines[streamInfIndices[1]].contains("BANDWIDTH=541816"))
        #expect(rewritten.contains("https://example.com/video/720p.m3u8"))
        #expect(rewritten.contains("https://example.com/video/225p.m3u8"))
    }
}
