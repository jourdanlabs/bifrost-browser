import Foundation
import Testing
@testable import HEIMDALLKit

@Test func verdictEnumHasNoApprovalPath() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sources = packageRoot.appending(path: "Sources/HEIMDALLKit").path
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/grep")
    process.arguments = ["-rn", "authorize", sources]
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus != 0)
}

@Test func emptyPolicyYieldsNoObjection() {
    let policy = Policy(id: "empty", version: "1.0.0", rules: [])
    let result = PolicyEvaluator(policy: policy).evaluate(context("https://example.com"))
    #expect(result.verdict == .noObjection)
}

@Test func httpURLYieldsHold() {
    let result = PolicyEvaluator(policy: .defaultV1).evaluate(context("http://example.com"))
    #expect(result.verdict.display == "HOLD")
    #expect(result.firedRules.map(\.id).contains("rule.scheme.http"))
}

@Test func crossOriginCredentialYieldsRefuse() {
    let result = PolicyEvaluator(policy: .defaultV1).evaluate(
        NavigationContext(
            url: URL(string: "https://login.bad.example")!,
            initiator: URL(string: "https://real.example")!,
            credentialFieldsPresent: true,
            timestamp: Date(timeIntervalSince1970: 1)
        )
    )
    #expect(result.verdict.display == "REFUSE")
}

@Test func underThresholdYieldsAbstain() {
    let policy = Policy(
        id: "low",
        version: "1.0.0",
        rules: [
            PolicyRule(
                id: "low.rule",
                description: "Low signal",
                weight: 0.10,
                action: .hold,
                match: .hostMatches("example.com")
            )
        ]
    )
    let result = PolicyEvaluator(policy: policy).evaluate(context("https://example.com"))
    #expect(result.verdict.display == "ABSTAIN")
}

@Test func evaluationIsDeterministic() {
    let evaluator = PolicyEvaluator(policy: .defaultV1)
    let request = context("http://example.com")
    let baseline = evaluator.evaluate(request)
    for _ in 0..<5 {
        let next = evaluator.evaluate(request)
        #expect(next.verdict == baseline.verdict)
        #expect(next.confidence == baseline.confidence)
    }
}

private func context(_ value: String) -> NavigationContext {
    NavigationContext(url: URL(string: value)!, timestamp: Date(timeIntervalSince1970: 1))
}
