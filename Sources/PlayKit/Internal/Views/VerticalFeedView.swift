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

    private let pagingLayout = VerticalPagingLayout()

    private lazy var collectionView: UICollectionView = {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: pagingLayout)
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.scrollsToTop = false
        collectionView.backgroundColor = .clear
        collectionView.isDirectionalLockEnabled = true
        collectionView.alwaysBounceHorizontal = false
        collectionView.isPagingEnabled = true
        collectionView.showsVerticalScrollIndicator = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.register(VerticalFeedCell.self)
        return collectionView
    }()

    private var subscriptions: Set<AnyCancellable> = []
    private var mostVisibleIndex: Int = .zero
    private var isLayoutInProgress: Bool = false
    private var lastCollectionViewSize: CGSize = .zero
    private var lastUserScrollingEnabled: Bool = true

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
        let didBoundsChange = bounds.size != lastCollectionViewSize
        if didBoundsChange {
            // Inform the layout which row to pin so its
            // invalidationContext(forBoundsChange:) adjusts contentOffset to
            // keep that cell in the visible region — and as a result UIKit
            // does NOT recycle it, which is what eliminates the flash.
            pagingLayout.focusedIndex = controller?.currentIndex ?? 0
            isLayoutInProgress = true
        }
        super.layoutSubviews()
        if didBoundsChange {
            lastCollectionViewSize = bounds.size

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
                guard let self else { return }
                if newIndex != self.mostVisibleIndex {
                    self.scrollToPage(newIndex, animated: self.controller?.setIndexWithAnimation ?? false)
                }
            }
            .store(in: &subscriptions)
    }

    private func subscribeToUserScrollingEnabled() {
        controller?.$isUserScrollingEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEnabled in
                guard let self else { return }
                let wasEnabled = self.lastUserScrollingEnabled
                self.lastUserScrollingEnabled = isEnabled
                self.applyUserScrolling(isEnabled: isEnabled)
                // Defence-in-depth: after the locked overlay animation
                // finishes, ensure the offset is exactly on currentIndex's
                // page. The layout's invalidationContext already does this
                // atomically per bounds change, but residual drift from
                // user pre-release motion can leave a small offset.
                if isEnabled, !wasEnabled, let index = self.controller?.currentIndex {
                    self.scrollToPage(index, animated: false)
                }
            }
            .store(in: &subscriptions)
    }

    private func applyUserScrolling(isEnabled: Bool) {
        collectionView.isScrollEnabled = isEnabled
        collectionView.panGestureRecognizer.isEnabled = isEnabled
    }

    private func scrollToPage(_ index: Int, animated: Bool) {
        let height = collectionView.bounds.height
        guard height > 0 else { return }
        let targetY = CGFloat(index) * height
        guard abs(collectionView.contentOffset.y - targetY) > 0.5 else { return }
        collectionView.setContentOffset(CGPoint(x: 0, y: targetY), animated: animated)
    }

    // TODO: Consider debouncing 👇
    fileprivate func onScroll(contentOffset: CGPoint) {
        guard !isLayoutInProgress else { return }
        guard controller?.isUserScrollingEnabled != false else { return }

        // Only respond to user-driven motion. setContentOffset from
        // subscribeToCurrentIndex / unlock-snap reaches here with both
        // flags false and must not feed back into currentIndex.
        guard collectionView.isDragging || collectionView.isDecelerating else { return }

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

extension VerticalFeedView: UICollectionViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        onScroll(contentOffset: scrollView.contentOffset)
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
