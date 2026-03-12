import SwiftUI

struct AddProfileView: View {
    @ObservedObject var profileManager: UserProfileManager
    @Environment(\.dismiss) private var dismiss
    
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
                    VStack(spacing: 20) {
                        // Header - More compact for landscape
                        VStack(spacing: 10) {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 40))
                                .foregroundColor(.blue)
                            
                            Text("Add New Athlete")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            Text("Create a profile for a new family member")
                                .font(.body)
                                .foregroundColor(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 20)
                        
                        // Form
                        VStack(spacing: 15) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Athlete Name")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                
                                ZStack(alignment: .leading) {
                                    if name.isEmpty {
                                        Text("Enter athlete's name")
                                            .foregroundColor(.gray)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 12)
                                    }
                                    TextField("", text: $name)
                                        .padding()
                                        .background(Color.white)
                                        .foregroundColor(.black)
                                        .cornerRadius(8)
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        // Action Buttons
                        VStack(spacing: 12) {
                            Button(action: createProfile) {
                                HStack {
                                    Image(systemName: "person.badge.plus")
                                    Text("Create Profile")
                                }
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(15)
                            }
                            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            
                            Button(action: { dismiss() }) {
                                Text("Cancel")
                                    .font(.title3)
                                    .foregroundColor(.white.opacity(0.8))
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.gray.opacity(0.3))
                                    .cornerRadius(15)
                            }
                        }
                        .padding(.horizontal)
                        
                        // Extra space to ensure scrolling works
                        Spacer(minLength: 200)
                    }
                    .frame(minHeight: UIScreen.main.bounds.height + 100)
                }
            }
            .navigationBarHidden(true)
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .alert("Profile Creation", isPresented: $showingAlert) {
                Button("OK") {
                    if alertMessage.contains("successfully") {
                        dismiss()
                    }
                }
            } message: {
                Text(alertMessage)
            }
        }
    }
    
    private func createProfile() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedName.isEmpty else {
            alertMessage = "Please enter a name for the athlete."
            showingAlert = true
            return
        }
        
        // Check if name already exists
        if profileManager.profiles.contains(where: { $0.name.lowercased() == trimmedName.lowercased() }) {
            alertMessage = "An athlete with this name already exists. Please choose a different name."
            showingAlert = true
            return
        }
        
        // Create the profile (email belongs to user account, not player)
        profileManager.addProfile(name: trimmedName, email: nil)
        
        alertMessage = "Profile for \(trimmedName) created successfully!"
        showingAlert = true
    }
}

#Preview {
    AddProfileView(profileManager: UserProfileManager())
} 