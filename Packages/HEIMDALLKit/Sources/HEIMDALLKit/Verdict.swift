import Foundation

public enum Verdict: Sendable, Hashable, Codable {
    case noObjection
    case abstain(reason: String)
    case hold(reason: String, policyId: String, confidence: Double)
    case refuse(reason: String, policyId: String, confidence: Double)

    public var display: String {
        switch self {
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

    public var reason: String {
        switch self {
        case .noObjection:
            return "No policy rule fired."
        case .abstain(let reason):
            return reason
        case .hold(let reason, _, _):
            return reason
        case .refuse(let reason, _, _):
            return reason
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case reason
        case policyId
        case confidence
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(display, forKey: .kind)
        try container.encode(reason, forKey: .reason)
        switch self {
        case .hold(_, let policyId, let confidence), .refuse(_, let policyId, let confidence):
            try container.encode(policyId, forKey: .policyId)
            try container.encode(confidence, forKey: .confidence)
        case .noObjection, .abstain:
            break
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        let reason = try container.decodeIfPresent(String.self, forKey: .reason) ?? ""
        switch kind {
        case "NO_OBJECTION":
            self = .noObjection
        case "ABSTAIN":
            self = .abstain(reason: reason)
        case "HOLD":
            self = .hold(
                reason: reason,
                policyId: try container.decode(String.self, forKey: .policyId),
                confidence: try container.decode(Double.self, forKey: .confidence)
            )
        case "REFUSE":
            self = .refuse(
                reason: reason,
                policyId: try container.decode(String.self, forKey: .policyId),
                confidence: try container.decode(Double.self, forKey: .confidence)
            )
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unknown verdict kind")
        }
    }
}
