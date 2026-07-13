import Foundation

public struct NavigationContext: Sendable, Hashable, Codable {
    public let url: URL
    public let initiator: URL?
    public let method: String
    public let isMainFrame: Bool
    public let hasFormSubmission: Bool
    public let credentialFieldsPresent: Bool
    public let timestamp: Date

    public init(
        url: URL,
        initiator: URL? = nil,
        method: String = "GET",
        isMainFrame: Bool = true,
        hasFormSubmission: Bool = false,
        credentialFieldsPresent: Bool = false,
        timestamp: Date = Date()
    ) {
        self.url = url
        self.initiator = initiator
        self.method = method
        self.isMainFrame = isMainFrame
        self.hasFormSubmission = hasFormSubmission
        self.credentialFieldsPresent = credentialFieldsPresent
        self.timestamp = timestamp
    }
}
