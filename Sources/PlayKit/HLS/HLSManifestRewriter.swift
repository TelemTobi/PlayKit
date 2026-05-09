//
//  HLSManifestRewriter.swift
//  PlayKit
//
//  Created by Telem Tobi on 06/05/2026.
//

import Foundation

/// Reorders variants in an HLS multivariant playlist so AVPlayer's
/// `startsOnFirstEligibleVariant=true` picks a desired starting variant
/// rather than the lowest-bitrate one.
///
/// Crucially, no variants are removed. AVPlayer's adaptive bitrate (ABR)
/// engine relies on the full ladder being present so it can downgrade when
/// the network deteriorates — dropping the low rungs from the manifest
/// causes hard stalls on weak cellular because ABR has nowhere to fall
/// back to. Resolution caps for the render surface are enforced separately
/// via `AVPlayerItem.preferredMaximumResolution`, which is documented as
/// a variant-eligibility constraint that still permits ABR to revisit
/// higher variants when bandwidth allows.
internal struct HLSManifestRewriter {
    /// Rewrites a multivariant playlist by:
    ///   1. expanding all relative URIs (variants and EXT-X-MEDIA renditions)
    ///      to absolute URLs against `baseURL`,
    ///   2. promoting one variant to the first position so AVPlayer's
    ///      "first eligible variant" pick lands on it, and
    ///   3. ordering the remainder ascending by height — purely for stable
    ///      output; AVPlayer's ABR considers all variants regardless of
    ///      tail order.
    ///
    /// The promoted variant is the smallest-height variant whose height is
    /// `>= targetHeight`. If no variant clears the bar (e.g. a low-ladder
    /// portrait source while the policy targets 720p), the highest-height
    /// variant is promoted instead so playback at least starts at the best
    /// quality the source offers.
    ///
    /// When `targetHeight` is `nil` no promotion happens — variants are
    /// returned in their source order, only with absolute URIs. Returns
    /// `nil` for media playlists (no `EXT-X-STREAM-INF` lines), in which
    /// case the caller should hand the original bytes back unchanged.
    static func rewrite(
        manifest: String,
        baseURL: URL,
        targetHeight: Int?
    ) -> String? {
        guard manifest.contains("#EXT-X-STREAM-INF") else { return nil }

        let rawLines = manifest.components(separatedBy: .newlines)
        var preamble: [String] = []
        var variants: [VariantBlock] = []
        var pendingStreamInf: String?

        for line in rawLines {
            if line.hasPrefix("#EXT-X-STREAM-INF") {
                pendingStreamInf = line
                continue
            }
            if let attrs = pendingStreamInf {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    pendingStreamInf = nil
                    preamble.append(line)
                    continue
                }
                let absolute = URL(string: trimmed, relativeTo: baseURL)?.absoluteString ?? trimmed
                variants.append(VariantBlock(
                    height: parseHeight(from: attrs),
                    attributesLine: attrs,
                    absoluteURI: absolute
                ))
                pendingStreamInf = nil
                continue
            }
            if line.hasPrefix("#EXT-X-MEDIA") {
                preamble.append(rewriteURIAttribute(in: line, baseURL: baseURL))
                continue
            }
            preamble.append(line)
        }

        guard !variants.isEmpty else { return nil }

        let ordered: [VariantBlock]
        if let targetHeight {
            let ascending = variants.sorted(by: heightAscending)
            // Smallest variant that meets the floor; if none, the highest
            // the source offers.
            let promotedIndex = ascending.firstIndex(where: { ($0.height ?? 0) >= targetHeight })
                ?? (ascending.count - 1)
            var rest = ascending
            let promoted = rest.remove(at: promotedIndex)
            ordered = [promoted] + rest
        } else {
            ordered = variants
        }

        var output = preamble
        for variant in ordered {
            output.append(variant.attributesLine)
            output.append(variant.absoluteURI)
        }
        return output.joined(separator: "\n")
    }

    private struct VariantBlock {
        let height: Int?
        let attributesLine: String
        let absoluteURI: String
    }

    private static func heightAscending(_ a: VariantBlock, _ b: VariantBlock) -> Bool {
        (a.height ?? 0) < (b.height ?? 0)
    }

    private static func parseHeight(from attributesLine: String) -> Int? {
        guard let range = attributesLine.range(of: "RESOLUTION=") else { return nil }
        let after = attributesLine[range.upperBound...]
        let token = after.split(whereSeparator: { $0 == "," || $0.isWhitespace }).first ?? Substring(after)
        let parts = token.split(separator: "x")
        guard parts.count == 2, let height = Int(parts[1]) else { return nil }
        return height
    }

    /// Rewrites the value of a `URI="..."` attribute to an absolute URL.
    /// Other attributes on the line are left untouched.
    private static func rewriteURIAttribute(in line: String, baseURL: URL) -> String {
        guard let uriRange = line.range(of: "URI=\"") else { return line }
        let valueStart = uriRange.upperBound
        guard let closingQuote = line[valueStart...].firstIndex(of: "\"") else { return line }
        let original = String(line[valueStart..<closingQuote])
        let absolute = URL(string: original, relativeTo: baseURL)?.absoluteString ?? original
        return line.replacingCharacters(in: valueStart..<closingQuote, with: absolute)
    }
}
