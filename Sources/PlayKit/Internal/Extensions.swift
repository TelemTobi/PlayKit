//
//  Extensions.swift
//  PlayKit
//
//  Created by Telem Tobi on 06/11/2025.
//

import Foundation

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

extension TimeInterval {
    var timeFormatted: String {
        guard !self.isNaN, !self.isInfinite else { return "" }
        let hours = Int(self / 3600)
        let minutes = (Int(self) % 3600) / 60
        let seconds = Int(self) % 60

        return if hours > 0 {
            String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

extension Task where Success == Never, Failure == Never {
    static func sleep(interval: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
    }
}
