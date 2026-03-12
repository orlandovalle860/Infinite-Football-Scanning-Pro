import SwiftUI

// MARK: - Last trained label from lastActive date
private func lastTrainedLabel(for date: Date) -> String {
    let cal = Calendar.current
    if cal.isDateInToday(date) { return "Today" }
    if cal.isDateInYesterday(date) { return "Yesterday" }
    let days = cal.dateComponents([.day], from: date, to: Date()).day ?? 0
    if days == 2 { return "2 days ago" }
    if days < 7 { return "\(days) days ago" }
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    return formatter.string(from: date)
}

// MARK: - Players Sheet (switch who you're training)
struct PlayersSheetView: View {
    @ObservedObject var profileManager: UserProfileManager
    @EnvironmentObject private var playerStore: PlayerStore
    @Environment(\.dismiss) private var dismiss

    @State private var isEditMode = false
    @State private var showingAddPlayer = false
    @State private var profileToRename: UserProfile?
    @State private var profileToRemove: UserProfile?
    @State private var showingRemoveAlert = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.1),
                        Color(red: 0.1, green: 0.1, blue: 0.15)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    Text("Switch who you're training.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                        .padding(.bottom, 12)

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(profileManager.profiles) { profile in
                                PlayerRowView(
                                    profile: profile,
                                    isCurrent: profileManager.currentProfile?.id == profile.id,
                                    isEditMode: isEditMode,
                                    lastTrainedText: lastTrainedLabel(for: profile.lastActive),
                                    onTap: {
                                        if isEditMode { return }
                                        profileManager.switchToProfile(profile)
                                        playerStore.selectPlayer(id: profile.id)
                                        dismiss()
                                    },
                                    onRename: { profileToRename = profile },
                                    onRemove: { profileToRemove = profile; showingRemoveAlert = true }
                                )
                            }
                        }
                        .padding(.horizontal)
                    }

                    VStack(spacing: 12) {
                        Button(action: { showingAddPlayer = true }) {
                            HStack {
                                Image(systemName: "plus")
                                Text("Add Player")
                            }
                            .font(.headline)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.yellow)
                            .cornerRadius(14)
                        }
                        .buttonStyle(PlainButtonStyle())

                        Text("Great for siblings or training groups.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))

                        Button(action: { isEditMode.toggle() }) {
                            Text("Edit")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.white.opacity(0.9))
                        }
                        .padding(.vertical, 8)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Players")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.clear, for: .navigationBar)
            .foregroundColor(.white)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.white)
                }
            }
            .sheet(isPresented: $showingAddPlayer) {
                AddPlayerView(profileManager: profileManager)
            }
            .sheet(item: $profileToRename) { profile in
                RenamePlayerView(profileManager: profileManager, profile: profile) {
                    profileToRename = nil
                }
            }
            .alert("Remove Player?", isPresented: $showingRemoveAlert) {
                Button("Cancel", role: .cancel) {
                    profileToRemove = nil
                }
                Button("Remove", role: .destructive) {
                    if let p = profileToRemove {
                        ProgressStore.shared.removeSessions(forPlayerId: p.id)
                        profileManager.deleteProfile(p)
                        playerStore.removePlayer(id: p.id)
                        if profileManager.profiles.isEmpty {
                            playerStore.clearAll()
                        }
                    }
                    profileToRemove = nil
                    if profileManager.profiles.isEmpty { dismiss() }
                }
            } message: {
                Text("This will delete their progress from this device.")
            }
        }
    }
}

// MARK: - Player row (name, last trained, Training now pill; edit: Rename / Remove)
struct PlayerRowView: View {
    let profile: UserProfile
    let isCurrent: Bool
    let isEditMode: Bool
    let lastTrainedText: String
    let onTap: () -> Void
    let onRename: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Group {
            if isEditMode {
                rowContent
                    .contentShape(Rectangle())
            } else {
                Button(action: onTap) {
                    rowContent
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(Color.white.opacity(isCurrent && !isEditMode ? 0.12 : 0.06))
        .cornerRadius(12)
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name)
                    .font(.body.weight(.semibold))
                    .foregroundColor(.white)
                Text("Last trained: \(lastTrainedText)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            Spacer(minLength: 8)
            if isEditMode {
                HStack(spacing: 12) {
                    Button("Rename", action: onRename)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.yellow)
                        .buttonStyle(.borderless)
                        Button("Remove", action: onRemove)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.red)
                            .buttonStyle(.borderless)
                }
            } else {
                if isCurrent {
                    Text("Training now")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.yellow)
                        .cornerRadius(20)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }
}

// MARK: - Add Player
struct AddPlayerView: View {
    @ObservedObject var profileManager: UserProfileManager
    @EnvironmentObject private var playerStore: PlayerStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var age = ""
    @State private var team = ""
    @State private var position = ""
    @State private var showMore = false
    @State private var validationMessage = ""

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.1),
                        Color(red: 0.1, green: 0.1, blue: 0.15)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Name")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.white)
                            TextField("Enter name", text: $name)
                                .textContentType(.name)
                                .padding()
                                .background(Color.white)
                                .foregroundColor(.black)
                                .cornerRadius(10)
                            if !validationMessage.isEmpty {
                                Text(validationMessage)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }

                        Button(action: { showMore.toggle() }) {
                            HStack {
                                Text("More")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.white.opacity(0.9))
                                Image(systemName: showMore ? "chevron.up" : "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }

                        if showMore {
                            VStack(alignment: .leading, spacing: 16) {
                                optionalField("Age (optional)", placeholder: "e.g. 12", text: $age)
                                    .keyboardType(.numberPad)
                                optionalField("Team (optional)", placeholder: "e.g. Hartford United", text: $team)
                                optionalField("Position (optional)", placeholder: "e.g. Midfielder", text: $position)
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Add Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.clear, for: .navigationBar)
            .foregroundColor(.white)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .foregroundColor(.yellow)
                }
            }
        }
    }

    private func optionalField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white.opacity(0.9))
            TextField(placeholder, text: text)
                .padding()
                .background(Color.white)
                .foregroundColor(.black)
                .cornerRadius(10)
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            validationMessage = "Please enter a name."
            return
        }
        validationMessage = ""
        let ageTrim = age.trimmingCharacters(in: .whitespacesAndNewlines)
        let teamTrim = team.trimmingCharacters(in: .whitespacesAndNewlines)
        let positionTrim = position.trimmingCharacters(in: .whitespacesAndNewlines)
        let newProfile = profileManager.addProfile(
            name: trimmed,
            email: nil,
            age: ageTrim.isEmpty ? nil : ageTrim,
            team: teamTrim.isEmpty ? nil : teamTrim,
            position: positionTrim.isEmpty ? nil : positionTrim
        )
        playerStore.addPlayer(id: newProfile.id, name: trimmed)
        dismiss()
    }
}

// MARK: - Rename Player
struct RenamePlayerView: View {
    @ObservedObject var profileManager: UserProfileManager
    let profile: UserProfile
    let onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var validationMessage = ""

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.1),
                        Color(red: 0.1, green: 0.1, blue: 0.15)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 16) {
                    Text("Name")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                    TextField("Enter name", text: $name)
                        .textContentType(.name)
                        .padding()
                        .background(Color.white)
                        .foregroundColor(.black)
                        .cornerRadius(10)
                    if !validationMessage.isEmpty {
                        Text(validationMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Rename Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.clear, for: .navigationBar)
            .foregroundColor(.white)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onDismiss()
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .foregroundColor(.yellow)
                }
            }
            .onAppear { name = profile.name }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            validationMessage = "Please enter a name."
            return
        }
        validationMessage = ""
        var updated = profile
        updated.name = trimmed
        profileManager.updateProfile(updated)
        onDismiss()
        dismiss()
    }
}

#Preview("Players sheet") {
    PlayersSheetView(profileManager: UserProfileManager())
        .environmentObject(PlayerStore())
}

#Preview("Add Player") {
    AddPlayerView(profileManager: UserProfileManager())
}
