import SwiftUI

struct AddProfileView: View {
    @ObservedObject var profileManager: UserProfileManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String = ""
    @State private var email: String = ""
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
                
                VStack(spacing: 30) {
                    // Header
                    VStack(spacing: 15) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                        
                        Text("Add New Athlete")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text("Create a profile for a new family member")
                            .font(.body)
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 40)
                    
                    // Form
                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Athlete Name")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            TextField("Enter athlete's name", text: $name)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .foregroundColor(.black)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email (Optional)")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            TextField("Enter email address", text: $email)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .foregroundColor(.black)
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                    
                    // Action Buttons
                    VStack(spacing: 15) {
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
                    .padding(.bottom, 40)
                }
            }
            .navigationBarHidden(true)
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
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        
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
        
        // Create the profile
        let emailToUse = trimmedEmail.isEmpty ? nil : trimmedEmail
        profileManager.addProfile(name: trimmedName, email: emailToUse)
        
        alertMessage = "Profile for \(trimmedName) created successfully!"
        showingAlert = true
    }
}

#Preview {
    AddProfileView(profileManager: UserProfileManager())
} 