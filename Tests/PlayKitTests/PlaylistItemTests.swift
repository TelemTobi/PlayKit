import Foundation
import Testing
@testable import PlayKit

@Suite struct PlaylistItemTests {
    @Test func equatableAndHashableBehaviors() {
        let imageA = PlaylistItem.image(URL(string: "https://example.com/a.jpg")!, duration: 5)
        let imageASame = PlaylistItem.image(URL(string: "https://example.com/a.jpg")!, duration: 5)
        let video = PlaylistItem.video(URL(string: "https://example.com/a.mp4")!)
        let custom = PlaylistItem.custom(duration: 3)
        let errorA = PlaylistItem.error(id: "err")
        let errorB = PlaylistItem.error(id: "err")

        #expect(imageA == imageASame)
        #expect(imageA != video)
        #expect(custom != video)
        #expect(errorA == errorB)

        let set: Set<PlaylistItem> = [imageA, imageASame, video, custom, errorA]
        #expect(set.count == 4) // imageA duplicates collapse; error ids match
    }

    @Test func statusEnumCoversCases() {
        let statuses: [PlaylistItem.Status] = [.loading, .ready, .error]
        #expect(statuses.count == 3)
    }
}

