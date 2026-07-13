import BIFROSTKit
@testable import BareBonesBrowserKit
import Foundation
import HEIMDALLKit
import LUNAStore
import XCTest

@MainActor
final class BIFROSTBrowserStatusTests: XCTestCase {
    func testStatusMapsClearNavigation() throws {
        let result = try gateway().evaluate(
            NavigationContext(url: URL(string: "https://example.com")!)
        )

        let status = BIFROSTBrowserStatus(result: result)

        XCTAssertEqual(status.state, .noObjection)
        XCTAssertEqual(status.headline, "NO_OBJECTION")
        XCTAssertEqual(status.receiptHash?.count, 64)
    }

    func testStatusMapsHttpNavigationToHold() throws {
        let result = try gateway().evaluate(
            NavigationContext(url: URL(string: "http://example.com")!)
        )

        let status = BIFROSTBrowserStatus(result: result)

        XCTAssertEqual(status.state, .hold)
        XCTAssertEqual(status.headline, "HOLD")
        XCTAssertEqual(status.policyId, "rule.scheme.http")
        XCTAssertTrue(status.isIntervention)
    }

    func testStatusMapsUserBlocklistToRefuse() throws {
        let result = try gateway().evaluate(
            NavigationContext(url: URL(string: "https://evil.example.com")!)
        )

        let status = BIFROSTBrowserStatus(result: result)

        XCTAssertEqual(status.state, .refuse)
        XCTAssertEqual(status.headline, "REFUSE")
        XCTAssertEqual(status.policyId, "rule.blocklist.user")
        XCTAssertTrue(status.isIntervention)
    }

    func testBrowserSearchNormalizesPlainHost() {
        XCTAssertEqual(
            BareBonesBrowserView.normalizedURL(from: "chatgpt.com")?.absoluteString,
            "https://chatgpt.com"
        )
    }

    func testBrowserSearchNormalizesSearchTerms() {
        XCTAssertEqual(
            BareBonesBrowserView.normalizedURL(from: "best roofing quote")?.absoluteString,
            "https://duckduckgo.com/?q=best%20roofing%20quote"
        )
    }

    func testModelRunsHoldContinuationOnlyOnce() {
        let model = BIFROSTBrowserModel()
        var continueCount = 0
        model.publishHold(
            BIFROSTBrowserStatus(
                state: .hold,
                headline: "HOLD",
                reason: "test hold",
                policyId: "test",
                confidence: 0.5,
                receiptHash: "abc123"
            )
        ) {
            continueCount += 1
        }

        model.continueHeldNavigation()
        model.continueHeldNavigation()

        XCTAssertEqual(continueCount, 1)
        XCTAssertNil(model.intervention)
    }

    func testAnswerVerifierFlagsUnsourcedNumbers() throws {
        let verdict = try XCTUnwrap(
            BIFROSTAnswerVerifier().evaluate(
                "Revenue was $12.4B, EBITDA was $3.1B, margin was 25%, debt was $4.2B, cash was $900M, and capex was $1.2B."
            )
        )

        XCTAssertEqual(verdict.display, .review)
        XCTAssertEqual(verdict.category, "unsourced_numeric_claims")
        XCTAssertEqual(verdict.label, "REVIEW · DENSE NUMBERS")
        XCTAssertEqual(verdict.inputHash.count, 64)
    }

    func testAnswerVerifierReportsVisibleSourceMarkerWithoutApproval() throws {
        let verdict = try XCTUnwrap(
            BIFROSTAnswerVerifier().evaluate(
                "The claim cites a marker only. Source: https://not-a-real-source.invalid/report"
            )
        )

        XCTAssertEqual(verdict.display, .noScanFlag)
        XCTAssertEqual(verdict.category, "sourced_shape")
        XCTAssertEqual(verdict.label, "NO SCAN FLAG · SOURCE MARKER")
        XCTAssertEqual(
            verdict.detail,
            "BIFROST recognized source-like text but did not open, authenticate, or validate the source or its support for the claims."
        )
    }

    func testAnswerVerifierTreatsOpposingTermsAsPossibleContradiction() throws {
        let verdict = try XCTUnwrap(
            BIFROSTAnswerVerifier().evaluate(
                "The validator returns true for valid input and false for invalid input."
            )
        )

        XCTAssertEqual(verdict.display, .review)
        XCTAssertEqual(verdict.category, "internal_contradiction")
        XCTAssertEqual(verdict.label, "REVIEW · POSSIBLE CONTRADICTION")
        XCTAssertEqual(
            verdict.detail,
            "BIFROST matched opposing terms in the same answer; it did not resolve their meaning or context."
        )
    }

    func testAnswerVerifierReportsSmallNumericAnswerWithoutApproval() throws {
        let verdict = try XCTUnwrap(
            BIFROSTAnswerVerifier().evaluate("The model uses 3 inputs and returns 2 values after validation.")
        )

        XCTAssertEqual(verdict.display, .noScanFlag)
        XCTAssertEqual(verdict.category, "light_numeric_check")
        XCTAssertEqual(verdict.label, "NO SCAN FLAG · LIGHT NUMERIC")
        XCTAssertEqual(
            verdict.action,
            "No configured review pattern matched. Check exact figures before relying on them."
        )
    }

    func testAnswerVerifierBasicCheckDoesNotClaimApproval() throws {
        let verdict = try XCTUnwrap(
            BIFROSTAnswerVerifier().evaluate(
                "The model normalizes each label after checking the input against the configured rules."
            )
        )

        XCTAssertEqual(verdict.display, .noScanFlag)
        XCTAssertEqual(verdict.category, "clean_basic_check")
        XCTAssertEqual(verdict.label, "NO SCAN FLAG · BASIC")
        XCTAssertEqual(
            verdict.detail,
            "This local text-pattern scan does not establish factual accuracy or suitability."
        )
    }

    func testAnswerVerifierFindsUnsupportedConfidence() throws {
        let verdict = try XCTUnwrap(
            BIFROSTAnswerVerifier().evaluate("This will definitely always work for every customer and is guaranteed to be correct.")
        )

        XCTAssertEqual(verdict.display, .review)
        XCTAssertEqual(verdict.category, "unsupported_confidence")
        XCTAssertEqual(verdict.label, "REVIEW · CERTAINTY LANGUAGE")
    }

    func testAnswerScanVocabularyHasNoAuthorizationPath() {
        XCTAssertEqual(
            Set(BIFROSTAnswerVerdict.Display.allCases.map(\.rawValue)),
            Set(["NO SCAN FLAG", "REVIEW"])
        )
    }

    func testEveryAnswerScanBranchUsesCalibratedCopy() throws {
        let samples: [(category: String, text: String)] = [
            (
                "code_edge_case",
                "Use this snippet: ```js const value = rows[0].name; return value.toUpperCase(); ```"
            ),
            (
                "internal_contradiction",
                "The validator returns true for valid input and false for invalid input."
            ),
            (
                "current_claim_no_source",
                "The latest release currently supports the standard workflow for this product."
            ),
            (
                "unsourced_numeric_claims",
                "Revenue was $12.4B, EBITDA was $3.1B, margin was 25%, debt was $4.2B, cash was $900M, and capex was $1.2B."
            ),
            (
                "unsupported_confidence",
                "This will definitely always work for every customer and is guaranteed to be correct."
            ),
            (
                "judgment_call",
                "The best policy depends on context and includes ethical trade-offs for each community."
            ),
            (
                "sourced_shape",
                "The claim cites a marker only. Source: https://not-a-real-source.invalid/report"
            ),
            (
                "light_numeric_check",
                "The model uses 3 inputs and returns 2 values after validation."
            ),
            (
                "clean_basic_check",
                "The model normalizes each label after checking the input against configured rules."
            ),
        ]
        let forbiddenPublicCopy = #"\b(approve|approved|approval|safe|safety|unsafe|certify|certified|cleared|trust|trusted|reject|rejected|rejection|verified|verification)\b|high-risk|blocking signal|source trail"#
        var observedCategories = Set<String>()

        for sample in samples {
            let verdict = try XCTUnwrap(
                BIFROSTAnswerVerifier().evaluate(sample.text),
                "Expected answer-scan result for \(sample.category)"
            )
            XCTAssertEqual(verdict.category, sample.category)
            observedCategories.insert(verdict.category)

            let publicCopy = [
                verdict.display.rawValue,
                verdict.label,
                verdict.headline,
                verdict.detail,
                verdict.action,
            ].joined(separator: " ")
            XCTAssertNil(
                publicCopy.range(
                    of: forbiddenPublicCopy,
                    options: [.regularExpression, .caseInsensitive]
                ),
                "Uncalibrated copy in \(sample.category): \(publicCopy)"
            )
        }

        XCTAssertEqual(observedCategories, Set(samples.map { $0.category }))
    }

    func testAnswerObserverCoversGoogleGeminiSurface() {
        let script = BIFROSTAnswerObserverScript.source

        XCTAssertTrue(script.contains("google\\.com"))
        XCTAssertTrue(script.contains("about gemini"))
        XCTAssertTrue(script.contains("message-content"))
        XCTAssertTrue(script.contains("scanPending"))
        XCTAssertTrue(BIFROSTAnswerObserverScript.collectOnceSource.contains("[data-bifrost-answer]"))
        XCTAssertTrue(BIFROSTAnswerObserverScript.collectOnceSource.contains("chatgpt\\.com"))
        XCTAssertTrue(BIFROSTAnswerObserverScript.collectOnceSource.contains("isLikelyLLMSurface"))
    }

    func testClearingAnswerScanCancelsDelayedVerdict() async throws {
        let model = BIFROSTBrowserModel()
        let verdict = try XCTUnwrap(
            BIFROSTAnswerVerifier().evaluate(
                "Revenue was $12.4B, EBITDA was $3.1B, margin was 25%, debt was $4.2B, cash was $900M, and capex was $1.2B."
            )
        )

        model.beginAnswerScan()
        model.publishAnswerVerdict(verdict)
        XCTAssertTrue(model.answerScanning)

        model.clearAnswerVerdict()
        try await Task.sleep(nanoseconds: 600_000_000)

        XCTAssertFalse(model.answerScanning)
        XCTAssertNil(model.answerVerdict)
    }

    func testLocalStoreNormalizesBlocklistHosts() {
        XCTAssertEqual(BIFROSTLocalStore.normalizedHost("https://Example.com/path?q=1"), "example.com")
        XCTAssertEqual(BIFROSTLocalStore.normalizedHost("HTTP://Sub.Example.com"), "sub.example.com")
    }

    private func gateway() throws -> BIFROSTGateway {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = try LUNAStore(databaseURL: directory.appendingPathComponent("luna.jsonl"))
        return BIFROSTGateway(
            policy: .defaultV1,
            store: store,
            onHeldRequest: { _, _ in .userCancelled },
            onRefusedRequest: { _, _ in }
        )
    }
}
