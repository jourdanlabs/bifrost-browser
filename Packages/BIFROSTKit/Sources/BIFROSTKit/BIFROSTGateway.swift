import Foundation
import HEIMDALLKit
import LUNAStore
@preconcurrency import WebKit

public enum HoldOutcome: Sendable, Hashable {
    case userAffirmed
    case userCancelled
}

public enum GatewayDecision: Sendable, Hashable {
    case allow
    case cancel
}

public struct GatewayResult: Sendable, Hashable {
    public let decision: GatewayDecision
    public let evaluation: EvaluationResult
    public let auditRow: AuditRow
}

@MainActor
public final class BIFROSTGateway: NSObject, WKNavigationDelegate {
    public typealias HoldHandler = @MainActor (NavigationContext, EvaluationResult) async -> HoldOutcome
    public typealias RefuseHandler = @MainActor (NavigationContext, EvaluationResult) -> Void

    private let policy: Policy
    private let evaluator: PolicyEvaluator
    private let store: LUNAStore
    private let onHeldRequest: HoldHandler
    private let onRefusedRequest: RefuseHandler
    private var resolvedRequests = Set<String>()

    public init(
        policy: Policy,
        store: LUNAStore,
        onHeldRequest: @escaping HoldHandler,
        onRefusedRequest: @escaping RefuseHandler
    ) {
        self.policy = policy
        self.evaluator = PolicyEvaluator(policy: policy)
        self.store = store
        self.onHeldRequest = onHeldRequest
        self.onRefusedRequest = onRefusedRequest
    }

    @discardableResult
    public func evaluate(_ context: NavigationContext) throws -> GatewayResult {
        let evaluation = evaluator.evaluate(context)
        let row = try store.append(
            AuditRowInput(
                timestamp: context.timestamp,
                context: context,
                verdict: evaluation.verdict,
                policyId: policy.id,
                policyVersion: policy.version,
                confidence: evaluation.confidence
            )
        )
        return GatewayResult(decision: Self.decision(for: evaluation.verdict), evaluation: evaluation, auditRow: row)
    }

    @discardableResult
    public func recordUserAffirmedHold(_ context: NavigationContext) throws -> GatewayResult {
        let evaluation = EvaluationResult(
            verdict: .abstain(reason: "User affirmed a HOLD for this navigation one time."),
            firedRules: [],
            rawScore: 0.0,
            confidence: 0.0
        )
        let row = try store.append(
            AuditRowInput(
                timestamp: Date(),
                context: context,
                verdict: evaluation.verdict,
                policyId: policy.id,
                policyVersion: policy.version,
                confidence: evaluation.confidence
            )
        )
        return GatewayResult(decision: .allow, evaluation: evaluation, auditRow: row)
    }

    public nonisolated func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        Task { @MainActor in
            let context = Self.context(from: navigationAction)
            let fingerprint = Self.fingerprint(context)
            if resolvedRequests.remove(fingerprint) != nil {
                do {
                    _ = try recordUserAffirmedHold(context)
                    decisionHandler(.allow)
                } catch {
                    decisionHandler(.cancel)
                }
                return
            }

            do {
                let result = try evaluate(context)
                switch result.evaluation.verdict {
                case .noObjection, .abstain:
                    decisionHandler(.allow)
                case .hold:
                    decisionHandler(.cancel)
                    let outcome = await onHeldRequest(context, result.evaluation)
                    if outcome == .userAffirmed {
                        resolvedRequests.insert(fingerprint)
                        webView.load(navigationAction.request)
                    }
                case .refuse:
                    decisionHandler(.cancel)
                    onRefusedRequest(context, result.evaluation)
                }
            } catch {
                decisionHandler(.cancel)
            }
        }
    }

    private static func decision(for verdict: Verdict) -> GatewayDecision {
        switch verdict {
        case .noObjection, .abstain:
            return .allow
        case .hold, .refuse:
            return .cancel
        }
    }

    private static func context(from action: WKNavigationAction) -> NavigationContext {
        NavigationContext(
            url: action.request.url ?? URL(string: "about:blank")!,
            initiator: nil,
            method: action.request.httpMethod ?? "GET",
            isMainFrame: action.targetFrame?.isMainFrame ?? true,
            hasFormSubmission: action.navigationType == .formSubmitted || action.navigationType == .formResubmitted,
            credentialFieldsPresent: false,
            timestamp: Date()
        )
    }

    private static func fingerprint(_ context: NavigationContext) -> String {
        "\(context.method)|\(context.url.absoluteString)|\(context.isMainFrame)"
    }
}
