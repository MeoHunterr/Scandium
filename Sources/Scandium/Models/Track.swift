// Track.swift — Codable structs for SoundCloud API v2 JSON
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import Foundation

// MARK: - Search Response

struct SearchResponse: Codable {
    let collection: [Track]
    let totalResults: Int?
    let nextHref: String?
    let queryUrn: String?

    enum CodingKeys: String, CodingKey {
        case collection
        case totalResults = "total_results"
        case nextHref = "next_href"
        case queryUrn = "query_urn"
    }
}

// MARK: - Track

struct Track: Codable, Identifiable, Equatable, Hashable {
    let id: Int
    let title: String
    let description: String?
    let duration: Int
    let fullDuration: Int?
    let genre: String?
    let tagList: String?
    let artworkURL: String?
    let waveformURL: String?
    let streamable: Bool?
    let downloadable: Bool?
    let playbackCount: Int?
    let likesCount: Int?
    let repostsCount: Int?
    let commentCount: Int?
    let permalinkURL: String?
    let permalink: String?
    let uri: String?
    let urn: String?
    let kind: String?
    let createdAt: String?
    let lastModified: String?
    let user: SoundCloudUser?
    let media: MediaInfo?
    let publisherMetadata: PublisherMetadata?
    let stationURN: String?
    let stationPermalink: String?

    enum CodingKeys: String, CodingKey {
        case id, title, description, duration, genre, uri, urn, kind, permalink, streamable, downloadable, media, user
        case fullDuration = "full_duration"
        case tagList = "tag_list"
        case artworkURL = "artwork_url"
        case waveformURL = "waveform_url"
        case playbackCount = "playback_count"
        case likesCount = "likes_count"
        case repostsCount = "reposts_count"
        case commentCount = "comment_count"
        case permalinkURL = "permalink_url"
        case createdAt = "created_at"
        case lastModified = "last_modified"
        case publisherMetadata = "publisher_metadata"
        case stationURN = "station_urn"
        case stationPermalink = "station_permalink"
    }

    static func == (lhs: Track, rhs: Track) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: - Artwork Helpers

    /// Returns high-resolution 500x500 artwork URL with fallback to artist avatar
    var highResArtworkURL: URL? {
        if let raw = artworkURL {
            let upgraded = Self.upgradeArtwork(urlString: raw, to: .t500x500)
            if let url = URL(string: upgraded) { return url }
        }
        if let avatar = user?.avatarURL {
            let upgraded = Self.upgradeArtwork(urlString: avatar, to: .t500x500)
            if let url = URL(string: upgraded) { return url }
        }
        return nil
    }

    /// Returns default size artwork URL with fallback to artist avatar
    var artworkImageURL: URL? {
        if let raw = artworkURL, let url = URL(string: raw) {
            return url
        }
        if let avatar = user?.avatarURL, let url = URL(string: avatar) {
            return url
        }
        return nil
    }

    /// Returns artwork at given size with fallback to artist avatar
    func artworkURL(size: ArtworkSize) -> URL? {
        if let raw = artworkURL {
            let upgraded = Self.upgradeArtwork(urlString: raw, to: size)
            if let url = URL(string: upgraded) { return url }
        }
        if let avatar = user?.avatarURL {
            let upgraded = Self.upgradeArtwork(urlString: avatar, to: size)
            if let url = URL(string: upgraded) { return url }
        }
        return nil
    }

    /// Replaces the SoundCloud artwork size token in a URL string.
    static func upgradeArtwork(urlString: String, to size: ArtworkSize) -> String {
        let sizeTokens = [
            "-t500x500",
            "-crop",
            "-t300x300",
            "-large",
            "-t200x200",
            "-t120x120",
            "-t67x67",
            "-t47x47",
            "-small",
            "-mini",
            "-tiny",
            "-badge",
            "-original"
        ]
        var result = urlString
        for token in sizeTokens {
            if result.contains(token) {
                result = result.replacingOccurrences(of: token, with: size.token)
                return result
            }
        }
        return result
    }

    // MARK: - Duration Helpers

    /// Duration in seconds (API returns milliseconds).
    var durationInSeconds: TimeInterval {
        TimeInterval(duration) / 1000.0
    }

    /// Full duration in seconds (for tracks with intros/outros), falls back to `duration`.
    var fullDurationInSeconds: TimeInterval {
        TimeInterval(fullDuration ?? duration) / 1000.0
    }

    /// Human-readable duration string (e.g., "3:45" or "1:02:30").
    var formattedDuration: String {
        Self.formatDuration(durationInSeconds)
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let hrs = totalSeconds / 3600
        let mins = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hrs > 0 {
            return String(format: "%d:%02d:%02d", hrs, mins, secs)
        } else {
            return String(format: "%d:%02d", mins, secs)
        }
    }

    // MARK: - Playback Count Helpers

    /// Human-readable playback count (e.g., "1.2M", "450K", "1,234").
    var formattedPlaybackCount: String? {
        guard let count = playbackCount else { return nil }
        return Self.formatCount(count)
    }

    static func formatCount(_ count: Int) -> String {
        if count >= 1_000_000_000 {
            let value = Double(count) / 1_000_000_000.0
            return String(format: "%.1fB", value)
        } else if count >= 1_000_000 {
            let value = Double(count) / 1_000_000.0
            return String(format: "%.1fM", value)
        } else if count >= 1_000 {
            let value = Double(count) / 1_000.0
            return String(format: "%.1fK", value)
        } else {
            return "\(count)"
        }
    }
}

// MARK: - Artwork Size

enum ArtworkSize: String, CaseIterable {
    case mini
    case tiny
    case small
    case badge
    case t67x67
    case t47x47
    case t120x120
    case t200x200
    case t300x300
    case large
    case t500x500
    case crop
    case original

    var token: String {
        switch self {
        case .mini:     return "-mini"
        case .tiny:     return "-tiny"
        case .small:    return "-small"
        case .badge:    return "-badge"
        case .t67x67:   return "-t67x67"
        case .t47x47:   return "-t47x47"
        case .t120x120: return "-t120x120"
        case .t200x200: return "-t200x200"
        case .t300x300: return "-t300x300"
        case .large:    return "-large"
        case .t500x500: return "-t500x500"
        case .crop:     return "-crop"
        case .original: return "-original"
        }
    }
}

// MARK: - SoundCloud User

struct SoundCloudUser: Codable, Identifiable, Equatable, Hashable {
    let id: Int
    let username: String
    let fullName: String?
    let avatarURL: String?
    let permalink: String?
    let permalinkURL: String?
    let uri: String?
    let urn: String?
    let verified: Bool?
    let city: String?
    let countryCode: String?
    let followersCount: Int?
    let followingsCount: Int?
    let trackCount: Int?
    let playlistCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, username, permalink, uri, urn, verified, city
        case fullName = "full_name"
        case avatarURL = "avatar_url"
        case permalinkURL = "permalink_url"
        case countryCode = "country_code"
        case followersCount = "followers_count"
        case followingsCount = "followings_count"
        case trackCount = "track_count"
        case playlistCount = "playlist_count"
    }

    static func == (lhs: SoundCloudUser, rhs: SoundCloudUser) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// Avatar URL upgraded to 500×500
    var highResAvatarURL: URL? {
        guard let raw = avatarURL else { return nil }
        let upgraded = Track.upgradeArtwork(urlString: raw, to: .t500x500)
        return URL(string: upgraded)
    }
}

// MARK: - Media Info

struct MediaInfo: Codable, Equatable, Hashable {
    let transcodings: [Transcoding]
}

// MARK: - Transcoding

struct Transcoding: Codable, Equatable, Hashable {
    let url: String
    let preset: String?
    let duration: Int?
    let snipped: Bool?
    let format: TranscodingFormat
    let quality: String?

    /// Whether this transcoding uses the progressive (direct MP3) protocol.
    var isProgressive: Bool {
        format.protocol == "progressive"
    }

    /// Whether this transcoding uses HLS (.m3u8) protocol.
    var isHLS: Bool {
        format.protocol == "hls"
    }
}

// MARK: - Transcoding Format

struct TranscodingFormat: Codable, Equatable, Hashable {
    let `protocol`: String
    let mimeType: String

    enum CodingKeys: String, CodingKey {
        case `protocol`
        case mimeType = "mime_type"
    }
}

// MARK: - Stream URL Response

struct StreamURLResponse: Codable {
    let url: String
}

// MARK: - Publisher Metadata

struct PublisherMetadata: Codable, Equatable, Hashable {
    let id: Int?
    let urn: String?
    let artist: String?
    let albumTitle: String?
    let containsMusic: Bool?
    let publisher: String?
    let isrc: String?
    let releaseTitle: String?

    enum CodingKeys: String, CodingKey {
        case id, urn, artist, publisher, isrc
        case albumTitle = "album_title"
        case containsMusic = "contains_music"
        case releaseTitle = "release_title"
    }
}

// MARK: - Waveform Data

struct WaveformData: Codable {
    let width: Int
    let height: Int
    let samples: [Float]
}

// MARK: - Playlist Model

struct SoundCloudPlaylist: Codable, Identifiable, Equatable, Hashable {
    let id: Int
    let title: String
    let description: String?
    let duration: Int?
    let trackCount: Int?
    let artworkURL: String?
    let permalinkURL: String?
    let tracks: [Track]?
    let user: SoundCloudUser?

    enum CodingKeys: String, CodingKey {
        case id, title, description, duration, tracks, user
        case trackCount = "track_count"
        case artworkURL = "artwork_url"
        case permalinkURL = "permalink_url"
    }

    static func == (lhs: SoundCloudPlaylist, rhs: SoundCloudPlaylist) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var highResArtworkURL: URL? {
        if let raw = artworkURL {
            let upgraded = Track.upgradeArtwork(urlString: raw, to: .t500x500)
            if let url = URL(string: upgraded) { return url }
        }
        if let avatar = user?.avatarURL {
            let upgraded = Track.upgradeArtwork(urlString: avatar, to: .t500x500)
            if let url = URL(string: upgraded) { return url }
        }
        return nil
    }
}

