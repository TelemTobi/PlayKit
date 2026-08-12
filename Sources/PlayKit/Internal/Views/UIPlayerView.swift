//
//  UIPlayerView.swift
//  PlayKit
//
//  Created by Telem Tobi on 06/11/2025.
//

import Combine
import UIKit
import AVKit

final class UIPlayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    private var player: AVPlayer!
    private let errorDuration: TimeInterval = 5
    internal var rate: Float = 1
    internal var qualityPolicy: HLSQualityPolicy = .automatic

    /// Telemetry label of the surface this view belongs to, forwarded on every
    /// notification so consumers can segment by where playback happened.
    internal var surface: String?

    private(set) var item: PlaylistItem?
    private(set) var status = CurrentValueSubject<PlaylistItem.Status, Never>(.ready)
    private(set) var reachedEnd = PassthroughSubject<Void, Never>()

    private(set) var durationInSeconds: TimeInterval = .zero
    private(set) var progressInSeconds = CurrentValueSubject<TimeInterval, Never>(.zero)
    private(set) var hasCaptions: Bool = false

    private var statusSubscription: AnyCancellable?
    private var reachedEndSubscription: AnyCancellable?
    private var readyObserver: NSKeyValueObservation?
    private var timeObserverToken: Any?
    private var timeControlStatusSubscription: AnyCancellable?
    private var presentationSizeSubscription: AnyCancellable?

    /// Identifies the current video's lifecycle across every notification.
    /// Regenerated on each `prepare`, so re-preparing the same URL is reported
    /// as a distinct playback.
    private var playbackId = UUID().uuidString

    /// `true` between preparing a video item and reporting its teardown.
    /// Guards against reporting a finish twice, or reporting one for an item
    /// that was never a video.
    private var isPlaybackReportable = false
    private var hasStartedPlaying = false
    private var hasReachedEnd = false
    private var hasFailed = false

    private var imageLoadingTask: Task<Void, Never>?
    private var timerSubscription: AnyCancellable?
    
    private let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        return imageView
    }()
    
    convenience init(player: AVPlayer, qualityPolicy: HLSQualityPolicy = .automatic) {
        self.init(frame: .zero)
        self.player = player
        self.player.appliesMediaSelectionCriteriaAutomatically = false
        self.qualityPolicy = qualityPolicy

        playerLayer.player = player
        playerLayer.backgroundColor = UIColor.clear.cgColor
        
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    func prepare(item: PlaylistItem?) {
        guard item != self.item else { return }
        
        cancel()
        self.item = item
        self.status.value = .loading
        self.hasCaptions = false
        
        guard let item else { return }
        
        switch item {
        case let .image(_, url, duration, _):
            durationInSeconds = duration
            progressInSeconds.value = .zero
            loadImage(from: url)
            
        case let .video(_, url, _):
            let prepared = HLSAssetFactory.prepare(
                url: url,
                policy: qualityPolicy,
                viewPixelSize: currentRenderPixelSize()
            )
            player.replaceCurrentItem(with: prepared.item)
            player.automaticallyWaitsToMinimizeStalling = true

            playbackId = UUID().uuidString
            isPlaybackReportable = true

            NotificationCenter.default.post(
                name: PlayKit.videoPrepareStartedNotification,
                object: PlayKit.NotificationPayload(
                    url: url,
                    playbackId: playbackId,
                    surface: surface,
                    context: prepared.context
                )
            )

            registerStatusSubscription()
            registerTimeSubscription()
            registerReachedEndSubscription()
            registerTimeControlStatusSubscription()
            registerPresentationSizeSubscription()

        case let .custom(_, duration, _):
            durationInSeconds = duration
            progressInSeconds.value = .zero
            status.value = .ready
            
        case .error:
            durationInSeconds = errorDuration
            progressInSeconds.value = .zero
            status.value = .error
        }
    }
    
    func playWhenReady() {
        guard let item else { return }
        
        switch item {
        case let .image(_, _, duration, _), let .custom(_, duration, _):
            runNonVideoTimer(for: duration)
            
        case let .video(_, url, _):
            guard player.rate.isZero else { return }
            
            NotificationCenter.default.post(
                name: PlayKit.videoRequestedNotification,
                object: PlayKit.NotificationPayload(
                    url: url,
                    playbackId: playbackId,
                    surface: surface
                )
            )
            
            if playerLayer.isReadyForDisplay {
                player.play()
                player.rate = rate
                return
                
            } else if status.value == .error {
                runNonVideoTimer(for: errorDuration)
                return
            }
            
            readyObserver = playerLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] layer, _ in
                if layer.isReadyForDisplay {
                    Task { @MainActor [weak self] in
                        guard self?.readyObserver != nil else { return }
                        
                        self?.readyObserver = nil
                        self?.player.play()
                        self?.player.rate = self?.rate ?? 1
                    }
                }
            }
            
        case .error:
            runNonVideoTimer(for: errorDuration)
        }
    }
    
    func pause() {
        player.pause()
        readyObserver = nil
        timerSubscription?.cancel()
        rate = 1
    }
    
    func seekToBeginning() {
        player.seek(to: .zero)
        progressInSeconds.value = .zero
    }

    func restart() {
        guard let item else { return }

        switch item {
        case .image, .custom, .error:
            seekToBeginning()
            playWhenReady()

        case .video:
            // PlaylistItem is not Sendable; the value is only read on the main actor.
            nonisolated(unsafe) let item = item
            player.seek(to: .zero) { [weak self] finished in
                guard finished else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.item == item else { return }
                    progressInSeconds.value = .zero
                    player.play()
                    player.rate = rate
                }
            }
        }
    }
    
    func cancel() {
        // Report before releasing the item — its access and error logs go with
        // it, and they're the only record of what actually happened.
        reportPlaybackFinishedIfNeeded()

        item = nil
        player.cancelPendingPrerolls()
        player.replaceCurrentItem(with: nil)
        readyObserver = nil
        statusSubscription?.cancel()
        presentationSizeSubscription?.cancel()
        imageView.image = nil
        progressInSeconds.value = .zero
        durationInSeconds = .zero
        timerSubscription?.cancel()
        hasCaptions = false
        hasStartedPlaying = false
        hasReachedEnd = false
        hasFailed = false
    }
    
    func setGravity(_ gravity: AVLayerVideoGravity) {
        playerLayer.videoGravity = gravity
        
        imageView.contentMode = switch gravity {
        case .resize: .scaleToFill
        case .resizeAspect: .scaleAspectFit
        case .resizeAspectFill: .scaleAspectFill
        default: .scaleAspectFit
        }
    }
    
    func setProgress(_ newValue: TimeInterval) {
        switch item {
        case .image, .custom, .error:
            progressInSeconds.value = newValue
        
        case .video:
            Task { [weak self] in
                let newTime = CMTime(seconds: newValue, preferredTimescale: 600)
                _ = await self?.player.seek(to: newTime, toleranceBefore: .zero, toleranceAfter: .zero)
            }
        
        case .none:
            break
        }
    }
    
    func setRate(_ rate: Float) {
        self.rate = rate
        player.rate = rate
    }
    
    /// The render surface's pixel size used to cap HLS variant resolution.
    ///
    /// Returns a *square* whose side is the long edge of the view (or the
    /// screen, when the view isn't laid out yet) times the screen scale.
    /// `AVPlayerItem.preferredMaximumResolution` is a per-axis constraint,
    /// so a literal portrait-shaped cap rejects every landscape variant —
    /// using the long edge on both axes accepts variants whose long edge
    /// fits while still excluding genuinely oversized ones.
    private func currentRenderPixelSize() -> CGSize {
        let scale = window?.screen.scale ?? UIScreen.main.scale
        let pointSize: CGSize
        if bounds.width > 0, bounds.height > 0 {
            pointSize = bounds.size
        } else {
            pointSize = window?.screen.bounds.size ?? UIScreen.main.bounds.size
        }
        let longEdge = max(pointSize.width, pointSize.height) * scale
        return CGSize(width: longEdge, height: longEdge)
    }

    func setMuted(_ newValue: Bool) {
        player.isMuted = newValue
    }

    func setShowsBuiltInClosedCaptions(_ newValue: Bool) {
        guard let playerItem = player.currentItem else { return }

        Task { [weak self] in
            guard let legibleGroup = try? await playerItem.asset.loadMediaSelectionGroup(for: .legible),
                  let captionsOption = legibleGroup.captionsOption,
                  self?.player.currentItem == playerItem
            else { return }

            self?.player.currentItem?.select(newValue ? captionsOption : nil, in: legibleGroup)
        }
    }
}

extension UIPlayerView {
    private func registerStatusSubscription() {
        statusSubscription?.cancel()
        statusSubscription = player.publisher(for: \.currentItem?.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                switch status {
                case .readyToPlay:
                    let duration = self?.player.currentItem?.duration.seconds ?? .zero
                    self?.durationInSeconds = (duration.isNaN || duration.isInfinite) ? .zero : duration

                    self?.loadCaptionAvailability()

                    self?.status.value = .ready
                    self?.reportVideoEvent(PlayKit.videoReadyNotification)

                case .failed:
                    self?.status.value = .error
                    self?.durationInSeconds = self?.errorDuration ?? .zero
                    self?.hasFailed = true

                    if case let .video(_, url, _) = self?.item, let self {
                        NotificationCenter.default.post(
                            name: PlayKit.videoErrorNotification,
                            object: PlayKit.NotificationPayload(
                                url: url,
                                playbackId: playbackId,
                                surface: surface,
                                error: player.currentItem?.error
                            )
                        )
                    }

                default:
                    self?.status.value = .loading
                }
            }
    }
    
    private func loadCaptionAvailability() {
        guard let currentItem = player.currentItem else { return }

        Task { [weak self] in
            guard let legibleGroup = try? await currentItem.asset.loadMediaSelectionGroup(for: .legible),
                  self?.player.currentItem == currentItem
            else { return }

            self?.hasCaptions = legibleGroup.hasSelectableCaptions
        }
    }

    private func registerTimeSubscription() {
        if let timeObserverToken {
            player.removeTimeObserver(timeObserverToken)
        }
        
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .global()) { [weak self] time in
            Task { @MainActor [weak self] in
                self?.progressInSeconds.value = time.seconds
            }
        }
    }
    
    private func registerReachedEndSubscription() {
        reachedEndSubscription?.cancel()
        
        reachedEndSubscription = NotificationCenter.default
            .publisher(for: AVPlayerItem.didPlayToEndTimeNotification, object: player.currentItem)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.hasReachedEnd = true
                self?.reachedEnd.send()
            }
    }

    /// Reports each resolution `AVPlayer` settles on — the initial variant pick
    /// and every ABR switch. `presentationSize` is the only observable that
    /// reflects the variant actually being decoded, as opposed to the one the
    /// manifest suggested.
    private func registerPresentationSizeSubscription() {
        presentationSizeSubscription?.cancel()

        presentationSizeSubscription = player.publisher(for: \.currentItem?.presentationSize)
            .compactMap { $0 }
            .filter { $0 != .zero }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] presentationSize in
                guard let self, isPlaybackReportable,
                      case let .video(_, url, _) = item else { return }

                let indicatedBitrate = player.currentItem?
                    .accessLog()?
                    .events
                    .last
                    .flatMap { $0.indicatedBitrate > 0 ? $0.indicatedBitrate : nil }

                NotificationCenter.default.post(
                    name: PlayKit.videoVariantChangedNotification,
                    object: PlayKit.NotificationPayload(
                        url: url,
                        playbackId: playbackId,
                        surface: surface,
                        variant: PlayKit.PlaybackVariant(
                            presentationSize: presentationSize,
                            indicatedBitrate: indicatedBitrate
                        )
                    )
                )
            }
    }

    /// Posts a lifecycle notification carrying only this playback's identity.
    private func reportVideoEvent(_ name: Notification.Name) {
        guard isPlaybackReportable, case let .video(_, url, _) = item else { return }

        NotificationCenter.default.post(
            name: name,
            object: PlayKit.NotificationPayload(
                url: url,
                playbackId: playbackId,
                surface: surface
            )
        )
    }

    /// Posts the teardown notification with the item's aggregated logs, once
    /// per playback.
    private func reportPlaybackFinishedIfNeeded() {
        guard isPlaybackReportable, case let .video(_, url, _) = item else { return }
        isPlaybackReportable = false

        let outcome: PlayKit.NotificationPayload.Outcome = if hasFailed {
            .failed
        } else if hasReachedEnd {
            .completed
        } else {
            .interrupted
        }

        NotificationCenter.default.post(
            name: PlayKit.videoFinishedNotification,
            object: PlayKit.NotificationPayload(
                url: url,
                playbackId: playbackId,
                surface: surface,
                metrics: player.currentItem.map(PlayKit.PlaybackMetrics.init(item:)),
                outcome: outcome
            )
        )
    }
    
    private func registerTimeControlStatusSubscription() {
        timeControlStatusSubscription?.cancel()
        
        timeControlStatusSubscription = player.publisher(for: \.timeControlStatus)
            .removeDuplicates()
            .sink { [weak self] status in
                guard let self, case let .video(_, url, _) = item else { return }
                
                switch status {
                case .playing:
                    self.status.value = .ready

                    NotificationCenter.default.post(
                        name: PlayKit.videoStartedNotification,
                        object: PlayKit.NotificationPayload(
                            url: url,
                            playbackId: playbackId,
                            surface: surface
                        )
                    )

                    hasStartedPlaying = true

                case .waitingToPlayAtSpecifiedRate:
                    if player.reasonForWaitingToPlay == AVPlayer.WaitingReason.toMinimizeStalls {
                        self.status.value = .loading

                        NotificationCenter.default.post(
                            name: PlayKit.videoStalledNotification,
                            object: PlayKit.NotificationPayload(
                                url: url,
                                playbackId: playbackId,
                                surface: surface,
                                // Every cold start waits here once before the
                                // first frame; only a wait after playback began
                                // is a rebuffer the viewer experienced as one.
                                isRebuffer: hasStartedPlaying
                            )
                        )
                    }

                default:
                    break
                }
            }
    }
    
    private func loadImage(from url: URL) {
        imageLoadingTask?.cancel()
        
        imageLoadingTask = Task { [weak self, item] in
            let uiImage = await ImageProvider.shared.loadImage(from: url)
            guard item == self?.item else { return }
            
            guard let uiImage else {
                self?.status.value = .error
                return
            }
        
            Task { @MainActor in
                guard item == self?.item else { return }
                self?.imageView.image = uiImage
                self?.status.value = .ready
            }
        }
    }
    
    private func runNonVideoTimer(for duration: TimeInterval) {
        timerSubscription?.cancel()
        
        timerSubscription = Timer.publish(every: 0.1, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                let currentProgress = progressInSeconds.value
                progressInSeconds.value = currentProgress + (0.1 * Double(rate))
                
                if progressInSeconds.value >= duration {
                    reachedEnd.send()
                }
            }
    }
}

private extension AVMediaSelectionGroup {
    var captionsOption: AVMediaSelectionOption? {
        options.first { $0.mediaType == .subtitle || $0.mediaType == .closedCaption }
    }

    var hasSelectableCaptions: Bool {
        options.contains { ($0.mediaType == .subtitle || $0.mediaType == .closedCaption) && $0.extendedLanguageTag != nil }
    }
}
