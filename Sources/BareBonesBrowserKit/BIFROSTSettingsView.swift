//
//  BIFROSTSettingsView.swift
//  BIFROST
//
//  Created by JourdanLabs on 06/07/2026.
//  Portions derived from DuckDuckGo BareBonesBrowser under Apache-2.0.
//

import Foundation
import HEIMDALLKit
import LUNAStore
import SwiftUI

private enum BIFROSTInspectorDesign {
    static let background = Color(red: 0.984, green: 0.985, blue: 0.988)
    static let surface = Color.white
    static let border = Color(red: 0.882, green: 0.890, blue: 0.912)
    static let text = Color(red: 0.125, green: 0.114, blue: 0.145)
    static let mutedText = Color(red: 0.430, green: 0.410, blue: 0.485)
    static let purple = Color(red: 0.419, green: 0.129, blue: 0.659)
}

struct BIFROSTSettingsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case policy = "Policy"
        case ledger = "Ledger"
        case blocklist = "Blocklist"

        var id: String { rawValue }
    }

    @State private var selectedSection: Section = .policy
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("BIFROST Inspector")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(BIFROSTInspectorDesign.text)
                    Text("Policy, receipts, and local blocklist.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(BIFROSTInspectorDesign.mutedText)
                }

                Picker("Settings", selection: $selectedSection) {
                    ForEach(Section.allCases) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .tint(BIFROSTInspectorDesign.purple)
                .frame(width: 320)

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.vertical, 14)
            .background(BIFROSTInspectorDesign.surface)

            Rectangle()
                .fill(BIFROSTInspectorDesign.border)
                .frame(height: 1)

            Group {
                switch selectedSection {
                case .policy:
                    BIFROSTPolicySettingsView()
                case .ledger:
                    BIFROSTLedgerSettingsView()
                case .blocklist:
                    BIFROSTBlocklistSettingsView()
                }
            }
            .background(BIFROSTInspectorDesign.background)
        }
        .background(BIFROSTInspectorDesign.background)
        .frame(minWidth: 620, idealWidth: 760, minHeight: 520, idealHeight: 640)
    }
}

private struct BIFROSTPolicySettingsView: View {
    private let policy = BIFROSTLocalStore.policy()

    var body: some View {
        List(policy.rules, id: \.id) { rule in
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                    Text(rule.description)
                        .foregroundStyle(.primary)
                    BIFROSTJSONBox(text: ruleJSON(rule))
                }
                .padding(.vertical, 8)
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(rule.id)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(rule.description)
                            .lineLimit(2)
                    }
                    Spacer()
                    Text(String(format: "%.2f", rule.weight))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(rule.action.rawValue.uppercased())
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(actionColor(rule.action).opacity(0.12))
                        .foregroundStyle(actionColor(rule.action))
                        .clipShape(Capsule())
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(BIFROSTInspectorDesign.background)
    }

    private func actionColor(_ action: PolicyAction) -> Color {
        switch action {
        case .noObjection, .abstain:
            return Color(red: 0.10, green: 0.48, blue: 0.31)
        case .hold:
            return Color(red: 0.74, green: 0.45, blue: 0.12)
        case .refuse:
            return Color(red: 0.70, green: 0.16, blue: 0.20)
        }
    }

    private func ruleJSON(_ rule: PolicyRule) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard
            let data = try? encoder.encode(rule),
            let text = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return text
    }
}

private struct BIFROSTLedgerSettingsView: View {
    @State private var rows: [AuditRow] = []
    @State private var verification: String = "Not checked"
    @State private var exportPath: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Verify chain", action: verify)
                    .buttonStyle(.bordered)
                Button("Export...", action: export)
                    .buttonStyle(.bordered)
                Spacer()
                Text("\(rows.count) rows")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding([.horizontal, .top])

            Text(verification)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            if let exportPath {
                Text("Exported \(exportPath)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            List(rows.reversed(), id: \.id) { row in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(verdictLabel(row.verdict))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(verdictColor(row.verdict))
                        Spacer()
                        Text(String(format: "%.2f", row.confidence))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Text(row.context.url.absoluteString)
                        .lineLimit(1)
                    Text(String(row.rowHash.prefix(20)))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .scrollContentBackground(.hidden)
        }
        .background(BIFROSTInspectorDesign.background)
        .onAppear(perform: load)
    }

    private func load() {
        do {
            let store = try LUNAStore(databaseURL: BIFROSTLocalStore.ledgerURL())
            rows = Array(try store.read().suffix(100))
        } catch {
            rows = []
            verification = "Ledger unavailable"
        }
    }

    private func verify() {
        do {
            let store = try LUNAStore(databaseURL: BIFROSTLocalStore.ledgerURL())
            switch try store.verify() {
            case .ok(let rowCount, let headHash):
                verification = "OK · \(rowCount) rows · head \(String(headHash.prefix(20)))"
            case .tampered(let index, _, _):
                verification = "TAMPERED · row \(index)"
            }
            load()
        } catch {
            verification = "Verify failed"
        }
    }

    private func export() {
        do {
            let store = try LUNAStore(databaseURL: BIFROSTLocalStore.ledgerURL())
            let stamp = ISO8601DateFormatter()
                .string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let url = try BIFROSTLocalStore.exportsDirectory()
                .appendingPathComponent("bifrost-luna-\(stamp).jsonl")
            try store.exportJSONL(to: url)
            exportPath = url.path
            load()
        } catch {
            exportPath = "failed"
        }
    }

    private func verdictLabel(_ verdict: Verdict) -> String {
        switch verdict {
        case .noObjection:
            return "NO_OBJECTION"
        case .abstain:
            return "ABSTAIN"
        case .hold:
            return "HOLD"
        case .refuse:
            return "REFUSE"
        }
    }

    private func verdictColor(_ verdict: Verdict) -> Color {
        switch verdict {
        case .noObjection, .abstain:
            return Color(red: 0.10, green: 0.48, blue: 0.31)
        case .hold:
            return Color(red: 0.74, green: 0.45, blue: 0.12)
        case .refuse:
            return Color(red: 0.70, green: 0.16, blue: 0.20)
        }
    }
}

private struct BIFROSTBlocklistSettingsView: View {
    @State private var hosts = BIFROSTLocalStore.readBlocklist()
    @State private var newHost = ""

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                TextField("example.com", text: $newHost)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add", action: add)
                    .buttonStyle(.bordered)
            }
            .padding([.horizontal, .top])

            List {
                ForEach(hosts, id: \.self) { host in
                    HStack {
                        Text(host)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                        Spacer()
                        Button {
                            hosts.removeAll { $0 == host }
                            BIFROSTLocalStore.saveBlocklist(hosts)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .background(BIFROSTInspectorDesign.background)
    }

    private func add() {
        let host = BIFROSTLocalStore.normalizedHost(newHost)
        guard host.isEmpty == false else { return }
        hosts.append(host)
        hosts = hosts.uniqued()
        BIFROSTLocalStore.saveBlocklist(hosts)
        newHost = ""
    }
}

private struct BIFROSTJSONBox: View {
    let text: String

    var body: some View {
        ScrollView(.horizontal) {
            Text(text)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .background(Color.secondary.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(BIFROSTInspectorDesign.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
