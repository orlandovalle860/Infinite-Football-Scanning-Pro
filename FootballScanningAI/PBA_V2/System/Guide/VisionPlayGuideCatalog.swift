//
//  VisionPlayGuideCatalog.swift
//  FootballScanningAI
//
//  Data-driven VisionPlay Guide — reference pages (not onboarding).
//

import Foundation

// MARK: - IDs

enum VisionPlayGuidePageID: String, CaseIterable, Identifiable, Hashable {
    case welcome
    case partnerMode
    case partnerModeSetup
    case soloMode
    case meetTheBall
    case awayFromPressure
    case dribbleOrPass
    case oneTouchPassing

    var id: String { rawValue }

    /// Ordered reading order across the whole Guide.
    static var readingOrder: [VisionPlayGuidePageID] {
        [
            .welcome,
            .partnerModeSetup,
            .partnerMode,
            .soloMode,
            .meetTheBall,
            .awayFromPressure,
            .dribbleOrPass,
            .oneTouchPassing
        ]
    }

    var previous: VisionPlayGuidePageID? {
        guard let idx = Self.readingOrder.firstIndex(of: self), idx > 0 else { return nil }
        return Self.readingOrder[idx - 1]
    }

    var next: VisionPlayGuidePageID? {
        guard let idx = Self.readingOrder.firstIndex(of: self),
              idx + 1 < Self.readingOrder.count else { return nil }
        return Self.readingOrder[idx + 1]
    }

    static func page(for activity: ActivityKind) -> VisionPlayGuidePageID {
        switch activity {
        case .twoMinuteTest: return .meetTheBall
        case .awayFromPressure: return .awayFromPressure
        case .dribbleOrPass: return .dribbleOrPass
        case .oneTouchPassing: return .oneTouchPassing
        }
    }
}

enum VisionPlayGuideSection: String, CaseIterable, Identifiable {
    case gettingStarted
    case activities

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gettingStarted: return "Getting Started"
        case .activities: return "Activities"
        }
    }

    var pages: [VisionPlayGuidePageID] {
        switch self {
        case .gettingStarted:
            return [.welcome, .partnerModeSetup, .partnerMode, .soloMode]
        case .activities:
            return [.meetTheBall, .awayFromPressure, .dribbleOrPass, .oneTouchPassing]
        }
    }
}

// MARK: - Content model

enum VisionPlayGuideVisualKind: String, Equatable {
    case meetTheBall
    case awayFromPressure
    case dribbleOrPass
    case soloCalibration
    case partnerModeSetup
    /// Reserved for a future Player Display screenshot asset.
    case oneTouchPassing
}

/// One short block: optional section heading + paragraphs and/or bullets.
struct VisionPlayGuideTextBlock: Equatable, Identifiable {
    let id: String
    var heading: String?
    var paragraphs: [String]
    var bullets: [String]

    init(
        id: String,
        heading: String? = nil,
        paragraphs: [String] = [],
        bullets: [String] = []
    ) {
        self.id = id
        self.heading = heading
        self.paragraphs = paragraphs
        self.bullets = bullets
    }
}

struct VisionPlayGuidePageContent: Identifiable, Equatable {
    let id: VisionPlayGuidePageID
    let section: VisionPlayGuideSection
    let title: String
    let visual: VisionPlayGuideVisualKind?
    let blocks: [VisionPlayGuideTextBlock]

    /// Short label for the table of contents.
    var contentsTitle: String { title }
}

// MARK: - Presentation

/// Opens the Guide sheet at the table of contents or a specific page.
enum VisionPlayGuidePresentation: Identifiable, Equatable {
    case contents
    case page(VisionPlayGuidePageID)

    var id: String {
        switch self {
        case .contents: return "contents"
        case .page(let page): return "page-\(page.rawValue)"
        }
    }

    var initialPage: VisionPlayGuidePageID? {
        switch self {
        case .contents: return nil
        case .page(let page): return page
        }
    }
}

// MARK: - Catalog

enum VisionPlayGuideCatalog {
    static func content(for id: VisionPlayGuidePageID) -> VisionPlayGuidePageContent {
        pagesByID[id]!
    }

    static var allPages: [VisionPlayGuidePageContent] {
        VisionPlayGuidePageID.readingOrder.map { content(for: $0) }
    }

    private static let pagesByID: [VisionPlayGuidePageID: VisionPlayGuidePageContent] = {
        Dictionary(uniqueKeysWithValues: makePages().map { ($0.id, $0) })
    }()

    private static func makePages() -> [VisionPlayGuidePageContent] {
        [
            VisionPlayGuidePageContent(
                id: .welcome,
                section: .gettingStarted,
                title: "Welcome to VisionPlay",
                visual: nil,
                blocks: [
                    VisionPlayGuideTextBlock(
                        id: "welcome-intro",
                        paragraphs: [
                            "VisionPlay helps players build better habits before receiving the ball.",
                            "Every repetition follows the same process."
                        ]
                    ),
                    VisionPlayGuideTextBlock(
                        id: "welcome-process",
                        paragraphs: [
                            "Observe.",
                            "Recognize.",
                            "Act."
                        ]
                    )
                ]
            ),
            VisionPlayGuidePageContent(
                id: .partnerMode,
                section: .gettingStarted,
                title: "Partner Mode",
                visual: nil,
                blocks: [
                    VisionPlayGuideTextBlock(
                        id: "partner-flow",
                        bullets: [
                            "The player continuously moves inside the receiving zone while scanning the Player Display.",
                            "When the beep sounds, the player checks into the center of the receiving zone.",
                            "At the same moment, the coach taps the Coach Remote and serves the ball.",
                            "The player performs the Critical Scan while the ball is traveling."
                        ]
                    ),
                    VisionPlayGuideTextBlock(
                        id: "partner-timing",
                        heading: "Timing",
                        paragraphs: [
                            "The timing between the pass and the Critical Scan is what makes the training representative of football."
                        ]
                    )
                ]
            ),
            VisionPlayGuidePageContent(
                id: .partnerModeSetup,
                section: .gettingStarted,
                title: "Partner Mode Setup",
                visual: .partnerModeSetup,
                blocks: [
                    VisionPlayGuideTextBlock(
                        id: "partner-setup-intro",
                        paragraphs: [
                            "VisionPlay recreates the moments immediately before a player receives the ball."
                        ]
                    ),
                    VisionPlayGuideTextBlock(
                        id: "partner-setup-steps",
                        heading: "Before your first session",
                        bullets: [
                            "Mark a 5 × 5 yard receiving zone with four cones.",
                            "Position the iPad 3–5 yards behind the back edge of the receiving zone, facing the player.",
                            "Position the coach approximately 10–12 yards in front of the receiving zone. Adjust the distance to suit the player's age, ability, and training environment."
                        ]
                    )
                ]
            ),
            VisionPlayGuidePageContent(
                id: .soloMode,
                section: .gettingStarted,
                title: "Solo Mode",
                visual: .soloCalibration,
                blocks: [
                    VisionPlayGuideTextBlock(
                        id: "solo-steps",
                        bullets: [
                            "Position the Player Display.",
                            "Complete calibration.",
                            "Begin training."
                        ]
                    ),
                    VisionPlayGuideTextBlock(
                        id: "solo-note",
                        paragraphs: [
                            "Calibration only needs to be completed once."
                        ]
                    )
                ]
            ),
            VisionPlayGuidePageContent(
                id: .meetTheBall,
                section: .activities,
                title: ActivityKind.twoMinuteTest.displayName,
                visual: .meetTheBall,
                blocks: [
                    VisionPlayGuideTextBlock(
                        id: "mtb-objective",
                        heading: "Objective",
                        paragraphs: [
                            "Learn to identify where the ball appears before receiving."
                        ]
                    ),
                    VisionPlayGuideTextBlock(
                        id: "mtb-observe",
                        heading: "Observe",
                        paragraphs: [
                            "Perform a critical scan while the ball is traveling toward you."
                        ]
                    ),
                    VisionPlayGuideTextBlock(
                        id: "mtb-recognize",
                        heading: "Recognize",
                        paragraphs: [
                            "Identify where the ball appears."
                        ]
                    ),
                    VisionPlayGuideTextBlock(
                        id: "mtb-act",
                        heading: "Act",
                        paragraphs: [
                            "Dribble out of the Receiving Zone through the same side where the ball appeared."
                        ]
                    )
                ]
            ),
            VisionPlayGuidePageContent(
                id: .awayFromPressure,
                section: .activities,
                title: ActivityKind.awayFromPressure.displayName,
                visual: .awayFromPressure,
                blocks: [
                    VisionPlayGuideTextBlock(
                        id: "afp-objective",
                        heading: "Objective",
                        paragraphs: [
                            "Learn to receive away from pressure."
                        ]
                    ),
                    VisionPlayGuideTextBlock(
                        id: "afp-observe",
                        heading: "Observe",
                        paragraphs: [
                            "Perform a critical scan while the ball is traveling toward you."
                        ]
                    ),
                    VisionPlayGuideTextBlock(
                        id: "afp-recognize",
                        heading: "Recognize",
                        paragraphs: [
                            "Identify where the pressure is coming from."
                        ]
                    ),
                    VisionPlayGuideTextBlock(
                        id: "afp-act",
                        heading: "Act",
                        paragraphs: [
                            "Receive away from pressure with your first touch."
                        ]
                    )
                ]
            ),
            VisionPlayGuidePageContent(
                id: .dribbleOrPass,
                section: .activities,
                title: ActivityKind.dribbleOrPass.displayName,
                visual: .dribbleOrPass,
                blocks: [
                    VisionPlayGuideTextBlock(
                        id: "dop-objective",
                        heading: "Objective",
                        paragraphs: [
                            "Learn to recognize when to dribble and when to pass."
                        ]
                    ),
                    VisionPlayGuideTextBlock(
                        id: "dop-observe",
                        heading: "Observe",
                        paragraphs: [
                            "Perform a critical scan while the ball is traveling toward you."
                        ]
                    ),
                    VisionPlayGuideTextBlock(
                        id: "dop-recognize",
                        heading: "Recognize",
                        bullets: [
                            "Green lane = teammate",
                            "Red lane = pressure",
                            "No cue = open space"
                        ]
                    ),
                    VisionPlayGuideTextBlock(
                        id: "dop-act",
                        heading: "Act",
                        paragraphs: [
                            "Pass to the teammate.",
                            "Dribble into the open space."
                        ]
                    )
                ]
            ),
            VisionPlayGuidePageContent(
                id: .oneTouchPassing,
                section: .activities,
                title: ActivityKind.oneTouchPassing.displayName,
                visual: nil,
                blocks: [
                    VisionPlayGuideTextBlock(
                        id: "otp-objective",
                        heading: "Objective",
                        paragraphs: [
                            "Learn to identify the correct passing option before receiving."
                        ]
                    ),
                    VisionPlayGuideTextBlock(
                        id: "otp-observe",
                        heading: "Observe",
                        paragraphs: [
                            "Perform a critical scan while the ball is traveling toward you."
                        ]
                    ),
                    VisionPlayGuideTextBlock(
                        id: "otp-recognize",
                        heading: "Recognize",
                        paragraphs: [
                            "Identify the teammate."
                        ]
                    ),
                    VisionPlayGuideTextBlock(
                        id: "otp-act",
                        heading: "Act",
                        paragraphs: [
                            "Play a one-touch pass."
                        ]
                    )
                ]
            )
        ]
    }
}
