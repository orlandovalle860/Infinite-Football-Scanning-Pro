import SwiftUI

struct EditProfileView: View {
    @ObservedObject var profileManager: UserProfileManager
    let profile: UserProfile
    
    @State private var name: String
    @State private var email: String
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @Environment(\.dismiss) private var dismiss
    
    init(profileManager: UserProfileManager, profile: UserProfile) {
        self.profileManager = profileManager
        self.profile = profile
        self._name = State(initialValue: profile.name)
        self._email = State(initialValue: profile.email ?? "")
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Personal Information") {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                    
                    TextField("Email (Optional)", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                }
                
                Section("Profile Information") {
                    HStack {
                        Text("Member Since")
                        Spacer()
                        Text(profile.dateCreated.formatted(date: .abbreviated, time: .omitted))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Last Active")
                        Spacer()
                        Text(profile.lastActive.formatted(date: .abbreviated, time: .shortened))
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Training Statistics") {
                    HStack {
                        Text("Total Sessions")
                        Spacer()
                        Text("\(profile.totalSessions)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Total Training Time")
                        Spacer()
                        Text(formatTime(profile.totalTrainingTime))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Longest Session")
                        Spacer()
                        Text(formatTime(profile.longestSession))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveProfile()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .alert("Profile Update", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }
    
    private func saveProfile() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            alertMessage = "Please enter a valid name"
            showingAlert = true
            return
        }
        
        var updatedProfile = profile
        updatedProfile.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedProfile.email = email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : email.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedProfile.lastActive = Date()
        
        profileManager.updateProfile(updatedProfile)
        dismiss()
    }
    
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let hours = Int(timeInterval) / 3600
        let minutes = Int(timeInterval) / 60 % 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

#Preview {
    EditProfileView(
        profileManager: UserProfileManager(),
        profile: UserProfile(name: "John Doe", email: "john@example.com")
    )
} 