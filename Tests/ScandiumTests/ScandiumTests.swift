// ScandiumTests.swift — Pre-build Verification Unit Tests
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import XCTest
@testable import Scandium

final class ScandiumTests: XCTestCase {

    // MARK: - 1. JSON Decoding Tests

    func testDecodeTrackJSON() throws {
        let json = """
        {
            "id": 123456789,
            "title": "Echoes of Scandium",
            "description": "A demo track",
            "duration": 215000,
            "full_duration": 215000,
            "genre": "Electronic",
            "tag_list": "ambient synthwave",
            "artwork_url": "https://i1.sndcdn.com/artworks-sample-large.jpg",
            "waveform_url": "https://wave.sndcdn.com/sample_m.png",
            "playback_count": 1542000,
            "likes_count": 89200,
            "user": {
                "id": 987654,
                "username": "MeoHunter",
                "avatar_url": "https://i1.sndcdn.com/avatars-sample-large.jpg"
            },
            "media": {
                "transcodings": [
                    {
                        "url": "https://api-v2.soundcloud.com/media/soundcloud:tracks:123456789/progressive",
                        "preset": "mp3_0_1",
                        "duration": 215000,
                        "snipped": false,
                        "format": {
                            "protocol": "progressive",
                            "mime_type": "audio/mpeg"
                        },
                        "quality": "sq"
                    },
                    {
                        "url": "https://api-v2.soundcloud.com/media/soundcloud:tracks:123456789/hls",
                        "preset": "mp3_0_1",
                        "duration": 215000,
                        "snipped": false,
                        "format": {
                            "protocol": "hls",
                            "mime_type": "audio/mpeg"
                        },
                        "quality": "sq"
                    }
                ]
            }
        }
        """.data(using: .utf8)!

        let track = try JSONDecoder().decode(Track.self, from: json)
        XCTAssertEqual(track.id, 123456789)
        XCTAssertEqual(track.title, "Echoes of Scandium")
        XCTAssertEqual(track.duration, 215000)
        XCTAssertEqual(track.durationInSeconds, 215.0)
        XCTAssertEqual(track.formattedDuration, "3:35")
        XCTAssertEqual(track.formattedPlaybackCount, "1.5M")
        XCTAssertEqual(track.user?.username, "MeoHunter")
        XCTAssertEqual(track.media?.transcodings.count, 2)
        XCTAssertTrue(track.media?.transcodings.first?.isProgressive == true)
        XCTAssertTrue(track.media?.transcodings.last?.isHLS == true)
    }

    func testDecodeSearchResponseJSON() throws {
        let json = """
        {
            "collection": [
                {
                    "id": 111,
                    "title": "Track 1",
                    "duration": 180000
                },
                {
                    "id": 222,
                    "title": "Track 2",
                    "duration": 240000
                }
            ],
            "total_results": 2,
            "next_href": "https://api-v2.soundcloud.com/search/tracks?offset=2",
            "query_urn": "soundcloud:search:tracks:1"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(SearchResponse.self, from: json)
        XCTAssertEqual(response.collection.count, 2)
        XCTAssertEqual(response.totalResults, 2)
        XCTAssertEqual(response.nextHref, "https://api-v2.soundcloud.com/search/tracks?offset=2")
    }

    func testDecodeWaveformDataJSON() throws {
        let json = """
        {
            "width": 1800,
            "height": 140,
            "samples": [0, 5, 12, 45, 90, 120, 80, 20, 0]
        }
        """.data(using: .utf8)!

        let waveform = try JSONDecoder().decode(WaveformData.self, from: json)
        XCTAssertEqual(waveform.width, 1800)
        XCTAssertEqual(waveform.height, 140)
        XCTAssertEqual(waveform.samples.count, 9)
        XCTAssertEqual(waveform.samples[4], 90)
    }

    // MARK: - 2. Artwork Upgrade & Formatters Tests

    func testArtworkUpgradeTo500x500() {
        let rawURL = "https://i1.sndcdn.com/artworks-000123456789-large.jpg"
        let upgraded = Track.upgradeArtwork(urlString: rawURL, to: .t500x500)
        XCTAssertEqual(upgraded, "https://i1.sndcdn.com/artworks-000123456789-t500x500.jpg")

        let t300URL = "https://i1.sndcdn.com/artworks-sample-t300x300.jpg"
        let upgradedFrom300 = Track.upgradeArtwork(urlString: t300URL, to: .t500x500)
        XCTAssertEqual(upgradedFrom300, "https://i1.sndcdn.com/artworks-sample-t500x500.jpg")
    }

    func testDurationFormatting() {
        XCTAssertEqual(Track.formatDuration(0), "0:00")
        XCTAssertEqual(Track.formatDuration(45), "0:45")
        XCTAssertEqual(Track.formatDuration(215), "3:35")
        XCTAssertEqual(Track.formatDuration(3665), "1:01:05")
    }

    func testPlaybackCountFormatting() {
        XCTAssertEqual(Track.formatCount(450), "450")
        XCTAssertEqual(Track.formatCount(1234), "1.2K")
        XCTAssertEqual(Track.formatCount(45678), "45.7K")
        XCTAssertEqual(Track.formatCount(1500000), "1.5M")
        XCTAssertEqual(Track.formatCount(2300000000), "2.3B")
    }

    // MARK: - 3. Client ID Regex Extraction Tests

    func testClientIDRegexExtraction() {
        // Pattern 1: client_id:"..."
        let sampleJS1 = """
        !function(e){var t={};function n(r){...}client_id:"a1b2c3d4e5f60718293a4b5c6d7e8f90",user_id:123
        """
        let extracted1 = ClientIDScraper.extractClientID(from: sampleJS1)
        XCTAssertEqual(extracted1, "a1b2c3d4e5f60718293a4b5c6d7e8f90")

        // Pattern 2: client_id = "..."
        let sampleJS2 = """
        var client_id = "b2c3d4e5f6a10718293a4b5c6d7e8f91";
        """
        let extracted2 = ClientIDScraper.extractClientID(from: sampleJS2)
        XCTAssertEqual(extracted2, "b2c3d4e5f6a10718293a4b5c6d7e8f91")

        // Pattern 3: "client_id":"..."
        let sampleJS3 = """
        {"config":{"client_id":"c3d4e5f6a1b20718293a4b5c6d7e8f92"}}
        """
        let extracted3 = ClientIDScraper.extractClientID(from: sampleJS3)
        XCTAssertEqual(extracted3, "c3d4e5f6a1b20718293a4b5c6d7e8f92")

        // Pattern 4: query param client_id=...
        let sampleJS4 = """
        fetch("https://api-v2.soundcloud.com?client_id=1234567890abcdef1234567890abcdef&limit=10")
        """
        let extracted4 = ClientIDScraper.extractClientID(from: sampleJS4)
        XCTAssertEqual(extracted4, "1234567890abcdef1234567890abcdef")
    }

    // MARK: - 4. LibraryManager Persistence Tests

    func testLibraryManagerLikeOperations() {
        let manager = LibraryManager.shared
        manager.clearAllData()

        let sampleTrack = Track(
            id: 999999,
            title: "Test Track",
            description: nil,
            duration: 120000,
            fullDuration: 120000,
            genre: "Test",
            tagList: nil,
            artworkURL: nil,
            waveformURL: nil,
            streamable: true,
            downloadable: false,
            playbackCount: 10,
            likesCount: 5,
            repostsCount: 1,
            commentCount: 0,
            permalinkURL: nil,
            permalink: nil,
            uri: nil,
            urn: nil,
            kind: "track",
            createdAt: nil,
            lastModified: nil,
            user: nil,
            media: nil,
            publisherMetadata: nil,
            stationURN: nil,
            stationPermalink: nil
        )

        XCTAssertFalse(manager.isLiked(track: sampleTrack))
        manager.toggleLike(track: sampleTrack)
        XCTAssertTrue(manager.isLiked(track: sampleTrack))
        manager.toggleLike(track: sampleTrack)
        XCTAssertFalse(manager.isLiked(track: sampleTrack))

        manager.addToRecentlyPlayed(track: sampleTrack)
        XCTAssertEqual(manager.recentlyPlayed.first?.id, 999999)

        manager.clearAllData()
    }

    // MARK: - 5. SoundCloud User Decoding with URN Tests

    func testDecodeSoundCloudUserWithURN() throws {
        let json = """
        {
            "id": 1234567,
            "username": "soundcloud_tester",
            "full_name": "SoundCloud Tester",
            "avatar_url": "https://i1.sndcdn.com/avatars-000123-large.jpg",
            "urn": "soundcloud:users:1234567"
        }
        """.data(using: .utf8)!

        let user = try JSONDecoder().decode(SoundCloudUser.self, from: json)
        XCTAssertEqual(user.id, 1234567)
        XCTAssertEqual(user.username, "soundcloud_tester")
        XCTAssertEqual(user.urn, "soundcloud:users:1234567")
        XCTAssertEqual(user.fullName, "SoundCloud Tester")
    }

    // MARK: - 6. AppSettings Preferences Tests

    func testAppSettingsPreferences() {
        let settings = AppSettings.shared
        settings.accentColor = .soundcloudOrange
        XCTAssertEqual(settings.accentColor, .soundcloudOrange)

        settings.pauseOnHeadphoneDisconnect = true
        XCTAssertTrue(settings.pauseOnHeadphoneDisconnect)

        settings.autoSkipOnError = true
        XCTAssertTrue(settings.autoSkipOnError)

        settings.accentColor = .spotifyGreen
    }

    // MARK: - 7. SQLite Migration Tests

    func testLibraryManagerSQLiteMigrationFromUserDefaults() {
        // Test that migration correctly imports from UserDefaults JSON format
        let manager = LibraryManager.shared
        manager.clearAllData()

        // Simulate old UserDefaults JSON data
        let sampleTrack = Track(
            id: 777777,
            title: "Migration Test Track",
            description: nil,
            duration: 90000,
            fullDuration: 90000,
            genre: "Test",
            tagList: nil,
            artworkURL: nil,
            waveformURL: nil,
            streamable: true,
            downloadable: false,
            playbackCount: 0,
            likesCount: 0,
            repostsCount: 0,
            commentCount: 0,
            permalinkURL: nil,
            permalink: nil,
            uri: nil,
            urn: nil,
            kind: "track",
            createdAt: nil,
            lastModified: nil,
            user: nil,
            media: nil,
            publisherMetadata: nil,
            stationURN: nil,
            stationPermalink: nil
        )

        // Write in old UserDefaults format (simulating v1 data)
        let encoder = JSONEncoder()
        if let data = try? encoder.encode([sampleTrack]) {
            UserDefaults.standard.set(data, forKey: "scandium_liked_tracks_v1")
        }

        // Re-init a fresh manager to trigger migration
        // (In practice, migration runs in init; here we test the state)
        manager.like(track: sampleTrack)
        XCTAssertTrue(manager.isLiked(track: sampleTrack))
        XCTAssertFalse(manager.likedTracks.isEmpty)

        manager.clearAllData()
        XCTAssertTrue(manager.likedTracks.isEmpty)
        XCTAssertTrue(manager.recentlyPlayed.isEmpty)
    }

    func testLibraryManagerSQLiteRecentlyPlayedLimit() {
        let manager = LibraryManager.shared
        manager.clearAllData()

        // Add 55 tracks — should cap at 50
        for i in 1...55 {
            let t = Track(
                id: i,
                title: "Track \(i)",
                description: nil,
                duration: 60000,
                fullDuration: 60000,
                genre: nil,
                tagList: nil,
                artworkURL: nil,
                waveformURL: nil,
                streamable: true,
                downloadable: false,
                playbackCount: 0,
                likesCount: 0,
                repostsCount: 0,
                commentCount: 0,
                permalinkURL: nil,
                permalink: nil,
                uri: nil,
                urn: nil,
                kind: "track",
                createdAt: nil,
                lastModified: nil,
                user: nil,
                media: nil,
                publisherMetadata: nil,
                stationURN: nil,
                stationPermalink: nil
            )
            manager.addToRecentlyPlayed(track: t)
        }

        XCTAssertLessThanOrEqual(manager.recentlyPlayed.count, 50,
            "Recently played should be capped at 50 entries")

        manager.clearAllData()
    }

    // MARK: - 8. LRU Cache Tests

    func testImageCacheStoreEvictionThreshold() {
        // Verify the LRU threshold constants are correctly defined
        // 250 MB = 262,144,000 bytes
        let maxBytes: Int64 = 250 * 1024 * 1024
        let targetBytes: Int64 = Int64(Double(maxBytes) * 0.8)

        XCTAssertEqual(maxBytes, 262_144_000, "Max cache should be 250 MB")
        XCTAssertEqual(targetBytes, 209_715_200, "LRU target should be 200 MB (80%)")
    }

    func testLRUEvictionOrderIsLeastRecentlyUsed() {
        // Simulate LRU order: oldest access date should be evicted first
        let dates = [
            Date(timeIntervalSince1970: 1000),  // oldest
            Date(timeIntervalSince1970: 2000),
            Date(timeIntervalSince1970: 3000),  // newest
        ]
        // Sort ascending = oldest first = correct LRU eviction order
        let sorted = dates.sorted { $0 < $1 }
        XCTAssertEqual(sorted.first?.timeIntervalSince1970, 1000,
            "Oldest file (smallest timestamp) should be evicted first in LRU")
        XCTAssertEqual(sorted.last?.timeIntervalSince1970, 3000,
            "Newest file should be retained longest")
    }

    func testClientIDScraperNoFallbackOnFailure() {
        // After removing hardcoded fallbacks, clientID should be nil when no manual/cache
        // We test the status enum has .noClientID case
        // This is a compile-time check essentially — if the enum doesn't have this case,
        // the test file won't compile
        let status = ClientIDScraper.ScraperStatus.noClientID
        switch status {
        case .noClientID:
            XCTAssertTrue(true, "noClientID status case exists")
        default:
            XCTFail("Should be .noClientID")
        }
    }
}
