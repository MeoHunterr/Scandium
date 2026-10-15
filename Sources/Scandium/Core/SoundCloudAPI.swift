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

    /// Fetches a user's liked tracks
    func getUserLikes(userID: Int, oauthToken: String? = nil, limit: Int = 50) async throws -> [Track] {
        let clientID = try await scraper.getClientID()
        let urlString = "\(Self.baseURL)/users/\(userID)/likes?client_id=\(clientID)&limit=\(limit)"
        var headers: [String: String]? = nil
        if let token = oauthToken, !token.isEmpty {
            headers = ["Authorization": "OAuth \(token)"]
        }

        // Try decoding as collection of items with embedded track or direct tracks
        let data = try await performRawRequest(urlString: urlString, headers: headers)
        if let direct = try? JSONDecoder().decode(SearchResponse.self, from: data) {
            return direct.collection
        }

        struct LikeWrapper: Codable {
            let track: Track?
        }
        struct LikesResponse: Codable {
            let collection: [LikeWrapper]
        }
        if let wrapped = try? JSONDecoder().decode(LikesResponse.self, from: data) {
            return wrapped.collection.compactMap { $0.track }
        }

        return []
    }

    /// Fetches a user's public playlists
    func getUserPlaylists(userID: Int, oauthToken: String? = nil) async throws -> [SoundCloudPlaylist] {
        let clientID = try await scraper.getClientID()
        let urlString = "\(Self.baseURL)/users/\(userID)/playlists?client_id=\(clientID)&limit=20"
        var headers: [String: String]? = nil
        if let token = oauthToken, !token.isEmpty {
            headers = ["Authorization": "OAuth \(token)"]
        }

        struct PlaylistCollection: Codable {
            let collection: [SoundCloudPlaylist]
        }

        let data = try await performRawRequest(urlString: urlString, headers: headers)
        if let col = try? JSONDecoder().decode(PlaylistCollection.self, from: data) {
            return col.collection
        }
        if let arr = try? JSONDecoder().decode([SoundCloudPlaylist].self, from: data) {
            return arr
        }
        return []
    }

    /// Fetches related / recommended tracks for a given track ID
    func getRelatedTracks(trackID: Int, limit: Int = 15) async throws -> [Track] {
        let clientID = try await scraper.getClientID()
        let urlString = "\(Self.baseURL)/tracks/\(trackID)/related?client_id=\(clientID)&limit=\(limit)"

        let response = try await performRequest(
            urlString: urlString,
            decodeAs: SearchResponse.self,
            retryCount: 0
        )
        return response.collection
    }

    /// Fetches the authenticated user's stream / feed
    func getUserStream(oauthToken: String, limit: Int = 20) async throws -> [Track] {
        let clientID = try await scraper.getClientID()
        let urlString = "\(Self.baseURL)/stream?client_id=\(clientID)&limit=\(limit)"
        let headers = ["Authorization": "OAuth \(oauthToken)"]

        let data = try await performRawRequest(urlString: urlString, headers: headers)
        if let direct = try? JSONDecoder().decode(SearchResponse.self, from: data) {
            return direct.collection
        }

        struct StreamItem: Codable {
            let track: Track?
        }
        struct StreamResponse: Codable {
            let collection: [StreamItem]
        }
        if let streamRes = try? JSONDecoder().decode(StreamResponse.self, from: data) {
            return streamRes.collection.compactMap { $0.track }
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
    /// Prioritizes progressive (direct MP3) over HLS for lower CPU overhead on legacy devices.
    func resolveStreamURL(for track: Track) async throws -> URL {
        guard let transcodings = track.media?.transcodings, !transcodings.isEmpty else {
            throw APIError.noTranscodings
        }

        let sorted = prioritizeTranscodings(transcodings)

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

    /// Sorts transcodings to prefer progressive MP3, then HLS, then others.
    /// Within the same protocol, prefers audio/mpeg over opus.
    private func prioritizeTranscodings(_ transcodings: [Transcoding]) -> [Transcoding] {
        transcodings.sorted { a, b in
            let scoreA = transcodingPriority(a)
            let scoreB = transcodingPriority(b)
            return scoreA > scoreB
        }
    }

    private func transcodingPriority(_ transcoding: Transcoding) -> Int {
        var score = 0

        if transcoding.isProgressive {
            score += 100
        } else if transcoding.isHLS {
            score += 50
        }

        if transcoding.format.mimeType.contains("mpeg") {
            score += 20
        } else if transcoding.format.mimeType.contains("ogg") || transcoding.format.mimeType.contains("opus") {
            score += 10
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

    // MARK: - Generic Request with Auto-Retry on 401/403

    private func performRequest<T: Decodable>(
        urlString: String,
        decodeAs type: T.Type,
        retryCount: Int
    ) async throws -> T {
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
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if (httpResponse.statusCode == 401 || httpResponse.statusCode == 403) && retryCount < Self.maxRetries {
            try await scraper.refreshClientID()
            let newClientID = try await scraper.getClientID()
            let refreshedURLString = replaceClientID(in: urlString, with: newClientID)
            return try await performRequest(
                urlString: refreshedURLString,
                decodeAs: type,
                retryCount: retryCount + 1
            )
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw APIError.decodingFailed(underlying: error)
        }
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
        case .noStreamURL:
            return "Could not resolve a stream URL for this track."
        case .invalidStreamURL(let url):
            return "Invalid stream URL received: \(url)"
        case .noWaveformURL:
            return "This track has no waveform data URL."
        }
    }
}
