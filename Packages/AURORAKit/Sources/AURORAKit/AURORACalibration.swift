import Foundation

public struct AURORACalibration: Sendable, Hashable {
    public let midpoint: Double
    public let steepness: Double

    public init(midpoint: Double = 0.50, steepness: Double = 8.0) {
        self.midpoint = midpoint
        self.steepness = steepness
    }

    public func confidence(rawScore: Double) -> Double {
        let clamped = min(1.0, max(0.0, rawScore))
        return 1.0 / (1.0 + exp(-steepness * (clamped - midpoint)))
    }
}
