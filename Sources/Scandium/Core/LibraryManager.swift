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

    /// O(1) lookup set synchronized with `likedTracks`
    private var likedTrackIDs = Set<Int>()

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

    // MARK: - Sync Tracking

    private var isSyncingLikes: Bool = false
    private var locallyLikedDuringSyncIDs = Set<Int>()
    private var locallyUnlikedDuringSyncIDs = Set<Int>()

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
            let rc = sqlite3_open(cPath, &db)
            if rc != SQLITE_OK {
                print("[LibraryManager] Failed to open SQLite DB (code \(rc))")
                if let failedDB = db {
                    sqlite3_close(failedDB)
                }
                db = nil
            }
        }
    }

    private func createTables() {
        guard let db = db else { return }
        dbQueue.sync {
            let statements = [
                """
                CREATE TABLE IF NOT EXISTS liked_tracks (
                    id INTEGER PRIMARY KEY,
                    json_data TEXT NOT NULL,
                    position INTEGER
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS recently_played (
                    id INTEGER PRIMARY KEY,
                    json_data TEXT NOT NULL,
                    position INTEGER
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS playlists (
                    id INTEGER PRIMARY KEY,
                    json_data TEXT NOT NULL,
                    position INTEGER
                );
                """
            ]
            for sql in statements {
                let rc = sqlite3_exec(db, sql, nil, nil, nil)
                if rc != SQLITE_OK {
                    print("[LibraryManager] Failed to create table (code \(rc))")
                }
            }
        }
    }

    // MARK: - Migration from UserDefaults

    private func migrateFromUserDefaultsIfNeeded() {
        let ud = UserDefaults.standard
        let migratedLikedKey     = Self.legacyLikedKey + Self.migratedSuffix
        let migratedRecentKey    = Self.legacyRecentKey + Self.migratedSuffix
        let migratedPlaylistsKey = Self.legacyPlaylistsKey + Self.migratedSuffix

        // Migrate liked tracks: remove legacy key & mark migrated only when decode and SQLite insert succeed
        if let data = ud.data(forKey: Self.legacyLikedKey),
           !ud.bool(forKey: migratedLikedKey),
           let tracks = try? JSONDecoder().decode([Track].self, from: data) {
            let inserted = dbQueue.sync { self._insertLikedTracks(tracks) }
            if inserted {
                ud.removeObject(forKey: Self.legacyLikedKey)
                ud.set(true, forKey: migratedLikedKey)
            }
        }

        // Migrate recently played
        if let data = ud.data(forKey: Self.legacyRecentKey),
           !ud.bool(forKey: migratedRecentKey),
           let tracks = try? JSONDecoder().decode([Track].self, from: data) {
            let inserted = dbQueue.sync { self._insertRecentlyPlayed(tracks) }
            if inserted {
                ud.removeObject(forKey: Self.legacyRecentKey)
                ud.set(true, forKey: migratedRecentKey)
            }
        }

        // Migrate playlists
        if let data = ud.data(forKey: Self.legacyPlaylistsKey),
           !ud.bool(forKey: migratedPlaylistsKey),
           let playlists = try? JSONDecoder().decode([SoundCloudPlaylist].self, from: data) {
            let inserted = dbQueue.sync { self._insertPlaylists(playlists) }
            if inserted {
                ud.removeObject(forKey: Self.legacyPlaylistsKey)
                ud.set(true, forKey: migratedPlaylistsKey)
            }
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
                self.likedTrackIDs  = Set(liked.map { $0.id })
                self.recentlyPlayed = recent
                self.userPlaylists  = playlists
            }
        }
    }

    // MARK: - Liked Tracks API

    func isLiked(track: Track) -> Bool {
        likedTrackIDs.contains(track.id)
    }

    func toggleLike(track: Track) {
        if isLiked(track: track) {
            unlike(track: track)
        } else {
            like(track: track)
        }
    }

    func like(track: Track) {
        if isSyncingLikes {
            locallyLikedDuringSyncIDs.insert(track.id)
            locallyUnlikedDuringSyncIDs.remove(track.id)
        }
        guard likedTrackIDs.insert(track.id).inserted else { return }
        likedTracks.insert(track, at: 0)
        let snapshot = likedTracks
        dbQueue.async { self._upsertLikedTracks(snapshot) }
    }

    func unlike(track: Track) {
        if isSyncingLikes {
            locallyUnlikedDuringSyncIDs.insert(track.id)
            locallyLikedDuringSyncIDs.remove(track.id)
        }
        likedTrackIDs.remove(track.id)
        likedTracks.removeAll(where: { $0.id == track.id })
        let remaining = likedTracks
        dbQueue.async {
            self._deleteTrack(id: track.id, table: "liked_tracks")
            // Re-index remaining positions
            for (pos, t) in remaining.enumerated() {
                self._updatePosition(id: t.id, position: pos, table: "liked_tracks")
            }
        }
    }

    func clearLikedTracks() {
        likedTracks.removeAll()
        likedTrackIDs.removeAll()
        dbQueue.async { self._deleteAll(table: "liked_tracks") }
    }

    /// Merges remote liked tracks into local liked tracks, avoiding duplicates (never prunes/replaces SQLite)
    func syncLikedTracks(_ tracks: [Track]) {
        var changed = false
        for track in tracks.reversed() {
            if likedTrackIDs.insert(track.id).inserted {
                likedTracks.insert(track, at: 0)
                changed = true
            }
        }
        if changed {
            let snapshot = self.likedTracks
            dbQueue.async { self._upsertLikedTracks(snapshot) }
        }
    }

    func beginLikesSync() {
        isSyncingLikes = true
        locallyLikedDuringSyncIDs.removeAll()
        locallyUnlikedDuringSyncIDs.removeAll()
    }

    func endLikesSyncWithoutFinalize() {
        isSyncingLikes = false
        locallyLikedDuringSyncIDs.removeAll()
        locallyUnlikedDuringSyncIDs.removeAll()
    }

    /// Incremental sync for liked tracks — called page-by-page as pages arrive from SoundCloud API.
    func syncLikedTracksIncremental(pageTracks: [Track], isFirstPage: Bool) {
        let filteredPageTracks = pageTracks.filter { !locallyUnlikedDuringSyncIDs.contains($0.id) }
        if isFirstPage {
            var uniquePage: [Track] = []
            var seen = Set<Int>()
            for t in filteredPageTracks {
                if seen.insert(t.id).inserted {
                    uniquePage.append(t)
                }
            }
            let pageIDs = seen
            let localAdditions = likedTracks.filter {
                locallyLikedDuringSyncIDs.contains($0.id) && !pageIDs.contains($0.id)
            }
            let remaining = likedTracks.filter {
                !pageIDs.contains($0.id) && !locallyLikedDuringSyncIDs.contains($0.id)
            }
            likedTracks = localAdditions + uniquePage + remaining
            likedTrackIDs = Set(likedTracks.map { $0.id })
        } else {
            var added: [Track] = []
            for t in filteredPageTracks {
                if likedTrackIDs.insert(t.id).inserted {
                    added.append(t)
                }
            }
            likedTracks.append(contentsOf: added)
        }
        let snapshot = likedTracks
        dbQueue.async { self._upsertLikedTracks(snapshot) }
    }

    /// Prunes any local liked tracks that were not returned during full sync.
    /// Only executes when `completed == true` (all pagination pages succeeded without error).
    /// Preserves tracks newly liked locally while sync was in progress.
    func finalizeLikedTracksSync(syncedIDs: Set<Int>, completed: Bool) {
        defer {
            isSyncingLikes = false
            locallyLikedDuringSyncIDs.removeAll()
            locallyUnlikedDuringSyncIDs.removeAll()
        }
        guard completed else { return }

        let filtered = likedTracks.filter {
            syncedIDs.contains($0.id) || locallyLikedDuringSyncIDs.contains($0.id)
        }
        if filtered.count != likedTracks.count {
            likedTracks = filtered
            likedTrackIDs = Set(filtered.map { $0.id })
            let snapshot = likedTracks
            dbQueue.async { self._insertLikedTracks(snapshot) }
        }
    }

    /// Synchronizes user playlists from SoundCloud account in a single SQLite transaction.
    func syncUserPlaylists(_ playlists: [SoundCloudPlaylist]) {
        self.userPlaylists = playlists
        let snapshot = playlists
        dbQueue.async { self._insertPlaylists(snapshot) }
    }

    /// Clears account-synced likes and playlists on logout while preserving local listening history.
    func clearSyncedAccountData() {
        isSyncingLikes = false
        locallyLikedDuringSyncIDs.removeAll()
        locallyUnlikedDuringSyncIDs.removeAll()
        likedTracks.removeAll()
        likedTrackIDs.removeAll()
        userPlaylists.removeAll()
        dbQueue.async {
            self._deleteAll(table: "liked_tracks")
            self._deleteAll(table: "playlists")
        }
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
        likedTrackIDs.removeAll()
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

    private static let validTables: Set<String> = ["liked_tracks", "recently_played", "playlists"]

    private func _isValidTable(_ table: String) -> Bool {
        Self.validTables.contains(table)
    }

    private func _queryTracks(table: String) -> [Track] {
        guard let db = db, _isValidTable(table) else { return [] }
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

    private func _executeTransaction(_ db: OpaquePointer, work: () -> Bool) -> Bool {
        guard sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil) == SQLITE_OK else {
            return false
        }
        guard work() else {
            sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
            return false
        }
        if sqlite3_exec(db, "COMMIT;", nil, nil, nil) != SQLITE_OK {
            sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
            return false
        }
        return true
    }

    private func _writeRows<Item: Encodable>(
        items: [Item],
        idProvider: (Item) -> Int,
        table: String,
        replaceExisting: Bool
    ) -> Bool {
        guard let db = db, _isValidTable(table) else { return false }
        return _executeTransaction(db) {
            if replaceExisting {
                guard sqlite3_exec(db, "DELETE FROM \(table);", nil, nil, nil) == SQLITE_OK else {
                    return false
                }
            }
            let encoder = JSONEncoder()
            let sql = "INSERT OR REPLACE INTO \(table) (id, json_data, position) VALUES (?, ?, ?);"
            for (pos, item) in items.enumerated() {
                guard let data = try? encoder.encode(item),
                      let jsonStr = String(data: data, encoding: .utf8) else {
                    return false
                }
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                    sqlite3_finalize(stmt)
                    return false
                }
                sqlite3_bind_int64(stmt, 1, Int64(idProvider(item)))
                _ = jsonStr.withCString { cStr in
                    sqlite3_bind_text(stmt, 2, cStr, -1, SQLITE_TRANSIENT)
                }
                sqlite3_bind_int64(stmt, 3, Int64(pos))
                let stepRC = sqlite3_step(stmt)
                sqlite3_finalize(stmt)
                guard stepRC == SQLITE_DONE else {
                    return false
                }
            }
            return true
        }
    }

    /// Upserts rows in liked_tracks without deleting existing rows (safe for incremental/merge-only sync)
    @discardableResult
    private func _upsertLikedTracks(_ tracks: [Track]) -> Bool {
        _writeRows(items: tracks, idProvider: { $0.id }, table: "liked_tracks", replaceExisting: false)
    }

    /// Replaces all rows in table with the given tracks (position = array index)
    @discardableResult
    private func _insertLikedTracks(_ tracks: [Track]) -> Bool {
        _writeRows(items: tracks, idProvider: { $0.id }, table: "liked_tracks", replaceExisting: true)
    }

    /// Replaces all rows in recently_played with the given tracks (position = array index)
    @discardableResult
    private func _insertRecentlyPlayed(_ tracks: [Track]) -> Bool {
        _writeRows(items: tracks, idProvider: { $0.id }, table: "recently_played", replaceExisting: true)
    }

    /// Replaces all rows in playlists with the given playlists
    @discardableResult
    private func _insertPlaylists(_ playlists: [SoundCloudPlaylist]) -> Bool {
        _writeRows(items: playlists, idProvider: { $0.id }, table: "playlists", replaceExisting: true)
    }

    private func _deleteTrack(id: Int, table: String) {
        guard let db = db, _isValidTable(table) else { return }
        var stmt: OpaquePointer?
        let sql = "DELETE FROM \(table) WHERE id = ?;"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, Int64(id))
            _ = sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    private func _updatePosition(id: Int, position: Int, table: String) {
        guard let db = db, _isValidTable(table) else { return }
        var stmt: OpaquePointer?
        let sql = "UPDATE \(table) SET position = ? WHERE id = ?;"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, Int64(position))
            sqlite3_bind_int64(stmt, 2, Int64(id))
            _ = sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    private func _deleteAll(table: String) {
        guard let db = db, _isValidTable(table) else { return }
        _ = sqlite3_exec(db, "DELETE FROM \(table);", nil, nil, nil)
    }
}
