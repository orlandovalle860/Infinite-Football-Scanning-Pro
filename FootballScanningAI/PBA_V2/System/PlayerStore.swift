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
    @Published var selectedPlayerId: UUID?

    private let playersKey = "pba_players_v1"
    private let selectedKey = "pba_selected_player_v1"

    func load() {
        if let data = UserDefaults.standard.data(forKey: playersKey),
           let decoded = try? JSONDecoder().decode([Player].self, from: data) {
            players = decoded
        } else {
            players = []
        }
        if let uuidString = UserDefaults.standard.string(forKey: selectedKey),
           let uuid = UUID(uuidString: uuidString) {
            selectedPlayerId = players.contains(where: { $0.id == uuid }) ? uuid : players.first?.id
        } else {
            selectedPlayerId = players.first?.id
        }
    }

    func persist() {
        if let data = try? JSONEncoder().encode(players) {
            UserDefaults.standard.set(data, forKey: playersKey)
        }
        if let id = selectedPlayerId {
            UserDefaults.standard.set(id.uuidString, forKey: selectedKey)
        } else {
            UserDefaults.standard.removeObject(forKey: selectedKey)
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

    func selectPlayer(id: UUID) {
        guard players.contains(where: { $0.id == id }) else { return }
        selectedPlayerId = id
        persist()
    }

    var selectedPlayer: Player? {
        players.first(where: { $0.id == selectedPlayerId })
    }
}
