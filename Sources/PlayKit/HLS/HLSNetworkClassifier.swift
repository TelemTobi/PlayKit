//
//  HLSNetworkClassifier.swift
//  PlayKit
//
//  Created by Telem Tobi on 06/05/2026.
//

import Foundation
import Network
#if os(iOS) && !targetEnvironment(macCatalyst)
import CoreTelephony
#endif

internal enum HLSNetworkClass: Sendable {
    case unconstrained
    case fastCellular
    case slowCellular
    case constrained
    case unknown
}

/// Snapshots the device's current network class for HLS variant selection.
internal final class HLSNetworkClassifier: @unchecked Sendable {
    static let shared = HLSNetworkClassifier()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "PlayKit.HLSNetworkClassifier", qos: .utility)
    private var lock = os_unfair_lock_s()
    private var cachedPath: NWPath?

    #if os(iOS) && !targetEnvironment(macCatalyst)
    private let telephony = CTTelephonyNetworkInfo()
    #endif

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            os_unfair_lock_lock(&self.lock)
            self.cachedPath = path
            os_unfair_lock_unlock(&self.lock)
        }
        monitor.start(queue: queue)
    }

    var current: HLSNetworkClass {
        os_unfair_lock_lock(&lock)
        let path = cachedPath
        os_unfair_lock_unlock(&lock)

        guard let path, path.status == .satisfied else { return .unknown }
        if path.isConstrained { return .constrained }

        if path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) {
            return .unconstrained
        }
        if path.usesInterfaceType(.cellular) {
            return isFastCellular ? .fastCellular : .slowCellular
        }
        return .unknown
    }

    private var isFastCellular: Bool {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        guard let radios = telephony.serviceCurrentRadioAccessTechnology?.values, !radios.isEmpty else {
            return true
        }
        return radios.contains(where: Self.isFastRadio)
        #else
        return true
        #endif
    }

    #if os(iOS) && !targetEnvironment(macCatalyst)
    private static func isFastRadio(_ tech: String) -> Bool {
        if tech == CTRadioAccessTechnologyLTE { return true }
        if #available(iOS 14.1, *) {
            if tech == CTRadioAccessTechnologyNR { return true }
            if tech == CTRadioAccessTechnologyNRNSA { return true }
        }
        return false
    }
    #endif
}
