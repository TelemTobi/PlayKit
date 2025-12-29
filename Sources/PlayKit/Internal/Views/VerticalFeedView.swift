//
//  VerticalFeedView.swift
//  PlayKit
//
//  Created by Telem Tobi on 13/12/2025.
//

import Combine
import UIKit

@MainActor
protocol VerticalFeedViewDelegate: AnyObject {
    func playerView(for item: PlaylistItem) -> UIView?
    func overlayView(for index: Int) -> UIView?
}

final class VerticalFeedView: UIView, PlaylistContentView {
    private weak var controller: PlaylistController?
    private weak var delegate: VerticalFeedViewDelegate?
    
    private lazy var collectionView: UICollectionView = {
        let collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: .verticalFeed(onScroll: onScroll)
        )
        collectionView.dataSource = self
        collectionView.scrollsToTop = false
        collectionView.register(VerticalFeedCell.self)
        return collectionView
    }()

    private var itemsSubscription: AnyCancellable?
    private var lastCollectionViewSize: CGSize = .zero
    
    convenience init(controller: PlaylistController?, delegate: VerticalFeedViewDelegate?) {
        self.init(frame: .zero)
        self.controller = controller
        self.delegate = delegate
        
        self.subscribeToPlaylistItems()
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        addSubview(collectionView)
        collectionView.anchorToSuperview()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastCollectionViewSize {
            lastCollectionViewSize = bounds.size
            collectionView.collectionViewLayout.invalidateLayout()
            collectionView.layoutIfNeeded()
            
//            let currentItemIndexPath = IndexPath(row: controller?.currentIndex ?? .zero, section: .zero)
//            collectionView.scrollToItem(at: currentItemIndexPath, at: .centeredVertically, animated: false)
        }
    }
    
    func reloadData() {
        collectionView.reloadData()
    }
    
    private func subscribeToPlaylistItems() {
        itemsSubscription?.cancel()
        
        itemsSubscription = controller?.$items
            .filter { !$0.isEmpty }
            .debounce(for: 0.1, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.collectionView.reloadData()
            }
    }
    
    // TODO: Consider debouncing 👇
    private func onScroll(contentOffset: CGPoint) {
        let visibleRect = CGRect(origin: contentOffset, size: collectionView.bounds.size)
        
        var maxVisibility: CGFloat = 0
        var mostVisibleCell: UICollectionViewCell?
        
        for cell in collectionView.visibleCells {
            let intersection = visibleRect.intersection(cell.frame)
            let visibilityPercentage = (intersection.width * intersection.height) / (cell.frame.width * cell.frame.height)
            
            if visibilityPercentage > maxVisibility {
                maxVisibility = visibilityPercentage
                mostVisibleCell = cell
            }
        }
        
        if let cell = mostVisibleCell as? VerticalFeedCell,
            let mostVisibleIndex = collectionView.indexPath(for: cell)?.row,
            mostVisibleIndex != controller?.currentIndex {
            controller?.setCurrentIndex(mostVisibleIndex)
        }
    }
}

extension VerticalFeedView: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        controller?.items.count ?? .zero
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeue(VerticalFeedCell.self, for: indexPath)

        guard let playlistItem = controller?.items[safe: indexPath.row],
              let playerView = delegate?.playerView(for: playlistItem) else { return cell }
        
        let overlay = delegate?.overlayView(for: indexPath.row)
        cell.embed(playerView, with: overlay)
        return cell
    }
}

fileprivate class VerticalFeedCell: UICollectionViewCell {
    override func prepareForReuse() {
        super.prepareForReuse()
        contentView.subviews.forEach { $0.removeFromSuperview() }
    }
    
    func embed(_ view: UIView, with overlay: UIView? = nil) {
        contentView.addSubview(view)
        view.anchorToSuperview()
        
        if let overlay {
            overlay.backgroundColor = .clear
            contentView.addSubview(overlay)
            overlay.anchorToSuperview()
        }
    }
}
