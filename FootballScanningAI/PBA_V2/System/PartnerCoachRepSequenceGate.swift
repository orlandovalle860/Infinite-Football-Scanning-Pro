import Foundation

/// Tracks the display-side sequence after each successfully applied coach ``nextRep``.
/// Used to ignore **stale** indices between reps (`repIndex < expectedNextCoachRepIndex`); coach can still skip ahead.
struct PartnerCoachRepSequenceGate: Equatable {
    private(set) var expectedNextCoachRepIndex: Int = 0

    mutating func reset() {
        expectedNextCoachRepIndex = 0
    }

    mutating func recordNextRepSuccessfullyApplied(_ repIndex: Int) {
        expectedNextCoachRepIndex = repIndex + 1
    }
}
