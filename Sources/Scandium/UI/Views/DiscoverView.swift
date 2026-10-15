// DiscoverView.swift — Spotify-style clean Home & Music screen
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject var api: SoundCloudAPI
    @EnvironmentObject var player: AudioPlayerEngine
    @EnvironmentObject var library: LibraryManager
    @EnvironmentObject var scraper: ClientIDScraper

    let onNavigateToSearch: () -> Void
    let onNavigateToLibrary: () -> Void

    @ObservedObject private var store = DiscoverDataStore.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var showClientIDSheet: Bool = false

    init(
        onNavigateToSearch: @escaping () -> Void = {},
        onNavigateToLibrary: @escaping () -> Void = {}
    ) {
        self.onNavigateToSearch = onNavigateToSearch
        self.onNavigateToLibrary = onNavigateToLibrary
    }

    private var emptyQuickCard: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .frame(width: 56, height: 56)
            Text(settings.loc("Chưa tải được dữ liệu", "Unable to load data"))
                .font(.system(size: 12))
                .foregroundColor(ScandiumTheme.subtext)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 8)
        }
        .frame(height: 56)
        .background(ScandiumTheme.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: ScandiumTheme.cornerRadiusSmall, style: .continuous))
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                // Header (Under Safe Area)
                headerView
                    .padding(.top, 8)

                if let error = store.error {
                    homeErrorBanner(error)
                }

                // 2-Column Quick Picks Grid (Spotify style: 56pt height, #181818)
                quickPicksSection

                // Personalized Carousel (Gợi ý cá nhân theo tài khoản / Client ID / Thư viện)
                if !store.personalizedTracks.isEmpty || store.isLoading {
                    carouselSection(
                        title: store.personalizedTitle,
                        subtitle: store.personalizedSubtitle,
                        tracks: store.personalizedTracks
                    )
                }

                // Horizontal Carousel: Thịnh hành (Trending)
                carouselSection(
                    title: settings.loc("Thịnh hành (VN)", "Trending (VN)"),
                    tracks: store.trendingTracks
                )

                // Horizontal Carousel: Chill & R&B
                carouselSection(
                    title: settings.loc("Chill & R&B", "Chill & R&B"),
                    tracks: store.chillTracks
                )

                // Horizontal Carousel: Remix & EDM
                carouselSection(
                    title: settings.loc("Remix sôi động", "Remix & Dance"),
                    tracks: store.remixTracks
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 130) // Ensure content is never hidden behind floating player & tab bar
        }
        .refreshable {
            await store.refresh(api: api)
        }
        .sheet(isPresented: $showClientIDSheet) {
            ClientIDConfigModal(scraper: scraper)
        }
        .onAppear {
            store.loadInitialData(api: api)
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Scandium")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(ScandiumTheme.textPrimary)
            }

            Spacer()

            HStack(spacing: 10) {
                // Refresh / Reload Button
                Button(action: {
                    Task {
                        await store.refresh(api: api)
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(ScandiumTheme.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(ScandiumTheme.surfaceElevated)
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())

                // Search Shortcut
                Button(action: onNavigateToSearch) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(ScandiumTheme.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(ScandiumTheme.surfaceElevated)
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())

                // Status & Config Pill
                Button(action: { showClientIDSheet = true }) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(scraper.lastError == nil ? ScandiumTheme.spotifyGreen : Color.orange)
                            .frame(width: 7, height: 7)

                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(ScandiumTheme.textPrimary.opacity(0.85))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .background(ScandiumTheme.surfaceElevated)
                    .clipShape(Capsule())
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    // MARK: - 2-Column Quick Picks Grid (Spotify Style)

    private var quickPicksSection: some View {
        let columns = [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ]

        return LazyVGrid(columns: columns, spacing: 8) {
            // Card 1: Liked Songs (Classic Spotify Favorite)
            likedSongsQuickCard

            // Cards 2-6: Dynamic quick-pick tracks
            if store.quickPicks.isEmpty {
                if store.isLoading {
                    ForEach(0..<5, id: \.self) { _ in
                        shimmerQuickCard
                    }
                } else {
                    ForEach(0..<5, id: \.self) { _ in
                        emptyQuickCard
                    }
                }
            } else {
                ForEach(Array(store.quickPicks.prefix(5).enumerated()), id: \.offset) { _, track in
                    quickPickCard(track: track)
                }
            }
        }
    }

    private var likedSongsQuickCard: some View {
        Button(action: onNavigateToLibrary) {
            HStack(spacing: 8) {
                // Left 56x56 gradient artwork with heart
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 0.28, green: 0.15, blue: 0.65),
                            Color(red: 0.55, green: 0.35, blue: 0.85)
                        ],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    )
                    Image(systemName: "heart.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(width: 56, height: 56)
                .clipped()

                Text(settings.loc("Bài hát đã thích", "Liked Songs"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ScandiumTheme.textPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 56)
            .background(ScandiumTheme.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: ScandiumTheme.cornerRadiusSmall, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func quickPickCard(track: Track) -> some View {
        Button(action: {
            player.play(track: track)
        }) {
            HStack(spacing: 8) {
                CachedAsyncImage(
                    url: track.artworkURL(size: .t120x120) ?? track.artworkImageURL,
                    width: 56,
                    height: 56,
                    cornerRadius: 0
                )

                Text(track.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(player.currentTrack?.id == track.id ? ScandiumTheme.spotifyGreen : ScandiumTheme.textPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 56)
            .background(ScandiumTheme.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: ScandiumTheme.cornerRadiusSmall, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var shimmerQuickCard: some View {
        HStack(spacing: 8) {
            ShimmerView()
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 12)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 60, height: 10)
            }
            .padding(.trailing, 8)
        }
        .frame(height: 56)
        .background(ScandiumTheme.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: ScandiumTheme.cornerRadiusSmall, style: .continuous))
    }

    // MARK: - Horizontal Carousel Section (148x148 square cards)

    private func carouselSection(title: String, subtitle: String? = nil, tracks: [Track]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(ScandiumTheme.textPrimary)
                if let sub = subtitle, !sub.isEmpty {
                    Text(sub)
                        .font(.system(size: 12))
                        .foregroundColor(ScandiumTheme.subtext)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    if tracks.isEmpty {
                        if store.isLoading {
                            ForEach(0..<4, id: \.self) { _ in
                                shimmerCarouselCard
                            }
                        } else {
                            ForEach(0..<2, id: \.self) { _ in
                                emptyCarouselCard
                            }
                        }
                    } else {
                        ForEach(Array(tracks.enumerated()), id: \.offset) { _, track in
                            carouselCard(track: track)
                        }
                    }
                }
            }
        }
    }

    private func carouselCard(track: Track) -> some View {
        Button(action: {
            player.play(track: track)
        }) {
            VStack(alignment: .leading, spacing: 6) {
                // Square 148x148 Artwork, 8pt corner radius, strictly clipped
                CachedAsyncImage(
                    url: track.highResArtworkURL ?? track.artworkImageURL,
                    width: 148,
                    height: 148,
                    cornerRadius: 8
                )

                // Track title (white, bold)
                Text(track.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(player.currentTrack?.id == track.id ? ScandiumTheme.spotifyGreen : ScandiumTheme.textPrimary)
                    .lineLimit(1)
                    .frame(width: 148, alignment: .leading)

                // Artist name (gray #A7A7A7)
                Text(track.user?.username ?? "SoundCloud")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(ScandiumTheme.subtext)
                    .lineLimit(1)
                    .frame(width: 148, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var shimmerCarouselCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            ShimmerView()
                .frame(width: 148, height: 148)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.08))
                .frame(width: 120, height: 12)

            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.04))
                .frame(width: 80, height: 10)
        }
        .frame(width: 148)
    }

    private var emptyCarouselCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .frame(width: 148, height: 148)
            Text(settings.loc("Chưa có dữ liệu", "No data available"))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(ScandiumTheme.subtext)
                .lineLimit(1)
            Text(settings.loc("Kéo xuống hoặc bấm thử lại", "Pull down or tap retry"))
                .font(.system(size: 11))
                .foregroundColor(ScandiumTheme.subtext.opacity(0.8))
                .lineLimit(1)
        }
        .frame(width: 148)
    }

    // MARK: - Data Loading

    private func homeErrorBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(ScandiumTheme.subtext)
                .lineLimit(nil)

            Button(action: {
                store.loadInitialData(api: api, force: true)
            }) {
                Text(settings.loc("Thử tải lại", "Retry"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(ScandiumTheme.spotifyGreen)
                    .clipShape(Capsule())
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ScandiumTheme.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Discover Data Store (Persistent across tab switches)

final class DiscoverDataStore: ObservableObject {
    static let shared = DiscoverDataStore()

    @Published var quickPicks: [Track] = []
    @Published var personalizedTracks: [Track] = []
    @Published var personalizedTitle: String = "Made for You"
    @Published var personalizedSubtitle: String? = nil
    @Published var trendingTracks: [Track] = []
    @Published var chillTracks: [Track] = []
    @Published var remixTracks: [Track] = []
    @Published var isLoading: Bool = false
    @Published var isRefreshing: Bool = false
    @Published var error: String?

    private var hasLoaded: Bool = false
    private let cacheKey = "scandium_discover_cached_payload_v1"

    private struct DiscoverCachePayload: Codable {
        let quickPicks: [Track]
        let personalizedTracks: [Track]
        let personalizedTitle: String
        let personalizedSubtitle: String?
        let trendingTracks: [Track]
        let chillTracks: [Track]
        let remixTracks: [Track]
    }

    private init() {
        loadCachedFeed()
    }

    private func loadCachedFeed() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let payload = try? JSONDecoder().decode(DiscoverCachePayload.self, from: data) else {
            return
        }
        self.quickPicks = payload.quickPicks
        self.personalizedTracks = payload.personalizedTracks
        self.personalizedTitle = payload.personalizedTitle
        self.personalizedSubtitle = payload.personalizedSubtitle
        self.trendingTracks = payload.trendingTracks
        self.chillTracks = payload.chillTracks
        self.remixTracks = payload.remixTracks
        self.hasLoaded = true
    }

    private func saveCachedFeed() {
        let payload = DiscoverCachePayload(
            quickPicks: quickPicks,
            personalizedTracks: personalizedTracks,
            personalizedTitle: personalizedTitle,
            personalizedSubtitle: personalizedSubtitle,
            trendingTracks: trendingTracks,
            chillTracks: chillTracks,
            remixTracks: remixTracks
        )
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    func refresh(api: SoundCloudAPI) async {
        await MainActor.run {
            self.isRefreshing = true
        }
        await loadData(api: api, force: true)
        await MainActor.run {
            self.isRefreshing = false
        }
    }

    func loadInitialData(api: SoundCloudAPI, force: Bool = false) {
        // If already loading, avoid duplicate triggers
        if isLoading && !force {
            return
        }

        Task {
            await loadData(api: api, force: force)
        }
    }

    private func loadData(api: SoundCloudAPI, force: Bool) async {
        await MainActor.run {
            // Only set fullscreen shimmer if we have no cached content to show
            if self.quickPicks.isEmpty && self.trendingTracks.isEmpty {
                self.isLoading = true
            }
            self.error = nil
        }

        let auth = SoundCloudAuthManager.shared
        let library = LibraryManager.shared

        // 1. Personalized Tracks resolution
        async let persTask = fetchPersonalizedTracks(api: api, auth: auth, library: library, force: force)

        // 2. Dynamic Quick Picks (user favorites + rotating queries with random offset)
        async let qpTask = fetchQuickPicks(api: api, auth: auth, library: library, force: force)

        // 3. Rotating Curated Sections with random offsets on force refresh
        let trendingOffset = force ? Int.random(in: 0...5) : 0
        let chillOffset = force ? Int.random(in: 0...5) : 0
        let remixOffset = force ? Int.random(in: 0...5) : 0

        async let trTask = safeSearch(api: api, query: "Top Vietnam", limit: 10, offset: trendingOffset)
        async let chTask = safeSearch(api: api, query: "Chill R&B", limit: 10, offset: chillOffset)
        async let rmTask = safeSearch(api: api, query: "Remix Lo-Fi", limit: 10, offset: remixOffset)

        let (persResult, qpTracks, trTracks, chTracks, rmTracks) = await (persTask, qpTask, trTask, chTask, rmTask)

        await MainActor.run {
            self.personalizedTracks = self.deduplicateTracks(persResult.tracks)
            self.personalizedTitle = persResult.title
            self.personalizedSubtitle = persResult.subtitle

            if !qpTracks.isEmpty { self.quickPicks = self.deduplicateTracks(qpTracks) }
            if !trTracks.isEmpty { self.trendingTracks = self.deduplicateTracks(trTracks) }
            if !chTracks.isEmpty { self.chillTracks = self.deduplicateTracks(chTracks) }
            if !rmTracks.isEmpty { self.remixTracks = self.deduplicateTracks(rmTracks) }

            self.isLoading = false
            self.hasLoaded = true
            self.saveCachedFeed()

            if self.quickPicks.isEmpty && self.trendingTracks.isEmpty && self.personalizedTracks.isEmpty {
                self.error = AppSettings.shared.loc(
                    "Không tải được dữ liệu âm nhạc. Hãy thử lại hoặc kiểm tra cấu hình mạng.",
                    "Unable to load music data. Please try again or check network config."
                )
            }
        }
    }

    private func fetchQuickPicks(api: SoundCloudAPI, auth: SoundCloudAuthManager, library: LibraryManager, force: Bool) async -> [Track] {
        var candidatePicks: [Track] = []
        var seenIDs = Set<Int>()

        // 1. User personalized seeds (favorites, liked, recently played)
        let userSeeds = (auth.userLikedTracks + library.likedTracks + library.recentlyPlayed).shuffled()
        for track in userSeeds {
            if seenIDs.insert(track.id).inserted {
                candidatePicks.append(track)
                if candidatePicks.count >= 3 { break }
            }
        }

        // 2. Rotating genre queries with randomized offsets to guarantee fresh results on every reload
        let queryPool = [
            "V-Pop Hits",
            "Top Trending",
            "EDM Festival",
            "Chill R&B",
            "Acoustic Pop",
            "Vietnamese Indie",
            "Remix Dance",
            "Deep House",
            "Lo-Fi Beats"
        ].shuffled()

        for q in queryPool.prefix(2) {
            let offset = force ? Int.random(in: 0...10) : 0
            let fetched = await safeSearch(api: api, query: q, limit: 6, offset: offset)
            for track in fetched {
                if seenIDs.insert(track.id).inserted {
                    candidatePicks.append(track)
                }
            }
        }

        if candidatePicks.isEmpty {
            let fallback = await safeSearch(api: api, query: "Top Hits", limit: 6, offset: 0)
            return fallback
        }

        return Array(candidatePicks.prefix(6))
    }

    private func fetchPersonalizedTracks(api: SoundCloudAPI, auth: SoundCloudAuthManager, library: LibraryManager, force: Bool) async -> (title: String, subtitle: String?, tracks: [Track]) {
        let isEn = AppSettings.shared.language == .english

        // Priority 1: User is logged in to SoundCloud with OAuth
        if auth.isAuthenticated {
            if let token = auth.oauthToken, !token.isEmpty {
                do {
                    let stream = try await api.getUserStream(oauthToken: token, limit: 12)
                    if !stream.isEmpty {
                        let username = auth.currentUser?.username ?? (isEn ? "you" : "bạn")
                        let title = isEn ? "Feed for \(username)" : "Bảng tin của \(username)"
                        let subtitle = isEn ? "New tracks from artists you follow" : "Bài hát mới từ nghệ sĩ bạn theo dõi"
                        return (title, subtitle, stream)
                    }
                } catch {
                    // Fall back to liked tracks
                }
            }

            if let seed = auth.userLikedTracks.randomElement() {
                do {
                    let related = try await api.getRelatedTracks(trackID: seed.id, limit: 12)
                    if !related.isEmpty {
                        let title = isEn ? "Related Recommendations" : "Gợi ý liên quan"
                        let subtitle = isEn ? "Based on '\(seed.title)' you liked" : "Dựa trên '\(seed.title)' bạn đã thích"
                        return (title, subtitle, related)
                    }
                } catch {}
            }
        }

        // Priority 1.5: If user has followed artists, discover songs by their followed artists
        if auth.isAuthenticated, !auth.userFollowings.isEmpty {
            if let randomArtist = auth.userFollowings.randomElement() {
                let artistTracks = await safeSearch(api: api, query: randomArtist.username, limit: 12, offset: 0)
                if !artistTracks.isEmpty {
                    let title = isEn ? "From Artists You Follow" : "Từ nghệ sĩ bạn theo dõi"
                    let subtitle = isEn ? "Top tracks from \(randomArtist.username)" : "Các bài hát nổi bật của \(randomArtist.username)"
                    return (title, subtitle, artistTracks)
                }
            }
        }

        // Priority 2: In-app liked songs
        if let seed = library.likedTracks.randomElement() {
            do {
                let related = try await api.getRelatedTracks(trackID: seed.id, limit: 12)
                if !related.isEmpty {
                    let title = isEn ? "Made for You" : "Dành riêng cho bạn"
                    let subtitle = isEn ? "Inspired by '\(seed.title)'" : "Lấy cảm hứng từ bài '\(seed.title)'"
                    return (title, subtitle, related)
                }
            } catch {}
        }

        // Priority 3: Recently played songs in history
        if let seed = library.recentlyPlayed.first {
            do {
                let related = try await api.getRelatedTracks(trackID: seed.id, limit: 12)
                if !related.isEmpty {
                    let title = isEn ? "Keep Listening" : "Tiếp tục nghe theo gu của bạn"
                    let subtitle = isEn ? "Suggestions from '\(seed.title)'" : "Gợi ý từ bài '\(seed.title)'"
                    return (title, subtitle, related)
                }
            } catch {}
        }

        // Priority 4: Dynamic client session recommendations with rich variety
        let dynamicQueries = [
            ("V-Pop Hot Hits", "Tuyển tập nhạc Việt thịnh hành"),
            ("Acoustic Chill", "Giai điệu mộc mạc thư giãn"),
            ("Deep Electronic & EDM", "Sôi động với năng lượng cao"),
            ("Lo-Fi Study Beats", "Tập trung và làm việc hiệu quả"),
            ("Indie Vibes", "Những thanh âm indie độc đáo")
        ]
        let chosen = dynamicQueries.randomElement() ?? ("Discover Weekly", "Khám phá hàng tuần")
        let randomOffset = force ? Int.random(in: 0...4) : 0
        let tracks = await safeSearch(api: api, query: chosen.0, limit: 12, offset: randomOffset)
        let title = isEn ? chosen.0 : chosen.0
        let subtitle = isEn ? "Curated discovery for your taste" : chosen.1
        return (title, subtitle, tracks)
    }

    private func safeSearch(api: SoundCloudAPI, query: String, limit: Int, offset: Int = 0) async -> [Track] {
        do {
            let response = try await api.searchTracks(query: query, limit: limit, offset: offset)
            return response.collection
        } catch {
            return []
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
}

// MARK: - Client ID Config Modal

struct ClientIDConfigModal: View {
    @ObservedObject var scraper: ClientIDScraper
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.presentationMode) var presentationMode

    @State private var inputID: String = ""
    @State private var isRefreshing: Bool = false
    @State private var showGuideSheet: Bool = false
    @State private var statusToast: String?

    init(scraper: ClientIDScraper) {
        self.scraper = scraper
    }

    var body: some View {
        NavigationView {
            ZStack {
                ScandiumTheme.bgPrimary.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        // Status Card
                        HStack(spacing: 12) {
                            Circle()
                                .fill(scraper.lastError == nil ? ScandiumTheme.spotifyGreen : Color.orange)
                                .frame(width: 10, height: 10)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(settings.loc("Trạng thái Token dịch vụ (Client ID)", "Service Token / Client ID Status"))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(ScandiumTheme.textPrimary)
                                Text(scraper.statusDescription)
                                    .font(.system(size: 12))
                                    .foregroundColor(ScandiumTheme.subtext)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(ScandiumTheme.surfaceDark)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        // Current ID info
                        if let current = scraper.currentClientID {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(settings.loc("Token hiện hành:", "Current Token:"))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(ScandiumTheme.subtext)
                                Text(current)
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundColor(ScandiumTheme.textPrimary)
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(ScandiumTheme.surfaceElevated)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }

                        // Auto scrape button
                        Button(action: {
                            guard !isRefreshing else { return }
                            isRefreshing = true
                            Task {
                                do {
                                    try await scraper.refreshClientID()
                                    await MainActor.run {
                                        isRefreshing = false
                                        statusToast = settings.loc("Làm mới Token thành công!", "Refreshed Token successfully!")
                                    }
                                } catch {
                                    await MainActor.run {
                                        isRefreshing = false
                                        statusToast = "\(settings.loc("Lỗi", "Error")): \(error.localizedDescription)"
                                    }
                                }
                            }
                        }) {
                            HStack {
                                if isRefreshing {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: ScandiumTheme.textPrimary))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                Text(settings.loc("Tự động làm mới Client ID", "Auto-Refresh Client ID"))
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(ScandiumTheme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(ScandiumTheme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(PlainButtonStyle())

                        HairlineDivider()

                        // Manual Entry
                        VStack(alignment: .leading, spacing: 8) {
                            Text(settings.loc("Cấu hình Client ID thủ công", "Manual Client ID Config"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(ScandiumTheme.textPrimary)

                            TextField(settings.loc("Dán chuỗi 32 ký tự...", "Paste 32-character key..."), text: $inputID)
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundColor(ScandiumTheme.textPrimary)
                                .padding(12)
                                .background(ScandiumTheme.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            HStack(spacing: 10) {
                                Button(action: {
                                    scraper.setManualClientID(inputID)
                                    presentationMode.wrappedValue.dismiss()
                                }) {
                                    Text(settings.loc("Lưu Client ID", "Save Client ID"))
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.black)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 40)
                                        .background(ScandiumTheme.spotifyGreen)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }

                                if scraper.manualClientID != nil {
                                    Button(action: {
                                        scraper.setManualClientID(nil)
                                        inputID = ""
                                        presentationMode.wrappedValue.dismiss()
                                    }) {
                                        Text(settings.loc("Khôi phục", "Reset"))
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(ScandiumTheme.textPrimary)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 40)
                                            .background(ScandiumTheme.surfaceElevated)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                        }

                        // Guide button
                        Button(action: {
                            showGuideSheet = true
                        }) {
                            HStack {
                                Image(systemName: "questionmark.circle")
                                Text(settings.loc("Xem hướng dẫn lấy Client ID trên máy tính", "How to extract Client ID from PC"))
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(ScandiumTheme.subtext)
                        }
                        .padding(.top, 4)
                    }
                    .padding(20)
                }
            }
            .navigationTitle(settings.loc("Cấu hình dịch vụ", "Service Configuration"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(settings.loc("Đóng", "Close")) {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(ScandiumTheme.textPrimary)
                }
            }
            .sheet(isPresented: $showGuideSheet) {
                ClientIDGuideSheet()
            }
            .onAppear {
                if let manual = scraper.manualClientID {
                    inputID = manual
                }
            }
        }
        .preferredColorScheme(settings.themeMode.colorScheme)
    }
}
