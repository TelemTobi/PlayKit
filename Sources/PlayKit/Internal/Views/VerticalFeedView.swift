//
//  VerticalFeedView.swift
//  PlayKit
//
//  Created by Telem Tobi on 13/12/2025.
//

import Combine
import UIKit

protocol VerticalFeedViewDelegate: AnyObject {
    func numberOfPlayers() -> Int
    func status(for index: Int) -> PlaylistItem.Status
    func player(for index: Int) -> UIPlayerView
}

final class VerticalFeedView: UIView {
    private weak var delegate: VerticalFeedViewDelegate?

    private lazy var tableView: UITableView = {
        let tableView = UITableView()
        tableView.delegate = self
        tableView.dataSource = self
        tableView.isPagingEnabled = true
        return tableView
    }()

    var currentIndex = CurrentValueSubject<Int, Never>(.zero)

    override init(frame: CGRect) {
        super.init(frame: frame)
        
        tableView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.topAnchor.constraint(equalTo: topAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension VerticalFeedView: UITableViewDelegate, UITableViewDataSource {
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        delegate?.numberOfPlayers() ?? .zero
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell() // TODO: Dequeue instead
        let contentView = delegate?.player(for: indexPath.row)
//        cell.addSubview(...)
        return cell
    }
}
