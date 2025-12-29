//
//  VerticalFeedLayout.swift
//  PlayKit
//
//  Created by Telem Tobi on 29/12/2025.
//

import UIKit

fileprivate final class VerticalPagerLayout: UICollectionViewFlowLayout {
    override func prepare() {
        super.prepare()
        guard let cv = collectionView else { return }
        scrollDirection = .vertical
        minimumLineSpacing = 0
        minimumInteritemSpacing = 0
        itemSize = cv.bounds.size          // full screen per cell
        sectionInset = .zero
    }

    // Keep current page anchored on bounds changes (e.g., rotation)
    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        return newBounds.size != collectionView?.bounds.size
    }
}

final class VerticalPagerView: UICollectionView, UICollectionViewDelegate {
    private var currentIndex: Int = 0

    init() {
        super.init(frame: .zero, collectionViewLayout: VerticalPagerLayout())
        isPagingEnabled = true
        showsVerticalScrollIndicator = false
        decelerationRate = .fast
        delegate = self
        // set dataSource, register cell, etc.
    }

    required init?(coder: NSCoder) { fatalError() }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        snapToNearestPage()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { snapToNearestPage() }
    }

    private func snapToNearestPage() {
        let pageHeight = bounds.height
        guard pageHeight > 0 else { return }
        let rawIndex = (contentOffset.y + pageHeight / 2) / pageHeight
        let index = max(0, Int(rawIndex.rounded()))
        currentIndex = index
        scrollToItem(at: IndexPath(item: index, section: 0), at: .top, animated: true)
    }
}
