//
//  CreatePlayerProfileAfterTestView.swift
//  FootballScanningAI
//
//  Shown after first 2-Minute Test. Create profile (name, age, team, position) or skip with temporary "Player".
//

import SwiftUI

/// Summary from the 2-Minute Test to store on the new profile.
struct TestResultSummary {
    let decisionScore: Int
    let status: String
    let consistency: String
}

struct CreatePlayerProfileAfterTestView: View {
    @ObservedObject var profileManager: UserProfileManager
    @EnvironmentObject private var playerStore: PlayerStore
    let testResult: TestResultSummary?
    /// When set (e.g. from 2-min results in fullScreenCover), called after save/skip so the cover can dismiss.
    var onComplete: (() -> Void)? = nil
    @AppStorage("hasCompletedInitialTest") private var hasCompletedInitialTest = false

    @State private var name: String = ""
    @State private var age: String = ""
    @State private var team: String = ""
    @State private var position: String = ""
    @FocusState private var nameFocused: Bool

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmedName.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Create Player Profile")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                Text("Save your results and track progress. You can add more details later.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Name (required)")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white.opacity(0.9))
                    TextField("Player name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .focused($nameFocused)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Age (optional)")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white.opacity(0.9))
                    TextField("e.g. 14", text: $age)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Team (optional)")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white.opacity(0.9))
                    TextField("Team name", text: $team)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Position (optional)")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white.opacity(0.9))
                    TextField("e.g. Midfielder", text: $position)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(spacing: 12) {
                    Button(action: saveProfile) {
                        Text("Save Profile")
                            .font(.headline)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(canSave ? Color.yellow : Color.gray)
                            .cornerRadius(12)
                    }
                    .disabled(!canSave)
                    .buttonStyle(PlainButtonStyle())

                    Button(action: skipAndContinue) {
                        Text("Skip for now")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.top, 8)

                Spacer(minLength: 40)
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.1),
                    Color(red: 0.1, green: 0.1, blue: 0.15)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .preferredColorScheme(.dark)
        .navigationTitle("Create Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            nameFocused = true
        }
    }

    private func saveProfile() {
        let ageVal = age.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : age.trimmingCharacters(in: .whitespacesAndNewlines)
        let teamVal = team.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : team.trimmingCharacters(in: .whitespacesAndNewlines)
        let positionVal = position.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : position.trimmingCharacters(in: .whitespacesAndNewlines)
        profileManager.createProfile(
            name: trimmedName,
            email: nil,
            age: ageVal,
            team: teamVal,
            position: positionVal,
            decisionScore: testResult?.decisionScore,
            status: testResult?.status,
            consistency: testResult?.consistency
        )
        if playerStore.selectedPlayer != nil {
            playerStore.renameSelected(to: trimmedName)
        } else {
            playerStore.addPlayer(name: trimmedName)
        }
        hasCompletedInitialTest = true
        onComplete?()
    }

    private func skipAndContinue() {
        profileManager.createProfile(
            name: "Player",
            email: nil,
            age: nil,
            team: nil,
            position: nil,
            decisionScore: testResult?.decisionScore,
            status: testResult?.status,
            consistency: testResult?.consistency
        )
        if playerStore.selectedPlayer == nil {
            playerStore.addPlayer(name: "Player")
        }
        hasCompletedInitialTest = true
        onComplete?()
    }
}
