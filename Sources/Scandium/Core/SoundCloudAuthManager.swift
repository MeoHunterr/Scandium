// SoundCloudAuthManager.swift — SoundCloud user authentication & sync manager
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import Foundation
import Combine

final class SoundCloudAuthManager: ObservableObject {
    static let shared = SoundCloudAuthManager()

    // MARK: - Published State

    @Published private(set) var isLoggedIn: Bool = false
    @Published private(set) var isAuthenticated: Bool = false
    @Published private(set) var isPublicProfile: Bool = false
    @Published private(set) var currentUser: SoundCloudUser?
    @Published private(set) var oauthToken: String?
    @Published private(set) var userPlaylists: [SoundCloudPlaylist] = []
    @Published private(set) var userAlbums: [SoundCloudPlaylist] = []
    @Published private(set) var userFollowings: [SoundCloudUser] = []
    @Published private(set) var userLikedTracks: [Track] = []
    @Published private(set) var isLoading: Bool = false
    @Published var errorMessage: String?

    // MARK: - Storage Keys

    private let legacyTokenKey = "scandium_soundcloud_oauth_token"
    private let scOAuthTokenKey = "sc_oauth_token"
    private let userKey = "scandium_soundcloud_current_user"
    private let playlistsKey = "scandium_soundcloud_user_playlists"
    private let followingsKey = "scandium_soundcloud_user_followings"
    private let userLikesKey = "scandium_soundcloud_user_likes"

    private var api: SoundCloudAPI?
    private var syncTask: Task<Void, Never>?
    private var syncGeneration: Int = 0

    private init() {
        loadPersistedState()
    }

    func setAPI(_ api: SoundCloudAPI) {
        self.api = api
    }

    // MARK: - Persistence

    private func loadPersistedState() {
        let keychainToken = KeychainHelper.loadString(key: scOAuthTokenKey)
        let legacyUDToken = UserDefaults.standard.string(forKey: scOAuthTokenKey) ??
                            UserDefaults.standard.string(forKey: legacyTokenKey)

        if let token = keychainToken, !token.isEmpty {
            self.oauthToken = token
            self.isLoggedIn = true
            self.isAuthenticated = true
            self.isPublicProfile = false
            UserDefaults.standard.removeObject(forKey: scOAuthTokenKey)
            UserDefaults.standard.removeObject(forKey: legacyTokenKey)
        } else if let legacyToken = legacyUDToken, !legacyToken.isEmpty {
            // Migrate plaintext token to Keychain and purge from UserDefaults only if Keychain save succeeds
            if KeychainHelper.saveString(key: scOAuthTokenKey, value: legacyToken) {
                UserDefaults.standard.removeObject(forKey: scOAuthTokenKey)
                UserDefaults.standard.removeObject(forKey: legacyTokenKey)
                self.oauthToken = legacyToken
                self.isLoggedIn = true
                self.isAuthenticated = true
                self.isPublicProfile = false
            } else {
                self.oauthToken = nil
                self.isAuthenticated = false
            }
        } else {
            self.oauthToken = nil
            self.isAuthenticated = false
        }

        if let userData = UserDefaults.standard.data(forKey: userKey),
           let user = try? JSONDecoder().decode(SoundCloudUser.self, from: userData) {
            self.currentUser = user
            self.isLoggedIn = true
            if !self.isAuthenticated {
                self.isPublicProfile = true
            }
        }

        if let plData = UserDefaults.standard.data(forKey: playlistsKey),
           let playlists = try? JSONDecoder().decode([SoundCloudPlaylist].self, from: plData) {
            self.userPlaylists = playlists
            self.userAlbums = playlists.filter { ($0.trackCount ?? 0) >= 5 || ($0.title.lowercased().contains("album") || $0.title.lowercased().contains("ep")) }
        }

        if let folData = UserDefaults.standard.data(forKey: followingsKey),
           let followings = try? JSONDecoder().decode([SoundCloudUser].self, from: folData) {
            self.userFollowings = followings
        }

        if let likesData = UserDefaults.standard.data(forKey: userLikesKey),
           let likes = try? JSONDecoder().decode([Track].self, from: likesData) {
            self.userLikedTracks = likes
        }
    }

    private func savePersistedState() {
        if let token = oauthToken, !token.isEmpty {
            if KeychainHelper.saveString(key: scOAuthTokenKey, value: token) {
                UserDefaults.standard.removeObject(forKey: scOAuthTokenKey)
                UserDefaults.standard.removeObject(forKey: legacyTokenKey)
            }
        } else {
            KeychainHelper.delete(key: scOAuthTokenKey)
            UserDefaults.standard.removeObject(forKey: scOAuthTokenKey)
            UserDefaults.standard.removeObject(forKey: legacyTokenKey)
        }

        if let user = currentUser, let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: userKey)
        } else {
            UserDefaults.standard.removeObject(forKey: userKey)
        }

        if let folData = try? JSONEncoder().encode(userFollowings) {
            UserDefaults.standard.set(folData, forKey: followingsKey)
        }

        // Liked tracks and playlists are persisted in SQLite via LibraryManager;
        // purge legacy heavy blobs from UserDefaults to keep persistence lightweight.
        UserDefaults.standard.removeObject(forKey: playlistsKey)
        UserDefaults.standard.removeObject(forKey: userLikesKey)
    }

    // MARK: - Save OAuth Token

    @MainActor
    func saveToken(_ token: String) {
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanToken.isEmpty else { return }

        syncTask?.cancel()
        syncGeneration += 1
        let generation = syncGeneration

        self.isLoading = true
        self.errorMessage = nil

        syncTask = Task { [weak self] in
            await self?.fetchUserProfileAndSync(token: cleanToken, generation: generation)
        }
    }

    @MainActor
    func handleOAuthToken(_ token: String) async {
        saveToken(token)
    }

    // MARK: - Fetch User Profile & Auto-Sync Library

    @MainActor
    private func fetchUserProfileAndSync(token: String, generation: Int) async {
        guard let api = api else {
            KeychainHelper.delete(key: scOAuthTokenKey)
            UserDefaults.standard.removeObject(forKey: scOAuthTokenKey)
            UserDefaults.standard.removeObject(forKey: legacyTokenKey)
            self.oauthToken = nil
            self.isLoggedIn = false
            self.isAuthenticated = false
            self.isLoading = false
            return
        }

        do {
            // Gọi endpoint /me để lấy ID (urn/id), username, avatar_url
            let me = try await api.getMe(oauthToken: token)
            guard !Task.isCancelled, self.syncGeneration == generation else { return }

            if KeychainHelper.saveString(key: scOAuthTokenKey, value: token) {
                UserDefaults.standard.removeObject(forKey: scOAuthTokenKey)
                UserDefaults.standard.removeObject(forKey: legacyTokenKey)
            }

            self.oauthToken = token
            self.currentUser = me
            self.isPublicProfile = false
            self.isLoggedIn = true
            self.isAuthenticated = true
            self.savePersistedState()

            // Tự động đồng bộ likes và playlists
            await syncLibraryInternal(token: token, user: me, generation: generation)
        } catch {
            guard !Task.isCancelled, self.syncGeneration == generation else { return }
            print("[ScandiumAuth] /me request failed: \(error.localizedDescription)")
            KeychainHelper.delete(key: scOAuthTokenKey)
            UserDefaults.standard.removeObject(forKey: scOAuthTokenKey)
            UserDefaults.standard.removeObject(forKey: legacyTokenKey)

            self.oauthToken = nil
            self.currentUser = nil
            self.isPublicProfile = false
            self.isLoggedIn = false
            self.isAuthenticated = false
            self.errorMessage = AppSettings.shared.loc("Không thể tải hồ sơ: \(error.localizedDescription)", "Unable to fetch profile: \(error.localizedDescription)")
            self.savePersistedState()
        }

        if self.syncGeneration == generation {
            self.isLoading = false
        }
    }

    // MARK: - Sign In: Resolve Profile URL (Public Profile Mode)

    @MainActor
    func handleProfileURL(_ urlString: String) async {
        let clean = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        syncTask?.cancel()
        syncGeneration += 1
        let generation = syncGeneration

        self.isLoading = true
        self.errorMessage = nil

        guard let api = api else {
            self.isLoading = false
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let resolvedUser = try await api.resolveURL(url: clean)
                guard !Task.isCancelled, self.syncGeneration == generation else { return }

                KeychainHelper.delete(key: scOAuthTokenKey)
                UserDefaults.standard.removeObject(forKey: scOAuthTokenKey)
                UserDefaults.standard.removeObject(forKey: legacyTokenKey)

                self.oauthToken = nil
                self.currentUser = resolvedUser
                self.isAuthenticated = false
                self.isPublicProfile = true
                self.isLoggedIn = true
                self.savePersistedState()

                await self.syncLibraryInternal(token: nil, user: resolvedUser, generation: generation)
            } catch {
                guard !Task.isCancelled, self.syncGeneration == generation else { return }
                self.errorMessage = AppSettings.shared.loc("Không thể tìm thấy tài khoản: \(error.localizedDescription)", "Account not found: \(error.localizedDescription)")
            }

            if self.syncGeneration == generation {
                self.isLoading = false
            }
        }
        self.syncTask = task
        await task.value
    }

    // MARK: - Synchronize Library (Likes & Playlists)

    @MainActor
    func syncLibrary() async {
        guard let user = currentUser else { return }

        syncTask?.cancel()
        syncGeneration += 1
        let generation = syncGeneration
        let token = oauthToken

        self.isLoading = true
        let task = Task { @MainActor [weak self] in
            guard let self = self else { return }
            await self.syncLibraryInternal(token: token, user: user, generation: generation)
            if self.syncGeneration == generation {
                self.isLoading = false
            }
        }
        self.syncTask = task
        await task.value
    }

    @MainActor
    private func syncLibraryInternal(token: String?, user: SoundCloudUser, generation: Int) async {
        guard let api = api else { return }
        guard !Task.isCancelled, self.syncGeneration == generation else { return }

        let isOAuthAuthenticated = (token != nil && !(token?.isEmpty ?? true))

        // 1. Liked Tracks Sync
        if isOAuthAuthenticated, let oauth = token {
            LibraryManager.shared.beginLikesSync()
            var isFirstLikesPage = true
            var allLikesIDs = Set<Int>()
            var likesSyncCompleted = false

            let onLikesPage: ([Track]) async -> Void = { [weak self] pageTracks in
                guard let self = self else { return }
                await MainActor.run {
                    guard !Task.isCancelled, self.syncGeneration == generation else { return }
                    let isFirst = isFirstLikesPage
                    isFirstLikesPage = false
                    for t in pageTracks {
                        allLikesIDs.insert(t.id)
                    }
                    LibraryManager.shared.syncLikedTracksIncremental(pageTracks: pageTracks, isFirstPage: isFirst)
                    self.userLikedTracks = LibraryManager.shared.likedTracks
                }
            }

            do {
                _ = try await api.getMeLikesTracks(oauthToken: oauth, limit: 50, onPage: onLikesPage)
                likesSyncCompleted = true
            } catch {
                if !Task.isCancelled && self.syncGeneration == generation {
                    isFirstLikesPage = true
                    allLikesIDs.removeAll()
                    do {
                        _ = try await api.getUserLikes(userID: user.id, oauthToken: oauth, limit: 50, onPage: onLikesPage)
                        likesSyncCompleted = true
                    } catch {
                        print("[ScandiumAuth] Likes sync failed: \(error.localizedDescription)")
                    }
                }
            }

            guard self.syncGeneration == generation else {
                return
            }

            if !Task.isCancelled && likesSyncCompleted {
                LibraryManager.shared.finalizeLikedTracksSync(syncedIDs: allLikesIDs, completed: true)
                self.userLikedTracks = LibraryManager.shared.likedTracks
                self.savePersistedState()
            } else {
                LibraryManager.shared.endLikesSyncWithoutFinalize()
                if Task.isCancelled { return }
            }
        } else {
            // Public profile mode (oauthToken == nil): merge-only, never prune/replace SQLite
            var publicLikes: [Track] = []
            var seenPublicIDs = Set<Int>()

            let onPublicLikesPage: ([Track]) async -> Void = { [weak self] pageTracks in
                guard let self = self else { return }
                await MainActor.run {
                    guard !Task.isCancelled, self.syncGeneration == generation else { return }
                    for t in pageTracks where seenPublicIDs.insert(t.id).inserted {
                        publicLikes.append(t)
                    }
                    self.userLikedTracks = publicLikes
                    LibraryManager.shared.syncLikedTracks(pageTracks)
                }
            }

            _ = try? await api.getUserLikes(userID: user.id, oauthToken: nil, limit: 50, onPage: onPublicLikesPage)
            guard !Task.isCancelled, self.syncGeneration == generation else { return }
        }

        // 2. Playlists Sync (accumulate all pages first; write SQLite in 1 transaction only on full completion in OAuth mode)
        var accumulatedPlaylists: [SoundCloudPlaylist] = []
        var seenPlaylistIDs = Set<Int>()
        var playlistsSyncCompleted = false

        if isOAuthAuthenticated, let oauth = token {
            do {
                let fetched = try await api.getMePlaylists(oauthToken: oauth, userID: user.id, limit: 50)
                guard !Task.isCancelled, self.syncGeneration == generation else { return }
                for pl in fetched where seenPlaylistIDs.insert(pl.id).inserted {
                    accumulatedPlaylists.append(pl)
                }
                playlistsSyncCompleted = true
            } catch {
                print("[ScandiumAuth] Playlists sync failed: \(error.localizedDescription)")
            }

            guard !Task.isCancelled, self.syncGeneration == generation else { return }

            if playlistsSyncCompleted {
                self.userPlaylists = accumulatedPlaylists
                self.userAlbums = accumulatedPlaylists.filter {
                    ($0.trackCount ?? 0) >= 5 ||
                    ($0.title.lowercased().contains("album") || $0.title.lowercased().contains("ep"))
                }
                LibraryManager.shared.syncUserPlaylists(accumulatedPlaylists)
                self.savePersistedState()
            }
        } else {
            // Public profile mode: display only, never overwrite/prune SQLite playlists
            if let fetched = try? await api.getUserPlaylists(userID: user.id, oauthToken: nil, limit: 50) {
                guard !Task.isCancelled, self.syncGeneration == generation else { return }
                for pl in fetched where seenPlaylistIDs.insert(pl.id).inserted {
                    accumulatedPlaylists.append(pl)
                }
                self.userPlaylists = accumulatedPlaylists
                self.userAlbums = accumulatedPlaylists.filter {
                    ($0.trackCount ?? 0) >= 5 ||
                    ($0.title.lowercased().contains("album") || $0.title.lowercased().contains("ep"))
                }
                self.savePersistedState()
            }
        }

        guard !Task.isCancelled, self.syncGeneration == generation else { return }

        // 3. User Followings
        if let followings = try? await api.getUserFollowings(userID: user.id, oauthToken: token, limit: 30) {
            guard !Task.isCancelled, self.syncGeneration == generation else { return }
            self.userFollowings = followings
            self.savePersistedState()
        }
    }

    private func deduplicateTracks(_ tracks: [Track]) -> [Track] {
        var seen = Set<Int>()
        var result: [Track] = []
        result.reserveCapacity(tracks.count)
        for track in tracks {
            if seen.insert(track.id).inserted {
                result.append(track)
            }
        }
        return result
    }

    // MARK: - Sign Out

    @MainActor
    func logout() {
        let wasAuthenticated = self.isAuthenticated || (self.oauthToken != nil)

        syncTask?.cancel()
        syncTask = nil
        syncGeneration += 1

        self.isLoggedIn = false
        self.isAuthenticated = false
        self.isPublicProfile = false
        self.currentUser = nil
        self.oauthToken = nil
        self.userPlaylists = []
        self.userAlbums = []
        self.userFollowings = []
        self.userLikedTracks = []
        self.isLoading = false
        self.errorMessage = nil

        KeychainHelper.delete(key: scOAuthTokenKey)
        UserDefaults.standard.removeObject(forKey: scOAuthTokenKey)
        UserDefaults.standard.removeObject(forKey: legacyTokenKey)
        UserDefaults.standard.removeObject(forKey: userKey)
        UserDefaults.standard.removeObject(forKey: playlistsKey)
        UserDefaults.standard.removeObject(forKey: followingsKey)
        UserDefaults.standard.removeObject(forKey: userLikesKey)

        if wasAuthenticated {
            LibraryManager.shared.clearSyncedAccountData()
        }
    }
}
