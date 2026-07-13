//
//  BIFROSTBrowserStatus.swift
//  BIFROST
//
//  Created by JourdanLabs on 06/07/2026.
//  Portions derived from DuckDuckGo BareBonesBrowser under Apache-2.0.
//

import BIFROSTKit
import Combine
import Foundation
import HEIMDALLKit

public struct BIFROSTBrowserStatus: Sendable, Equatable {
    public enum State: String, Sendable {
        case idle
        case noObjection
        case abstain
        case hold
        case refuse
    }

    public let state: State
    public let headline: String
    public let reason: String
    public let policyId: String?
    public let confidence: Double?
    public let receiptHash: String?

    public static let idle = BIFROSTBrowserStatus(
        state: .idle,
        headline: "BIFROST idle",
        reason: "No navigation has been evaluated yet.",
        policyId: nil,
        confidence: nil,
        receiptHash: nil
    )

    public init(
        state: State,
        headline: String,
        reason: String,
        policyId: String?,
        confidence: Double?,
        receiptHash: String?
    ) {
        self.state = state
        self.headline = headline
        self.reason = reason
        self.policyId = policyId
        self.confidence = confidence
        self.receiptHash = receiptHash
    }

    public init(result: GatewayResult) {
        let verdict = result.evaluation.verdict
        let state: State
        let headline: String
        let policyId: String?

        switch verdict {
        case .noObjection:
            state = .noObjection
            headline = "NO_OBJECTION"
            policyId = nil
        case .abstain:
            state = .abstain
            headline = "ABSTAIN"
            policyId = nil
        case .hold(_, let ruleId, _):
            state = .hold
            headline = "HOLD"
            policyId = ruleId
        case .refuse(_, let ruleId, _):
            state = .refuse
            headline = "REFUSE"
            policyId = ruleId
        }

        self.init(
            state: state,
            headline: headline,
            reason: verdict.reason,
            policyId: policyId,
            confidence: result.evaluation.confidence,
            receiptHash: result.auditRow.rowHash
        )
    }

    public var isIntervention: Bool {
        state == .hold || state == .refuse
    }
}

@MainActor
public final class BIFROSTBrowserModel: ObservableObject {
    @Published public private(set) var status: BIFROSTBrowserStatus
    @Published public private(set) var intervention: BIFROSTBrowserStatus?
    @Published public private(set) var answerVerdict: BIFROSTAnswerVerdict?
    @Published public private(set) var answerScanning: Bool = false
    private var continueAction: (() -> Void)?
    private var scanStartedAt: Date?
    private var pendingAnswerVerdictTask: Task<Void, Never>?
    private var answerGeneration: UInt64 = 0
    /// Minimum time the scan state stays visible before a verdict replaces it.
    /// Perception pacing only — evaluation itself is never delayed or altered.
    private static let minimumScanDisplay: TimeInterval = 0.45

    public init(status: BIFROSTBrowserStatus = .idle) {
        self.status = status
        self.intervention = status.isIntervention ? status : nil
    }

    public func publish(_ status: BIFROSTBrowserStatus) {
        self.status = status
        continueAction = nil
        if status.isIntervention {
            intervention = status
        }
    }

    public func publishHold(_ status: BIFROSTBrowserStatus, continueAction: @escaping () -> Void) {
        self.status = status
        self.continueAction = continueAction
        intervention = status
    }

    public func dismissIntervention() {
        intervention = nil
        continueAction = nil
    }

    public func beginAnswerScan() {
        answerGeneration &+= 1
        pendingAnswerVerdictTask?.cancel()
        pendingAnswerVerdictTask = nil
        answerVerdict = nil
        if !answerScanning {
            answerScanning = true
            scanStartedAt = Date()
        }
    }

    public func publishAnswerVerdict(_ verdict: BIFROSTAnswerVerdict) {
        pendingAnswerVerdictTask?.cancel()
        pendingAnswerVerdictTask = nil
        let elapsed = scanStartedAt.map { Date().timeIntervalSince($0) } ?? Self.minimumScanDisplay
        let remaining = Self.minimumScanDisplay - elapsed
        if answerScanning, remaining > 0 {
            let generation = answerGeneration
            pendingAnswerVerdictTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                guard
                    Task.isCancelled == false,
                    let self,
                    self.answerGeneration == generation
                else {
                    return
                }
                self.answerScanning = false
                self.scanStartedAt = nil
                self.answerVerdict = verdict
                self.pendingAnswerVerdictTask = nil
            }
        } else {
            answerScanning = false
            scanStartedAt = nil
            answerVerdict = verdict
        }
    }

    public func clearAnswerVerdict() {
        answerGeneration &+= 1
        pendingAnswerVerdictTask?.cancel()
        pendingAnswerVerdictTask = nil
        answerVerdict = nil
        answerScanning = false
        scanStartedAt = nil
    }

    public func continueHeldNavigation() {
        let action = continueAction
        intervention = nil
        continueAction = nil
        action?()
    }
}
