// LibraryManager.swift — Local persistence for Liked Tracks & Recently Played (SQLite3)
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import Foundation
import Combine
import SQLite3

// MARK: - SQLite Helpers

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class LibraryManager: ObservableObject {

    static let shared = LibraryManager()

    // MARK: - Published State

    @Published private(set) var likedTracks: [Track] = []
    @Published private(set) var recentlyPlayed: [Track] = []
    @Published private(set) var userPlaylists: [SoundCloudPlaylist] = []

    // MARK: - Constants

    private static let maxRecentlyPlayed = 50

    // Legacy UserDefaults keys (for one-time migration)
    private static let legacyLikedKey      = "scandium_liked_tracks_v1"
    private static let legacyRecentKey     = "scandium_recently_played_v1"
    private static let legacyPlaylistsKey  = "scandium_user_playlists_v1"

    // Migration sentinel suffix
    private static let migratedSuffix      = "_migrated"

    // MARK: - SQLite

    private var db: OpaquePointer?
    private let dbQueue = DispatchQueue(label: "com.scandium.db")

    // MARK: - Init

    init() {
        openDatabase()
        createTables()
        migrateFromUserDefaultsIfNeeded()
        loadData()
    }

    // MARK: - Database Setup

    private func openDatabase() {
        let dirs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        guard let dir = dirs.first else { return }
        let dbURL = dir.appendingPathComponent("scandium_library.db")
        let path = dbURL.path
        path.withCString { cPath in
            if sqlite3_open(cPath, &db) != SQLITE_OK {
                db = nil
            }
        }
    }

    private func createTables() {
        guard let db = db else { return }
        dbQueue.sync {
            let createLiked = """
                CREATE TABLE IF NOT EXISTS liked_tracks (
                    id INTEGER PRIMARY KEY,
                    json_data TEXT NOT NULL,
                    position INTEGER
                );
            """
            let createRecent = """
                CREATE TABLE IF NOT EXISTS recently_played (
                    id INTEGER PRIMARY KEY,
                    json_data TEXT NOT NULL,
                    position INTEGER
                );
            """
            let createPlaylists = """
                CREATE TABLE IF NOT EXISTS playlists (
                    id INTEGER PRIMARY KEY,
                    json_data TEXT NOT NULL,
                    position INTEGER
                );
            """
            sqlite3_exec(db, createLiked, nil, nil, nil)
            sqlite3_exec(db, createRecent, nil, nil, nil)
            sqlite3_exec(db, createPlaylists, nil, nil, nil)
        }
    }

    // MARK: - Migration from UserDefaults

    private func migrateFromUserDefaultsIfNeeded() {
        let ud = UserDefaults.standard
        let migratedLikedKey     = Self.legacyLikedKey + Self.migratedSuffix
        let migratedRecentKey    = Self.legacyRecentKey + Self.migratedSuffix
        let migratedPlaylistsKey = Self.legacyPlaylistsKey + Self.migratedSuffix

        // Migrate liked tracks
        if let data = ud.data(forKey: Self.legacyLikedKey),
           !ud.bool(forKey: migratedLikedKey) {
            if let tracks = try? JSONDecoder().decode([Track].self, from: data) {
                dbQueue.sync { self._insertLikedTracks(tracks) }
            }
            ud.removeObject(forKey: Self.legacyLikedKey)
            ud.set(true, forKey: migratedLikedKey)
        }

        // Migrate recently played
        if let data = ud.data(forKey: Self.legacyRecentKey),
           !ud.bool(forKey: migratedRecentKey) {
            if let tracks = try? JSONDecoder().decode([Track].self, from: data) {
                dbQueue.sync { self._insertRecentlyPlayed(tracks) }
            }
            ud.removeObject(forKey: Self.legacyRecentKey)
            ud.set(true, forKey: migratedRecentKey)
        }

        // Migrate playlists
        if let data = ud.data(forKey: Self.legacyPlaylistsKey),
           !ud.bool(forKey: migratedPlaylistsKey) {
            if let playlists = try? JSONDecoder().decode([SoundCloudPlaylist].self, from: data) {
                dbQueue.sync { self._insertPlaylists(playlists) }
            }
            ud.removeObject(forKey: Self.legacyPlaylistsKey)
            ud.set(true, forKey: migratedPlaylistsKey)
        }
    }

    // MARK: - Load from SQLite

    private func loadData() {
        dbQueue.sync {
            let liked     = self._queryTracks(table: "liked_tracks")
            let recent    = self._queryTracks(table: "recently_played")
            let playlists = self._queryPlaylists()
            DispatchQueue.main.async {
                self.likedTracks    = liked
                self.recentlyPlayed = recent
                self.userPlaylists  = playlists
            }
        }
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
        // Renumber positions
        dbQueue.async { self._insertLikedTracks(self.likedTracks) }
    }

    func unlike(track: Track) {
        likedTracks.removeAll(where: { $0.id == track.id })
        dbQueue.async {
            self._deleteTrack(id: track.id, table: "liked_tracks")
            // Re-index remaining positions
            for (pos, t) in self.likedTracks.enumerated() {
                self._updatePosition(id: t.id, position: pos, table: "liked_tracks")
            }
        }
    }

    func clearLikedTracks() {
        likedTracks.removeAll()
        dbQueue.async { self._deleteAll(table: "liked_tracks") }
    }

    /// Merges remote liked tracks into local liked tracks, avoiding duplicates
    func syncLikedTracks(_ tracks: [Track]) {
        var changed = false
        for track in tracks.reversed() {
            if !isLiked(track: track) {
                likedTracks.insert(track, at: 0)
                changed = true
            }
        }
        if changed {
            dbQueue.async { self._insertLikedTracks(self.likedTracks) }
        }
    }

    /// Synchronizes user playlists from SoundCloud account
    func syncUserPlaylists(_ playlists: [SoundCloudPlaylist]) {
        self.userPlaylists = playlists
        dbQueue.async { self._insertPlaylists(playlists) }
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

        let snapshot = recentlyPlayed
        dbQueue.async { self._insertRecentlyPlayed(snapshot) }
    }

    func clearRecentlyPlayed() {
        recentlyPlayed.removeAll()
        dbQueue.async { self._deleteAll(table: "recently_played") }
    }

    func clearAllData() {
        likedTracks.removeAll()
        recentlyPlayed.removeAll()
        userPlaylists.removeAll()
        dbQueue.async {
            self._deleteAll(table: "liked_tracks")
            self._deleteAll(table: "recently_played")
            self._deleteAll(table: "playlists")
        }
        // Also clean up legacy UserDefaults keys for safety
        let ud = UserDefaults.standard
        ud.removeObject(forKey: Self.legacyLikedKey)
        ud.removeObject(forKey: Self.legacyRecentKey)
        ud.removeObject(forKey: Self.legacyPlaylistsKey)
    }

    // MARK: - Private SQLite Helpers (run on dbQueue)

    private func _queryTracks(table: String) -> [Track] {
        guard let db = db else { return [] }
        var results: [Track] = []
        var stmt: OpaquePointer?
        let sql = "SELECT json_data FROM \(table) ORDER BY position ASC;"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let cStr = sqlite3_column_text(stmt, 0) {
                    let jsonStr = String(cString: cStr)
                    if let data = jsonStr.data(using: .utf8),
                       let track = try? JSONDecoder().decode(Track.self, from: data) {
                        results.append(track)
                    }
                }
            }
        }
        sqlite3_finalize(stmt)
        return results
    }

    private func _queryPlaylists() -> [SoundCloudPlaylist] {
        guard let db = db else { return [] }
        var results: [SoundCloudPlaylist] = []
        var stmt: OpaquePointer?
        let sql = "SELECT json_data FROM playlists ORDER BY position ASC;"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let cStr = sqlite3_column_text(stmt, 0) {
                    let jsonStr = String(cString: cStr)
                    if let data = jsonStr.data(using: .utf8),
                       let playlist = try? JSONDecoder().decode(SoundCloudPlaylist.self, from: data) {
                        results.append(playlist)
                    }
                }
            }
        }
        sqlite3_finalize(stmt)
        return results
    }

    /// Replaces all rows in table with the given tracks (position = array index)
    private func _insertLikedTracks(_ tracks: [Track]) {
        guard let db = db else { return }
        sqlite3_exec(db, "DELETE FROM liked_tracks;", nil, nil, nil)
        let encoder = JSONEncoder()
        for (pos, track) in tracks.enumerated() {
            guard let data = try? encoder.encode(track),
                  let jsonStr = String(data: data, encoding: .utf8) else { continue }
            var stmt: OpaquePointer?
            let sql = "INSERT OR REPLACE INTO liked_tracks (id, json_data, position) VALUES (?, ?, ?);"
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt, 1, Int64(track.id))
                _ = jsonStr.withCString { cStr in
                    sqlite3_bind_text(stmt, 2, cStr, -1, SQLITE_TRANSIENT)
                }
                sqlite3_bind_int64(stmt, 3, Int64(pos))
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    /// Replaces all rows in recently_played with the given tracks (position = array index)
    private func _insertRecentlyPlayed(_ tracks: [Track]) {
        guard let db = db else { return }
        sqlite3_exec(db, "DELETE FROM recently_played;", nil, nil, nil)
        let encoder = JSONEncoder()
        for (pos, track) in tracks.enumerated() {
            guard let data = try? encoder.encode(track),
                  let jsonStr = String(data: data, encoding: .utf8) else { continue }
            var stmt: OpaquePointer?
            let sql = "INSERT OR REPLACE INTO recently_played (id, json_data, position) VALUES (?, ?, ?);"
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt, 1, Int64(track.id))
                _ = jsonStr.withCString { cStr in
                    sqlite3_bind_text(stmt, 2, cStr, -1, SQLITE_TRANSIENT)
                }
                sqlite3_bind_int64(stmt, 3, Int64(pos))
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    /// Replaces all rows in playlists with the given playlists
    private func _insertPlaylists(_ playlists: [SoundCloudPlaylist]) {
        guard let db = db else { return }
        sqlite3_exec(db, "DELETE FROM playlists;", nil, nil, nil)
        let encoder = JSONEncoder()
        for (pos, playlist) in playlists.enumerated() {
            guard let data = try? encoder.encode(playlist),
                  let jsonStr = String(data: data, encoding: .utf8) else { continue }
            var stmt: OpaquePointer?
            let sql = "INSERT OR REPLACE INTO playlists (id, json_data, position) VALUES (?, ?, ?);"
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt, 1, Int64(playlist.id))
                _ = jsonStr.withCString { cStr in
                    sqlite3_bind_text(stmt, 2, cStr, -1, SQLITE_TRANSIENT)
                }
                sqlite3_bind_int64(stmt, 3, Int64(pos))
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    private func _deleteTrack(id: Int, table: String) {
        guard let db = db else { return }
        var stmt: OpaquePointer?
        let sql = "DELETE FROM \(table) WHERE id = ?;"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, Int64(id))
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    private func _updatePosition(id: Int, position: Int, table: String) {
        guard let db = db else { return }
        var stmt: OpaquePointer?
        let sql = "UPDATE \(table) SET position = ? WHERE id = ?;"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, Int64(position))
            sqlite3_bind_int64(stmt, 2, Int64(id))
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    private func _deleteAll(table: String) {
        guard let db = db else { return }
        sqlite3_exec(db, "DELETE FROM \(table);", nil, nil, nil)
    }
}
