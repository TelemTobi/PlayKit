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
    static var verticalFeed: UICollectionViewCompositionalLayout {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .fractionalHeight(1.0)
        )
        let layoutItem = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .fractionalHeight(1.0)
        )
        let layoutGroup = NSCollectionLayoutGroup.vertical(
            layoutSize: groupSize,
            subitems: [layoutItem]
        )

        let layoutSection = NSCollectionLayoutSection(group: layoutGroup)
        layoutSection.orthogonalScrollingBehavior = .groupPaging

        let config = UICollectionViewCompositionalLayoutConfiguration()
        config.scrollDirection = .horizontal
        config.contentInsetsReference = .none

        return UICollectionViewCompositionalLayout(section: layoutSection, configuration: config)
    }
}
