//
//  VerticalPagingLayout.swift
//  PlayKit
//
//  Vertical full-bounds paging layout that keeps a designated focused
//  cell pinned across bounds-size changes. The invalidation context
//  driven by `focusedIndex` adjusts `contentOffset` atomically with the
//  cell-frame recompute, so the focused cell's frame stays inside the
//  visible region across the bounds change. UIKit therefore never
//  recycles it — which means `VerticalFeedCell.prepareForReuse` doesn't
//  fire and the player view isn't stripped + re-embedded during e.g. a
//  resizing overlay animation. That's the flash this layout exists to
//  prevent.
//
//  Cells stack vertically. The collection view itself is the paging
//  scroll surface — there's no orthogonal scrolling indirection.
//

import UIKit

final class VerticalPagingLayout: UICollectionViewLayout {
    /// Row to keep pinned across bounds-size changes. The view sets this
    /// before bounds change so `invalidationContext(forBoundsChange:)`
    /// knows how to adjust `contentOffset`.
    var focusedIndex: Int = 0

    private var lastCollectionViewSize: CGSize = .zero

    override var collectionViewContentSize: CGSize {
        guard let collectionView else { return .zero }
        let count = collectionView.numberOfItems(inSection: 0)
        return CGSize(
            width: collectionView.bounds.width,
            height: CGFloat(count) * collectionView.bounds.height
        )
    }

    override func prepare() {
        super.prepare()
        if let size = collectionView?.bounds.size {
            lastCollectionViewSize = size
        }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard let collectionView else { return nil }
        let height = collectionView.bounds.height
        let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
        attributes.frame = CGRect(
            x: 0,
            y: CGFloat(indexPath.row) * height,
            width: collectionView.bounds.width,
            height: height
        )
        return attributes
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard let collectionView else { return nil }
        let height = collectionView.bounds.height
        guard height > 0 else { return [] }

        let count = collectionView.numberOfItems(inSection: 0)
        guard count > 0 else { return [] }

        let first = max(0, Int(floor(rect.minY / height)))
        let last = min(count - 1, Int(ceil(rect.maxY / height)))
        guard first <= last else { return [] }

        return (first...last).compactMap {
            layoutAttributesForItem(at: IndexPath(row: $0, section: 0))
        }
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        guard let collectionView else { return false }
        // Invalidate only on size changes — origin-only changes (regular
        // scrolling) don't need a re-layout.
        return newBounds.size != collectionView.bounds.size
    }

    override func invalidationContext(forBoundsChange newBounds: CGRect) -> UICollectionViewLayoutInvalidationContext {
        let context = super.invalidationContext(forBoundsChange: newBounds)
        guard let collectionView else { return context }

        let oldSize = collectionView.bounds.size
        let newSize = newBounds.size
        guard newSize != oldSize, newSize.height > 0 else { return context }

        // Atomically move contentOffset so focusedIndex's new frame sits at
        // the top of the visible region. Because we report this together
        // with the layout invalidation (not via setContentOffset afterward),
        // UIKit treats the cell as continuously visible and never recycles
        // it — that's what kills the prepareForReuse flash.
        let targetOffsetY = CGFloat(focusedIndex) * newSize.height
        let currentOffsetY = collectionView.contentOffset.y
        let adjustmentY = targetOffsetY - currentOffsetY
        if adjustmentY != 0 {
            context.contentOffsetAdjustment = CGPoint(x: 0, y: adjustmentY)
        }

        return context
    }

    override func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint) -> CGPoint {
        snapToPage(near: proposedContentOffset.y)
    }

    override func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint, withScrollingVelocity velocity: CGPoint) -> CGPoint {
        // Let UIKit's paging behavior handle velocity-based page selection;
        // we only need to snap the proposed offset to a page boundary.
        snapToPage(near: proposedContentOffset.y)
    }

    private func snapToPage(near y: CGFloat) -> CGPoint {
        guard let collectionView else { return CGPoint(x: 0, y: y) }
        let height = collectionView.bounds.height
        guard height > 0 else { return CGPoint(x: 0, y: y) }
        let count = collectionView.numberOfItems(inSection: 0)
        guard count > 0 else { return CGPoint(x: 0, y: y) }
        let page = (y / height).rounded()
        let clamped = max(0, min(CGFloat(count - 1), page))
        return CGPoint(x: 0, y: clamped * height)
    }
}
