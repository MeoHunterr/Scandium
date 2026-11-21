// SoundCloudAPI.swift — API v2 networking layer for SoundCloud
// Project: Scandium | Author: MeoHunter | License: GPL-3.0
//
// Provides search, stream URL resolution, and waveform data fetching
// against the SoundCloud API v2 endpoint.

import Foundation

final class SoundCloudAPI: ObservableObject {

    // MARK: - Constants

    private static let baseURL = "https://api-v2.soundcloud.com"
    private static let defaultLimit = 25
    private static let maxRetries = 2

    // MARK: - Dependencies

    private let scraper: ClientIDScraper
    private let session: URLSession

    // MARK: - Published State

    @Published private(set) var isSearching: Bool = false
    @Published private(set) var lastError: String?

    // MARK: - Init

    init(scraper: ClientIDScraper, session: URLSession = .shared) {
        self.scraper = scraper
        self.session = session
    }

    // MARK: - Search Tracks

    /// Searches SoundCloud for tracks matching the given query.
    /// Automatically retries with a refreshed client_id on 401/403.
    func searchTracks(query: String, limit: Int = defaultLimit, offset: Int = 0) async throws -> SearchResponse {
        let clientID = try await scraper.getClientID()
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=")
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query

        let urlString = "\(Self.baseURL)/search/tracks?q=\(encodedQuery)&client_id=\(clientID)&limit=\(limit)&offset=\(offset)&linked_partitioning=1"

        return try await performRequest(
            urlString: urlString,
            decodeAs: SearchResponse.self,
            retryCount: 0
        )
    }

    /// Fetches the next page of search results using the `next_href` from a previous response.
    func searchTracksNextPage(nextHref: String) async throws -> SearchResponse {
        var urlString = nextHref
        if !urlString.contains("client_id=") {
            let clientID = try await scraper.getClientID()
            let separator = urlString.contains("?") ? "&" : "?"
            urlString += "\(separator)client_id=\(clientID)"
        }

        return try await performRequest(
            urlString: urlString,
            decodeAs: SearchResponse.self,
            retryCount: 0
        )
    }

    // MARK: - Search Users / Artists

    /// Searches SoundCloud for users / artists matching the given query.
    func searchUsers(query: String, limit: Int = defaultLimit) async throws -> [SoundCloudUser] {
        let clientID = try await scraper.getClientID()
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=")
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query

        let urlString = "\(Self.baseURL)/search/users?q=\(encodedQuery)&client_id=\(clientID)&limit=\(limit)&linked_partitioning=1"

        struct UserSearchResponse: Codable {
            let collection: [SoundCloudUser]
            let totalResults: Int?
            let nextHref: String?

            enum CodingKeys: String, CodingKey {
                case collection
                case totalResults = "total_results"
                case nextHref = "next_href"
            }
        }

        let data = try await performRawRequest(urlString: urlString)
        if let resp = try? JSONDecoder().decode(UserSearchResponse.self, from: data) {
            return resp.collection
        }
        if let arr = try? JSONDecoder().decode([SoundCloudUser].self, from: data) {
            return arr
        }
        return []
    }

    // MARK: - Resolve Track by ID

    /// Fetches a single track by its numeric ID.
    func getTrack(id: Int) async throws -> Track {
        let clientID = try await scraper.getClientID()
        let urlString = "\(Self.baseURL)/tracks/\(id)?client_id=\(clientID)"

        return try await performRequest(
            urlString: urlString,
            decodeAs: Track.self,
            retryCount: 0
        )
    }

    // MARK: - User & Authentication API

    /// Resolves any SoundCloud URL (e.g. soundcloud.com/username or track permalink)
    func resolveURL(url: String) async throws -> SoundCloudUser {
        let clientID = try await scraper.getClientID()
        let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullURL = cleanURL.hasPrefix("http") ? cleanURL : "https://soundcloud.com/\(cleanURL)"
        let encoded = fullURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? fullURL
        let urlString = "\(Self.baseURL)/resolve?url=\(encoded)&client_id=\(clientID)"

        return try await performRequest(
            urlString: urlString,
            decodeAs: SoundCloudUser.self,
            retryCount: 0
        )
    }

    /// Fetches the authenticated user's profile using OAuth token
    func getMe(oauthToken: String) async throws -> SoundCloudUser {
        let clientID = try await scraper.getClientID()
        let urlString = "\(Self.baseURL)/me?client_id=\(clientID)"

        return try await performRequest(
            urlString: urlString,
            decodeAs: SoundCloudUser.self,
            headers: ["Authorization": "OAuth \(oauthToken)"],
            retryCount: 0
        )
    }

    // MARK: - Likes Pagination & Decoding

    /// Decodes a page of liked tracks from raw data, safely handling wrapped and direct formats.
    static func parseLikesPage(from data: Data) -> (tracks: [Track], nextHref: String?) {
        struct LikeItem: Decodable {
            let track: Track?

            enum CodingKeys: String, CodingKey {
                case track
            }

            init(from decoder: Decoder) throws {
                if let container = try? decoder.container(keyedBy: CodingKeys.self),
                   let t = try? container.decodeIfPresent(Track.self, forKey: .track) {
                    self.track = t
                    return
                }
                if let t = try? Track(from: decoder) {
                    self.track = t
                    return
                }
                self.track = nil
            }
        }

        struct LikesEnvelope: Decodable {
            let collection: [LikeItem]
            let nextHref: String?

            enum CodingKeys: String, CodingKey {
                case collection
                case nextHref = "next_href"
            }
        }

        if let env = try? JSONDecoder().decode(LikesEnvelope.self, from: data) {
            let tracks = env.collection.compactMap { $0.track }
            return (tracks, env.nextHref)
        }

        if let direct = try? JSONDecoder().decode(SearchResponse.self, from: data) {
            return (direct.collection, direct.nextHref)
        }

        if let tracks = try? JSONDecoder().decode([Track].self, from: data) {
            return (tracks, nil)
        }

        return ([], nil)
    }

    /// Fetches a single page of liked tracks from urlString
    func fetchLikesPage(
        urlString: String,
        oauthToken: String?
    ) async throws -> (tracks: [Track], nextHref: String?) {
        var finalURL = urlString
        if !finalURL.contains("client_id=") {
            let clientID = try await scraper.getClientID()
            let separator = finalURL.contains("?") ? "&" : "?"
            finalURL += "\(separator)client_id=\(clientID)"
        }

        var headers: [String: String]? = nil
        if let token = oauthToken, !token.isEmpty {
            headers = ["Authorization": "OAuth \(token)"]
        }

        let data = try await performRawRequest(urlString: finalURL, headers: headers)
        return Self.parseLikesPage(from: data)
    }

    /// Fetches all liked tracks with pagination following `next_href`.
    /// Emits each page via `onPage` to support incremental syncing.
    func fetchAllLikes(
        initialURL: String,
        oauthToken: String?,
        delayNanoseconds: UInt64 = 120_000_000,
        onPage: (([Track]) async -> Void)? = nil
    ) async throws -> [Track] {
        var allTracks: [Track] = []
        var nextURL: String? = initialURL
        var visitedURLs = Set<String>()

        while let currentURL = nextURL, !currentURL.isEmpty {
            if visitedURLs.contains(currentURL) {
                break
            }
            visitedURLs.insert(currentURL)

            let (pageTracks, nextHref) = try await fetchLikesPage(
                urlString: currentURL,
                oauthToken: oauthToken
            )

            if !pageTracks.isEmpty {
                allTracks.append(contentsOf: pageTracks)
                if let onPage = onPage {
                    await onPage(pageTracks)
                }
            }

            guard let next = nextHref, !next.isEmpty else {
                break
            }
            nextURL = next

            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
        }

        return allTracks
    }

    /// Fetches the authenticated user's liked tracks via /me/likes/tracks with pagination
    func getMeLikesTracks(
        oauthToken: String,
        limit: Int = 50,
        onPage: (([Track]) async -> Void)? = nil
    ) async throws -> [Track] {
        let clientID = try await scraper.getClientID()
        let initialURL = "\(Self.baseURL)/me/likes/tracks?client_id=\(clientID)&limit=\(limit)&linked_partitioning=1"
        return try await fetchAllLikes(
            initialURL: initialURL,
            oauthToken: oauthToken,
            onPage: onPage
        )
    }

    /// Fetches a user's liked tracks with pagination
    func getUserLikes(
        userID: Int,
        oauthToken: String? = nil,
        limit: Int = 50,
        onPage: (([Track]) async -> Void)? = nil
    ) async throws -> [Track] {
        let clientID = try await scraper.getClientID()
        let initialURL = "\(Self.baseURL)/users/\(userID)/likes?client_id=\(clientID)&limit=\(limit)&linked_partitioning=1"
        return try await fetchAllLikes(
            initialURL: initialURL,
            oauthToken: oauthToken,
            onPage: onPage
        )
    }

    // MARK: - Playlists Pagination & Decoding

    /// Decodes a page of playlists from raw data, safely handling wrapped and direct formats.
    static func parsePlaylistsPage(from data: Data) -> (playlists: [SoundCloudPlaylist], nextHref: String?) {
        struct PlaylistItem: Decodable {
            let playlist: SoundCloudPlaylist?

            enum CodingKeys: String, CodingKey {
                case playlist
                case systemPlaylist = "system_playlist"
            }

            init(from decoder: Decoder) throws {
                if let container = try? decoder.container(keyedBy: CodingKeys.self) {
                    if let p = try? container.decodeIfPresent(SoundCloudPlaylist.self, forKey: .playlist) {
                        self.playlist = p
                        return
                    }
                    if let sp = try? container.decodeIfPresent(SoundCloudPlaylist.self, forKey: .systemPlaylist) {
                        self.playlist = sp
                        return
                    }
                }
                if let p = try? SoundCloudPlaylist(from: decoder) {
                    self.playlist = p
                    return
                }
                self.playlist = nil
            }
        }

        struct PlaylistsEnvelope: Decodable {
            let collection: [PlaylistItem]
            let nextHref: String?

            enum CodingKeys: String, CodingKey {
                case collection
                case nextHref = "next_href"
            }
        }

        if let env = try? JSONDecoder().decode(PlaylistsEnvelope.self, from: data) {
            let playlists = env.collection.compactMap { $0.playlist }
            return (playlists, env.nextHref)
        }

        struct DirectCollection: Decodable {
            let collection: [SoundCloudPlaylist]
            let nextHref: String?

            enum CodingKeys: String, CodingKey {
                case collection
                case nextHref = "next_href"
            }
        }

        if let direct = try? JSONDecoder().decode(DirectCollection.self, from: data) {
            return (direct.collection, direct.nextHref)
        }

        if let arr = try? JSONDecoder().decode([SoundCloudPlaylist].self, from: data) {
            return (arr, nil)
        }

        return ([], nil)
    }

    /// Fetches a single page of playlists from urlString
    func fetchPlaylistsPage(
        urlString: String,
        oauthToken: String?
    ) async throws -> (playlists: [SoundCloudPlaylist], nextHref: String?) {
        var finalURL = urlString
        if !finalURL.contains("client_id=") {
            let clientID = try await scraper.getClientID()
            let separator = finalURL.contains("?") ? "&" : "?"
            finalURL += "\(separator)client_id=\(clientID)"
        }

        var headers: [String: String]? = nil
        if let token = oauthToken, !token.isEmpty {
            headers = ["Authorization": "OAuth \(token)"]
        }

        let data = try await performRawRequest(urlString: finalURL, headers: headers)
        return Self.parsePlaylistsPage(from: data)
    }

    /// Fetches all playlists with pagination following `next_href`.
    /// Emits each page via `onPage` to support incremental syncing.
    func fetchAllPlaylists(
        initialURL: String,
        oauthToken: String?,
        delayNanoseconds: UInt64 = 120_000_000,
        onPage: (([SoundCloudPlaylist]) async -> Void)? = nil
    ) async throws -> [SoundCloudPlaylist] {
        var allPlaylists: [SoundCloudPlaylist] = []
        var nextURL: String? = initialURL
        var visitedURLs = Set<String>()

        while let currentURL = nextURL, !currentURL.isEmpty {
            if visitedURLs.contains(currentURL) {
                break
            }
            visitedURLs.insert(currentURL)

            let (pagePlaylists, nextHref) = try await fetchPlaylistsPage(
                urlString: currentURL,
                oauthToken: oauthToken
            )

            if !pagePlaylists.isEmpty {
                allPlaylists.append(contentsOf: pagePlaylists)
                if let onPage = onPage {
                    await onPage(pagePlaylists)
                }
            }

            guard let next = nextHref, !next.isEmpty else {
                break
            }
            nextURL = next

            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
        }

        return allPlaylists
    }

    /// Fetches the authenticated user's playlists (public, private, liked)
    func getMePlaylists(
        oauthToken: String,
        userID: Int? = nil,
        limit: Int = 50,
        onPage: (([SoundCloudPlaylist]) async -> Void)? = nil
    ) async throws -> [SoundCloudPlaylist] {
        let clientID = try await scraper.getClientID()

        // 1. If userID is available, fetch liked_and_owned with OAuth header
        // This endpoint returns owned (public & private) + liked playlists!
        if let uid = userID {
            let likedAndOwnedURL = "\(Self.baseURL)/users/\(uid)/playlists/liked_and_owned?client_id=\(clientID)&limit=\(limit)&linked_partitioning=1"
            do {
                let results = try await fetchAllPlaylists(
                    initialURL: likedAndOwnedURL,
                    oauthToken: oauthToken,
                    onPage: onPage
                )
                if !results.isEmpty {
                    return results
                }
            } catch {
                print("[SoundCloudAPI] liked_and_owned error: \(error.localizedDescription)")
            }
        }

        // 2. Try /me/playlists
        let mePlaylistsURL = "\(Self.baseURL)/me/playlists?client_id=\(clientID)&limit=\(limit)&linked_partitioning=1"
        do {
            let results = try await fetchAllPlaylists(
                initialURL: mePlaylistsURL,
                oauthToken: oauthToken,
                onPage: onPage
            )
            if !results.isEmpty {
                return results
            }
        } catch {
            print("[SoundCloudAPI] /me/playlists error: \(error.localizedDescription)")
        }

        // 3. Fallback to /users/{uid}/playlists
        if let uid = userID {
            let userPlaylistsURL = "\(Self.baseURL)/users/\(uid)/playlists?client_id=\(clientID)&limit=\(limit)&linked_partitioning=1"
            return try await fetchAllPlaylists(
                initialURL: userPlaylistsURL,
                oauthToken: oauthToken,
                onPage: onPage
            )
        }

        return []
    }

    /// Fetches a user's playlists with pagination
    func getUserPlaylists(
        userID: Int,
        oauthToken: String? = nil,
        limit: Int = 50,
        onPage: (([SoundCloudPlaylist]) async -> Void)? = nil
    ) async throws -> [SoundCloudPlaylist] {
        let clientID = try await scraper.getClientID()
        let urlString = "\(Self.baseURL)/users/\(userID)/playlists?client_id=\(clientID)&limit=\(limit)&linked_partitioning=1"
        return try await fetchAllPlaylists(
            initialURL: urlString,
            oauthToken: oauthToken,
            onPage: onPage
        )
    }

    /// Fetches a specific playlist and its tracks
    func getPlaylist(id: Int, oauthToken: String? = nil) async throws -> SoundCloudPlaylist {
        let clientID = try await scraper.getClientID()
        let urlString = "\(Self.baseURL)/playlists/\(id)?client_id=\(clientID)"
        var headers: [String: String]? = nil
        if let token = oauthToken, !token.isEmpty {
            headers = ["Authorization": "OAuth \(token)"]
        }
        return try await performRequest(
            urlString: urlString,
            decodeAs: SoundCloudPlaylist.self,
            headers: headers,
            retryCount: 0
        )
    }

    /// Fetches artists/users followed by the user
    func getUserFollowings(userID: Int, oauthToken: String? = nil, limit: Int = 30) async throws -> [SoundCloudUser] {
        let clientID = try await scraper.getClientID()
        let urlString = "\(Self.baseURL)/users/\(userID)/followings?client_id=\(clientID)&limit=\(limit)"
        var headers: [String: String]? = nil
        if let token = oauthToken, !token.isEmpty {
            headers = ["Authorization": "OAuth \(token)"]
        }

        struct FollowingsResponse: Codable {
            let collection: [SoundCloudUser]
        }

        let data = try await performRawRequest(urlString: urlString, headers: headers)
        if let resp = try? JSONDecoder().decode(FollowingsResponse.self, from: data) {
            return resp.collection
        }
        if let arr = try? JSONDecoder().decode([SoundCloudUser].self, from: data) {
            return arr
        }
        return []
    }

    /// Fetches tracks published by a specific user / artist.
    func getUserTracks(userID: Int, limit: Int = 30) async throws -> [Track] {
        let clientID = try await scraper.getClientID()
        let urlString = "\(Self.baseURL)/users/\(userID)/tracks?client_id=\(clientID)&limit=\(limit)&linked_partitioning=1"

        let data = try await performRawRequest(urlString: urlString)
        if let resp = try? JSONDecoder().decode(SearchResponse.self, from: data) {
            return resp.collection
        }
        if let arr = try? JSONDecoder().decode([Track].self, from: data) {
            return arr
        }
        return []
    }

    /// Fetches related / recommended tracks for a given track ID
    func getRelatedTracks(trackID: Int, limit: Int = 15) async throws -> [Track] {
        let clientID = try await scraper.getClientID()
        let urlString = "\(Self.baseURL)/tracks/\(trackID)/related?client_id=\(clientID)&limit=\(limit)"

        let data = try await performRawRequest(urlString: urlString)
        if let direct = try? JSONDecoder().decode(SearchResponse.self, from: data) {
            return direct.collection
        }
        if let arr = try? JSONDecoder().decode([Track].self, from: data) {
            return arr
        }
        struct RelatedWrapper: Decodable {
            let collection: [Track]
        }
        if let wrapped = try? JSONDecoder().decode(RelatedWrapper.self, from: data) {
            return wrapped.collection
        }
        return []
    }

    /// Fetches the authenticated user's stream / following feed (new tracks & reposts from followed artists)
    func getFollowingStream(oauthToken: String, limit: Int = 30) async throws -> [Track] {
        let clientID = try await scraper.getClientID()
        let urlString = "\(Self.baseURL)/stream?client_id=\(clientID)&limit=\(limit)"
        let headers = ["Authorization": "OAuth \(oauthToken)"]

        let data = try await performRawRequest(urlString: urlString, headers: headers)

        struct StreamItem: Decodable {
            let track: Track?

            enum CodingKeys: String, CodingKey {
                case track
            }

            init(from decoder: Decoder) throws {
                if let container = try? decoder.container(keyedBy: CodingKeys.self),
                   let t = try? container.decodeIfPresent(Track.self, forKey: .track) {
                    self.track = t
                    return
                }
                if let t = try? Track(from: decoder) {
                    self.track = t
                    return
                }
                self.track = nil
            }
        }

        struct StreamResponse: Decodable {
            let collection: [StreamItem]
        }

        if let streamRes = try? JSONDecoder().decode(StreamResponse.self, from: data) {
            let tracks = streamRes.collection.compactMap { $0.track }
            if !tracks.isEmpty {
                return tracks
            }
        }

        if let direct = try? JSONDecoder().decode(SearchResponse.self, from: data) {
            return direct.collection
        }
        if let arr = try? JSONDecoder().decode([Track].self, from: data) {
            return arr
        }
        return []
    }

    /// Fetches the authenticated user's stream / feed (backward compatibility alias)
    func getUserStream(oauthToken: String, limit: Int = 20) async throws -> [Track] {
        try await getFollowingStream(oauthToken: oauthToken, limit: limit)
    }

    /// Fetches trending charts from SoundCloud API v2
    func getCharts(
        genre: String = "soundcloud:genres:all-music",
        kind: String = "trending",
        limit: Int = 30,
        offset: Int = 0
    ) async throws -> [Track] {
        let clientID = try await scraper.getClientID()
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=")
        let encodedGenre = genre.addingPercentEncoding(withAllowedCharacters: allowed) ?? genre
        let urlString = "\(Self.baseURL)/charts?kind=\(kind)&genre=\(encodedGenre)&client_id=\(clientID)&limit=\(limit)&offset=\(offset)&linked_partitioning=1"

        let data = try await performRawRequest(urlString: urlString)

        struct ChartItem: Decodable {
            let track: Track?

            enum CodingKeys: String, CodingKey {
                case track
            }

            init(from decoder: Decoder) throws {
                if let container = try? decoder.container(keyedBy: CodingKeys.self),
                   let t = try? container.decodeIfPresent(Track.self, forKey: .track) {
                    self.track = t
                    return
                }
                if let t = try? Track(from: decoder) {
                    self.track = t
                    return
                }
                self.track = nil
            }
        }

        struct ChartResponse: Decodable {
            let collection: [ChartItem]
        }

        if let chartRes = try? JSONDecoder().decode(ChartResponse.self, from: data) {
            let tracks = chartRes.collection.compactMap { $0.track }
            if !tracks.isEmpty {
                return tracks
            }
        }

        if let direct = try? JSONDecoder().decode(SearchResponse.self, from: data) {
            return direct.collection
        }

        if let arr = try? JSONDecoder().decode([Track].self, from: data) {
            return arr
        }

        return []
    }

    // MARK: - Generic Networking Helper

    private func performRequest<T: Decodable>(
        urlString: String,
        decodeAs type: T.Type,
        headers: [String: String]? = nil,
        retryCount: Int = 0
    ) async throws -> T {
        let data = try await performRawRequest(urlString: urlString, headers: headers, retryCount: retryCount)
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw APIError.decodingFailed(underlying: error)
        }
    }

    private func performRawRequest(
        urlString: String,
        headers: [String: String]? = nil,
        retryCount: Int = 0
    ) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL(urlString)
        }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let headers = headers {
            for (key, val) in headers {
                request.setValue(val, forHTTPHeaderField: key)
            }
        }
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if (httpResponse.statusCode == 401 || httpResponse.statusCode == 403) && retryCount < Self.maxRetries {
            try await scraper.refreshClientID()
            let newClientID = try await scraper.getClientID()
            let refreshedURLString = replaceClientID(in: urlString, with: newClientID)
            return try await performRawRequest(
                urlString: refreshedURLString,
                headers: headers,
                retryCount: retryCount + 1
            )
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }

        return data
    }

    /// Resolves the direct stream URL for a track.
    /// Strictly filters out unsupported codecs (ogg/opus) on iOS 15.
    /// Prioritizes Progressive audio/mpeg -> HLS audio/mpeg -> HLS audio/mp4 (AAC).
    func resolveStreamURL(for track: Track) async throws -> URL {
        var currentTrack = track
        if currentTrack.media?.transcodings.isEmpty ?? true {
            if let full = try? await getTrack(id: track.id) {
                currentTrack = full
            }
        }

        guard let transcodings = currentTrack.media?.transcodings, !transcodings.isEmpty else {
            throw APIError.noTranscodings
        }

        // Strictly eliminate all ogg and opus transcodings as iOS 15 AVPlayer cannot decode them
        let compatibleTranscodings = transcodings.filter { transcoding in
            let mime = transcoding.format.mimeType.lowercased()
            if mime.contains("ogg") || mime.contains("opus") {
                return false
            }
            return mime.contains("mpeg") || mime.contains("mp4") || mime.contains("aac")
        }

        guard !compatibleTranscodings.isEmpty else {
            throw APIError.unsupportedAudioCodec
        }

        let sorted = prioritizeTranscodings(compatibleTranscodings)

        var lastError: Error = APIError.noStreamURL

        for transcoding in sorted {
            do {
                let streamURL = try await fetchStreamURL(from: transcoding)
                return streamURL
            } catch {
                lastError = error
                continue
            }
        }

        throw lastError
    }

    /// Sorts transcodings by strict priority:
    /// Progressive audio/mpeg -> HLS audio/mpeg -> HLS audio/mp4 (AAC).
    private func prioritizeTranscodings(_ transcodings: [Transcoding]) -> [Transcoding] {
        transcodings.sorted { a, b in
            let scoreA = transcodingPriority(a)
            let scoreB = transcodingPriority(b)
            return scoreA > scoreB
        }
    }

    private func transcodingPriority(_ transcoding: Transcoding) -> Int {
        var score = 0
        let mime = transcoding.format.mimeType.lowercased()

        // Strict priority: Progressive audio/mpeg -> HLS audio/mpeg -> HLS audio/mp4 (AAC)
        if transcoding.isProgressive && mime.contains("mpeg") {
            score = 300
        } else if transcoding.isHLS && mime.contains("mpeg") {
            score = 200
        } else if (transcoding.isHLS || transcoding.isProgressive) && (mime.contains("mp4") || mime.contains("aac")) {
            score = 100
        } else {
            score = 10
        }

        // Prefer non-snipped full stream over snipped preview
        if transcoding.snipped != true {
            score += 50
        }

        if transcoding.quality == "hq" {
            score += 5
        }

        return score
    }

    /// Fetches the actual media URL from a transcoding endpoint.
    /// The transcoding URL returns JSON `{ "url": "https://cf-media.sndcdn.com/..." }`.
    private func fetchStreamURL(from transcoding: Transcoding) async throws -> URL {
        let clientID = try await scraper.getClientID()
        let separator = transcoding.url.contains("?") ? "&" : "?"
        let urlString = "\(transcoding.url)\(separator)client_id=\(clientID)"

        let response: StreamURLResponse = try await performRequest(
            urlString: urlString,
            decodeAs: StreamURLResponse.self,
            retryCount: 0
        )

        guard let streamURL = URL(string: response.url) else {
            throw APIError.invalidStreamURL(response.url)
        }

        return streamURL
    }

    // MARK: - Waveform Data

    /// Fetches waveform sample data from the track's waveform URL.
    /// SoundCloud waveform URLs point to JSON with `{ width, height, samples: [Float] }`.
    func fetchWaveform(for track: Track) async throws -> WaveformData {
        guard let waveformURLString = track.waveformURL else {
            throw APIError.noWaveformURL
        }

        let jsonURLString = waveformURLString
            .replacingOccurrences(of: "/w/", with: "/w/json/")
            .replacingOccurrences(of: ".png", with: ".json")

        guard let url = URL(string: jsonURLString) else {
            throw APIError.invalidURL(jsonURLString)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw APIError.httpError(statusCode: statusCode)
        }

        let decoder = JSONDecoder()
        let waveform = try decoder.decode(WaveformData.self, from: data)
        return waveform
    }

    /// Fetches waveform samples as a float array for UI scrubbers.
    func getWaveformData(for track: Track) async throws -> [Float] {
        let waveform = try await fetchWaveform(for: track)
        return waveform.samples
    }

    /// Replaces the client_id parameter in a URL string with a new value.
    private func replaceClientID(in urlString: String, with newID: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"client_id=[a-zA-Z0-9]+"#, options: []) else {
            return urlString
        }
        let range = NSRange(urlString.startIndex..<urlString.endIndex, in: urlString)
        return regex.stringByReplacingMatches(
            in: urlString,
            options: [],
            range: range,
            withTemplate: "client_id=\(newID)"
        )
    }
}

// MARK: - API Errors

enum APIError: LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingFailed(underlying: Error)
    case noTranscodings
    case unsupportedAudioCodec
    case noStreamURL
    case invalidStreamURL(String)
    case noWaveformURL

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .invalidResponse:
            return "Received an invalid response from the server."
        case .httpError(let code):
            return "Server returned HTTP \(code)."
        case .decodingFailed(let err):
            return "Failed to decode response: \(err.localizedDescription)"
        case .noTranscodings:
            return "This track has no available stream transcodings."
        case .unsupportedAudioCodec:
            return "This track contains no supported MP3 or AAC streams for iOS 15."
        case .noStreamURL:
            return "Could not resolve a stream URL for this track."
        case .invalidStreamURL(let url):
            return "Invalid stream URL received: \(url)"
        case .noWaveformURL:
            return "This track has no waveform data URL."
        }
    }
}
