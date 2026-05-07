//
//  HLSAssetLoaderDelegate.swift
//  PlayKit
//
//  Created by Telem Tobi on 06/05/2026.
//

import Foundation
import AVFoundation

/// Intercepts AVPlayer's request for a multivariant HLS playlist so the
/// payload can be filtered and reordered before AVPlayer parses it.
///
/// Only the master playlist URL is wrapped with the custom scheme; rewritten
/// playlists contain absolute `https` URIs for variant playlists and audio
/// renditions, which AVPlayer fetches directly and bypass this delegate.
internal final class HLSAssetLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate {
    static let scheme = "pkhls"

    private let configuration: HLSQualityPolicy.Configuration
    private let networkClass: () -> HLSNetworkClass
    private let viewPixelHeight: () -> Int?

    /// Tracks the in-flight `URLSessionDataTask` for each loading request so
    /// the task can be cancelled when AVPlayer cancels the request — for
    /// example when the player item is replaced. Without this the cancelled
    /// fetch keeps running in the background and eats cellular bandwidth.
    /// Keys are held weakly so dropped requests don't pin tasks alive.
    private let pendingTasks = NSMapTable<AVAssetResourceLoadingRequest, URLSessionDataTask>.weakToStrongObjects()
    private let pendingTasksLock = NSLock()

    init(
        configuration: HLSQualityPolicy.Configuration,
        viewPixelHeight: @escaping () -> Int?,
        networkClass: @escaping () -> HLSNetworkClass = { HLSNetworkClassifier.shared.current }
    ) {
        self.configuration = configuration
        self.viewPixelHeight = viewPixelHeight
        self.networkClass = networkClass
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard let requestedURL = loadingRequest.request.url,
              requestedURL.scheme == HLSAssetLoaderDelegate.scheme,
              let originalURL = restoreOriginalURL(from: requestedURL) else {
            return false
        }

        let networkClass = self.networkClass()
        let configuration = self.configuration
        let viewPixelHeight = self.viewPixelHeight()

        let task = Self.sharedSession.dataTask(with: originalURL) { [weak self, weak loadingRequest] data, response, error in
            guard let loadingRequest, !loadingRequest.isCancelled else { return }
            self?.removePendingTask(for: loadingRequest)

            guard let data, error == nil else {
                loadingRequest.finishLoading(with: error ?? URLError(.badServerResponse))
                return
            }
            guard let manifestText = String(data: data, encoding: .utf8) else {
                // Not a UTF-8 manifest — return raw bytes so AVPlayer can deal with it.
                Self.respond(to: loadingRequest, with: data)
                return
            }

            let baseURL = (response as? HTTPURLResponse)?.url ?? originalURL
            let minimumHeight = configuration.minimumHeight(for: networkClass)
            let ordering: HLSManifestRewriter.Ordering = (networkClass == .unconstrained)
                ? .highestFirst
                : .lowestFirst
            let maximumHeight = configuration.capsResolutionToViewSize ? viewPixelHeight : nil

            let rewritten = HLSManifestRewriter.rewrite(
                manifest: manifestText,
                baseURL: baseURL,
                minimumHeight: minimumHeight,
                maximumHeight: maximumHeight,
                ordering: ordering
            ) ?? manifestText

            let outputData = Data(rewritten.utf8)
            Self.respond(to: loadingRequest, with: outputData)
        }

        setPendingTask(task, for: loadingRequest)
        task.resume()
        return true
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        pendingTasksLock.lock()
        let task = pendingTasks.object(forKey: loadingRequest)
        pendingTasks.removeObject(forKey: loadingRequest)
        pendingTasksLock.unlock()
        task?.cancel()
    }

    private func setPendingTask(_ task: URLSessionDataTask, for request: AVAssetResourceLoadingRequest) {
        pendingTasksLock.lock()
        pendingTasks.setObject(task, forKey: request)
        pendingTasksLock.unlock()
    }

    private func removePendingTask(for request: AVAssetResourceLoadingRequest) {
        pendingTasksLock.lock()
        pendingTasks.removeObject(forKey: request)
        pendingTasksLock.unlock()
    }

    private static func respond(to loadingRequest: AVAssetResourceLoadingRequest, with data: Data) {
        if let info = loadingRequest.contentInformationRequest {
            info.contentType = "application/vnd.apple.mpegurl"
            info.contentLength = Int64(data.count)
            info.isByteRangeAccessSupported = false
        }
        loadingRequest.dataRequest?.respond(with: data)
        loadingRequest.finishLoading()
    }

    private func restoreOriginalURL(from custom: URL) -> URL? {
        guard var components = URLComponents(url: custom, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = "https"
        return components.url
    }

    /// Single process-wide URLSession used by all loader instances.
    ///
    /// Sharing avoids the per-item cost of building an ephemeral session
    /// (separate connection pool, no TLS session reuse, no shared cookies),
    /// which makes a measurable difference on cellular where every fresh
    /// handshake costs hundreds of milliseconds. Default configuration is
    /// used so cookies, credentials, and the system URL cache flow through
    /// the same channels as the rest of the app.
    static let sharedSession: URLSession = {
        let config = URLSessionConfiguration.default
        return URLSession(configuration: config)
    }()
}

private extension HLSQualityPolicy.Configuration {
    func minimumHeight(for networkClass: HLSNetworkClass) -> Int? {
        switch networkClass {
        case .unconstrained: return wifiMinimumHeight
        case .fastCellular: return fastCellularMinimumHeight
        case .slowCellular: return slowCellularMinimumHeight
        case .constrained, .unknown: return nil
        }
    }
}
