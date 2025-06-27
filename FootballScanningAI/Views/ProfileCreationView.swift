import SwiftUI

struct ProfileCreationView: View {
    @ObservedObject var profileManager: UserProfileManager
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
                
                ScrollView {
                    VStack(spacing: 30) {
                        // Header
                        VStack(spacing: 16) {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.blue)
                            
                            Text("Welcome to")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                            
                            Text("Infinite Football Scanning Pro")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                                .multilineTextAlignment(.center)
                            
                            Text("Create your first athlete profile to start training")
                                .font(.body)
                                .foregroundColor(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding(.top, 20)
                        
                        // Form
                        VStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Athlete Name")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                
                                TextField("", text: $name)
                                    .placeholder(when: name.isEmpty) {
                                        Text("Enter athlete's name")
                                            .foregroundColor(.gray)
                                    }
                                    .padding()
                                    .background(Color.white)
                                    .foregroundColor(.black)
                                    .cornerRadius(10)
                                    .autocapitalization(.words)
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Email (Optional)")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                
                                TextField("", text: $email)
                                    .placeholder(when: email.isEmpty) {
                                        Text("Enter email address")
                                            .foregroundColor(.gray)
                                    }
                                    .padding()
                                    .background(Color.white)
                                    .foregroundColor(.black)
                                    .cornerRadius(10)
                                    .keyboardType(.emailAddress)
                                    .autocapitalization(.none)
                            }
                        }
                        .padding(.horizontal)
                        
                        // Create Profile Button
                        Button(action: createProfile) {
                            HStack {
                                Image(systemName: "person.badge.plus")
                                Text("Create Profile")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(name.isEmpty ? Color.gray : Color.blue)
                            .cornerRadius(15)
                        }
                        .disabled(name.isEmpty)
                        .padding(.horizontal)
                        
                        // Benefits
                        VStack(alignment: .leading, spacing: 12) {
                            Text("What you'll get:")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            BenefitRow(icon: "chart.line.uptrend.xyaxis", text: "Track training progress")
                            BenefitRow(icon: "clock", text: "Monitor session durations")
                            BenefitRow(icon: "gear", text: "Save preferences")
                            BenefitRow(icon: "calendar", text: "View training history")
                            BenefitRow(icon: "person.2", text: "Support multiple athletes")
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(15)
                        .padding(.horizontal)
                        
                        // Extra space to ensure scrolling works
                        Spacer(minLength: 200)
                    }
                    .frame(minHeight: UIScreen.main.bounds.height + 100)
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
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalEmail = trimmedEmail.isEmpty ? nil : trimmedEmail
        
        profileManager.createProfile(name: trimmedName, email: finalEmail)
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
} 