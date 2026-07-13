//
//  BIFROSTAnswerVerifier.swift
//  BIFROST
//
//  Created by JourdanLabs on 06/07/2026.
//  Portions derived from DuckDuckGo BareBonesBrowser under Apache-2.0.
//

import CryptoKit
import Foundation

public struct BIFROSTAnswerVerdict: Sendable, Equatable {
    public enum Display: String, Sendable, CaseIterable {
        case noScanFlag = "NO SCAN FLAG"
        case review = "REVIEW"
    }

    public let display: Display
    public let category: String
    public let label: String
    public let headline: String
    public let detail: String
    public let action: String
    public let inputHash: String
}

public struct BIFROSTAnswerVerifier: Sendable {
    public init() {}

    public func evaluate(_ output: String) -> BIFROSTAnswerVerdict? {
        let normalized = normalize(output)
        guard normalized.count >= 24 else {
            return nil
        }

        let inputHash = sha256Hex(normalized)
        let numbers = matches(numberPattern, in: normalized)
        let hasSourceMarker = visibleSourceMarker(in: normalized)
        let lower = normalized.lowercased()

        if hasCodeEdgeCase(in: normalized) {
            return verdict(
                .review,
                category: "code_edge_case",
                label: "REVIEW · CODE PATTERN",
                headline: "A code pattern may need boundary-case review.",
                detail: "BIFROST found direct index or method access and did not find a visible guard in the scanned text.",
                action: "Check null, empty, and boundary cases before using the snippet.",
                inputHash: inputHash
            )
        }

        if hasContradiction(in: lower) {
            return verdict(
                .review,
                category: "internal_contradiction",
                label: "REVIEW · POSSIBLE CONTRADICTION",
                headline: "The scanned text contains a possible contradiction pattern.",
                detail: "BIFROST matched opposing terms in the same answer; it did not resolve their meaning or context.",
                action: "Compare the claims in context and against a source of record before relying on them.",
                inputHash: inputHash
            )
        }

        if isCurrentClaim(lower) && hasSourceMarker == false {
            return verdict(
                .review,
                category: "current_claim_no_source",
                label: "REVIEW · CURRENT WORDING",
                headline: "The scan found time-sensitive wording without a visible source marker.",
                detail: "BIFROST matched a configured recency term; it did not determine whether the claim is current.",
                action: "Check a current source of record before relying on the claim.",
                inputHash: inputHash
            )
        }

        if numbers.count >= 6 && hasSourceMarker == false {
            return verdict(
                .review,
                category: "unsourced_numeric_claims",
                label: "REVIEW · DENSE NUMBERS",
                headline: "The scan found dense numeric content without a visible source marker.",
                detail: "BIFROST counted \(numbers.count) numeric patterns and found no configured source marker.",
                action: "Check the figures against source documents before using them.",
                inputHash: inputHash
            )
        }

        if overconfidenceCount(in: lower) >= 2 {
            return verdict(
                .review,
                category: "unsupported_confidence",
                label: "REVIEW · CERTAINTY LANGUAGE",
                headline: "The scan found repeated absolute-confidence language.",
                detail: "BIFROST matched configured certainty terms; it did not determine whether the claims are correct.",
                action: "Check the claim externally or rewrite it with explicit uncertainty and citations.",
                inputHash: inputHash
            )
        }

        if looksLikeJudgmentCall(lower) {
            return verdict(
                .review,
                category: "judgment_call",
                label: "REVIEW · JUDGMENT LANGUAGE",
                headline: "The scan found subjective wording with context or trade-off language.",
                detail: "BIFROST matched configured judgment terms; it does not settle the question.",
                action: "Treat the output as framing and review the underlying values, context, and evidence.",
                inputHash: inputHash
            )
        }

        if hasSourceMarker {
            return verdict(
                .noScanFlag,
                category: "sourced_shape",
                label: "NO SCAN FLAG · SOURCE MARKER",
                headline: "A source marker is visible; no configured review pattern matched.",
                detail: "BIFROST recognized source-like text but did not open, authenticate, or validate the source or its support for the claims.",
                action: "Open the cited material and check that it supports the answer before relying on it.",
                inputHash: inputHash
            )
        }

        if numbers.isEmpty == false {
            return verdict(
                .noScanFlag,
                category: "light_numeric_check",
                label: "NO SCAN FLAG · LIGHT NUMERIC",
                headline: "Numeric content is below the configured review threshold.",
                detail: "BIFROST counted \(numbers.count) numeric patterns; the unsourced-number review threshold is 6.",
                action: "No configured review pattern matched. Check exact figures before relying on them.",
                inputHash: inputHash
            )
        }

        return verdict(
            .noScanFlag,
            category: "clean_basic_check",
            label: "NO SCAN FLAG · BASIC",
            headline: "No configured review pattern matched the scanned text.",
            detail: "This local text-pattern scan does not establish factual accuracy or suitability.",
            action: "Check relevant sources and domain requirements before relying on the answer.",
            inputHash: inputHash
        )
    }

    private func verdict(
        _ display: BIFROSTAnswerVerdict.Display,
        category: String,
        label: String,
        headline: String,
        detail: String,
        action: String,
        inputHash: String
    ) -> BIFROSTAnswerVerdict {
        BIFROSTAnswerVerdict(
            display: display,
            category: category,
            label: label,
            headline: headline,
            detail: detail,
            action: action,
            inputHash: inputHash
        )
    }

    private func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func visibleSourceMarker(in text: String) -> Bool {
        text.range(of: #"https?://"#, options: .regularExpression) != nil ||
            text.range(of: #"\bdoi:\s*\S+"#, options: [.regularExpression, .caseInsensitive]) != nil ||
            text.range(of: #"\barxiv:\s*\S+"#, options: [.regularExpression, .caseInsensitive]) != nil ||
            text.range(of: #"\b(sec\.gov|pubmed|fda|edgar)\b"#, options: [.regularExpression, .caseInsensitive]) != nil ||
            text.range(of: #"\[\d+\]"#, options: .regularExpression) != nil ||
            text.range(of: #"\bsource:\s+\S+"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func hasCodeEdgeCase(in text: String) -> Bool {
        let hasCode = text.contains("```") ||
            text.range(of: #"\b(function|const|let|var|def|return)\b"#, options: .regularExpression) != nil
        let hasDirectAccess = text.range(of: #"\[[0-9]+\]\.[A-Za-z_]"#, options: .regularExpression) != nil ||
            text.range(of: #"\.[A-Za-z_]+\("#, options: .regularExpression) != nil
        let hasGuard = text.range(of: #"\b(if|guard)\b|(\?\.|\?\?)|\.length|\.isEmpty|nil|null|undefined"#, options: [.regularExpression, .caseInsensitive]) != nil
        return hasCode && hasDirectAccess && hasGuard == false
    }

    private func hasContradiction(in lower: String) -> Bool {
        (lower.contains("approved") && lower.contains("rejected")) ||
            (lower.contains("true") && lower.contains("false")) ||
            (lower.contains("o(1)") && lower.contains("o(n)"))
    }

    private func isCurrentClaim(_ lower: String) -> Bool {
        lower.range(of: #"\b(today|latest|currently|current|recent|now|as of 20\d{2})\b"#, options: .regularExpression) != nil
    }

    private func overconfidenceCount(in lower: String) -> Int {
        matches(#"\b(always|never|guaranteed|definitely|certainly|undeniably|100%|impossible|cannot fail)\b"#, in: lower).count
    }

    private func looksLikeJudgmentCall(_ lower: String) -> Bool {
        lower.range(of: #"\b(best|worst|good|bad|better|should|moral|ethical|political party)\b"#, options: .regularExpression) != nil &&
            lower.range(of: #"\b(depends|trade[- ]?off|critics|supporters|context)\b"#, options: .regularExpression) != nil
    }

    private func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let range = Range(match.range, in: text) else {
                return nil
            }
            return String(text[range])
        }
    }

    private var numberPattern: String {
        #"(?<![A-Za-z])\$?\d+(?:\.\d+)?\s?(?:%|B|M|K|T|bn|mm|million|billion|trillion|x|×)?"#
    }

    private func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
