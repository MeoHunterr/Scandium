// LibraryManager.swift — Local persistence for Liked Tracks & Recently Played
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import Foundation
import Combine

final class LibraryManager: ObservableObject {

    static let shared = LibraryManager()

    // MARK: - Published State

    @Published private(set) var likedTracks: [Track] = []
    @Published private(set) var recentlyPlayed: [Track] = []

    // MARK: - Storage Keys

    private static let likedTracksKey = "scandium_liked_tracks_v1"
    private static let recentlyPlayedKey = "scandium_recently_played_v1"
    private static let maxRecentlyPlayed = 50

    // MARK: - Init

    init() {
        loadData()
    }

    // MARK: - Liked Tracks API

    func isLiked(track: Track) -> Bool {
        likedTracks.contains(where: { $0.id == track.id })
    }

    func toggleLike(track: Track) {
        if isLiked(track: track) {
            unlike(track: track)
        } else {
            like(track: track)
        }
    }

    func like(track: Track) {
        guard !isLiked(track: track) else { return }
        likedTracks.insert(track, at: 0)
        saveLikedTracks()
    }

    func unlike(track: Track) {
        likedTracks.removeAll(where: { $0.id == track.id })
        saveLikedTracks()
    }

    func clearLikedTracks() {
        likedTracks.removeAll()
        saveLikedTracks()
    }

    // MARK: - Recently Played API

    func addToRecentlyPlayed(track: Track) {
        // Remove if already in list to move to top
        recentlyPlayed.removeAll(where: { $0.id == track.id })
        recentlyPlayed.insert(track, at: 0)

        // Enforce maximum capacity
        if recentlyPlayed.count > Self.maxRecentlyPlayed {
            recentlyPlayed = Array(recentlyPlayed.prefix(Self.maxRecentlyPlayed))
        }

        saveRecentlyPlayed()
    }

    func clearRecentlyPlayed() {
        recentlyPlayed.removeAll()
        saveRecentlyPlayed()
    }

    func clearAllData() {
        likedTracks.removeAll()
        recentlyPlayed.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.likedTracksKey)
        UserDefaults.standard.removeObject(forKey: Self.recentlyPlayedKey)
    }

    // MARK: - Persistence Helpers

    private func loadData() {
        let decoder = JSONDecoder()

        if let likedData = UserDefaults.standard.data(forKey: Self.likedTracksKey),
           let tracks = try? decoder.decode([Track].self, from: likedData) {
            self.likedTracks = tracks
        }

        if let recentData = UserDefaults.standard.data(forKey: Self.recentlyPlayedKey),
           let tracks = try? decoder.decode([Track].self, from: recentData) {
            self.recentlyPlayed = tracks
        }
    }

    private func saveLikedTracks() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(likedTracks) {
            UserDefaults.standard.set(data, forKey: Self.likedTracksKey)
        }
    }

    private func saveRecentlyPlayed() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(recentlyPlayed) {
            UserDefaults.standard.set(data, forKey: Self.recentlyPlayedKey)
        }
    }
}
