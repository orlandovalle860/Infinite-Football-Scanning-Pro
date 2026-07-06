import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit)
/// Retained generators for escalating “start next rep” pulses while the coach waits on TAP TO START.
/// Not stored in SwiftUI `@State` — reference types there corrupt dispatch state on beta iPadOS.
private final class CoachWaitingRepHapticKit {
    let light = UIImpactFeedbackGenerator(style: .light)
    let medium = UIImpactFeedbackGenerator(style: .medium)
    let heavy = UIImpactFeedbackGenerator(style: .heavy)

    func prepareAll() {
        light.prepare()
        medium.prepare()
        heavy.prepare()
    }
}
#endif

enum SwipeDirection: String {
    case up = "Forward"
    case down = "Back"
    case left = "Left"
    case right = "Right"
}

extension SwipeDirection {
    var gate: Gate {
        switch self {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        }
    }
}

enum SessionPhase {
    case idle
    case waitingForNextRep
    case waitingBeep
    case waitingPass
    case logging
}

struct CoachSessionView: View {
    @Environment(\.dismiss) private var dismiss
    /// Shown as de-emphasized header copy (nav bar title is cleared on coach remotes).
    let coachRemoteHeaderTitle: String
    let totalReps: Int
    /// Authoritative 1-based rep counter owned by the parent coach remote view.
    /// This view never mutates it — the parent advances the count after each rep
    /// and rotates `.id(coachSessionInputResetToken)` to re-seed this view.
    let currentRepOneBased: Int
    let preBeepDelayRange: ClosedRange<Double>
    /// When `true`, `startRep()` does NOT schedule its local pre-beep timer.
    /// Instead, the view stays in `.waitingBeep` until `externalBeepArmedRepIndex`
    /// is updated to match the current 0-based rep index (done by the parent
    /// upon receiving a `beepArmed` message from the display). This prevents the
    /// coach's PASS button from arming before the iPad's decision window has
    /// actually opened — a user tap during that gap was being silently dropped
    /// by the display's hard gate and cooking the rep.
    let waitsForExternalBeepArm: Bool
    /// Parent-owned 0-based rep index indicating which rep the display has beeped
    /// for. When `waitsForExternalBeepArm == true` and this changes to match
    /// `currentRepZeroBased` while `phase == .waitingBeep`, the view transitions
    /// to `.waitingPass`. Parent sets this from `.beepArmed(repIndex)`.
    @Binding var externalBeepArmedRepIndex: Int?
    /// When set after PASS, swipe logs this 0-based rep (optional; does not block next rep tap).
    @Binding var pendingDirectionLogRepZeroBased: Int?
    /// Return `true` to acknowledge a start-rep tap; `false` tells this view to
    /// stay in `.idle` (and not beep / arm for pass) because the parent rejected
    /// the start (e.g. still waiting for a rep-started ack). Prevents coach/display
    /// desync after a rejected tap.
    let onRepStarted: ((Int) -> Bool)?
    let onPassTriggered: ((Int) -> Bool)?
    let onDirectionLogged: ((Int, SwipeDirection) -> Void)?
    /// When non-empty, first block only (rep 1) may show lightweight coach cues until ``CoachFirstRunGuidanceStore`` marks the activity completed.
    let coachFirstRunActivityId: String
    /// Multipeer / relay link to the display — idle haptics only when connected.
    let coachTransportConnected: Bool
    /// Evaluative copy for the coach while logging direction (player display intentionally stays clean).
    let loggingPhaseEvaluativeTitle: String?
    let loggingPhaseEvaluativeSubtitle: String?

    /// Read-only: cancel UI nudge if partner session ends or link drops (does not send relay traffic).
    @ObservedObject private var partnerSessionCoordinator: TrainingPartnerConnectionCoordinator

    @State private var phase: SessionPhase = .idle
    @State private var lastDirection: SwipeDirection? = nil
    @State private var preBeepWorkToken = UUID()
    @State private var beepTime: Date?
    @State private var passSentForRep: Set<Int> = []
    /// UI-only: repeating escalating haptics while waiting to start the next rep.
    #if canImport(UIKit)
    private static let waitingRepHapticKit = CoachWaitingRepHapticKit()
    #endif
    @State private var waitingRepHapticLoopToken = UUID()
    @State private var tapToStartVisualEscalationToken = UUID()
    @State private var showTapToStartEscalatedScalePulse = false
    @State private var validTapFeedbackActive = false
    @State private var validTapFeedbackToken = UUID()

    @State private var firstRunEphemeralGuidanceText: String?
    @State private var firstRunEphemeralGuidanceOpacity: Double = 0
    @State private var firstRunEphemeralGuidanceToken = UUID()

    init(
        coachRemoteHeaderTitle: String = "",
        totalReps: Int = 12,
        currentRepOneBased: Int = 1,
        preBeepDelayRange: ClosedRange<Double> = 0.0...0.0,
        waitsForExternalBeepArm: Bool = false,
        externalBeepArmedRepIndex: Binding<Int?> = .constant(nil),
        pendingDirectionLogRepZeroBased: Binding<Int?> = .constant(nil),
        onRepStarted: ((Int) -> Bool)? = nil,
        onPassTriggered: ((Int) -> Bool)? = nil,
        onDirectionLogged: ((Int, SwipeDirection) -> Void)? = nil,
        coachFirstRunActivityId: String = "",
        coachTransportConnected: Bool = true,
        loggingPhaseEvaluativeTitle: String? = nil,
        loggingPhaseEvaluativeSubtitle: String? = nil
    ) {
        self.coachRemoteHeaderTitle = coachRemoteHeaderTitle
        self.totalReps = totalReps
        self.currentRepOneBased = max(1, min(currentRepOneBased, max(totalReps, 1)))
        self.preBeepDelayRange = preBeepDelayRange
        self.waitsForExternalBeepArm = waitsForExternalBeepArm
        self._externalBeepArmedRepIndex = externalBeepArmedRepIndex
        self._pendingDirectionLogRepZeroBased = pendingDirectionLogRepZeroBased
        self.onRepStarted = onRepStarted
        self.onPassTriggered = onPassTriggered
        self.onDirectionLogged = onDirectionLogged
        self.coachFirstRunActivityId = coachFirstRunActivityId
        self.coachTransportConnected = coachTransportConnected
        self.loggingPhaseEvaluativeTitle = loggingPhaseEvaluativeTitle
        self.loggingPhaseEvaluativeSubtitle = loggingPhaseEvaluativeSubtitle
        _partnerSessionCoordinator = ObservedObject(wrappedValue: TrainingPartnerConnectionCoordinator.shared)
    }

    /// Parent-owned 0-based rep index used for logging + callbacks.
    private var currentRepZeroBased: Int { currentRepOneBased - 1 }

    /// Coach is idle on “TAP TO START” (before first rep or between reps).
    private var isTapToStartIdlePhase: Bool {
        phase == .idle || phase == .waitingForNextRep
    }

    /// First rep only, once per activity, until the parent marks the activity’s first run completed after a full block.
    private var coachFirstRunGuidanceActive: Bool {
        guard !coachFirstRunActivityId.isEmpty,
              currentRepOneBased == 1,
              !CoachFirstRunGuidanceStore.hasCompletedFirstRun(activityId: coachFirstRunActivityId)
        else { return false }
        return true
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        if !coachRemoteHeaderTitle.isEmpty {
                            Text(coachRemoteHeaderTitle)
                                .font(.subheadline)
                                .fontWeight(.regular)
                                .foregroundColor(.white.opacity(0.7))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        PartnerLinkPassiveStatusLine(role: .coach, coachPresentation: .sessionRepHeader)
                        Text("Rep \(currentRepOneBased) of \(totalReps)")
                            .foregroundColor(.white)
                            .font(.title3.weight(.semibold))
                    }
                    Spacer(minLength: 8)
                }
                .padding(.horizontal)
                .padding(.top, 4)

                Spacer(minLength: 48)

                Group {
                    if isTapToStartIdlePhase {
                        VStack(spacing: 10) {
                            PulsingTapToStartPrompt(
                                foregroundOpacity: primaryActionTextOpacity,
                                escalatedScalePulse: showTapToStartEscalatedScalePulse
                            )
                            if coachFirstRunGuidanceActive {
                                Text("Tap to start the rep")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.white.opacity(0.6))
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .allowsHitTesting(false)
                    } else {
                        VStack(spacing: 10) {
                            Text(statusText)
                                .foregroundColor(.white.opacity(primaryActionTextOpacity))
                                .font(.largeTitle.weight(.bold))
                            if phase == .logging {
                                if let t = loggingPhaseEvaluativeTitle, !t.isEmpty {
                                    Text(t)
                                        .font(.title3.weight(.semibold))
                                        .foregroundColor(.white.opacity(0.92))
                                        .multilineTextAlignment(.center)
                                }
                                if let s = loggingPhaseEvaluativeSubtitle, !s.isEmpty {
                                    Text(s)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(.white.opacity(0.78))
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 12)
                                }
                            }
                        }
                    }
                }

                // Direction feedback
                if let direction = lastDirection {
                    Text(direction.rawValue)
                        .font(.largeTitle)
                        .foregroundColor(.green)
                        .padding(.top, 8)
                }

                Spacer()
            }

            if let guidance = firstRunEphemeralGuidanceText {
                VStack {
                    Spacer()
                    Text(guidance)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 36)
                }
                .allowsHitTesting(false)
                .opacity(firstRunEphemeralGuidanceOpacity)
            }
        }
        .scaleEffect(validTapFeedbackActive ? 0.985 : 1.0)
        .opacity(validTapFeedbackActive ? 0.88 : 1.0)
        .animation(.easeOut(duration: 0.1), value: validTapFeedbackActive)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 25)
                .onEnded { value in
                    handleSwipe(value)
                }
        )
        .simultaneousGesture(
            TapGesture()
                .onEnded {
                    handleTap()
                }
        )
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.48))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            }
        }
        .background(DisableSwipeBack())
        .onAppear {
            #if canImport(UIKit)
            Self.waitingRepHapticKit.prepareAll()
            #endif
            if coachWaitingStartRepHapticsEligible() {
                scheduleCoachWaitingStartRepHapticLoop()
            }
        }
        .onDisappear {
            cancelPreBeepWork()
            cancelCoachWaitingStartRepHapticLoop()
            cancelFirstRunEphemeralGuidance()
            cancelValidTapFeedback()
        }
        .onChange(of: phase) { oldPhase, newPhase in
            cancelFirstRunEphemeralGuidance()
            if newPhase == .idle || newPhase == .waitingForNextRep {
                scheduleCoachWaitingStartRepHapticLoop()
            } else {
                cancelCoachWaitingStartRepHapticLoop()
            }
            triggerFirstRunEphemeralGuidanceIfNeeded(from: oldPhase, to: newPhase)
        }
        .onChange(of: currentRepOneBased) { _, _ in
            if currentRepOneBased != 1 { cancelFirstRunEphemeralGuidance() }
            if coachWaitingStartRepHapticsEligible() {
                scheduleCoachWaitingStartRepHapticLoop()
            } else {
                cancelCoachWaitingStartRepHapticLoop()
            }
        }
        .onChange(of: coachTransportConnected) { _, _ in
            if coachWaitingStartRepHapticsEligible() {
                scheduleCoachWaitingStartRepHapticLoop()
            } else {
                cancelCoachWaitingStartRepHapticLoop()
            }
        }
        .onChange(of: partnerSessionCoordinator.isPartnerDisplayCountdownActive) { _, _ in
            if coachWaitingStartRepHapticsEligible() {
                scheduleCoachWaitingStartRepHapticLoop()
            } else {
                cancelCoachWaitingStartRepHapticLoop()
            }
        }
        .onChange(of: partnerSessionCoordinator.isPartnerTrainingSessionActive) { _, active in
            if !active {
                cancelCoachWaitingStartRepHapticLoop()
                cancelFirstRunEphemeralGuidance()
            } else if coachWaitingStartRepHapticsEligible() {
                scheduleCoachWaitingStartRepHapticLoop()
            }
        }
        .onChange(of: partnerSessionCoordinator.isMidSessionPartnerDisconnect) { _, disconnected in
            if disconnected {
                cancelCoachWaitingStartRepHapticLoop()
                cancelFirstRunEphemeralGuidance()
            } else if coachWaitingStartRepHapticsEligible() {
                scheduleCoachWaitingStartRepHapticLoop()
            }
        }
        .onChange(of: externalBeepArmedRepIndex) { _, newValue in
            // Only honor beep-arm signals in external-arm mode and only when
            // they match the rep we're currently waiting on. Stale signals (for
            // a previous rep, or during `.idle`/`.waitingPass`) are ignored.
            guard waitsForExternalBeepArm else { return }
            guard phase == .waitingBeep else { return }
            guard let armedRep = newValue, armedRep == currentRepZeroBased else { return }
            beep()
        }
    }

    private var statusText: String {
        switch phase {
        case .idle, .waitingForNextRep: return "TAP TO START"
        case .waitingBeep: return "WAIT..."
        case .waitingPass: return "PASS (TAP)"
        case .logging: return "SWIPE NOW"
        }
    }

    /// Core action prompt stays visually primary; transitional copy is slightly softer.
    private var primaryActionTextOpacity: Double {
        switch phase {
        case .idle, .waitingForNextRep, .waitingPass, .logging:
            return 0.95
        case .waitingBeep:
            return 0.72
        }
    }

    private func handleTap() {
        switch phase {
        case .idle, .waitingForNextRep:
            guard CoachTapInputGuard.mayStartNextRep() else {
                print("[INPUT-GUARD] Start rep tap debounced (650ms after PASS or prior start)")
                return
            }
            print("[INPUT] Start next rep")
            startRep()
        case .waitingPass:
            let currentRep = currentRepZeroBased
            guard !passSentForRep.contains(currentRep) else {
                print("[INPUT-GUARD] Duplicate pass ignored for rep \(currentRep)")
                return
            }
            print("[INPUT] PASS triggered for rep \(currentRep)")
            // Only mark as sent on acceptance. If the parent rejects (e.g.,
            // `state != .armedForPass` yet because the display hasn't acked
            // rep-started), we must allow the next tap to retry — otherwise
            // the child gets stuck in `.waitingPass` and subsequent swipes are
            // dropped by `handleSwipe`'s `phase == .logging` guard.
            if triggerPass() {
                passSentForRep.insert(currentRep)
            } else {
                print("[INPUT-GUARD] PASS rejected by parent for rep \(currentRep) — will retry on next tap")
            }
        case .waitingBeep:
            print("[INPUT-GUARD] Tap ignored before beep")
        case .logging:
            guard CoachTapInputGuard.mayStartNextRep() else {
                print("[INPUT-GUARD] Start rep tap debounced (650ms after PASS or prior start)")
                return
            }
            print("[INPUT] Start next rep (logging optional)")
            startRep()
        }
    }

    private func startRep() {
        cancelCoachWaitingStartRepHapticLoop()
        // Ask parent first. If it rejects (e.g., still waiting for a rep-started
        // ack or mid-send), stay in `.idle` so the next tap can retry cleanly.
        // Never advance phase on rejection — otherwise
        // the child races ahead to `.waitingPass` while the parent is still
        // `.ready`, and the user's pass tap silently fails.
        let accepted = onRepStarted?(currentRepZeroBased) ?? true
        guard accepted else {
            print("[INPUT-GUARD] Start rep rejected by parent — remaining idle")
            scheduleCoachWaitingStartRepHapticLoop()
            return
        }
        CoachTapInputGuard.recordAcceptedStartRepTap()
        registerValidTapFeedback()
        triggerHaptic(style: .light)
        lastDirection = nil
        beepTime = nil
        phase = .waitingBeep

        preBeepWorkToken = UUID()
        // External-arm mode: do NOT schedule the local pre-beep timer. The
        // parent will drive `externalBeepArmedRepIndex` when the iPad's beep
        // fires, and the `.onChange` handler below will transition us to
        // `.waitingPass`. This is the fix for "tap-before-beep" breaking the
        // rep — the PASS button literally cannot arm until the display is ready.
        if waitsForExternalBeepArm {
            // If the display already beeped for this rep before we transitioned
            // (rare race — e.g., stale message left over from recovery), honor
            // it immediately rather than hanging in `.waitingBeep` forever.
            if externalBeepArmedRepIndex == currentRepZeroBased {
                beep()
            }
            return
        }
        let delay = Double.random(in: preBeepDelayRange)
        let token = preBeepWorkToken
        if delay <= 0 {
            beep()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard self.preBeepWorkToken == token else { return }
                beep()
            }
        }
    }

    private func cancelPreBeepWork() {
        preBeepWorkToken = UUID()
    }

    private func beep() {
        guard phase == .waitingBeep else { return }
        beepTime = Date()
        phase = .waitingPass
    }

    @discardableResult
    private func triggerPass() -> Bool {
        guard phase == .waitingPass else { return false }
        let accepted = onPassTriggered?(currentRepZeroBased) ?? true
        guard accepted else { return false }
        CoachTapInputGuard.recordPassTap()
        registerValidTapFeedback()
        triggerHaptic(style: .medium)
        phase = .waitingForNextRep
        return true
    }

    private func handleSwipe(_ value: DragGesture.Value) {
        guard phase == .logging || phase == .waitingForNextRep else {
            print("[INPUT-GUARD] Swipe ignored — not in logging phase")
            return
        }
        guard pendingDirectionLogRepZeroBased != nil || phase == .logging else {
            print("[INPUT-GUARD] Swipe ignored — no pending direction log")
            return
        }
        let dx = value.translation.width
        let dy = value.translation.height

        guard abs(dx) > 30 || abs(dy) > 30 else { return }

        let direction: SwipeDirection

        if abs(dx) > abs(dy) {
            direction = dx > 0 ? .right : .left
        } else {
            direction = dy > 0 ? .down : .up
        }
        let logRep = pendingDirectionLogRepZeroBased ?? currentRepZeroBased
        print("[INPUT] Swipe logged direction \(direction.rawValue) for rep \(logRep)")
        triggerHaptic(style: .rigid)
        lastDirection = nil
        lastDirection = direction
        beepTime = nil
        onDirectionLogged?(logRep, direction)
        passSentForRep.remove(logRep)
        pendingDirectionLogRepZeroBased = nil
        if phase == .logging {
            phase = .waitingForNextRep
        }
    }

    private func triggerHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }

    /// Brief full-screen pulse on accepted coach tap — no text or icons.
    private func registerValidTapFeedback() {
        validTapFeedbackToken = UUID()
        let token = validTapFeedbackToken
        withAnimation(.easeOut(duration: 0.1)) {
            validTapFeedbackActive = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard validTapFeedbackToken == token else { return }
            withAnimation(.easeOut(duration: 0.1)) {
                validTapFeedbackActive = false
            }
        }
    }

    private func cancelValidTapFeedback() {
        validTapFeedbackToken = UUID()
        validTapFeedbackActive = false
    }

    // MARK: - Waiting to start next rep (TAP TO START): escalating haptics + optional scale pulse (UI-only)

    @MainActor
    private func coachWaitingStartRepHapticsEligible() -> Bool {
        guard phase == .waitingForNextRep || phase == .idle else { return false }
        guard coachTransportConnected else { return false }
        guard partnerSessionCoordinator.isPartnerTrainingSessionActive else { return false }
        guard !partnerSessionCoordinator.isPartnerDisplayCountdownActive else { return false }
        guard !partnerSessionCoordinator.isMidSessionPartnerDisconnect else { return false }
        return true
    }

    private func cancelTapToStartVisualEscalation() {
        tapToStartVisualEscalationToken = UUID()
        showTapToStartEscalatedScalePulse = false
    }

    private func cancelCoachWaitingStartRepHapticLoop() {
        waitingRepHapticLoopToken = UUID()
        cancelTapToStartVisualEscalation()
    }

    private func scheduleTapToStartVisualEscalationIfNeeded() {
        cancelTapToStartVisualEscalation()
        guard coachWaitingStartRepHapticsEligible() else { return }
        tapToStartVisualEscalationToken = UUID()
        let token = tapToStartVisualEscalationToken
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard tapToStartVisualEscalationToken == token else { return }
            guard coachWaitingStartRepHapticsEligible() else { return }
            showTapToStartEscalatedScalePulse = true
        }
    }

    private func scheduleCoachWaitingStartRepHapticLoop() {
        cancelCoachWaitingStartRepHapticLoop()
        guard coachWaitingStartRepHapticsEligible() else { return }
        let loopStart = Date()
        waitingRepHapticLoopToken = UUID()
        let token = waitingRepHapticLoopToken
        #if canImport(UIKit)
        let kit = Self.waitingRepHapticKit
        kit.prepareAll()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            while waitingRepHapticLoopToken == token {
                guard coachWaitingStartRepHapticsEligible() else { break }
                let elapsed = Date().timeIntervalSince(loopStart)
                if elapsed < 5 {
                    kit.light.prepare()
                    kit.light.impactOccurred()
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    guard waitingRepHapticLoopToken == token, coachWaitingStartRepHapticsEligible() else { break }
                    kit.light.prepare()
                    kit.light.impactOccurred()
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                } else if elapsed < 8 {
                    kit.medium.prepare()
                    kit.medium.impactOccurred()
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    guard waitingRepHapticLoopToken == token, coachWaitingStartRepHapticsEligible() else { break }
                    kit.medium.prepare()
                    kit.medium.impactOccurred()
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                } else {
                    kit.heavy.prepare()
                    kit.heavy.impactOccurred()
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    guard waitingRepHapticLoopToken == token, coachWaitingStartRepHapticsEligible() else { break }
                    kit.heavy.prepare()
                    kit.heavy.impactOccurred()
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    guard waitingRepHapticLoopToken == token, coachWaitingStartRepHapticsEligible() else { break }
                    kit.heavy.prepare()
                    kit.heavy.impactOccurred()
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }
        #endif
        scheduleTapToStartVisualEscalationIfNeeded()
    }

    // MARK: - First-run coach guidance (rep 1 only; UI-only)

    private func cancelFirstRunEphemeralGuidance() {
        firstRunEphemeralGuidanceToken = UUID()
        firstRunEphemeralGuidanceOpacity = 0
        firstRunEphemeralGuidanceText = nil
    }

    private func triggerFirstRunEphemeralGuidanceIfNeeded(from oldPhase: SessionPhase, to newPhase: SessionPhase) {
        guard coachFirstRunGuidanceActive else { return }
        if oldPhase == .waitingBeep, newPhase == .waitingPass {
            showFirstRunEphemeralGuidance("Tap and pass on the beep")
        } else if oldPhase == .waitingPass, newPhase == .logging {
            showFirstRunEphemeralGuidance("Swipe the direction the player went first")
        }
    }

    private func showFirstRunEphemeralGuidance(_ text: String) {
        guard coachFirstRunGuidanceActive else { return }
        cancelFirstRunEphemeralGuidance()
        firstRunEphemeralGuidanceToken = UUID()
        let token = firstRunEphemeralGuidanceToken
        firstRunEphemeralGuidanceText = text
        firstRunEphemeralGuidanceOpacity = 0
        Task { @MainActor in
            guard firstRunEphemeralGuidanceToken == token else { return }
            withAnimation(.easeIn(duration: 0.2)) {
                firstRunEphemeralGuidanceOpacity = 1
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard firstRunEphemeralGuidanceToken == token else { return }
            try? await Task.sleep(nanoseconds: 1_700_000_000)
            guard firstRunEphemeralGuidanceToken == token else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                firstRunEphemeralGuidanceOpacity = 0
            }
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard firstRunEphemeralGuidanceToken == token else { return }
            firstRunEphemeralGuidanceText = nil
        }
    }
}

// MARK: - Pulsing “TAP TO START” (only while `.waitingForNextRep`; does not affect layout hit testing)

private struct PulsingTapToStartPrompt: View {
    var foregroundOpacity: Double
    var escalatedScalePulse: Bool
    @State private var pulseDim = false
    @State private var scaleEmphasis: CGFloat = 1.0

    var body: some View {
        Text("TAP TO START")
            .foregroundColor(.white.opacity(foregroundOpacity * (pulseDim ? 0.86 : 1.0)))
            .font(.largeTitle.weight(.bold))
            .scaleEffect(scaleEmphasis)
            .allowsHitTesting(false)
            .onAppear {
                pulseDim = false
                withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true)) {
                    pulseDim = true
                }
                applyScalePulse(escalatedScalePulse)
            }
            .onChange(of: escalatedScalePulse) { _, on in
                applyScalePulse(on)
            }
    }

    private func applyScalePulse(_ on: Bool) {
        if on {
            scaleEmphasis = 1.0
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                scaleEmphasis = 1.05
            }
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                scaleEmphasis = 1.0
            }
        }
    }
}

struct DisableSwipeBack: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        DispatchQueue.main.async {
            controller.navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

#Preview {
    CoachSessionView(
        coachRemoteHeaderTitle: "Coach — Preview (12 reps)",
        totalReps: 12,
        currentRepOneBased: 1,
        preBeepDelayRange: 0.0...0.0,
        onRepStarted: nil,
        onPassTriggered: nil,
        onDirectionLogged: nil
    )
}
