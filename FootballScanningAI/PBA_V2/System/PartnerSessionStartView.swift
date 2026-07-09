//
//  PartnerSessionStartView.swift
//  FootballScanningAI
//
//  Home → Partner: explicit join code / relay warm-up without relying on first-launch or blocked training pushes.
//

import SwiftUI

/// Display-only state for the partner join / relay handoff screen.
enum PartnerConnectionState: Equatable {
    case loading
    case showingCode(String)
    case connected
}

struct PartnerSessionStartView: View {
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var relayDisplaySession = TrainingPartnerConnectionCoordinator.shared.relayDisplaySession
    @ObservedObject private var coachRelayRemoteService = TrainingPartnerConnectionCoordinator.shared.coachRelayRemoteService
    @Environment(\.dismiss) private var dismiss
    @State private var didScheduleAutoPop = false

    private var connectionState: PartnerConnectionState {
        if relayDisplaySession.relaySessionId == nil {
            return .loading
        }
        if coachRelayRemoteService.isCoachConnected || relayDisplaySession.isCoachPaired {
            return .connected
        }
        return .showingCode(relayDisplaySession.joinCode ?? "----")
    }

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.1)
                .ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "iphone.gen3")
                    .font(.system(size: 52, weight: .medium))
                    .foregroundStyle(.yellow)
                Text("Partner session")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Group {
                    switch connectionState {
                    case .loading:
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(.yellow)
                            Text("Generating join code…")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    case .showingCode(let code):
                        VStack(spacing: 12) {
                            Text("Join code")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                            Text(code)
                                .font(.system(size: 42, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                            Text("Enter this code on the coach device")
                                .font(.footnote)
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                        }
                    case .connected:
                        VStack(spacing: 10) {
                            Text("Coach connected")
                                .font(.headline)
                                .foregroundColor(.white)
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.green)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)

                Spacer()
                    .frame(minHeight: 8)

                Button {
                    trainSolo()
                } label: {
                    Text("Train on your own")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(32)
            .frame(maxWidth: 520)
        }
        .preferredColorScheme(.dark)
        .navigationTitle("Partner")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Back") {
                    dismiss()
                }
                .foregroundStyle(.white)
            }
        }
        .onAppear {
            // Display-host surface only. Phones must join via temporary Coach Remote flow —
            // never mint a second display join code here.
            #if canImport(UIKit)
            if UIDevice.current.userInterfaceIdiom == .phone {
                AppRoleDebug.log("routing_decision reason=partner_pairing_redirect_phone_to_temporary_coach_remote")
                router.replace(with: .coachRemote)
                return
            }
            #endif
            didScheduleAutoPop = false
            TrainingPartnerConnectionCoordinator.shared.beginPartnerTrainingSessionIfNeeded()
            Task {
                await TrainingPartnerConnectionCoordinator.shared.prepareRelayDisplayForActivity()
            }
        }
        .onChange(of: coachRelayRemoteService.isCoachConnected) { wasConnected, isConnected in
            guard !wasConnected, isConnected else { return }
            scheduleAutoPopToHome()
        }
        .onChange(of: relayDisplaySession.isCoachPaired) { wasPaired, isPaired in
            guard !wasPaired, isPaired else { return }
            scheduleAutoPopToHome()
        }
    }

    private func scheduleAutoPopToHome() {
        guard !didScheduleAutoPop else { return }
        didScheduleAutoPop = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            router.pop()
        }
    }

    private func trainSolo() {
        PBASessionFlowPolicy.persistTrainingMode(.solo)
        TrainingPartnerConnectionCoordinator.shared.endPartnerTrainingSession(reason: "PartnerSessionStartView.trainSolo", notifyPeer: true)
        router.replace(with: .oneTouchPassingSetup(mode: .solo))
    }
}
