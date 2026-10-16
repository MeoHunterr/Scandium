// SoundCloudAuthManager.swift — SoundCloud user authentication & sync manager
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import Foundation
import Combine

final class SoundCloudAuthManager: ObservableObject {
    static let shared = SoundCloudAuthManager()

    // MARK: - Published State

    @Published private(set) var isLoggedIn: Bool = false
    @Published private(set) var isAuthenticated: Bool = false
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

    private init() {
        loadPersistedState()
    }

    func setAPI(_ api: SoundCloudAPI) {
        self.api = api
    }

    // MARK: - Persistence

    private func loadPersistedState() {
        let storedToken = KeychainHelper.loadString(key: scOAuthTokenKey) ??
                          UserDefaults.standard.string(forKey: scOAuthTokenKey) ??
                          UserDefaults.standard.string(forKey: legacyTokenKey)

        if let token = storedToken, !token.isEmpty {
            self.oauthToken = token
            self.isLoggedIn = true
            self.isAuthenticated = true

            // Migrate plaintext token to Keychain and purge from UserDefaults
            _ = KeychainHelper.saveString(key: scOAuthTokenKey, value: token)
            UserDefaults.standard.removeObject(forKey: scOAuthTokenKey)
            UserDefaults.standard.removeObject(forKey: legacyTokenKey)
        }

        if let userData = UserDefaults.standard.data(forKey: userKey),
           let user = try? JSONDecoder().decode(SoundCloudUser.self, from: userData) {
            self.currentUser = user
            self.isLoggedIn = true
            self.isAuthenticated = true
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
        if let token = oauthToken {
            KeychainHelper.saveString(key: scOAuthTokenKey, value: token)
            UserDefaults.standard.removeObject(forKey: scOAuthTokenKey)
            UserDefaults.standard.removeObject(forKey: legacyTokenKey)
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

        if let plData = try? JSONEncoder().encode(userPlaylists) {
            UserDefaults.standard.set(plData, forKey: playlistsKey)
        }

        if let folData = try? JSONEncoder().encode(userFollowings) {
            UserDefaults.standard.set(folData, forKey: followingsKey)
        }

        if let likesData = try? JSONEncoder().encode(userLikedTracks) {
            UserDefaults.standard.set(likesData, forKey: userLikesKey)
        }
    }

    // MARK: - Save OAuth Token

    @MainActor
    func saveToken(_ token: String) {
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanToken.isEmpty else { return }

        KeychainHelper.saveString(key: scOAuthTokenKey, value: cleanToken)
        UserDefaults.standard.removeObject(forKey: scOAuthTokenKey)
        UserDefaults.standard.removeObject(forKey: legacyTokenKey)

        self.oauthToken = cleanToken
        self.isLoggedIn = true
        self.isAuthenticated = true
        self.isLoading = true
        self.errorMessage = nil

        Task {
            await self.fetchUserProfileAndSync(token: cleanToken)
        }
    }

    @MainActor
    func handleOAuthToken(_ token: String) async {
        saveToken(token)
    }

    // MARK: - Fetch User Profile & Auto-Sync Library

    @MainActor
    private func fetchUserProfileAndSync(token: String) async {
        guard let api = api else {
            self.isLoading = false
            self.savePersistedState()
            return
        }

        do {
            // Gọi endpoint /me để lấy ID (urn/id), username, avatar_url
            let me = try await api.getMe(oauthToken: token)
            self.currentUser = me
            self.isLoggedIn = true
            self.isAuthenticated = true
            self.savePersistedState()

            // Tự động đồng bộ likes và playlists
            await syncLibraryInternal(token: token, user: me)
        } catch {
            print("[ScandiumAuth] /me request failed: \(error.localizedDescription)")
            self.errorMessage = AppSettings.shared.loc("Không thể tải hồ sơ: \(error.localizedDescription)", "Unable to fetch profile: \(error.localizedDescription)")
            self.isLoggedIn = true
            self.isAuthenticated = true
            self.savePersistedState()
        }

        self.isLoading = false
    }

    // MARK: - Sign In: Resolve Profile URL

    @MainActor
    func handleProfileURL(_ urlString: String) async {
        let clean = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        self.isLoading = true
        self.errorMessage = nil

        guard let api = api else {
            self.isLoading = false
            return
        }

        do {
            let resolvedUser = try await api.resolveURL(url: clean)
            self.currentUser = resolvedUser
            self.isLoggedIn = true
            self.isAuthenticated = true
            self.savePersistedState()
            await syncLibrary()
        } catch {
            self.errorMessage = AppSettings.shared.loc("Không thể tìm thấy tài khoản: \(error.localizedDescription)", "Account not found: \(error.localizedDescription)")
        }

        self.isLoading = false
    }

    // MARK: - Synchronize Library (Likes & Playlists)

    @MainActor
    func syncLibrary() async {
        guard let user = currentUser else { return }
        self.isLoading = true
        await syncLibraryInternal(token: oauthToken, user: user)
        self.isLoading = false
    }

    @MainActor
    private func syncLibraryInternal(token: String?, user: SoundCloudUser) async {
        guard let api = api else { return }

        var likes: [Track] = []
        if let token = token, !token.isEmpty {
            do {
                likes = try await api.getMeLikesTracks(oauthToken: token, limit: 50)
            } catch {
                likes = (try? await api.getUserLikes(userID: user.id, oauthToken: token, limit: 50)) ?? []
            }
        } else {
            likes = (try? await api.getUserLikes(userID: user.id, oauthToken: nil, limit: 50)) ?? []
        }

        var playlists: [SoundCloudPlaylist] = []
        if let token = token, !token.isEmpty {
            do {
                playlists = try await api.getMePlaylists(oauthToken: token)
            } catch {
                playlists = (try? await api.getUserPlaylists(userID: user.id, oauthToken: token)) ?? []
            }
        } else {
            playlists = (try? await api.getUserPlaylists(userID: user.id, oauthToken: nil)) ?? []
        }

        let followings = (try? await api.getUserFollowings(userID: user.id, oauthToken: token, limit: 30)) ?? []

        let uniqueLikes = deduplicateTracks(likes)
        self.userLikedTracks = uniqueLikes
        self.userPlaylists = playlists
        self.userAlbums = playlists.filter { ($0.trackCount ?? 0) >= 5 || ($0.title.lowercased().contains("album") || $0.title.lowercased().contains("ep")) }
        self.userFollowings = followings

        LibraryManager.shared.syncLikedTracks(uniqueLikes)
        LibraryManager.shared.syncUserPlaylists(playlists)

        self.savePersistedState()
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
        self.isLoggedIn = false
        self.isAuthenticated = false
        self.currentUser = nil
        self.oauthToken = nil
        self.userPlaylists = []
        self.userAlbums = []
        self.userFollowings = []
        self.userLikedTracks = []
        self.errorMessage = nil

        KeychainHelper.delete(key: scOAuthTokenKey)
        UserDefaults.standard.removeObject(forKey: scOAuthTokenKey)
        UserDefaults.standard.removeObject(forKey: legacyTokenKey)
        UserDefaults.standard.removeObject(forKey: userKey)
        UserDefaults.standard.removeObject(forKey: playlistsKey)
        UserDefaults.standard.removeObject(forKey: followingsKey)
        UserDefaults.standard.removeObject(forKey: userLikesKey)

        LibraryManager.shared.syncUserPlaylists([])
    }
}
