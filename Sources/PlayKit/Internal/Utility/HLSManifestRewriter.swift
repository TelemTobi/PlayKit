//
//  HLSManifestRewriter.swift
//  PlayKit
//
//  Created by Telem Tobi on 05/05/2026.
//

import Foundation
import AVFoundation

/// `AVAssetResourceLoaderDelegate` that intercepts HLS multivariant playlists
/// and reorders `#EXT-X-STREAM-INF` entries so the highest-bandwidth variant
/// appears first.
///
/// Combined with `AVPlayerItem.startsOnFirstEligibleVariant = true`, this gives
/// AVPlayer a deterministic high-quality first variant regardless of how the
/// origin server orders its master playlist, working around the iOS 13+
/// "startup-optimized" heuristic that otherwise begins playback at the lowest
/// available bitrate.
///
/// Only the master playlist is rewritten; segment playlists, segments and
/// audio renditions are fetched directly by AVFoundation over HTTPS because
/// the rewriter resolves every URI in the manifest to an absolute URL before
/// returning it.
final class HLSManifestRewriter: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    /// Custom URL scheme used to route master-playlist loads through this
    /// delegate. Sub-resource loads (segments, audio playlists, etc.) bypass
    /// the delegate because their URIs are made absolute in the rewritten
    /// manifest.
    static let customScheme = "playkit-hls"

    private let originalURL: URL
    private let session: URLSession
    private let queue = DispatchQueue(label: "co.recapp.PlayKit.HLSManifestRewriter")
    private var activeTasks: [ObjectIdentifier: URLSessionDataTask] = [:]

    init(originalURL: URL) {
        self.originalURL = originalURL
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
        super.init()
    }

    /// Rewrites a video URL so that loads go through ``HLSManifestRewriter``.
    /// The host must keep the rewriter alive for as long as the player item is
    /// active; AVURLAsset holds its resource-loader delegate weakly.
    static func customSchemeURL(for url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = customScheme
        return components.url
    }

    // MARK: - AVAssetResourceLoaderDelegate

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard loadingRequest.request.url?.scheme == Self.customScheme else {
            return false
        }

        let task = session.dataTask(with: originalURL) { [weak self] data, response, error in
            guard let self else { return }
            self.queue.async {
                self.activeTasks.removeValue(forKey: ObjectIdentifier(loadingRequest))
            }
            self.complete(loadingRequest: loadingRequest, data: data, response: response, error: error)
        }

        queue.async { [weak self] in
            self?.activeTasks[ObjectIdentifier(loadingRequest)] = task
        }
        task.resume()
        return true
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        queue.async { [weak self] in
            self?.activeTasks.removeValue(forKey: ObjectIdentifier(loadingRequest))?.cancel()
        }
    }

    private func complete(
        loadingRequest: AVAssetResourceLoadingRequest,
        data: Data?,
        response: URLResponse?,
        error: Error?
    ) {
        if let error {
            loadingRequest.finishLoading(with: error)
            return
        }

        guard let data, !data.isEmpty else {
            loadingRequest.finishLoading(with: NSError(
                domain: "PlayKit.HLSManifestRewriter",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Empty response loading HLS playlist"]
            ))
            return
        }

        let payload: Data
        if let text = String(data: data, encoding: .utf8), text.contains("#EXT-X-STREAM-INF") {
            let rewritten = Self.rewriteMultivariantPlaylist(text, baseURL: originalURL)
            payload = rewritten.data(using: .utf8) ?? data
        } else {
            payload = data
        }

        if let info = loadingRequest.contentInformationRequest {
            info.contentType = "application/vnd.apple.mpegurl"
            info.contentLength = Int64(payload.count)
            info.isByteRangeAccessSupported = false
        }

        if let httpResponse = response as? HTTPURLResponse {
            loadingRequest.response = httpResponse
        }

        loadingRequest.dataRequest?.respond(with: payload)
        loadingRequest.finishLoading()
    }

    // MARK: - Manifest rewriting

    /// Rewrites a multivariant master playlist so:
    ///   1. Every relative URI (variant URI lines and `URI="..."` attributes
    ///      on `#EXT-X-MEDIA`, `#EXT-X-I-FRAME-STREAM-INF`, etc.) resolves to
    ///      an absolute URL relative to `baseURL`. This lets AVFoundation
    ///      fetch sub-resources directly over HTTPS without going through the
    ///      custom scheme.
    ///   2. `#EXT-X-STREAM-INF` blocks are reordered by `BANDWIDTH` (or
    ///      `AVERAGE-BANDWIDTH` when `BANDWIDTH` is missing) descending.
    ///
    /// Non-variant lines and the relative ordering of any I-frame variant
    /// blocks are preserved.
    static func rewriteMultivariantPlaylist(_ text: String, baseURL: URL) -> String {
        var lines = text.components(separatedBy: "\n")
        for index in lines.indices {
            lines[index] = absolutize(line: lines[index], baseURL: baseURL)
        }

        struct VariantBlock {
            var lines: [String]
            var bandwidth: Int
        }

        var output: [String] = []
        var blocks: [VariantBlock] = []
        var insertionIndex: Int?
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("#EXT-X-STREAM-INF") {
                if insertionIndex == nil {
                    insertionIndex = output.count
                }

                var blockLines: [String] = [line]
                var cursor = index + 1
                while cursor < lines.count {
                    let candidate = lines[cursor]
                    blockLines.append(candidate)
                    let candidateTrimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                    cursor += 1
                    if candidateTrimmed.isEmpty || candidateTrimmed.hasPrefix("#") {
                        continue
                    }
                    break
                }

                blocks.append(VariantBlock(lines: blockLines, bandwidth: parseBandwidth(line)))
                index = cursor
                continue
            }

            output.append(line)
            index += 1
        }

        guard !blocks.isEmpty, let insertionIndex else {
            return lines.joined(separator: "\n")
        }

        let sorted = blocks.sorted { $0.bandwidth > $1.bandwidth }
        output.insert(contentsOf: sorted.flatMap(\.lines), at: insertionIndex)
        return output.joined(separator: "\n")
    }

    private static func absolutize(line: String, baseURL: URL) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return line }

        if trimmed.hasPrefix("#") {
            return absolutizeURIAttribute(in: line, baseURL: baseURL)
        }

        guard let absolute = URL(string: trimmed, relativeTo: baseURL)?.absoluteString,
              absolute != trimmed,
              let range = line.range(of: trimmed)
        else {
            return line
        }
        return line.replacingCharacters(in: range, with: absolute)
    }

    private static func absolutizeURIAttribute(in line: String, baseURL: URL) -> String {
        guard let prefixRange = line.range(of: "URI=\"") else { return line }
        let valueStart = prefixRange.upperBound
        guard let endQuote = line[valueStart...].firstIndex(of: "\"") else { return line }
        let uri = String(line[valueStart..<endQuote])
        guard !uri.isEmpty,
              let absolute = URL(string: uri, relativeTo: baseURL)?.absoluteString,
              absolute != uri
        else { return line }
        return line.replacingOccurrences(of: "URI=\"\(uri)\"", with: "URI=\"\(absolute)\"")
    }

    private static func parseBandwidth(_ tagLine: String) -> Int {
        if let value = parseDecimalAttribute(tagLine, name: "BANDWIDTH") {
            return value
        }
        if let value = parseDecimalAttribute(tagLine, name: "AVERAGE-BANDWIDTH") {
            return value
        }
        return 0
    }

    private static func parseDecimalAttribute(_ line: String, name: String) -> Int? {
        guard let range = line.range(of: "\(name)=") else { return nil }
        var value = ""
        for character in line[range.upperBound...] {
            if character.isNumber {
                value.append(character)
            } else {
                break
            }
        }
        return Int(value)
    }
}
