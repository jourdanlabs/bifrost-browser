import CryptoKit
import Foundation
import HEIMDALLKit

public struct AuditRowInput: Sendable, Hashable, Codable {
    public let id: UUID
    public let timestamp: Date
    public let context: NavigationContext
    public let verdict: Verdict
    public let policyId: String
    public let policyVersion: String
    public let confidence: Double

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        context: NavigationContext,
        verdict: Verdict,
        policyId: String,
        policyVersion: String,
        confidence: Double
    ) {
        self.id = id
        self.timestamp = timestamp
        self.context = context
        self.verdict = verdict
        self.policyId = policyId
        self.policyVersion = policyVersion
        self.confidence = confidence
    }
}

public struct AuditRow: Sendable, Hashable, Codable {
    public let id: UUID
    public let timestamp: Date
    public let context: NavigationContext
    public let verdict: Verdict
    public let policyId: String
    public let policyVersion: String
    public let confidence: Double
    public let previousHash: String
    public let rowHash: String
}

public enum VerifyResult: Sendable, Hashable {
    case ok(rowCount: Int, headHash: String)
    case tampered(atIndex: Int, expectedHash: String, foundHash: String)
}

public final class LUNAStore {
    public static let genesisHash = sha256Hex(Data("BIFROST-LUNA-GENESIS".utf8))

    private let ledgerURL: URL
    private let fileManager: FileManager

    public init(databaseURL: URL, fileManager: FileManager = .default) throws {
        self.ledgerURL = databaseURL
        self.fileManager = fileManager
        let directory = databaseURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: databaseURL.path) == false {
            try Data().write(to: databaseURL)
        }
    }

    public func append(_ input: AuditRowInput) throws -> AuditRow {
        let rows = try read()
        let previousHash = rows.last?.rowHash ?? Self.genesisHash
        let payload = RowPayload(input)
        let payloadData = try Self.canonicalEncoder.encode(payload)
        let rowHash = Self.hash(previousHash: previousHash, payloadData: payloadData)
        let row = AuditRow(
            id: input.id,
            timestamp: input.timestamp,
            context: input.context,
            verdict: input.verdict,
            policyId: input.policyId,
            policyVersion: input.policyVersion,
            confidence: input.confidence,
            previousHash: previousHash,
            rowHash: rowHash
        )
        var data = try Data(contentsOf: ledgerURL)
        if data.isEmpty == false && data.last != 10 {
            data.append(10)
        }
        data.append(try Self.canonicalEncoder.encode(row))
        data.append(10)
        try data.write(to: ledgerURL, options: [.atomic])
        return row
    }

    public func read(limit: Int = .max, offset: Int = 0) throws -> [AuditRow] {
        let all = try read()
        guard offset < all.count else { return [] }
        return Array(all.dropFirst(offset).prefix(limit))
    }

    public func verify() throws -> VerifyResult {
        let rows = try read()
        var expectedPrevious = Self.genesisHash

        for (index, row) in rows.enumerated() {
            guard row.previousHash == expectedPrevious else {
                return .tampered(atIndex: index, expectedHash: expectedPrevious, foundHash: row.previousHash)
            }

            let payload = RowPayload(row)
            let payloadData = try Self.canonicalEncoder.encode(payload)
            let expectedHash = Self.hash(previousHash: row.previousHash, payloadData: payloadData)
            guard row.rowHash == expectedHash else {
                return .tampered(atIndex: index, expectedHash: expectedHash, foundHash: row.rowHash)
            }

            expectedPrevious = row.rowHash
        }

        return .ok(rowCount: rows.count, headHash: expectedPrevious)
    }

    public func exportJSONL(to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try fileManager.copyItem(at: ledgerURL, to: url)
    }

    private func read() throws -> [AuditRow] {
        let data = try Data(contentsOf: ledgerURL)
        guard data.isEmpty == false else { return [] }
        let text = String(decoding: data, as: UTF8.self)
        return try text
            .split(separator: "\n")
            .map { line in
                try Self.canonicalDecoder.decode(AuditRow.self, from: Data(line.utf8))
            }
    }

    private static func hash(previousHash: String, payloadData: Data) -> String {
        var data = Data(previousHash.utf8)
        data.append(payloadData)
        return sha256Hex(data)
    }

    private static let canonicalEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let canonicalDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private struct RowPayload: Codable {
    let id: UUID
    let timestamp: Date
    let context: NavigationContext
    let verdict: Verdict
    let policyId: String
    let policyVersion: String
    let confidence: Double

    init(_ input: AuditRowInput) {
        self.id = input.id
        self.timestamp = input.timestamp
        self.context = input.context
        self.verdict = input.verdict
        self.policyId = input.policyId
        self.policyVersion = input.policyVersion
        self.confidence = input.confidence
    }

    init(_ row: AuditRow) {
        self.id = row.id
        self.timestamp = row.timestamp
        self.context = row.context
        self.verdict = row.verdict
        self.policyId = row.policyId
        self.policyVersion = row.policyVersion
        self.confidence = row.confidence
    }
}

private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
