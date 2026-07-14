import Foundation
import HEIMDALLKit
import LUNAStore
import Testing
@testable import BIFROSTKit

@MainActor
@Test func noObjectionNavigationAllowsAndWritesRow() throws {
    let gateway = try makeGateway()
    let result = try gateway.evaluate(context("https://example.com"))
    #expect(result.decision == .allow)
    #expect(result.evaluation.verdict.display == "NO_OBJECTION")
    #expect(result.auditRow.verdict.display == "NO_OBJECTION")
}

@MainActor
@Test func holdNavigationCancelsAndWritesRow() throws {
    let gateway = try makeGateway()
    let result = try gateway.evaluate(context("http://example.com"))
    #expect(result.decision == .cancel)
    #expect(result.evaluation.verdict.display == "HOLD")
    #expect(result.auditRow.verdict.display == "HOLD")
}

@MainActor
@Test func refuseNavigationCancelsAndWritesRow() throws {
    let gateway = try makeGateway()
    let result = try gateway.evaluate(context("https://evil.example.com"))
    #expect(result.decision == .cancel)
    #expect(result.evaluation.verdict.display == "REFUSE")
    #expect(result.auditRow.verdict.display == "REFUSE")
}

@MainActor
@Test func everyNavigationWritesALunaRow() throws {
    let store = try makeStore()
    let gateway = BIFROSTGateway(
        policy: .defaultV1,
        store: store,
        onHeldRequest: { _, _ in .userCancelled },
        onRefusedRequest: { _, _ in }
    )
    let urls = [
        "https://example.com",
        "http://example.com",
        "https://evil.example.com",
        "https://duckduckgo.com"
    ]
    for value in urls {
        _ = try gateway.evaluate(context(value))
    }
    let rows = try store.read()
    #expect(rows.count == urls.count)
    #expect(try store.verify().rowCount == urls.count)
}

@MainActor
@Test func userAffirmedHoldWritesSecondLunaRow() throws {
    let store = try makeStore()
    let gateway = BIFROSTGateway(
        policy: .defaultV1,
        store: store,
        onHeldRequest: { _, _ in .userCancelled },
        onRefusedRequest: { _, _ in }
    )
    let heldContext = context("http://example.com")

    let hold = try gateway.evaluate(heldContext)
    let affirmed = try gateway.recordUserAffirmedHold(heldContext)
    let rows = try store.read()

    #expect(hold.decision == .cancel)
    #expect(affirmed.decision == .allow)
    #expect(rows.count == 2)
    #expect(rows[0].verdict.display == "HOLD")
    #expect(rows[1].verdict.display == "ABSTAIN")
    #expect(rows[1].verdict.reason == "User affirmed a HOLD for this navigation one time.")
    #expect(try store.verify().rowCount == 2)
}

@MainActor
private func makeGateway() throws -> BIFROSTGateway {
    BIFROSTGateway(
        policy: .defaultV1,
        store: try makeStore(),
        onHeldRequest: { _, _ in .userCancelled },
        onRefusedRequest: { _, _ in }
    )
}

private func makeStore() throws -> LUNAStore {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "bifrost-gateway-\(UUID().uuidString)", directoryHint: .isDirectory)
        .appending(path: "luna.jsonl")
    return try LUNAStore(databaseURL: url)
}

private func context(_ value: String) -> NavigationContext {
    NavigationContext(url: URL(string: value)!, timestamp: Date(timeIntervalSince1970: 1))
}

private extension VerifyResult {
    var rowCount: Int {
        if case .ok(let rowCount, _) = self {
            return rowCount
        }
        return -1
    }
}
