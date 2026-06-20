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

    /// Eagerly instantiates the shared classifier so its `NWPathMonitor`
    /// starts observing *before* the first video is prepared.
    ///
    /// The monitor is otherwise created lazily on the first `current`
    /// access — typically inside the first `makePlayerItem` — at which
    /// point it hasn't yet delivered a path and classification falls back
    /// to `.unknown` (→ passthrough → AVPlayer cold-starts on the lowest
    /// variant, defeating a configured quality floor). Warming up at
    /// controller creation gives the monitor the create-to-prepare window
    /// to settle. Safe and cheap to call repeatedly.
    static func warmUp() {
        _ = shared
    }

    /// The current network class.
    ///
    /// `NWPathMonitor.pathUpdateHandler` runs on its dispatch queue, so on
    /// app launch the first video can race ahead of the first callback.
    /// Falling back to `monitor.currentPath` in that window avoids
    /// classifying as `.unknown` — Apple documents `currentPath` as
    /// queryable at any time, returning the most recent path the monitor
    /// observed. See also ``warmUp()``, which starts the monitor early so
    /// this fallback has a settled path to read.
    ///
    /// Only a genuinely unsatisfied path (no connection determined yet)
    /// maps to `.unknown`. Any *satisfied* path is classified: cellular or
    /// otherwise-expensive (e.g. Personal Hotspot) is `.cellular`, and
    /// every other satisfied interface — Wi-Fi, wired, or `.other` such as
    /// a VPN tunnel — is `.unconstrained`. This keeps a transient or
    /// unusual interface from silently dropping to passthrough.
    var current: HLSNetworkClass {
        os_unfair_lock_lock(&lock)
        let cached = cachedPath
        os_unfair_lock_unlock(&lock)
        let path = cached ?? monitor.currentPath

        guard path.status == .satisfied else { return .unknown }
        if path.isConstrained { return .constrained }
        if path.usesInterfaceType(.cellular) || path.isExpensive {
            return .cellular
        }
        return .unconstrained
    }
}
