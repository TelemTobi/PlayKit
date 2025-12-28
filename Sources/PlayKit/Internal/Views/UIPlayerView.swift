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
    
    private(set) var item: PlaylistItem?
    private(set) var status = CurrentValueSubject<PlaylistItem.Status, Never>(.ready)
    private(set) var reachedEnd = PassthroughSubject<Void, Never>()

    private(set) var durationInSeconds: TimeInterval = .zero
    private(set) var progressInSeconds = CurrentValueSubject<TimeInterval, Never>(.zero)
    
    private var statusSubscription: AnyCancellable?
    private var reachedEndSubscription: AnyCancellable?
    private var readyObserver: NSKeyValueObservation?
    private var timeObserverToken: Any?
    private var timeControlStatusSubscription: AnyCancellable?

    private var imageLoadingTask: Task<Void, Never>?
    private var timerSubscription: AnyCancellable?
    
    private let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        return imageView
    }()
    
    convenience init(player: AVPlayer) {
        self.init(frame: .zero)
        self.player = player
        
        playerLayer.player = player
        
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
        
        guard let item else { return }
        
        switch item {
        case let .image(url, duration):
            durationInSeconds = duration
            progressInSeconds.value = .zero
            loadImage(from: url)
            
        case let .video(url):
            let item = AVPlayerItem(url: url)
            item.preferredForwardBufferDuration = 2.5
            player.replaceCurrentItem(with: item)
            player.automaticallyWaitsToMinimizeStalling = true

            registerStatusSubscription()
            registerTimeSubscription()
            registerReachedEndSubscription()
            registerTimeControlStatusSubscription()
            
        case let .custom(_, duration):
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
        case let .image(_, duration), let .custom(_, duration):
            runNonVideoTimer(for: duration)
            
        case let .video(url):
            guard player.rate.isZero else { return }
            
            NotificationCenter.default.post(
                name: PlayKit.videoRequestedNotification,
                object: PlayKit.NotificationPayload(url: url)
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
    
    func cancel() {
        item = nil
        player.cancelPendingPrerolls()
        player.replaceCurrentItem(with: nil)
        readyObserver = nil
        statusSubscription?.cancel()
        imageView.image = nil
        progressInSeconds.value = .zero
        durationInSeconds = .zero
        timerSubscription?.cancel()
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
}

extension UIPlayerView {
    private func registerStatusSubscription() {
        statusSubscription?.cancel()
        statusSubscription = player.publisher(for: \.currentItem?.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                switch status {
                case .readyToPlay:
                    self?.status.value = .ready
                    
                    let duration = self?.player.currentItem?.duration.seconds ?? .zero
                    self?.durationInSeconds = (duration.isNaN || duration.isInfinite) ? .zero : duration
                    
                case .failed:
                    self?.status.value = .error
                    self?.durationInSeconds = self?.errorDuration ?? .zero
                    
                    if case let .video(url) = self?.item {
                        NotificationCenter.default.post(
                            name: PlayKit.videoErrorNotification,
                            object: PlayKit.NotificationPayload(url: url, error: self?.player.currentItem?.error)
                        )
                    }
                    
                default:
                    self?.status.value = .loading
                }
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
                self?.reachedEnd.send()
            }
    }
    
    private func registerTimeControlStatusSubscription() {
        timeControlStatusSubscription?.cancel()
        
        timeControlStatusSubscription = player.publisher(for: \.timeControlStatus)
            .removeDuplicates()
            .sink { [weak self] status in
                guard let self, case let .video(url) = item else { return }
                
                switch status {
                case .playing:
                    self.status.value = .ready
                    
                    NotificationCenter.default.post(
                        name: PlayKit.videoStartedNotification,
                        object: PlayKit.NotificationPayload(url: url)
                    )
                    
                case .waitingToPlayAtSpecifiedRate:
                    if player.reasonForWaitingToPlay == AVPlayer.WaitingReason.toMinimizeStalls {
                        self.status.value = .loading
                        
                        NotificationCenter.default.post(
                            name: PlayKit.videoStalledNotification,
                            object: PlayKit.NotificationPayload(url: url)
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
