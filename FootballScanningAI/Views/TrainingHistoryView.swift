import SwiftUI

struct TrainingHistoryView: View {
    @ObservedObject var profileManager: UserProfileManager
    @State private var selectedFilter: SessionFilter = .all
    @State private var searchText = ""
    
    enum SessionFilter: String, CaseIterable {
        case all = "All"
        case colors = "Colors"
        case numbers = "Numbers"
        case arrows = "Arrows"
        case lanes = "Lanes"
        case fourGoalGame = "4-Goal Game"
    }
    
    var filteredSessions: [TrainingSession] {
        let allSessions = profileManager.currentProfile?.trainingSessions ?? []
        
        let filteredByType = selectedFilter == .all ? allSessions : allSessions.filter { session in
            switch selectedFilter {
            case .all:
                return true
            case .colors:
                return session.displayMode == .colors
            case .numbers:
                return session.displayMode == .numbers
            case .arrows:
                return session.displayMode == .colorsArrows
            case .lanes:
                return session.displayMode == .lanes
            case .fourGoalGame:
                return session.displayMode == .fourGoalGame
            }
        }
        
        if searchText.isEmpty {
            return filteredByType.sorted { $0.date > $1.date }
        } else {
            return filteredByType.filter { session in
                session.displayMode.rawValue.localizedCaseInsensitiveContains(searchText) ||
                formatDuration(session.duration).localizedCaseInsensitiveContains(searchText) ||
                session.date.formatted(date: Date.FormatStyle.DateStyle.abbreviated, time: Date.FormatStyle.TimeStyle.shortened).localizedCaseInsensitiveContains(searchText)
            }.sorted { $0.date > $1.date }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Filter and Search
                VStack(spacing: 12) {
                    // Search Bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        
                        TextField("Search sessions...", text: $searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    
                    // Filter Picker
                    Picker("Filter", selection: $selectedFilter) {
                        ForEach(SessionFilter.allCases, id: \.self) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                .padding()
                
                // Sessions List
                if filteredSessions.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "clock.badge.questionmark")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)
                        
                        Text(selectedFilter == .all ? "No training sessions yet" : "No \(selectedFilter.rawValue.lowercased()) sessions")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("Start training to see your history here")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGray6))
                } else {
                    List {
                        ForEach(groupedSessions.keys.sorted(by: >), id: \.self) { date in
                            Section(header: Text(formatDate(date))) {
                                ForEach(groupedSessions[date] ?? [], id: \.id) { session in
                                    NavigationLink(destination: SessionDetailView(session: session)) {
                                        SessionRowView(session: session)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(InsetGroupedListStyle())
                }
            }
            .navigationTitle("Training History")
            .navigationBarTitleDisplayMode(.large)
        }
    }
    
    private var groupedSessions: [Date: [TrainingSession]] {
        let calendar = Calendar.current
        return Dictionary(grouping: filteredSessions) { session in
            calendar.startOfDay(for: session.date)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        
        if calendar.isDate(date, inSameDayAs: today) {
            return "Today"
        } else if calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        } else {
            return date.formatted(date: Date.FormatStyle.DateStyle.abbreviated, time: Date.FormatStyle.TimeStyle.omitted)
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct SessionDetailView: View {
    let session: TrainingSession
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Session Header
                VStack(spacing: 12) {
                    Text(session.displayMode.rawValue.capitalized)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text(session.date.formatted(date: Date.FormatStyle.DateStyle.complete, time: Date.FormatStyle.TimeStyle.shortened))
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    Text("Duration: \(formatDuration(session.duration))")
                        .font(.headline)
                        .foregroundColor(.blue)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(16)
                
                // Session Details
                VStack(spacing: 16) {
                    DetailSection(title: "Display Settings", items: [
                        ("Mode", session.displayMode.rawValue.capitalized),
                        ("Number Color", session.numberColor.description),
                        ("Arrow Color", session.arrowColor.description),
                        ("Color Set", session.colorSet.rawValue.capitalized),
                        ("Action Set", session.actionSet.rawValue.capitalized)
                    ])
                    
                    DetailSection(title: "Training Elements", items: [
                        ("Colors Used", "\(session.colorsUsed.count)"),
                        ("Numbers Used", "\(session.numbersUsed.count)"),
                        ("Arrows Used", "\(session.arrowsUsed.count)"),
                        ("Lanes Used", "\(session.lanesUsed.count)")
                    ])
                    
                    DetailSection(title: "Critical Scan Settings", items: [
                        ("Delay", "\(session.criticalScanDelay)s"),
                        ("Duration", "\(session.criticalScanDuration)s"),
                        ("Reset Time", "\(session.criticalScanResetTime)s")
                    ])
                    
                    DetailSection(title: "Preferences", items: [
                        ("Screen Protection", session.screenProtectionEnabled ? "Enabled" : "Disabled"),
                        ("Sound", session.soundEnabled ? "Enabled" : "Disabled"),
                        ("Beep Interval", session.beepInterval.rawValue.capitalized)
                    ])
                }
            }
            .padding()
        }
        .navigationTitle("Session Details")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

struct DetailSection: View {
    let title: String
    let items: [(String, String)]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(spacing: 8) {
                ForEach(items, id: \.0) { item in
                    HStack {
                        Text(item.0)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(item.1)
                            .fontWeight(.medium)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

#Preview {
    TrainingHistoryView(profileManager: UserProfileManager())
}

struct SessionRowView: View {
    let session: TrainingSession

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(session.displayMode.rawValue.capitalized)
                    .font(.headline)
                Text(session.date, style: .date)
                    .font(.caption)
            }
            Spacer()
            Text(formatDuration(session.duration))
                .font(.headline)
        }
        .padding(.vertical, 4)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
} 