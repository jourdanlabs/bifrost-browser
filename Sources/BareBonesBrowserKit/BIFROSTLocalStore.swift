//
//  BIFROSTLocalStore.swift
//  BIFROST
//
//  Created by JourdanLabs on 06/07/2026.
//  Portions derived from DuckDuckGo BareBonesBrowser under Apache-2.0.
//

import Foundation
import HEIMDALLKit

public struct BIFROSTBookmark: Sendable, Hashable, Codable, Identifiable {
    public let id: UUID
    public let title: String
    public let url: URL
    public let createdAt: Date

    public init(id: UUID = UUID(), title: String, url: URL, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.url = url
        self.createdAt = createdAt
    }
}

enum BIFROSTLocalStore {
    static func supportDirectory() throws -> URL {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = root.appendingPathComponent("BIFROST", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func ledgerURL() throws -> URL {
        try supportDirectory().appendingPathComponent("luna-ledger.jsonl")
    }

    static func bookmarksURL() throws -> URL {
        try supportDirectory().appendingPathComponent("bookmarks.json")
    }

    static func blocklistURL() throws -> URL {
        try supportDirectory().appendingPathComponent("blocklist.json")
    }

    static func exportsDirectory() throws -> URL {
        let directory = try supportDirectory().appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func readBookmarks() -> [BIFROSTBookmark] {
        do {
            let url = try bookmarksURL()
            guard FileManager.default.fileExists(atPath: url.path) else { return [] }
            return try decoder.decode([BIFROSTBookmark].self, from: Data(contentsOf: url))
                .sorted { $0.createdAt > $1.createdAt }
        } catch {
            return []
        }
    }

    static func saveBookmarks(_ bookmarks: [BIFROSTBookmark]) {
        do {
            let url = try bookmarksURL()
            try encoder.encode(bookmarks).write(to: url, options: [.atomic])
        } catch {
            return
        }
    }

    static func addBookmark(title: String, url: URL) -> [BIFROSTBookmark] {
        var bookmarks = readBookmarks()
        guard bookmarks.contains(where: { $0.url.absoluteString == url.absoluteString }) == false else {
            return bookmarks
        }
        bookmarks.insert(BIFROSTBookmark(title: title, url: url), at: 0)
        saveBookmarks(bookmarks)
        return bookmarks
    }

    static func readBlocklist() -> [String] {
        do {
            let url = try blocklistURL()
            guard FileManager.default.fileExists(atPath: url.path) else { return [] }
            return try decoder.decode([String].self, from: Data(contentsOf: url))
                .map(normalizedHost)
                .filter { $0.isEmpty == false }
                .uniqued()
        } catch {
            return []
        }
    }

    static func saveBlocklist(_ hosts: [String]) {
        do {
            let normalized = hosts
                .map(normalizedHost)
                .filter { $0.isEmpty == false }
                .uniqued()
            let url = try blocklistURL()
            try encoder.encode(normalized).write(to: url, options: [.atomic])
        } catch {
            return
        }
    }

    static func policy() -> Policy {
        let userHosts = readBlocklist()
        guard userHosts.isEmpty == false else {
            return .defaultV1
        }

        var rules = Policy.defaultV1.rules
        rules.append(
            PolicyRule(
                id: "rule.blocklist.user.local",
                description: "Destination matches a host on the local user blocklist.",
                weight: 0.90,
                action: .refuse,
                match: .hostIn(Set(userHosts))
            )
        )

        return Policy(
            id: Policy.defaultV1.id,
            version: Policy.defaultV1.version,
            rules: rules,
            abstainThreshold: Policy.defaultV1.abstainThreshold,
            signalThreshold: Policy.defaultV1.signalThreshold
        )
    }

    static func policySignature() -> String {
        readBlocklist().joined(separator: "|")
    }

    static func normalizedHost(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let url = URL(string: trimmed), let host = url.host() {
            return host.lowercased()
        }
        return trimmed
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .split(separator: "/")
            .first
            .map(String.init) ?? ""
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
