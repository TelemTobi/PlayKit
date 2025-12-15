import Foundation
import Combine
import Testing
@testable import PlayKit

@Suite struct PlaylistControllerTests {
    @Test func clampsInvalidInitialIndexToZero() {
        let controller = PlaylistController(
            items: [.custom(duration: 1)],
            initialIndex: 5
        )
        #expect(controller.currentIndex == 0)
    }

    @Test func allowsEmptyItemsWithNonZeroInitialIndex() {
        let controller = PlaylistController(
            items: [],
            initialIndex: 3
        )
        #expect(controller.currentIndex == 3)
        #expect(controller.items.isEmpty)
    }

    @Test func maintainsValidInitialIndex() {
        let controller = PlaylistController(
            items: [.custom(duration: 1), .custom(duration: 2)],
            initialIndex: 1
        )
        #expect(controller.currentIndex == 1)
    }

    @Test func setItemsResetsIndexWhenOutOfBounds() {
        let controller = PlaylistController(
            items: [.custom(duration: 1), .custom(duration: 2)],
            initialIndex: 1
        )

        controller.setItems([.custom(duration: 3)])
        #expect(controller.currentIndex == 0)
        #expect(controller.items.count == 1)
    }

    @Test func setItemsKeepsIndexWhenStillValid() {
        let controller = PlaylistController(
            items: [.custom(duration: 1)],
            initialIndex: 0
        )

        controller.setItems([.custom(duration: 2), .custom(duration: 3)])
        #expect(controller.currentIndex == 0)
        #expect(controller.items.count == 2)
    }

    @Test func advanceClampsAtEnd() {
        let controller = PlaylistController(
            items: [.custom(duration: 1)],
            initialIndex: 0
        )

        controller.advanceToNext()
        #expect(controller.currentIndex == 0)
    }

    @Test func moveBackClampsAtStart() {
        let controller = PlaylistController(
            items: [.custom(duration: 1), .custom(duration: 2)],
            initialIndex: 0
        )

        controller.moveToPrevious()
        #expect(controller.currentIndex == 0)
    }

    @Test func setCurrentIndexIgnoresInvalidValues() {
        let controller = PlaylistController(
            items: [.custom(duration: 1), .custom(duration: 2)],
            initialIndex: 0
        )

        controller.setCurrentIndex(5)
        #expect(controller.currentIndex == 0)
    }

    @Test func setCurrentIndexUpdatesWhenValidAndDifferent() {
        let controller = PlaylistController(
            items: [.custom(duration: 1), .custom(duration: 2)],
            initialIndex: 0
        )

        controller.setCurrentIndex(1)
        #expect(controller.currentIndex == 1)
    }

    @Test func setRateTurnsOnPlaybackWhenPositive() {
        let controller = PlaylistController(
            items: [.custom(duration: 1)],
            initialIndex: 0
        )

        controller.setRate(1.5)
        #expect(controller.rate == 1.5)
        #expect(controller.isPlaying == true)
    }

    @Test func setFocusUpdatesFocusFlag() {
        let controller = PlaylistController(
            items: [.custom(duration: 1)],
            initialIndex: 0
        )

        controller.setFocus(true)
        #expect(controller.isFocused == true)

        controller.setFocus(false)
        #expect(controller.isFocused == false)
    }

    @Test func playAndPauseTogglePlayback() {
        let controller = PlaylistController(
            items: [.custom(duration: 1)],
            initialIndex: 0
        )

        controller.play()
        #expect(controller.isPlaying == true)

        controller.pause()
        #expect(controller.isPlaying == false)
    }

    @Test func setProgressPublishesValues() {
        let controller = PlaylistController(
            items: [.custom(duration: 1)],
            initialIndex: 0
        )

        var received: [TimeInterval] = []
        let cancellable = controller.progressPublisher
            .sink { received.append($0) }

        controller.setProgress(2.0)
        #expect(received == [2.0])

        cancellable.cancel()
    }

    @Test func rangedItemsReflectBufferWindow() {
        let controller = PlaylistController(
            items: [.custom(duration: 1), .custom(duration: 2), .custom(duration: 3)],
            initialIndex: 1,
            backwardBuffer: 1,
            forwardBuffer: 1,
            isFocused: false
        )

        let ranged = controller.rangedItems
        #expect(ranged.count == 3)
        #expect(ranged[0] == .custom(duration: 1))
        #expect(ranged[1] == .custom(duration: 2))
        #expect(ranged[2] == .custom(duration: 3))
        #expect(controller.currentItem == .custom(duration: 2))
    }
}

