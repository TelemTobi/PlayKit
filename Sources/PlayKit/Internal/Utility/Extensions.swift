//
//  Extensions.swift
//  PlayKit
//
//  Created by Telem Tobi on 06/11/2025.
//

import Foundation
import UIKit

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension Array {
    func removing(_ element: Element) -> Self where Element : Equatable {
        guard let index = firstIndex(of: element) else { return self }
        var result = self
        result.remove(at: index)
        return result
    }
}

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}

extension Task where Success == Never, Failure == Never {
    static func sleep(interval: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
    }
}

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
