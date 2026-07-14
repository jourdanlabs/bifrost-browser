import Foundation

public struct Policy: Sendable, Hashable, Codable {
    public let id: String
    public let version: String
    public let rules: [PolicyRule]
    public let abstainThreshold: Double
    public let signalThreshold: Double

    public init(
        id: String,
        version: String,
        rules: [PolicyRule],
        abstainThreshold: Double = 0.35,
        signalThreshold: Double = 0.50
    ) {
        self.id = id
        self.version = version
        self.rules = rules
        self.abstainThreshold = abstainThreshold
        self.signalThreshold = signalThreshold
    }

    public static let defaultV1 = Policy(
        id: "bifrost.default.v1",
        version: "1.0.0",
        rules: [
            PolicyRule(
                id: "rule.scheme.http",
                description: "Plain-text HTTP destination — credentials and content can be intercepted in transit.",
                weight: 0.45,
                action: .hold,
                match: .schemeNotIn(["https", "data", "about", "file"])
            ),
            PolicyRule(
                id: "rule.form.non-https",
                description: "Form submission to a non-HTTPS endpoint — submitted data would travel in plaintext.",
                weight: 0.70,
                action: .refuse,
                match: .formSubmitToNonHTTPS
            ),
            PolicyRule(
                id: "rule.cred.cross-origin",
                description: "A password field is being auto-filled across origins, a known credential-theft pattern.",
                weight: 0.80,
                action: .refuse,
                match: .crossOriginCredentialField
            ),
            PolicyRule(
                id: "rule.blocklist.user",
                description: "Destination matches an entry on the user's explicit blocklist.",
                weight: 0.90,
                action: .refuse,
                match: .hostIn(["evil.example.com"])
            )
        ]
    )
}

public struct PolicyRule: Sendable, Hashable, Codable {
    public let id: String
    public let description: String
    public let weight: Double
    public let action: PolicyAction
    public let match: MatchCriteria

    public init(id: String, description: String, weight: Double, action: PolicyAction, match: MatchCriteria) {
        self.id = id
        self.description = description
        self.weight = weight
        self.action = action
        self.match = match
    }
}

public enum PolicyAction: String, Sendable, Hashable, Codable {
    case noObjection
    case abstain
    case hold
    case refuse
}

public enum MatchCriteria: Sendable, Hashable, Codable {
    case hostMatches(String)
    case hostIn(Set<String>)
    case schemeNotIn(Set<String>)
    case formSubmitToNonHTTPS
    case crossOriginCredentialField

    private enum CodingKeys: String, CodingKey {
        case kind = "case"
        case value
    }

    public func matches(_ context: NavigationContext) -> Bool {
        switch self {
        case .hostMatches(let pattern):
            guard let host = context.url.host()?.lowercased() else { return false }
            return glob(pattern.lowercased(), matches: host)
        case .hostIn(let hosts):
            guard let host = context.url.host()?.lowercased() else { return false }
            return hosts.map { $0.lowercased() }.contains(host)
        case .schemeNotIn(let schemes):
            guard let scheme = context.url.scheme?.lowercased() else { return true }
            return !schemes.map { $0.lowercased() }.contains(scheme)
        case .formSubmitToNonHTTPS:
            return context.hasFormSubmission && context.url.scheme?.lowercased() != "https"
        case .crossOriginCredentialField:
            guard
                context.credentialFieldsPresent,
                let initiatorHost = context.initiator?.host()?.lowercased(),
                let destinationHost = context.url.host()?.lowercased()
            else {
                return false
            }
            return initiatorHost != destinationHost
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .hostMatches(let value):
            try container.encode("hostMatches", forKey: .kind)
            try container.encode(value, forKey: .value)
        case .hostIn(let value):
            try container.encode("hostIn", forKey: .kind)
            try container.encode(Array(value).sorted(), forKey: .value)
        case .schemeNotIn(let value):
            try container.encode("schemeNotIn", forKey: .kind)
            try container.encode(Array(value).sorted(), forKey: .value)
        case .formSubmitToNonHTTPS:
            try container.encode("formSubmitToNonHTTPS", forKey: .kind)
        case .crossOriginCredentialField:
            try container.encode("crossOriginCredentialField", forKey: .kind)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "hostMatches":
            self = .hostMatches(try container.decode(String.self, forKey: .value))
        case "hostIn":
            self = .hostIn(Set(try container.decode([String].self, forKey: .value)))
        case "schemeNotIn":
            self = .schemeNotIn(Set(try container.decode([String].self, forKey: .value)))
        case "formSubmitToNonHTTPS":
            self = .formSubmitToNonHTTPS
        case "crossOriginCredentialField":
            self = .crossOriginCredentialField
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unknown match criteria")
        }
    }

    private func glob(_ pattern: String, matches value: String) -> Bool {
        if pattern == value { return true }
        if pattern.hasPrefix("*.") {
            let suffix = String(pattern.dropFirst())
            return value.hasSuffix(suffix)
        }
        return false
    }
}
