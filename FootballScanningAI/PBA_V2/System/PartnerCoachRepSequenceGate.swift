import Foundation

/// Tracks the display-side sequence after each successfully applied coach ``nextRep``.
/// Used to ignore **stale** indices between reps (`repIndex < expectedNextCoachRepIndex`); coach can still skip ahead.
struct PartnerCoachRepSequenceGate: Equatable {
    private(set) var expectedNextCoachRepIndex: Int = 0

    mutating func reset() {
        expectedNextCoachRepIndex = 0
    }

    /// Timed partner free-train: coach wraps to `nextRep(0)` after the last chunk rep while the gate may still expect `chunkSize`.
    mutating func resetIfCoachWrappedToStartOfChunk(repIndex: Int, chunkSize: Int, loopsChunks: Bool) {
        guard loopsChunks, chunkSize > 0, repIndex == 0, expectedNextCoachRepIndex >= chunkSize else { return }
        reset()
    }

    mutating func recordNextRepSuccessfullyApplied(_ repIndex: Int) {
        expectedNextCoachRepIndex = repIndex + 1
    }

    /// After partner soft reconnect, coach re-sends `nextRep` for the same rep; rewind the stale guard from `expected = rep+1` so the apply path runs again.
    mutating func alignExpectedNextForCoachSoftReconnectReplay(repIndex: Int) {
        expectedNextCoachRepIndex = repIndex
    }
}
