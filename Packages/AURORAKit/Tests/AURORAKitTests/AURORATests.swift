import Testing
@testable import AURORAKit

@Test func calibrationAnchorsMatchSpec() {
    let aurora = AURORACalibration()
    #expect(abs(aurora.confidence(rawScore: 0.0) - 0.0180) < 0.001)
    #expect(aurora.confidence(rawScore: 0.5) == 0.5)
    #expect(abs(aurora.confidence(rawScore: 1.0) - 0.9820) < 0.001)
}

@Test func calibrationIsDeterministic() {
    let aurora = AURORACalibration()
    let baseline = aurora.confidence(rawScore: 0.62)
    for _ in 0..<5 {
        #expect(aurora.confidence(rawScore: 0.62) == baseline)
    }
}

@Test func confidenceIsBounded() {
    let aurora = AURORACalibration()
    for raw in stride(from: -1.0, through: 2.0, by: 0.05) {
        let confidence = aurora.confidence(rawScore: raw)
        #expect(confidence >= 0.0)
        #expect(confidence <= 1.0)
    }
}
