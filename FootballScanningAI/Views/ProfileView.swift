import SwiftUI

struct ProfileView: View {
    @ObservedObject var profileManager: UserProfileManager
    @State private var showingEditProfile = false
    @State private var showingDeleteAlert = false
    @State private var showingAddProfile = false
    @State private var showingProfileSelection = false
    
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
                        // Profile Selection Header
                        if profileManager.hasMultipleProfiles() {
                            VStack(spacing: 15) {
                                HStack {
                                    Text("Current Athlete")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Spacer()
                                    Button("Switch Athlete") {
                                        showingProfileSelection = true
                                    }
                                    .foregroundColor(.blue)
                                }
                                
                                // Current Profile Card
                                if let currentProfile = profileManager.currentProfile {
                                    ProfileCard(profile: currentProfile, isCurrent: true)
                                }
                            }
                            .padding()
                            .background(.ultraThinMaterial)
                            .cornerRadius(15)
                            .padding(.horizontal)
                        }
                        
                        // Current Profile Details
                        if let profile = profileManager.currentProfile {
                            // Profile Info Section
                            VStack(alignment: .leading, spacing: 15) {
                                Text("Profile Information")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                
                                VStack(spacing: 12) {
                                    InfoRow(label: "Name", value: profile.name)
                                    if let email = profile.email {
                                        InfoRow(label: "Email", value: email)
                                    }
                                    InfoRow(label: "Member Since", value: formatDate(profile.dateCreated))
                                    InfoRow(label: "Last Active", value: formatDate(profile.lastActive))
                                }
                            }
                            .padding()
                            .background(.ultraThinMaterial)
                            .cornerRadius(15)
                            .padding(.horizontal)
                            
                            // Training Statistics Section
                            VStack(alignment: .leading, spacing: 15) {
                                Text("Training Statistics")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                
                                LazyVGrid(columns: [
                                    GridItem(.flexible()),
                                    GridItem(.flexible())
                                ], spacing: 15) {
                                    StatCard(title: "Total Sessions", value: "\(profile.totalSessions)")
                                    StatCard(title: "Total Time", value: formatTime(profile.totalTrainingTime))
                                    StatCard(title: "This Week", value: "\(profile.sessionsThisWeek)")
                                    StatCard(title: "This Month", value: "\(profile.sessionsThisMonth)")
                                    StatCard(title: "Longest Session", value: formatTime(profile.longestSession))
                                    StatCard(title: "Average Session", value: formatTime(profile.averageSessionLength))
                                }
                            }
                            .padding()
                            .background(.ultraThinMaterial)
                            .cornerRadius(15)
                            .padding(.horizontal)
                            
                            // Family Stats (if multiple profiles)
                            if profileManager.hasMultipleProfiles() {
                                FamilyStatsView(familyStats: profileManager.getFamilyStats())
                            }
                            
                            // Action Buttons
                            VStack(spacing: 15) {
                                Button(action: { showingEditProfile = true }) {
                                    HStack {
                                        Image(systemName: "pencil")
                                        Text("Edit Profile")
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .cornerRadius(10)
                                }
                                
                                if profileManager.hasMultipleProfiles() {
                                    Button(action: { showingAddProfile = true }) {
                                        HStack {
                                            Image(systemName: "person.badge.plus")
                                            Text("Add New Athlete")
                                        }
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Color.green)
                                        .cornerRadius(10)
                                    }
                                }
                                
                                Button(action: { showingDeleteAlert = true }) {
                                    HStack {
                                        Image(systemName: "trash")
                                        Text("Delete Profile")
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.red)
                                    .cornerRadius(10)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.clear, for: .navigationBar)
            .foregroundColor(.white)
            .sheet(isPresented: $showingEditProfile) {
                if let profile = profileManager.currentProfile {
                    EditProfileView(profileManager: profileManager, profile: profile)
                }
            }
            .sheet(isPresented: $showingAddProfile) {
                AddProfileView(profileManager: profileManager)
            }
            .sheet(isPresented: $showingProfileSelection) {
                ProfileSelectionView(profileManager: profileManager)
            }
            .alert("Delete Profile", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if let profile = profileManager.currentProfile {
                        profileManager.deleteProfile(profile)
                    }
                }
            } message: {
                Text("Are you sure you want to delete this profile? This action cannot be undone.")
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let hours = Int(timeInterval) / 3600
        let minutes = Int(timeInterval) % 3600 / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

struct ProfileCard: View {
    let profile: UserProfile
    let isCurrent: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("\(profile.totalSessions) sessions • \(formatTime(profile.totalTrainingTime))")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
            
            if isCurrent {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.2))
        .cornerRadius(10)
    }
    
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let hours = Int(timeInterval) / 3600
        let minutes = Int(timeInterval) % 3600 / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.white.opacity(0.7))
            Spacer()
            Text(value)
                .foregroundColor(.white)
                .fontWeight(.medium)
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(10)
    }
}

struct FamilyStatsView: View {
    let familyStats: FamilyStats
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Family Overview")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 15) {
                StatCard(title: "Total Athletes", value: "\(familyStats.totalAthletes)")
                StatCard(title: "Total Sessions", value: "\(familyStats.totalSessions)")
                StatCard(title: "Total Training Time", value: formatTime(familyStats.totalTrainingTime))
                StatCard(title: "Avg Sessions/Athlete", value: String(format: "%.1f", familyStats.averageSessionsPerAthlete))
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(15)
        .padding(.horizontal)
    }
    
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let hours = Int(timeInterval) / 3600
        let minutes = Int(timeInterval) % 3600 / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

#Preview {
    ProfileView(profileManager: UserProfileManager())
} 