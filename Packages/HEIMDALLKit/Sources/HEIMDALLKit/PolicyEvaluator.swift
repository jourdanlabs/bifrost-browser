import AURORAKit
import Foundation

public struct EvaluationResult: Sendable, Hashable, Codable {
    public let verdict: Verdict
    public let firedRules: [PolicyRule]
    public let rawScore: Double
    public let confidence: Double

    public init(verdict: Verdict, firedRules: [PolicyRule], rawScore: Double, confidence: Double) {
        self.verdict = verdict
        self.firedRules = firedRules
        self.rawScore = rawScore
        self.confidence = confidence
    }
}

public struct PolicyEvaluator: Sendable {
    public let policy: Policy
    public let calibration: AURORACalibration

    public init(policy: Policy, calibration: AURORACalibration = .init()) {
        self.policy = policy
        self.calibration = calibration
    }

    public func evaluate(_ context: NavigationContext) -> EvaluationResult {
        let firedRules = policy.rules.filter { $0.match.matches(context) }
        guard firedRules.isEmpty == false else {
            return EvaluationResult(verdict: .noObjection, firedRules: [], rawScore: 0.0, confidence: 0.0)
        }

        let rawScore = min(1.0, firedRules.reduce(0.0) { $0 + max(0.0, $1.weight) })
        let confidence = calibration.confidence(rawScore: rawScore)
        let primaryRule = firedRules.sorted { $0.weight > $1.weight }.first!

        if confidence < policy.abstainThreshold {
            return EvaluationResult(
                verdict: .abstain(reason: "Policy signal stayed below the abstain threshold."),
                firedRules: firedRules,
                rawScore: rawScore,
                confidence: confidence
            )
        }

        if firedRules.contains(where: { $0.action == .refuse }) && confidence >= policy.signalThreshold {
            return EvaluationResult(
                verdict: .refuse(reason: primaryRule.description, policyId: primaryRule.id, confidence: confidence),
                firedRules: firedRules,
                rawScore: rawScore,
                confidence: confidence
            )
        }

        if firedRules.contains(where: { $0.action == .hold }) {
            return EvaluationResult(
                verdict: .hold(reason: primaryRule.description, policyId: primaryRule.id, confidence: confidence),
                firedRules: firedRules,
                rawScore: rawScore,
                confidence: confidence
            )
        }

        return EvaluationResult(
            verdict: .abstain(reason: "Policy signal did not cross a blocking threshold."),
            firedRules: firedRules,
            rawScore: rawScore,
            confidence: confidence
        )
    }
}
