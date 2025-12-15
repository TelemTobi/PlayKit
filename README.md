# PlayKit

A lightweight, UIKit-powered playlist engine for SwiftUI and UIKit that delivers smooth video and image playback with prebuffering. PlayKit focuses on fast integration for experiences that Apple’s stock components don’t cover well—tap-through story carousels and vertical, feed-style reels—so you can ship polished media surfaces without building a player stack from scratch.

## Why PlayKit?
- Purpose-built for story/reels patterns (tap-through and vertical feed).
- Prebuffered players for low-latency transitions.
- SwiftUI-friendly via `PlaylistView` while keeping UIKit rendering performance.
- Simple overlay hooks for per-item UI.
- Image, video, custom, and error items supported out of the box.
- Notification hooks for analytics and observability.

## See It in Action
- 📺 Demo video: coming soon (shows both tap-through and vertical feed with overlays).
- 📱 Demo project: [PlayKit Demo](https://github.com/your-org/playkit-demo)

## Requirements
- iOS 15+
- Swift 5.9+

## Installation (Swift Package Manager)
Add to your `Package.swift`:

```swift
.package(url: "https://github.com/your-org/PlayKit.git", from: "1.0.0")
```

Then add the dependency to your target:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "PlayKit", package: "PlayKit")
    ]
)
```

## Getting Started

### 1) Choose a playlist type
PlayKit supports two presentation styles via `PlaylistType`, covering both stories and reels use cases with minimal setup:
- `.tapThrough`: stacked players where only the active item is visible; perfect for stories or paging flows. You own the gestures—wire your tap/drag handlers to update `PlaylistController` (e.g., `advanceToNext()`, `moveToPrevious()`, `setCurrentIndex(_:)`).
- `.verticalFeed`: a vertically scrolling feed (reels-style) where the most visible cell becomes the current item; scrolling and index changes are handled for you.

### 2) Create a controller and items
```swift
import PlayKit

let controller = PlaylistController(
    items: [
        .video(URL(string: "https://cdn.example.com/video1.mp4")!),
        .image(URL(string: "https://cdn.example.com/image1.jpg")!, duration: 8),
        .custom(duration: 5)
    ],
    initialIndex: 0,
    isFocused: true
)
```

### 3) SwiftUI – Tap-through example
```swift
import SwiftUI
import PlayKit

struct StoriesView: View {
    @StateObject private var controller = PlaylistController(
        items: yourItems,
        isFocused: true
    )

    var body: some View {
        PlaylistView(
            type: .tapThrough,
            controller: controller,
            gravity: .resizeAspectFill
        )
        .ignoresSafeArea()
    }
}
```

### 4) SwiftUI – Vertical feed example
```swift
struct FeedView: View {
    @StateObject private var controller = PlaylistController(
        items: yourItems,
        isFocused: true
    )

    var body: some View {
        PlaylistView(
            type: .verticalFeed,
            controller: controller,
            gravity: .resizeAspectFill
        )
        .ignoresSafeArea()
    }
}
```

### 5) UIKit integration
```swift
let controller = PlaylistController(items: yourItems, isFocused: true)
let playlistView = UIPlaylistView()
playlistView.initialize(type: .tapThrough, controller: controller)
playlistView.gravity = .resizeAspectFill
playlistView.frame = view.bounds
view.addSubview(playlistView)
```

## Overlays per item
Both playlist types support overlays so you can layer UI (e.g., buttons, captions) per item.

```swift
PlaylistView(
    type: .verticalFeed,
    controller: controller,
    gravity: .resizeAspectFill,
    overlayForItemAtIndex: { index in
        VStack {
            Spacer()
            Text("Item \(index + 1)")
                .foregroundStyle(.white)
                .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
)
```

## Playback control
All interaction goes through `PlaylistController`; use these entry points to drive playback and navigation:
- `setFocus(_:)`: Reflect app lifecycle or navigation focus; PlayKit pauses when unfocused.
- `play()` / `pause()` or `setRate(_:)`: Control playback and speed.
- `setCurrentIndex(_:)`, `advanceToNext()`, `moveToPrevious()`: Navigate items.
- `setProgress(_:)`: Seek within the current item.

## Notifications (analytics & observability)
- `PlayKit.videoRequestedNotification`
- `PlayKit.videoStartedNotification`
- `PlayKit.videoStalledNotification`

Each carries `PlayKit.NotificationPayload` with the item URL and timestamp.

## Contributing
Have feedback, a bug, or an idea? Open an issue or PR. Collaboration is welcome to keep PlayKit solid and evolving. 🎉

