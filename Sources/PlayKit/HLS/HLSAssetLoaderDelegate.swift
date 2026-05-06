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
    private let session: URLSession

    init(
        configuration: HLSQualityPolicy.Configuration,
        viewPixelHeight: @escaping () -> Int?,
        networkClass: @escaping () -> HLSNetworkClass = { HLSNetworkClassifier.shared.current }
    ) {
        self.configuration = configuration
        self.viewPixelHeight = viewPixelHeight
        self.networkClass = networkClass
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.waitsForConnectivity = false
        self.session = URLSession(configuration: sessionConfig)
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

        let task = session.dataTask(with: originalURL) { data, response, error in
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
        task.resume()
        return true
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
