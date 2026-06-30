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
    private var compressedContentHeight: CGFloat?
    private var contentTopInset: CGFloat = .zero
    
    convenience init(controller: PlaylistController?, delegate: VerticalFeedViewDelegate?) {
        self.init(frame: .zero)

        self.controller = controller
        self.delegate = delegate

        self.subscribeToPlaylistItems()
        self.subscribeToCurrentIndex()
        self.subscribeToUserScrollingEnabled()
        self.subscribeToContentCompression()
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

    private func subscribeToContentCompression() {
        guard let controller else { return }

        controller.$compressedContentHeight
            .combineLatest(controller.$contentTopInset)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] height, topInset in
                self?.applyContentCompression(height: height, topInset: topInset)
            }
            .store(in: &subscriptions)
    }

    private func applyContentCompression(height: CGFloat?, topInset: CGFloat) {
        // Ignore redundant updates so a late callback (e.g. a trailing geometry
        // change after dismissal) can't re-apply the same value un-animated and
        // interrupt an in-flight expand/collapse animation.
        guard height != compressedContentHeight || topInset != contentTopInset else { return }

        // Animate only when entering/leaving the compressed state (crossing the nil
        // boundary). While the sheet is dragged, height streams in continuously and
        // should track the finger directly — animating each step would lag/jitter.
        let crossesCompressionBoundary = (compressedContentHeight == nil) != (height == nil)

        compressedContentHeight = height
        contentTopInset = topInset

        let apply = { [weak self] in
            guard let self else { return }
            for case let cell as VerticalFeedCell in collectionView.visibleCells {
                cell.applyCompression(height: height, topInset: topInset)
            }
            layoutIfNeeded()
        }

        if crossesCompressionBoundary {
            UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState], animations: apply)
        } else {
            apply()
        }
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
        cell.applyCompression(height: compressedContentHeight, topInset: contentTopInset)
        return cell
    }
}

fileprivate class VerticalFeedCell: UICollectionViewCell {
    // Only the player view is compressed; the overlay always fills the cell so its
    // own content (which the consumer hides/shows) never re-lays-out as the video
    // resizes. This mirrors how StoriesPlayerView keeps overlay layout decoupled
    // from the shrinking video.
    private var playerTopConstraint: NSLayoutConstraint?
    private var playerBottomConstraint: NSLayoutConstraint?
    private var playerHeightConstraint: NSLayoutConstraint?

    override func prepareForReuse() {
        super.prepareForReuse()
        contentView.subviews.forEach { $0.removeFromSuperview() }
        playerTopConstraint = nil
        playerBottomConstraint = nil
        playerHeightConstraint = nil
    }

    func embed(_ view: UIView, with overlay: UIView? = nil) {
        contentView.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false

        // Pin leading/trailing/top to the cell and keep both a bottom anchor
        // (full-bleed) and a height anchor (compressed) around so we can toggle
        // between them without rebuilding the view hierarchy.
        let top = view.topAnchor.constraint(equalTo: contentView.topAnchor)
        let bottom = view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        let height = view.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            top,
            bottom
        ])

        playerTopConstraint = top
        playerBottomConstraint = bottom
        playerHeightConstraint = height

        if let overlay {
            overlay.backgroundColor = .clear
            contentView.addSubview(overlay)
            overlay.anchorToSuperview()
        }
    }

    /// Toggles the player view between full-bleed (`height == nil`) and a
    /// top-anchored compressed region of the given height/offset.
    func applyCompression(height: CGFloat?, topInset: CGFloat) {
        guard let playerTopConstraint, let playerBottomConstraint, let playerHeightConstraint else { return }

        if let height {
            playerBottomConstraint.isActive = false
            playerTopConstraint.constant = topInset
            playerHeightConstraint.constant = height
            playerHeightConstraint.isActive = true
        } else {
            playerHeightConstraint.isActive = false
            playerTopConstraint.constant = 0
            playerBottomConstraint.isActive = true
        }
    }
}
