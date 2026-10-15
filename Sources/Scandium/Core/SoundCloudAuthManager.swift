// SoundCloudAuthManager.swift — SoundCloud user authentication & sync manager
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import Foundation
import Combine

final class SoundCloudAuthManager: ObservableObject {
    static let shared = SoundCloudAuthManager()

    // MARK: - Published State

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

    private let tokenKey = "scandium_soundcloud_oauth_token"
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
        if let token = UserDefaults.standard.string(forKey: tokenKey), !token.isEmpty {
            self.oauthToken = token
            self.isAuthenticated = true
        }

        if let userData = UserDefaults.standard.data(forKey: userKey),
           let user = try? JSONDecoder().decode(SoundCloudUser.self, from: userData) {
            self.currentUser = user
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
            UserDefaults.standard.set(token, forKey: tokenKey)
        } else {
            UserDefaults.standard.removeObject(forKey: tokenKey)
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

    // MARK: - Sign In: OAuth Token Captured (from WebView or Manual)

    @MainActor
    func handleOAuthToken(_ token: String) async {
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanToken.isEmpty else { return }

        self.oauthToken = cleanToken
        self.isLoading = true
        self.errorMessage = nil

        guard let api = api else {
            self.isLoading = false
            self.isAuthenticated = true
            self.savePersistedState()
            return
        }

        do {
            let me = try await api.getMe(oauthToken: cleanToken)
            self.currentUser = me
            self.isAuthenticated = true
            self.savePersistedState()
            await syncLibrary()
        } catch {
            print("[ScandiumAuth] getMe failed: \(error.localizedDescription)")
            self.errorMessage = AppSettings.shared.loc("Không thể tải hồ sơ: \(error.localizedDescription)", "Unable to fetch profile: \(error.localizedDescription)")
            self.isAuthenticated = true // Keep authenticated if token is valid
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
        guard let api = api, let user = currentUser else { return }
        self.isLoading = true

        do {
            async let fetchedLikes = api.getUserLikes(userID: user.id, oauthToken: oauthToken, limit: 50)
            async let fetchedPlaylists = api.getUserPlaylists(userID: user.id, oauthToken: oauthToken)
            async let fetchedFollowings = api.getUserFollowings(userID: user.id, oauthToken: oauthToken, limit: 30)

            let (likes, playlists, followings) = try await (fetchedLikes, fetchedPlaylists, fetchedFollowings)
            let uniqueLikes = deduplicateTracks(likes)

            self.userLikedTracks = uniqueLikes
            self.userPlaylists = playlists
            self.userAlbums = playlists.filter { ($0.trackCount ?? 0) >= 5 || ($0.title.lowercased().contains("album") || $0.title.lowercased().contains("ep")) }
            self.userFollowings = followings

            // Also merge into local LibraryManager so they appear across the app
            for track in uniqueLikes {
                if !LibraryManager.shared.isLiked(track: track) {
                    LibraryManager.shared.toggleLike(track: track)
                }
            }

            self.savePersistedState()
        } catch {
            print("[ScandiumAuth] syncLibrary failed: \(error.localizedDescription)")
            self.errorMessage = AppSettings.shared.loc("Lỗi khi đồng bộ danh sách: \(error.localizedDescription)", "Failed to synchronize library: \(error.localizedDescription)")
        }

        self.isLoading = false
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
        self.isAuthenticated = false
        self.currentUser = nil
        self.oauthToken = nil
        self.userPlaylists = []
        self.userAlbums = []
        self.userFollowings = []
        self.userLikedTracks = []
        self.errorMessage = nil

        UserDefaults.standard.removeObject(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: userKey)
        UserDefaults.standard.removeObject(forKey: playlistsKey)
        UserDefaults.standard.removeObject(forKey: followingsKey)
        UserDefaults.standard.removeObject(forKey: userLikesKey)
    }
}
