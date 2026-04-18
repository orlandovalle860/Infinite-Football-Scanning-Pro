import Foundation

/// Display-side session snapshot from coach `sessionStarted` (relay / Multipeer). **Navigation is separate** — this only holds drill identity and block sizing.
struct DisplaySessionState: Equatable, Sendable {
    /// Correlates with `TrainingPartnerConnectionCoordinator.partnerDisplaySurfaceId` so SwiftUI can recreate partner display roots cleanly.
    let instanceId: UUID
    let activityId: String
    let totalReps: Int
    var currentRepIndex: Int
    let startedAt: Date
}
