//
//  UIPlaylistView.swift
//  PlayKit
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
    private var playerTimeSubscriptions: Set<AnyCancellable> = []
    private var reachedEndSubscriptions: Set<AnyCancellable> = []
    private var bitrateSubscription: AnyCancellable?
    private var itemsSubscription: AnyCancellable?
    private var isPlayingSubscription: AnyCancellable?
    private var isFocusedSubscription: AnyCancellable?
    private var progressSubscription: AnyCancellable?
    private var indexSubscription: AnyCancellable?
    private var rateSubscription: AnyCancellable?
    
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
            subscribeToIsFocused()
            subscribeToProgress()
            subscribeToCurrentIndex()
            subscribeToRate()
            prepareCurrentPlayer()
            calculateBufferWindows()
        }
    }
    
    public var gravity: AVLayerVideoGravity = .resizeAspect {
        willSet {
            players.forEach { $0.setGravity(newValue) }
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        registerBitrateSubscription()
        registerLifecycleSubscriptions()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func initiatePlayers() {
        players.forEach { $0.removeFromSuperview() }
        players.removeAll()
        
        let backwardBuffer = controller?.backwardBuffer ?? .zero
        let forwardBuffer = controller?.forwardBuffer ?? .zero
        let newPlayers = createPlayers(count: backwardBuffer + forwardBuffer + 1)
        players.append(contentsOf: newPlayers)
    }
    
    private func createPlayers(count: Int) -> [UIPlayerView] {
        var newPlayers: [UIPlayerView] = []
        
        for _ in 0..<count {
            newPlayers.append(UIPlayerView())
        }
        
        for playerView in newPlayers {
            playerView.alpha = .zero
            playerView.setGravity(gravity)
            
            playerView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(playerView)
            NSLayoutConstraint.activate([
                playerView.leadingAnchor.constraint(equalTo: leadingAnchor),
                playerView.trailingAnchor.constraint(equalTo: trailingAnchor),
                playerView.topAnchor.constraint(equalTo: topAnchor),
                playerView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
        
        registerPlayerSubscriptions(for: newPlayers)
        return newPlayers
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
    
    private func registerBitrateSubscription() {
        bitrateSubscription?.cancel()
        bitrateSubscription = PlayKit.shared.bitratePublisher
            .filter { $0 > .zero }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] bitrate in
                self?.calculateBufferWindows(basedOn: bitrate)
            }
    }
    
    private func calculateBufferWindows(basedOn bitrate: Double? = nil) {
        let bitrate = bitrate ?? PlayKit.shared.lastObservedBitrate
        let newForwardBuffer = Int(bitrate / 1_000_000).clamped(to: 1...5)
        let newBackwardBuffer = Int(bitrate / 2_000_000).clamped(to: 1...2)

        if newForwardBuffer != controller?.forwardBuffer {
            controller?.forwardBuffer = newForwardBuffer
            
            let backwardBuffer = controller?.backwardBuffer ?? .zero
            let forwardBuffer = controller?.forwardBuffer ?? .zero
            let newPlayersCount = backwardBuffer + forwardBuffer + 1
            
            if players.count < newPlayersCount {
                let newPlayers = createPlayers(count: newPlayersCount - players.count)
                players.append(contentsOf: newPlayers)
            } else {
                let playersToRemove = players.suffix(players.count - newPlayersCount)
                players.removeLast(playersToRemove.count)
                for player in playersToRemove {
                    player.cancel()
                    player.removeFromSuperview()
                }
            }
        }
        
        if newBackwardBuffer != controller?.backwardBuffer {
            controller?.backwardBuffer = newBackwardBuffer
            
            let backwardBuffer = controller?.backwardBuffer ?? .zero
            let forwardBuffer = controller?.forwardBuffer ?? .zero
            let newPlayersCount = backwardBuffer + forwardBuffer + 1
            
            if players.count < newPlayersCount {
                let newPlayers = createPlayers(count: newPlayersCount - players.count)
                players.insert(contentsOf: newPlayers, at: .zero)
            } else {
                let playersToRemove = players.prefix(players.count - newPlayersCount)
                players.removeFirst(playersToRemove.count)
                for player in playersToRemove {
                    player.cancel()
                    player.removeFromSuperview()
                }
            }
        }
        
        if controller?.isFocused == true {
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
            
            player.progressInSeconds
                .filter { [weak self] _ in
                    player == self?.currentPlayer
                }
                .receive(on: DispatchQueue.main)
                .sink { [weak self] progress in
                    self?.controller?.progressInSeconds = progress
                    self?.controller?.durationInSeconds = self?.currentPlayer?.durationInSeconds ?? .zero
                }
                .store(in: &playerTimeSubscriptions)
            
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
                
                if controller?.isFocused == true {
                    controller?.isPlaying = true
                    currentPlayer?.alpha = 1
                    prepareRelativePlayers()
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
                if isPlaying {
                    self?.currentPlayer?.playWhenReady()
                } else {
                    self?.currentPlayer?.pause()
                }
            }
    }
    
    private func subscribeToIsFocused() {
        isFocusedSubscription?.cancel()
        
        isFocusedSubscription = controller?.$isFocused
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isFocused in
                self?.controller?.isPlaying = isFocused
                guard self?.controller?.items.isEmpty == false else { return }
                
                if isFocused {
                    self?.currentPlayer?.alpha = 1
                    self?.prepareRelativePlayers()
                } else {
                    self?.cancelRelativePlayers()
                    self?.controller?.setProgress(.zero)
                }
            }
    }
    
    private func subscribeToProgress() {
        progressSubscription?.cancel()
        
        progressSubscription = controller?.progressPublisher
            .sink { [weak self] progress in
                self?.currentPlayer?.setProgress(progress)
            }
    }
    
    private func subscribeToCurrentIndex() {
        indexSubscription?.cancel()
        
        indexSubscription = controller?.$currentIndex
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newIndex in
                self?.currentPlayer?.pause()
                self?.updatePlayers()
                self?.transitionToCurrentPlayer()
                
                Task { [newIndex] in
                    try? await Task.sleep(interval: 0.1)
                    guard newIndex == self?.controller?.currentIndex else { return }
                    self?.currentPlayer?.rate = self?.controller?.rate ?? 1
                    self?.currentPlayer?.playWhenReady()
                }
            }
    }
    
    private func subscribeToRate() {
        rateSubscription?.cancel()
        
        rateSubscription = controller?.$rate
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rate in
                self?.currentPlayer?.setRate(rate)
            }
    }
    
    private func prepareAllPlayers() {
        prepareCurrentPlayer()
        prepareRelativePlayers()
    }
    
    private func prepareCurrentPlayer() {
        if let currentItem = controller?.currentItem {
            currentPlayer?.prepare(item: currentItem)
        }
    }
    
    private func prepareRelativePlayers() {
        controller?.rangedItems.enumerated().forEach { index, item in
            if item != controller?.currentItem || item == .error {
                players[safe: index]?.prepare(item: item)
            }
        }
    }
    
    private func cancelRelativePlayers() {
        controller?.rangedItems.enumerated().forEach { index, item in
            if item != controller?.currentItem {
                players[safe: index]?.cancel()
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
                    players[safe: index]?.prepare(item: itemToPrepare)
                }
                
            } else if diff < 0 { // Moved backward, within buffer range
                let playersToReuse = players.suffix(abs(diff))
                players.removeLast(abs(diff))
                players.insert(contentsOf: playersToReuse, at: .zero)
                
                controller?.rangedItems.prefix(abs(diff)).enumerated().forEach { index, itemToPrepare in
                    players[safe: index]?.prepare(item: itemToPrepare)
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
