import SwiftUI

struct ProfileCreationView: View {
    @ObservedObject var profileManager: UserProfileManager
    @EnvironmentObject private var playerStore: PlayerStore
    @State private var name: String = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
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
                    VStack(spacing: 24) {
                        VStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.system(size: 56))
                                .foregroundColor(.yellow)
                            Text("Create a player profile")
                                .font(.title2.weight(.bold))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                            Text("Add a player to start training.")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.85))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding(.top, 20)

                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Name")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.white)
                                TextField("", text: $name)
                                    .placeholder(when: name.isEmpty) {
                                        Text("Enter player's name")
                                            .foregroundColor(.gray)
                                    }
                                    .padding()
                                    .background(Color.white)
                                    .foregroundColor(.black)
                                    .cornerRadius(10)
                                    .autocapitalization(.words)
                            }
                        }
                        .padding(.horizontal)

                        Button(action: createProfile) {
                            HStack(spacing: 8) {
                                Image(systemName: "person.badge.plus")
                                Text("Create Profile")
                            }
                            .font(.headline.weight(.semibold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(name.isEmpty ? Color.gray.opacity(0.6) : Color.yellow)
                            .cornerRadius(14)
                        }
                        .disabled(name.isEmpty)
                        .padding(.horizontal)
                        .padding(.top, 8)

                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationBarHidden(true)
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .alert("Profile Creation", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }
    
    private func createProfile() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            alertMessage = "Please enter a valid name"
            showingAlert = true
            return
        }
        
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profileManager.createProfile(name: trimmedName, email: nil)
        if let newProfile = profileManager.currentProfile {
            playerStore.addPlayer(id: newProfile.id, name: trimmedName)
        }
    }
}

// Extension to add placeholder functionality
extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content) -> some View {
        
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

#Preview {
    ProfileCreationView(profileManager: UserProfileManager())
        .environmentObject(PlayerStore())
} 