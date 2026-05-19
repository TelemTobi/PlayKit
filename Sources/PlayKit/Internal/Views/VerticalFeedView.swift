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
        collectionView.backgroundColor = .clear
        collectionView.isDirectionalLockEnabled = true
        collectionView.alwaysBounceHorizontal = false
        collectionView.register(VerticalFeedCell.self)
        return collectionView
    }()

    private var subscriptions: Set<AnyCancellable> = []
    private var mostVisibleIndex: Int = .zero
    private var isLayoutInProgress: Bool = false
    private var lastCollectionViewSize: CGSize = .zero
    
    convenience init(controller: PlaylistController?, delegate: VerticalFeedViewDelegate?) {
        self.init(frame: .zero)

        self.controller = controller
        self.delegate = delegate

        self.subscribeToPlaylistItems()
        self.subscribeToCurrentIndex()
        self.subscribeToUserScrollingEnabled()
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
            isLayoutInProgress = true
            lastCollectionViewSize = bounds.size

            let currentItemIndexPath = IndexPath(row: controller?.currentIndex ?? .zero, section: .zero)
            collectionView.collectionViewLayout.invalidateLayout()
            collectionView.layoutIfNeeded()
            collectionView.scrollToItem(at: currentItemIndexPath, at: [.centeredVertically, .centeredHorizontally], animated: false)

            if let isEnabled = controller?.isUserScrollingEnabled {
                applyUserScrolling(isEnabled: isEnabled)
            }

            DispatchQueue.main.async { [weak self] in
                self?.isLayoutInProgress = false
            }
        }
    }
    
    func reloadData() {
        collectionView.reloadData()
    }
    
    private func subscribeToPlaylistItems() {
        controller?.$items
            .filter { !$0.isEmpty }
            .debounce(for: 0.1, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.collectionView.reloadData()
            }
            .store(in: &subscriptions)
    }
    
    private func subscribeToCurrentIndex() {
        controller?.$currentIndex
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newIndex in
                if newIndex != self?.mostVisibleIndex {
                    let newIndexPath = IndexPath(row: newIndex, section: .zero)
                    let animated = self?.controller?.setIndexWithAnimation ?? false
                    self?.collectionView.scrollToItem(at: newIndexPath, at: [.centeredVertically, .centeredHorizontally], animated: animated)
                }

            }
            .store(in: &subscriptions)
    }

    private func subscribeToUserScrollingEnabled() {
        controller?.$isUserScrollingEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEnabled in
                self?.applyUserScrolling(isEnabled: isEnabled)
            }
            .store(in: &subscriptions)
    }

    private func applyUserScrolling(isEnabled: Bool) {
        guard let scrollView = orthogonalScrollView() else { return }
        scrollView.isScrollEnabled = isEnabled
        scrollView.panGestureRecognizer.isEnabled = isEnabled
    }

    private func orthogonalScrollView() -> UIScrollView? {
        findOrthogonalScrollView(in: collectionView)
    }

    private func findOrthogonalScrollView(in view: UIView) -> UIScrollView? {
        for subview in view.subviews {
            if let scrollView = subview as? UIScrollView, scrollView !== collectionView {
                return scrollView
            }
            if let found = findOrthogonalScrollView(in: subview) {
                return found
            }
        }
        return nil
    }
    
    // TODO: Consider debouncing 👇
    private func onScroll(contentOffset: CGPoint) {
        guard !isLayoutInProgress else { return }
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
            self.mostVisibleIndex = mostVisibleIndex
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
