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
    
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    
    let player = AVPlayer()
    let imageItemDuration: TimeInterval = 10
    var rate: Float = 1
    
    private(set) var item: PlaylistItem?
    private(set) var status = CurrentValueSubject<PlaylistItem.Status, Never>(.ready)
    private(set) var reachedEnd = PassthroughSubject<Void, Never>()

    private(set) var durationInSeconds: TimeInterval = .zero
    private(set) var progressInSeconds = CurrentValueSubject<TimeInterval, Never>(.zero)
    
    private var statusSubscription: AnyCancellable?
    private var reachedEndSubscription: AnyCancellable?
    private var readyObserver: NSKeyValueObservation?
    private var timeObserverToken: Any?

    private var imageLoadingTask: Task<Void, Never>?
    private var timerSubscription: AnyCancellable?
    
    private let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        return imageView
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
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
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func prepare(item: PlaylistItem?, targetSize: CGSize) {
        guard item != self.item else { return }
        
        cancel()
        self.item = item
        self.status.value = .loading
        
        guard let item else { return }
        
        switch item {
        case let.image(url):
            durationInSeconds = imageItemDuration
            progressInSeconds.value = .zero
            loadImage(from: url)
            
        case let .video(url):
            let item = AVPlayerItem(url: url)
            item.preferredMaximumResolution = targetSize
            item.preferredForwardBufferDuration = 5.0
            
            player.replaceCurrentItem(with: item)
            player.automaticallyWaitsToMinimizeStalling = true

            registerStatusSubscription()
            registerTimeSubscription()
            registerReachedEndSubscription()
            
        case .custom:
            status.value = .ready
            break
        }
    }
    
    func playWhenReady() {
        switch item {
        case .image:
            runNonVideoTimer()
            
        case .video:
            if playerLayer.isReadyForDisplay {
                player.play()
                player.rate = rate
                return
                
            } else if status.value == .error {
                runNonVideoTimer()
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
            
        case .custom, .none:
            break
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
                    self?.durationInSeconds = self?.imageItemDuration ?? .zero
                
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
    
    private func runNonVideoTimer() {
        timerSubscription?.cancel()
        
        timerSubscription = Timer.publish(every: 0.1, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                let currentProgress = progressInSeconds.value
                progressInSeconds.value = currentProgress + (0.1 * Double(rate))
                
                if progressInSeconds.value >= imageItemDuration {
                    reachedEnd.send()
                }
            }
    }
}
