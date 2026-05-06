//
//  HLSManifestRewriter.swift
//  PlayKit
//
//  Created by Telem Tobi on 06/05/2026.
//

import Foundation

/// Filters and reorders variants in an HLS multivariant playlist so the
/// initial variant chosen by AVPlayer is biased toward a desired floor and
/// ceiling.
///
/// AVPlayer respects the order of variants in the playlist when
/// `AVPlayerItem.startsOnFirstEligibleVariant == true`. Reordering the
/// rewritten playlist therefore controls the cold-start choice without
/// changing the set of variants AVPlayer can adapt to.
internal struct HLSManifestRewriter {
    enum Ordering {
        /// Sort kept variants from the highest height to the lowest.
        case highestFirst
        /// Sort kept variants from the lowest height to the highest.
        case lowestFirst
    }

    /// Rewrites a multivariant playlist by:
    ///   1. expanding all relative URIs (variants and EXT-X-MEDIA renditions)
    ///      to absolute URLs against `baseURL`,
    ///   2. dropping variants outside `[minimumHeight, maximumHeight]` while
    ///      always retaining at least one variant, and
    ///   3. ordering kept variants per `ordering`.
    ///
    /// Returns `nil` when the input doesn't appear to be a multivariant
    /// playlist (no `EXT-X-STREAM-INF` lines), in which case the caller
    /// should return the original bytes unchanged.
    static func rewrite(
        manifest: String,
        baseURL: URL,
        minimumHeight: Int?,
        maximumHeight: Int?,
        ordering: Ordering
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
                let height = parseHeight(from: attrs)
                variants.append(VariantBlock(
                    height: height,
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

        // Ceiling: keep variants <= max; if none qualify, keep the smallest so
        // playback still works on a tiny render surface or aggressive cap.
        var kept = variants
        if let maximumHeight {
            let underCap = kept.filter { ($0.height ?? Int.max) <= maximumHeight }
            if !underCap.isEmpty {
                kept = underCap
            } else if let smallest = kept.min(by: heightAscending) {
                kept = [smallest]
            }
        }

        // Floor: keep variants >= min; if none qualify, keep the highest so
        // playback still works for sources whose ladder tops out below floor.
        if let minimumHeight {
            let overFloor = kept.filter { ($0.height ?? 0) >= minimumHeight }
            if !overFloor.isEmpty {
                kept = overFloor
            } else if let highest = kept.max(by: heightAscending) {
                kept = [highest]
            }
        }

        switch ordering {
        case .highestFirst: kept.sort { heightAscending($1, $0) }
        case .lowestFirst: kept.sort(by: heightAscending)
        }

        var output = preamble
        for variant in kept {
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
