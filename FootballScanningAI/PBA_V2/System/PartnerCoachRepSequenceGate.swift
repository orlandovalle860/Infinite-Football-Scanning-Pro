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

    /// After partner soft reconnect, coach re-sends `nextRep` for the same rep; rewind the stale guard from `expected = rep+1` so the apply path runs again.
    mutating func alignExpectedNextForCoachSoftReconnectReplay(repIndex: Int) {
        expectedNextCoachRepIndex = repIndex
    }
}
