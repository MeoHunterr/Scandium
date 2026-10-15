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
}
