//
//  UIPlaylistView.swift
//  Tryout
//
//  Created by Telem Tobi on 06/11/2025.
//

import Combine
import UIKit
import AVKit

public final class UIPlaylistView: UIView {
    private var players: [UIPlayerView] = []
    
    private var lifecyleSubscriptions: Set<AnyCancellable> = []
    private var statusSubscriptions: Set<AnyCancellable> = []
    private var reachedEndSubscriptions: Set<AnyCancellable> = []
    private var playerTimeSubscription: AnyCancellable?
    private var itemsSubscription: AnyCancellable?
    private var isPlayingSubscription: AnyCancellable?
    private var progressSubscription: AnyCancellable?
    private var indexSubscription: AnyCancellable?
    private var accessLogSubscription: AnyCancellable?
    
    private var hasBeenPlayedBefore: Bool = false
    
    private var currentPlayer: UIPlayerView? {
        guard let backwardBuffer = controller?.backwardBuffer else { return nil }
        return players[safe: backwardBuffer]
    }
    
    private var relativePlayers: [UIPlayerView] {
        guard let currentPlayer else { return players }
        return players.removing(currentPlayer)
    }
    
    public var controller: PlaylistController? {
        didSet {
            subscribeToPlaylistItems()
            initiatePlayers()
            subscribeToIsPlaying()
            subscribeToProgress()
            subscribeToCurrentIndex()
            prepareCurrentPlayer()
        }
    }
    
    public var gravity: AVLayerVideoGravity = .resizeAspect {
        willSet {
            players.forEach { $0.setVideoGravity(newValue) }
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        registerAccessLogSubscription()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func initiatePlayers() {
        players.forEach { $0.removeFromSuperview() }
        players.removeAll()
        
        let backwardBuffer = controller?.backwardBuffer ?? .zero
        let forwardBuffer = controller?.forwardBuffer ?? .zero
        appendPlayers(count: backwardBuffer + forwardBuffer + 1)
    }
    
    private func appendPlayers(count: Int) {
        var newlyAddedPlayers: [UIPlayerView] = []
        
        for _ in 0..<count {
            newlyAddedPlayers.append(UIPlayerView())
        }
        
        players.append(contentsOf: newlyAddedPlayers)
        
        for playerView in newlyAddedPlayers {
            playerView.alpha = .zero
            playerView.setVideoGravity(gravity)
            playerView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(playerView)
            NSLayoutConstraint.activate([
                playerView.leadingAnchor.constraint(equalTo: leadingAnchor),
                playerView.trailingAnchor.constraint(equalTo: trailingAnchor),
                playerView.topAnchor.constraint(equalTo: topAnchor),
                playerView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
        
        registerPlayerSubscriptions(for: newlyAddedPlayers)
    }
    
    private func registerLifecycleSubscriptions() {
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                guard self?.controller?.isPlaying == true else { return }
                self?.currentPlayer?.pause()
            }
            .store(in: &lifecyleSubscriptions)
        
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                guard self?.controller?.isPlaying == true else { return }
                self?.currentPlayer?.playWhenReady()
            }
            .store(in: &lifecyleSubscriptions)
    }
    
    private func registerAccessLogSubscription() {
        accessLogSubscription?.cancel()
        accessLogSubscription = NotificationCenter.default
            .publisher(for: AVPlayerItem.newAccessLogEntryNotification)
            .compactMap { notification -> Double? in
                guard let lastEvent = (notification.object as? AVPlayerItem)?.accessLog()?.events.last else { return nil }
                
                if lastEvent.transferDuration > 0, lastEvent.numberOfBytesTransferred > 0 {
                    return (Double(lastEvent.numberOfBytesTransferred) * 8.0) / lastEvent.transferDuration
                }
                
                return lastEvent.observedBitrate
            }
            .filter { $0 > .zero }
            .removeDuplicates()
            .throttle(for: 10, scheduler: DispatchQueue.main, latest: false)
            .sink { [weak self] bitrate in
                guard let self else { return }
                
                let newForwardBuffer = Int(bitrate / 1_000_000).clamped(to: 1...5)
                guard newForwardBuffer != controller?.forwardBuffer else { return }
                
                controller?.forwardBuffer = newForwardBuffer
                
                let backwardBuffer = controller?.backwardBuffer ?? .zero
                let forwardBuffer = controller?.forwardBuffer ?? .zero
                let newPlayersCount = backwardBuffer + forwardBuffer + 1
                
                if players.count < newPlayersCount {
                    appendPlayers(count: newPlayersCount - players.count)
                } else {
                    let playersToRemove = players.suffix(players.count - newPlayersCount)
                    players.removeLast(playersToRemove.count)
                    for player in playersToRemove {
                        player.cancel()
                        player.removeFromSuperview()
                    }
                }
                
                prepareRelativePlayers()
            }
    }
    
    private func registerPlayerSubscriptions(for players: [UIPlayerView]) {
        players.forEach { player in
            player.status
                .filter { [weak self] _ in
                    player == self?.currentPlayer
                }
                .receive(on: DispatchQueue.main)
                .sink { [weak self] newStatus in
                    self?.controller?.status = newStatus
                }
                .store(in: &statusSubscriptions)
            
            player.reachedEnd
                .filter { [weak self] _ in
                    player == self?.currentPlayer
                }
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in
                    if self?.controller?.currentIndex == (self?.controller?.items.count ?? .zero) - 1 {
                        self?.controller?.reachedEnd.send()
                    } else {
                        self?.controller?.advanceToNext()
                    }
                }
                .store(in: &reachedEndSubscriptions)
        }
    }
    
    private func subscribeToPlaylistItems() {
        itemsSubscription?.cancel()
        
        itemsSubscription = controller?.$items
            .filter { !$0.isEmpty }
            .debounce(for: 0.1, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                prepareCurrentPlayer()
                
                if !hasBeenPlayedBefore, controller?.isPlaying == true {
                    currentPlayer?.alpha = 1
                    prepareRelativePlayers()
                    hasBeenPlayedBefore = true
                }
                
                if controller?.isPlaying == true {
                    currentPlayer?.playWhenReady()
                }
            }
    }
    
    private func subscribeToIsPlaying() {
        isPlayingSubscription?.cancel()
        
        isPlayingSubscription = controller?.$isPlaying
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPlaying in
                guard let self else { return }
                
                if !hasBeenPlayedBefore, isPlaying, controller?.items.isEmpty == false {
                    currentPlayer?.alpha = 1
                    prepareRelativePlayers()
                    hasBeenPlayedBefore = true
                }
                
                if isPlaying {
                    currentPlayer?.playWhenReady()
                } else {
                    currentPlayer?.pause()
                }
            }
    }
    
    private func subscribeToProgress() {
        progressSubscription?.cancel()
        
        progressSubscription = controller?.progressPublisher
            .sink { [weak self] progress in
                Task {
                    let newTime = CMTime(seconds: progress, preferredTimescale: 600)
                    _ = await self?.currentPlayer?.player.seek(to: newTime, toleranceBefore: .zero, toleranceAfter: .zero)
                }
            }
    }
    
    private func subscribeToCurrentIndex() {
        indexSubscription?.cancel()
        
        indexSubscription = controller?.$currentIndex
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newIndex in
                self?.currentPlayer?.pause()
                self?.updatePlayers()
                self?.transitionToCurrentPlayer()
                self?.controller?.isPlaying = true
                
                Task { [newIndex] in
                    try? await Task.sleep(interval: 0.1)
                    guard newIndex == self?.controller?.currentIndex else { return }
                    self?.currentPlayer?.playWhenReady()
                    self?.subscribeToCurrentPlayerProgress()
                }
            }
    }
    
    private func subscribeToCurrentPlayerProgress() {
        playerTimeSubscription?.cancel()
        
        playerTimeSubscription = currentPlayer?.progressInSeconds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                Task { @MainActor in
                    self?.controller?.progressInSeconds = progress
                    self?.controller?.durationInSeconds = self?.currentPlayer?.durationInSeconds ?? .zero
                }
            }
    }
    
    private func prepareAllPlayers() {
        prepareCurrentPlayer()
        prepareRelativePlayers()
    }
    
    private func prepareCurrentPlayer() {
        if let currentItem = controller?.currentItem {
            currentPlayer?.prepare(item: currentItem, targetSize: bounds.size)
            subscribeToCurrentPlayerProgress()
        }
    }
    
    private func prepareRelativePlayers() {
        controller?.rangedItems.enumerated().forEach { index, item in
            if item != controller?.currentItem {
                players[safe: index]?.prepare(item: item, targetSize: bounds.size)
            }
        }
    }
    
    private func updatePlayers() {
        let previouslyPlayedPlayer = currentPlayer
        
        if let rangedPlayerIndex = players.firstIndex(where: { player in
            guard let item = player.item else { return false }
            return controller?.rangedItems.contains(item) == true
        }) {
            let rangedItemIndex = controller?.rangedItems.firstIndex(where: { $0 == players[rangedPlayerIndex].item }) ?? .zero
            let diff = rangedPlayerIndex - rangedItemIndex
            
            if diff > 0 { // Moved forward, within buffer range
                let playersToReuse = players.prefix(diff)
                players.removeFirst(diff)
                players.append(contentsOf: playersToReuse)
                
                controller?.rangedItems.enumerated().suffix(diff).forEach { index, itemToPrepare in
                    players[safe: index]?.prepare(item: itemToPrepare, targetSize: bounds.size)
                }
                
            } else if diff < 0 { // Moved backward, within buffer range
                let playersToReuse = players.suffix(abs(diff))
                players.removeLast(abs(diff))
                players.insert(contentsOf: playersToReuse, at: .zero)
                
                controller?.rangedItems.prefix(abs(diff)).enumerated().forEach { index, itemToPrepare in
                    players[safe: index]?.prepare(item: itemToPrepare, targetSize: bounds.size)
                }
            }
        } else {
            prepareAllPlayers()
        }
        
        previouslyPlayedPlayer?.seekToBeginning()
        controller?.status = currentPlayer?.status.value ?? .loading
    }
    
    private func transitionToCurrentPlayer() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            currentPlayer?.alpha = 1
            relativePlayers.forEach { $0.alpha = .zero }
        }
    }
}
