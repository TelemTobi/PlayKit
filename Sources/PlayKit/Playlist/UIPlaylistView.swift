//
//  UIPlaylistView.swift
//  PlayKit
//
//  Created by Telem Tobi on 06/11/2025.
//

import Combine
import UIKit
import AVKit

/// A UIKit view that orchestrates buffered playback for a playlist.
///
/// The view hosts multiple ``UIPlayerView`` instances to keep items before and
/// after the current index preloaded, enabling smooth transitions when the
/// user advances or rewinds.
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
    
    private var playlistType: PlaylistType = .tapThrough
    private weak var contentView: PlaylistContentView?
    
    /// The controller that supplies playlist items and playback state.
    ///
    /// Assigning a controller wires the view to the controller's publishers and
    /// starts managing player lifecycles for the surrounding buffer window.
    public var controller: PlaylistController?
    
    /// The video gravity applied to all managed player views.
    ///
    /// Updates propagate immediately to existing players.
    public var gravity: AVLayerVideoGravity = .resizeAspect {
        willSet {
            players.forEach { $0.setGravity(newValue) }
        }
    }
    
    // TODO: Document ⚠️
    public var overlayForItemAtIndex: ((Int) -> UIView?)? = nil {
        didSet { contentView?.reloadData() }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        registerLifecycleSubscriptions()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerLifecycleSubscriptions()
    }
    
    public func initialize(type: PlaylistType, controller: PlaylistController) {
        self.playlistType = type
        self.controller = controller
        
        subscribeToPlaylistItems()
        initiatePlayers()
        subscribeToIsPlaying()
        subscribeToIsFocused()
        subscribeToProgress()
        subscribeToCurrentIndex()
        subscribeToRate()
        prepareCurrentPlayer()
    }
    
    private func initiatePlayers() {
        subviews.forEach { $0.removeFromSuperview() }
        players.removeAll()
        
        for player in controller?.players ?? [] {
            let playerView = UIPlayerView(player: player)
            playerView.setGravity(gravity)
            players.append(playerView)
        }
        
        prepareUserInterface()
        registerPlayerSubscriptions(for: players)
    }
    
    private func prepareUserInterface() {
        let contentView: PlaylistContentView = switch playlistType {
        case .tapThrough: TapThroughView(players: players)
        case .verticalFeed: VerticalFeedView(controller: controller, delegate: self)
        }
        
        addSubview(contentView)
        contentView.anchorToSuperview()
        self.contentView = contentView
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
                    switch self?.playlistType {
                    case .tapThrough:
                        if self?.controller?.currentIndex == (self?.controller?.items.count ?? .zero) - 1 {
                            self?.controller?.reachedEnd.send()
                        } else {
                            self?.controller?.advanceToNext()
                        }
                        
                    case .verticalFeed:
                        self?.currentPlayer?.seekToBeginning()
                        self?.currentPlayer?.playWhenReady()
                        
                    case .none:
                        break
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
                    guard newIndex == self?.controller?.currentIndex,
                          self?.controller?.isPlaying == true else { return }
                    
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
            if item != controller?.currentItem {
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
        switch playlistType {
        case .tapThrough:
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                currentPlayer?.alpha = 1
                relativePlayers.forEach { $0.alpha = .zero }
            }
            
        case .verticalFeed:
            break
        }
    }
}

extension UIPlaylistView: VerticalFeedViewDelegate {
    func playerView(for item: PlaylistItem) -> UIView? {
        players.first(where: { $0.item == item })
    }
    
    func overlayView(for index: Int) -> UIView? {
        overlayForItemAtIndex?(index)
    }
}
