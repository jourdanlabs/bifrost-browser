import Foundation
import HEIMDALLKit
import Testing
@testable import LUNAStore

@Test func genesisHashIsConstant() throws {
    let store = try makeStore()
    let row = try store.append(rowInput(0))
    #expect(row.previousHash == LUNAStore.genesisHash)
}

@Test func appendRowsThenVerifyOk() throws {
    let store = try makeStore()
    for index in 0..<100 {
        _ = try store.append(rowInput(index))
    }
    let result = try store.verify()
    guard case .ok(let rowCount, let headHash) = result else {
        Issue.record("Expected clean chain")
        return
    }
    #expect(rowCount == 100)
    #expect(headHash.isEmpty == false)
}

@Test func tamperDetectionNamesRow() throws {
    let (store, url) = try makeStoreWithURL()
    for index in 0..<10 {
        _ = try store.append(rowInput(index))
    }

    var lines = String(decoding: try Data(contentsOf: url), as: UTF8.self).split(separator: "\n").map(String.init)
    lines[5] = lines[5].replacingOccurrences(of: "https:\\/\\/example.com\\/5", with: "https:\\/\\/tampered.example\\/5")
    try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)

    let result = try store.verify()
    guard case .tampered(let index, _, _) = result else {
        Issue.record("Expected tamper report")
        return
    }
    #expect(index == 5)
}

@Test func exportRoundtripPreservesRows() throws {
    let store = try makeStore()
    for index in 0..<50 {
        _ = try store.append(rowInput(index))
    }
    let exportURL = temporaryURL().appending(path: "export.jsonl")
    try store.exportJSONL(to: exportURL)
    let exported = String(decoding: try Data(contentsOf: exportURL), as: UTF8.self)
    #expect(exported.split(separator: "\n").count == 50)
}

@Test func deterministicHeadHash() throws {
    let first = try makeStore()
    let second = try makeStore()
    for index in 0..<12 {
        _ = try first.append(rowInput(index))
        _ = try second.append(rowInput(index))
    }
    let firstResult = try first.verify()
    let secondResult = try second.verify()
    #expect(firstResult == secondResult)
}

private func makeStore() throws -> LUNAStore {
    try makeStoreWithURL().store
}

private func makeStoreWithURL() throws -> (store: LUNAStore, url: URL) {
    let url = temporaryURL().appending(path: "luna.jsonl")
    return (try LUNAStore(databaseURL: url), url)
}

private func temporaryURL() -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: "bifrost-luna-\(UUID().uuidString)", directoryHint: .isDirectory)
}

private func rowInput(_ index: Int) -> AuditRowInput {
    AuditRowInput(
        id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!,
        timestamp: Date(timeIntervalSince1970: Double(index)),
        context: NavigationContext(
            url: URL(string: "https://example.com/\(index)")!,
            timestamp: Date(timeIntervalSince1970: Double(index))
        ),
        verdict: .noObjection,
        policyId: "bifrost.default.v1",
        policyVersion: "1.0.0",
        confidence: 0.0
    )
}
