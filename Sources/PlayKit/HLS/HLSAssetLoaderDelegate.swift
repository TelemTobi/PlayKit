//
//  HLSAssetLoaderDelegate.swift
//  PlayKit
//
//  Created by Telem Tobi on 06/05/2026.
//

import Foundation
import AVFoundation

/// Intercepts AVPlayer's request for a multivariant HLS playlist so the
/// payload can be reordered before AVPlayer parses it.
///
/// The factory only attaches this delegate on Wi-Fi / wired networks —
/// cellular and constrained paths skip the rewrite entirely so AVPlayer's
/// native, bandwidth-aware ABR runs unimpeded. As a result this class
/// doesn't need to consult the network class itself.
///
/// Only the master playlist URL is wrapped with the custom scheme;
/// rewritten playlists contain absolute `https` URIs for variant
/// playlists and audio renditions, which AVPlayer fetches directly and
/// bypass this delegate.
internal final class HLSAssetLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate {
    static let scheme = "pkhls"

    private let targetHeight: Int?

    /// Tracks the in-flight `URLSessionDataTask` for each loading request
    /// so the task can be cancelled when AVPlayer cancels the request —
    /// for example when the player item is replaced. Without this the
    /// cancelled fetch keeps running in the background and eats
    /// bandwidth. Keys are held weakly so dropped requests don't pin
    /// tasks alive.
    private let pendingTasks = NSMapTable<AVAssetResourceLoadingRequest, URLSessionDataTask>.weakToStrongObjects()
    private let pendingTasksLock = NSLock()

    init(targetHeight: Int?) {
        self.targetHeight = targetHeight
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

        let targetHeight = self.targetHeight

        // `loadingRequest` MUST be captured strongly. Nothing else holds
        // it across this async hop — capturing it weakly causes the
        // closure to see `nil` by the time the response arrives, so
        // `finishLoading` never fires and AVPlayer waits forever before
        // failing the item.
        let task = Self.sharedSession.dataTask(with: originalURL) { [weak self] data, response, error in
            self?.removePendingTask(for: loadingRequest)

            guard !loadingRequest.isCancelled else { return }

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
            let rewritten = HLSManifestRewriter.rewrite(
                manifest: manifestText,
                baseURL: baseURL,
                targetHeight: targetHeight
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
    /// Sharing avoids the per-item cost of building an ephemeral session
    /// (separate connection pool, no TLS session reuse, no shared
    /// cookies). Default configuration so cookies, credentials, and the
    /// system URL cache flow through the same channels as the rest of
    /// the app.
    static let sharedSession: URLSession = {
        let config = URLSessionConfiguration.default
        return URLSession(configuration: config)
    }()
}
