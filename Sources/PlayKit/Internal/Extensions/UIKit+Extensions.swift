//
//  UIKit+Extensions.swift
//  PlayKit
//
//  Created by Telem Tobi on 13/12/2025.
//

import UIKit

extension UIView {
    func anchorToSuperview() {
        guard let superview else { return }
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            self.leadingAnchor.constraint(equalTo: superview.leadingAnchor),
            self.trailingAnchor.constraint(equalTo: superview.trailingAnchor),
            self.topAnchor.constraint(equalTo: superview.topAnchor),
            self.bottomAnchor.constraint(equalTo: superview.bottomAnchor)
        ])
    }
}

extension UICollectionView {
    func register(_ cellType: UICollectionViewCell.Type) {
        register(cellType, forCellWithReuseIdentifier: cellType.identifier)
    }
    
    func dequeue<Cell: UICollectionViewCell>(_ cellType: Cell.Type, for indexPath: IndexPath) -> Cell {
        dequeueReusableCell(withReuseIdentifier: cellType.identifier, for: indexPath) as! Cell
    }
}

extension UICollectionViewCell {
    static var identifier: String {
        return String(describing: self)
    }
}

extension UICollectionViewLayout {
    static func verticalFeed(onScroll: @MainActor @escaping (CGPoint) -> Void) -> UICollectionViewCompositionalLayout {
        let layout = UICollectionViewCompositionalLayout { _, env in
            let containerHeight = env.container.effectiveContentSize.height
            
            let item = NSCollectionLayoutItem(
                layoutSize: .init(
                    widthDimension: .fractionalWidth(1.0),
                    heightDimension: .absolute(containerHeight)
                )
            )
            
            let group = NSCollectionLayoutGroup.vertical(
                layoutSize: .init(
                    widthDimension: .fractionalWidth(1.0),
                    heightDimension: .absolute(containerHeight)
                ),
                subitems: [item]
            )
            
            let section = NSCollectionLayoutSection(group: group)
            section.orthogonalScrollingBehavior = .groupPaging
            section.visibleItemsInvalidationHandler = { _, offset, _ in onScroll(offset) }
            return section
        }

        layout.configuration.scrollDirection = .vertical
//        layout.configuration.contentInsetsReference = .none
        return layout
    }
}
