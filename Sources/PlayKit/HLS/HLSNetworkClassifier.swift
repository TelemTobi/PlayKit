//
//  HLSNetworkClassifier.swift
//  PlayKit
//
//  Created by Telem Tobi on 06/05/2026.
//

import Foundation
import Network

internal enum HLSNetworkClass: Sendable {
    case unconstrained
    case cellular
    case constrained
    case unknown
}

/// Snapshots the device's current network class for HLS variant selection.
///
/// We deliberately don't distinguish fast vs slow cellular. Earlier
/// versions branched on `CTTelephonyNetworkInfo` radio access tech
/// (LTE/NR → fast, otherwise slow) to decide whether to push a higher
/// initial variant. In practice the cellular floor we ship (360p,
/// ~310 Kbps) is below every modern cellular envelope, so the
/// distinction wasn't load-bearing — and dropping CoreTelephony removes
/// a framework dependency and a small privacy footprint.
internal final class HLSNetworkClassifier: @unchecked Sendable {
    static let shared = HLSNetworkClassifier()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "PlayKit.HLSNetworkClassifier", qos: .utility)
    private var lock = os_unfair_lock_s()
    private var cachedPath: NWPath?

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            os_unfair_lock_lock(&self.lock)
            self.cachedPath = path
            os_unfair_lock_unlock(&self.lock)
        }
        monitor.start(queue: queue)
    }

    /// The current network class.
    ///
    /// `NWPathMonitor.pathUpdateHandler` runs on its dispatch queue, so on
    /// app launch the first video can race ahead of the first callback.
    /// Falling back to `monitor.currentPath` in that window avoids
    /// classifying as `.unknown` and degrading initial playback to
    /// AVPlayer's "start on the lowest variant" default — Apple documents
    /// `currentPath` as queryable at any time, returning the most recent
    /// path the monitor observed.
    var current: HLSNetworkClass {
        os_unfair_lock_lock(&lock)
        let cached = cachedPath
        os_unfair_lock_unlock(&lock)
        let path = cached ?? monitor.currentPath

        guard path.status == .satisfied else { return .unknown }
        if path.isConstrained { return .constrained }

        if path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) {
            return .unconstrained
        }
        if path.usesInterfaceType(.cellular) {
            return .cellular
        }
        return .unknown
    }
}
