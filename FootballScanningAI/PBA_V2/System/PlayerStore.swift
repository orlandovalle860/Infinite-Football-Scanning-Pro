//
//  PlayerStore.swift
//  FootballScanningAI
//
//  PBA V2 — Local players (no sign-up); persist to UserDefaults.
//

import Foundation
import Combine

final class PlayerStore: ObservableObject {
    @Published private(set) var players: [Player] = []
    @Published var selectedPlayerId: UUID? {
        didSet {
            persistSelection()
        }
    }

    private let playersKey = "pba_players_v1"
    private let selectedKey = "pba_selected_player_v1"
    private let lastSelectedKey = "pba_last_selected_player_v1"
    /// Same keys as `UserProfileManager` — used to heal when `pba_players_v1` is empty but profiles still exist.
    private let userProfilesKey = "userProfiles"
    private let currentProfileIdKey = "currentProfileId"

    /// Load synchronously so the first SwiftUI frame sees saved players (avoids a flash of Intro when data exists).
    init() {
        load()
    }

    func load() {
        var healedFromUserProfiles = false
        if let data = UserDefaults.standard.data(forKey: playersKey),
           let decoded = try? JSONDecoder().decode([Player].self, from: data) {
            players = decoded
#if DEBUG
            print("[Profiles] source=local persisted UserDefaults \(playersKey) playerCount=\(players.count)")
#endif
        } else {
            players = []
#if DEBUG
            print("[Profiles] source=local no \(playersKey) data — starting with empty player list")
#endif
        }

        // If the player list file is missing but `UserProfileManager` data remains, mirror profiles into
        // `PlayerStore` so root routing does not briefly show Intro before `onAppear` / Supabase hydration.
        if players.isEmpty,
           let profileData = UserDefaults.standard.data(forKey: userProfilesKey),
           let loadedProfiles = try? JSONDecoder().decode([UserProfile].self, from: profileData),
           !loadedProfiles.isEmpty {
            players = loadedProfiles.map { Player(id: $0.id, name: $0.name, createdAt: $0.dateCreated) }
            healedFromUserProfiles = true
#if DEBUG
            print("[Profiles] source=local healed PlayerStore from \(userProfilesKey) count=\(players.count)")
#endif
        }

        if let uuidString = UserDefaults.standard.string(forKey: lastSelectedKey),
           let uuid = UUID(uuidString: uuidString) {
            selectedPlayerId = players.contains(where: { $0.id == uuid }) ? uuid : players.first?.id
        } else if let uuidString = UserDefaults.standard.string(forKey: selectedKey),
                  let uuid = UUID(uuidString: uuidString) {
            // Backward compatibility with older selection key.
            selectedPlayerId = players.contains(where: { $0.id == uuid }) ? uuid : players.first?.id
        } else if healedFromUserProfiles,
                  let idString = UserDefaults.standard.string(forKey: currentProfileIdKey),
                  let uuid = UUID(uuidString: idString),
                  players.contains(where: { $0.id == uuid }) {
            selectedPlayerId = uuid
        } else {
            selectedPlayerId = players.first?.id
        }

        if healedFromUserProfiles {
            persist()
        }
    }

    func persist() {
        if let data = try? JSONEncoder().encode(players) {
            UserDefaults.standard.set(data, forKey: playersKey)
        }
        persistSelection()
    }

    private func persistSelection() {
        if let id = selectedPlayerId {
            UserDefaults.standard.set(id.uuidString, forKey: selectedKey)
            UserDefaults.standard.set(id.uuidString, forKey: lastSelectedKey)
        } else {
            UserDefaults.standard.removeObject(forKey: selectedKey)
            UserDefaults.standard.removeObject(forKey: lastSelectedKey)
        }
    }

    func createDefaultIfNeeded() {
        if players.isEmpty {
            let p = Player(id: UUID(), name: "Player 1", createdAt: Date())
            players = [p]
            selectedPlayerId = p.id
            persist()
        }
    }

    func renameSelected(to newName: String) {
        guard let id = selectedPlayerId,
              let idx = players.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        players[idx] = Player(id: players[idx].id, name: trimmed, createdAt: players[idx].createdAt)
        persist()
    }

    func addPlayer(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "Player \(players.count + 1)" : trimmed
        let p = Player(id: UUID(), name: finalName, createdAt: Date())
        players.append(p)
        selectedPlayerId = p.id
        persist()
    }

    /// Add a player with a specific id (e.g. to sync with a newly created UserProfile).
    func addPlayer(id: UUID, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "Player" : trimmed
        let p = Player(id: id, name: finalName, createdAt: Date())
        players.append(p)
        selectedPlayerId = p.id
        persist()
    }

    /// Remove a player by id (e.g. when a profile is deleted).
    func removePlayer(id: UUID) {
        players.removeAll { $0.id == id }
        if selectedPlayerId == id {
            selectedPlayerId = players.first?.id
        }
        PartnerPassTempoCalibrationStore.clearSavedCalibration(playerId: id)
        SoloWallCalibrationController.clearSavedSoloWallCalibration(playerId: id)
        persist()
    }

    /// Clear all players and selection (e.g. when last profile is deleted). Call before routing to profile creation.
    func clearAll() {
        players = []
        selectedPlayerId = nil
        UserDefaults.standard.removeObject(forKey: playersKey)
        UserDefaults.standard.removeObject(forKey: selectedKey)
        UserDefaults.standard.removeObject(forKey: lastSelectedKey)
    }

    func selectPlayer(id: UUID) {
        guard players.contains(where: { $0.id == id }) else { return }
        selectedPlayerId = id
        persist()
    }

    /// Clears the selected player only (Switch Player). Keeps the player list for the same account/device.
    func clearSelectedPlayerOnly() {
        selectedPlayerId = nil
        persist()
    }

    var selectedPlayer: Player? {
        players.first(where: { $0.id == selectedPlayerId })
    }
}
