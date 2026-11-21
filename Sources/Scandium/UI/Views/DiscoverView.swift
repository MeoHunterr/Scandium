// DiscoverView.swift — Spotify-style clean Home & Music screen
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import SwiftUI
import UIKit

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

                // Following Stream Carousel (OAuth feed from followed artists)
                if !store.followingTracks.isEmpty {
                    carouselSection(
                        title: settings.loc("Mới từ nghệ sĩ bạn theo dõi", "New from Artists You Follow"),
                        subtitle: settings.loc("Bài hát mới và repost từ người bạn theo dõi", "Fresh tracks & reposts from artists you follow"),
                        tracks: store.followingTracks
                    )
                }

                // Personalized Carousel (Gợi ý cá nhân theo Seed Pool / Gu nhạc)
                if !store.personalizedTracks.isEmpty || store.isLoading {
                    carouselSection(
                        title: store.personalizedTitle,
                        subtitle: store.personalizedSubtitle,
                        tracks: store.personalizedTracks
                    )
                }

                // More from Favorite Artist Carousel
                if !store.artistSpotlightTracks.isEmpty {
                    carouselSection(
                        title: store.artistSpotlightTitle,
                        subtitle: store.artistSpotlightSubtitle,
                        tracks: store.artistSpotlightTracks
                    )
                }

                // Horizontal Carousel: Thịnh hành (Trending)
                carouselSection(
                    title: settings.loc("Thịnh hành", "Global Trending"),
                    tracks: store.trendingTracks
                )

                // Horizontal Carousel: Dynamic Genre 1
                if !store.genre1Tracks.isEmpty {
                    carouselSection(
                        title: store.genre1Title,
                        tracks: store.genre1Tracks
                    )
                }

                // Horizontal Carousel: Dynamic Genre 2
                if !store.genre2Tracks.isEmpty {
                    carouselSection(
                        title: store.genre2Title,
                        tracks: store.genre2Tracks
                    )
                }
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
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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
                let picks = Array(store.quickPicks.prefix(5))
                ForEach(Array(picks.enumerated()), id: \.offset) { _, track in
                    quickPickCard(track: track, in: picks)
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

    private func quickPickCard(track: Track, in picks: [Track]) -> some View {
        Button(action: {
            let idx = picks.firstIndex(where: { $0.id == track.id }) ?? 0
            player.playQueue(picks, startingAt: idx)
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
                            carouselCard(track: track, in: tracks)
                        }
                    }
                }
            }
        }
    }

    private func carouselCard(track: Track, in tracks: [Track]) -> some View {
        Button(action: {
            let idx = tracks.firstIndex(where: { $0.id == track.id }) ?? 0
            player.playQueue(tracks, startingAt: idx)
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

    // Tier 1: Quick Picks & Seed-Sampled Personalized Recommendations
    @Published var quickPicks: [Track] = []
    @Published var personalizedTracks: [Track] = []
    @Published var personalizedTitle: String = "Made for You"
    @Published var personalizedSubtitle: String? = nil

    // Tier 2: Authenticated Following Stream & Favorite Artist Spotlight
    @Published var followingTracks: [Track] = []
    @Published var artistSpotlightTracks: [Track] = []
    @Published var artistSpotlightTitle: String = ""
    @Published var artistSpotlightSubtitle: String? = nil

    // Tier 3: Anti-repetition Global Trending & Dynamic Genres
    @Published var trendingTracks: [Track] = []
    @Published var genre1Title: String = "Chill & R&B"
    @Published var genre1Tracks: [Track] = []
    @Published var genre2Title: String = "Remix & Dance"
    @Published var genre2Tracks: [Track] = []

    // Backward compatibility aliases
    var chillTracks: [Track] {
        get { genre1Tracks }
        set { genre1Tracks = newValue }
    }
    var remixTracks: [Track] {
        get { genre2Tracks }
        set { genre2Tracks = newValue }
    }

    @Published var isLoading: Bool = false
    @Published var isRefreshing: Bool = false
    @Published var error: String?

    private var hasLoaded: Bool = false
    private var isInFlight: Bool = false
    private var loadTask: Task<Void, Never>?
    private var loadGeneration: Int = 0
    private let cacheKey = "scandium_discover_cached_payload_v2"
    private let legacyCacheKey = "scandium_discover_cached_payload_v1"

    struct GenreCategory {
        let nameVI: String
        let nameEN: String
        let query: String
    }

    private static let genrePool: [GenreCategory] = [
        GenreCategory(nameVI: "Electronic & EDM", nameEN: "Electronic & Dance", query: "Electronic Dance EDM"),
        GenreCategory(nameVI: "Hip-Hop & Rap", nameEN: "Hip-Hop & Rap", query: "Hip-Hop Rap Trending"),
        GenreCategory(nameVI: "Chill & R&B", nameEN: "Chill & R&B", query: "Chill R&B Soul"),
        GenreCategory(nameVI: "Indie Khám Phá", nameEN: "Indie Discoveries", query: "Indie Alternative Pop"),
        GenreCategory(nameVI: "Lo-Fi Học Tập & Thư Giãn", nameEN: "Lo-Fi Beats & Chill", query: "Lo-Fi Beats Chill Study"),
        GenreCategory(nameVI: "Pop Thịnh Hành", nameEN: "Pop Hits", query: "Pop Hits Worldwide"),
        GenreCategory(nameVI: "Rock & Alternative", nameEN: "Rock & Alternative", query: "Rock Alternative Hits"),
        GenreCategory(nameVI: "Deep House & Club", nameEN: "Deep House & Club", query: "Deep House Club"),
        GenreCategory(nameVI: "Ambient Thư Giãn", nameEN: "Ambient & Relaxation", query: "Ambient Relaxing Meditation")
    ]

    private struct DiscoverCachePayload: Codable {
        let quickPicks: [Track]
        let personalizedTracks: [Track]
        let personalizedTitle: String
        let personalizedSubtitle: String?
        let trendingTracks: [Track]
        let chillTracks: [Track]
        let remixTracks: [Track]
        var followingTracks: [Track]?
        var artistSpotlightTracks: [Track]?
        var artistSpotlightTitle: String?
        var artistSpotlightSubtitle: String?
        var genre1Title: String?
        var genre2Title: String?
    }

    private init() {
        loadCachedFeed()
    }

    private func loadCachedFeed() {
        let ud = UserDefaults.standard
        let data = ud.data(forKey: cacheKey) ?? ud.data(forKey: legacyCacheKey)
        guard let data = data,
              let payload = try? JSONDecoder().decode(DiscoverCachePayload.self, from: data) else {
            return
        }
        self.quickPicks = payload.quickPicks
        self.personalizedTracks = payload.personalizedTracks
        self.personalizedTitle = payload.personalizedTitle
        self.personalizedSubtitle = payload.personalizedSubtitle
        self.trendingTracks = payload.trendingTracks
        self.genre1Tracks = payload.chillTracks
        self.genre2Tracks = payload.remixTracks
        self.genre1Title = payload.genre1Title ?? "Chill & R&B"
        self.genre2Title = payload.genre2Title ?? "Remix & Dance"
        self.followingTracks = payload.followingTracks ?? []
        self.artistSpotlightTracks = payload.artistSpotlightTracks ?? []
        self.artistSpotlightTitle = payload.artistSpotlightTitle ?? ""
        self.artistSpotlightSubtitle = payload.artistSpotlightSubtitle
        self.hasLoaded = true
    }

    private func saveCachedFeed() {
        let payload = DiscoverCachePayload(
            quickPicks: quickPicks,
            personalizedTracks: personalizedTracks,
            personalizedTitle: personalizedTitle,
            personalizedSubtitle: personalizedSubtitle,
            trendingTracks: trendingTracks,
            chillTracks: genre1Tracks,
            remixTracks: genre2Tracks,
            followingTracks: followingTracks,
            artistSpotlightTracks: artistSpotlightTracks,
            artistSpotlightTitle: artistSpotlightTitle,
            artistSpotlightSubtitle: artistSpotlightSubtitle,
            genre1Title: genre1Title,
            genre2Title: genre2Title
        )
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    @MainActor
    func refresh(api: SoundCloudAPI) async {
        loadTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        isInFlight = true
        isRefreshing = true

        let task = Task<Void, Never> { [weak self] in
            guard let self = self else { return }
            await self.loadData(api: api, force: true, generation: generation)
        }
        loadTask = task
        await task.value

        if loadGeneration == generation {
            isRefreshing = false
        }
    }

    @MainActor
    func loadInitialData(api: SoundCloudAPI, force: Bool = false) {
        if !force && (hasLoaded || isInFlight) {
            return
        }
        if force {
            loadTask?.cancel()
        } else if isInFlight {
            return
        }

        loadGeneration += 1
        let generation = loadGeneration
        isInFlight = true

        loadTask = Task<Void, Never> { [weak self] in
            guard let self = self else { return }
            await self.loadData(api: api, force: force, generation: generation)
        }
    }

    private func loadData(api: SoundCloudAPI, force: Bool, generation: Int) async {
        await MainActor.run {
            guard self.loadGeneration == generation else { return }
            if self.quickPicks.isEmpty && self.trendingTracks.isEmpty {
                self.isLoading = true
            }
            self.error = nil
        }

        let auth = SoundCloudAuthManager.shared
        let library = LibraryManager.shared

        // PHASE 1: Personalized Seed Sampling, Global Charts & Following Feed (max ~3-4 concurrent requests)
        async let seedTask = fetchRandomSeedRecommendations(api: api, auth: auth, library: library)
        async let trendingTask = fetchTrendingCharts(api: api)
        async let followingTask = fetchFollowingStreamTracks(api: api, auth: auth)

        let (seedResult, trendingResult, followingResult) = await (seedTask, trendingTask, followingTask)
        if Task.isCancelled { return }

        // PHASE 2: Favorite Artist Spotlight & 2 Dynamic Genre Carousels (max ~2-3 concurrent requests)
        let selectedGenres = Array(Self.genrePool.shuffled().prefix(2))
        async let artistTask = fetchFavoriteArtistSpotlight(api: api, auth: auth, library: library)
        async let genre1Task = fetchGenreSection(api: api, genre: selectedGenres[0])
        async let genre2Task = fetchGenreSection(api: api, genre: selectedGenres[1])

        let (artistResult, g1Result, g2Result) = await (artistTask, genre1Task, genre2Task)
        if Task.isCancelled { return }

        // Select Quick Picks:
        // Prioritize fresh random sample from personalized recommendations; cold start fallback to trending
        let qpCandidates: [Track]
        if !seedResult.tracks.isEmpty {
            qpCandidates = Array(seedResult.tracks.shuffled().prefix(5))
        } else if !trendingResult.isEmpty {
            qpCandidates = Array(trendingResult.shuffled().prefix(5))
        } else {
            qpCandidates = Array(g1Result.tracks.shuffled().prefix(5))
        }

        await MainActor.run {
            guard !Task.isCancelled, self.loadGeneration == generation else { return }

            self.quickPicks = self.deduplicateTracks(qpCandidates)
            self.followingTracks = followingResult

            if !seedResult.tracks.isEmpty {
                self.personalizedTracks = seedResult.tracks
                self.personalizedTitle = seedResult.title
                self.personalizedSubtitle = seedResult.subtitle
            } else if !g1Result.tracks.isEmpty {
                self.personalizedTracks = g1Result.tracks
                self.personalizedTitle = g1Result.title
                self.personalizedSubtitle = AppSettings.shared.language == .english ? "Curated discoveries for you" : "Tuyển tập khám phá dành riêng cho bạn"
            }

            self.artistSpotlightTracks = artistResult.tracks
            self.artistSpotlightTitle = artistResult.title
            self.artistSpotlightSubtitle = artistResult.subtitle

            if !trendingResult.isEmpty {
                self.trendingTracks = trendingResult
            }

            self.genre1Title = g1Result.title
            self.genre1Tracks = g1Result.tracks

            self.genre2Title = g2Result.title
            self.genre2Tracks = g2Result.tracks

            self.isLoading = false
            self.isInFlight = false
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

    // MARK: - Tier 1: Random Seed Sampling Engine

    private func fetchRandomSeedRecommendations(
        api: SoundCloudAPI,
        auth: SoundCloudAuthManager,
        library: LibraryManager
    ) async -> (title: String, subtitle: String?, tracks: [Track]) {
        let isEn = AppSettings.shared.language == .english
        var seeds: [Track] = []
        var seedIDs = Set<Int>()

        // 1. Pick up to 2 random tracks from recent 20 in recentlyPlayed
        let recentPool = Array(library.recentlyPlayed.prefix(20)).shuffled()
        for track in recentPool {
            if seedIDs.insert(track.id).inserted {
                seeds.append(track)
                if seeds.count >= 2 { break }
            }
        }

        // 2. Pick up to 2 random tracks from entire likedTracks (shuffled to surface older favorites)
        let likedPool = (library.likedTracks + (auth.isAuthenticated ? auth.userLikedTracks : [])).shuffled()
        var likedAdded = 0
        for track in likedPool {
            if seedIDs.insert(track.id).inserted {
                seeds.append(track)
                likedAdded += 1
                if likedAdded >= 2 { break }
            }
        }

        guard !seeds.isEmpty else {
            return (isEn ? "Discover Weekly" : "Khám phá âm nhạc", nil, [])
        }

        // Fetch related tracks in parallel with withTaskGroup (max 2-4 seeds)
        var fetchedTracks: [Track] = []
        await withTaskGroup(of: [Track].self) { group in
            for seed in seeds {
                group.addTask {
                    do {
                        return try await api.getRelatedTracks(trackID: seed.id, limit: 12)
                    } catch {
                        return []
                    }
                }
            }
            for await list in group {
                fetchedTracks.append(contentsOf: list)
            }
        }

        // Filter and reorder:
        // - Deduplicate by ID
        // - Defer songs in the last 15 of recentlyPlayed to the end
        // - Shuffle final candidates
        let recent15IDs = Set(library.recentlyPlayed.prefix(15).map(\.id))
        var seenIDs = Set<Int>()
        var freshTracks: [Track] = []
        var deferredTracks: [Track] = []

        for track in fetchedTracks {
            guard seenIDs.insert(track.id).inserted else { continue }
            if recent15IDs.contains(track.id) {
                deferredTracks.append(track)
            } else {
                freshTracks.append(track)
            }
        }

        var result = freshTracks.shuffled()
        result.append(contentsOf: deferredTracks)

        let title = isEn ? "Made for You" : "Dành riêng cho bạn"
        let subtitle: String?
        if seeds.count >= 2 {
            let names = seeds.prefix(2).map(\.title).joined(separator: ", ")
            subtitle = isEn ? "Based on '\(names)' & your favorites" : "Lấy cảm hứng từ '\(names)' & bài hát bạn thích"
        } else if let firstSeed = seeds.first {
            subtitle = isEn ? "Based on '\(firstSeed.title)'" : "Lấy cảm hứng từ '\(firstSeed.title)'"
        } else {
            subtitle = isEn ? "Based on your music taste" : "Dựa trên gu âm nhạc của bạn"
        }

        return (title, subtitle, result)
    }

    // MARK: - Tier 2: Real Following Feed & Favorite Artist Spotlight

    private func fetchFollowingStreamTracks(api: SoundCloudAPI, auth: SoundCloudAuthManager) async -> [Track] {
        guard auth.isAuthenticated, let token = auth.oauthToken, !token.isEmpty else {
            return []
        }
        do {
            let stream = try await api.getFollowingStream(oauthToken: token, limit: 20)
            return deduplicateTracks(stream)
        } catch {
            return []
        }
    }

    private func fetchFavoriteArtistSpotlight(
        api: SoundCloudAPI,
        auth: SoundCloudAuthManager,
        library: LibraryManager
    ) async -> (title: String, subtitle: String?, tracks: [Track]) {
        let isEn = AppSettings.shared.language == .english
        let allTracks = library.likedTracks + library.recentlyPlayed + (auth.isAuthenticated ? auth.userLikedTracks : [])
        var artistFrequency: [Int: (user: SoundCloudUser, count: Int)] = [:]

        for track in allTracks {
            guard let user = track.user, user.id > 0 else { continue }
            if let existing = artistFrequency[user.id] {
                artistFrequency[user.id] = (existing.user, existing.count + 1)
            } else {
                artistFrequency[user.id] = (user, 1)
            }
        }

        let sortedArtists = artistFrequency.values
            .sorted { $0.count > $1.count }
            .map(\.user)

        // Randomly pick from top 4 frequent artists for dynamic discovery across sessions
        guard let chosenArtist = sortedArtists.prefix(4).randomElement() else {
            return ("", nil, [])
        }

        do {
            let tracks = try await api.getUserTracks(userID: chosenArtist.id, limit: 12)
            let dedup = deduplicateTracks(tracks)
            let title = isEn ? "More from \(chosenArtist.username)" : "Thêm từ \(chosenArtist.username)"
            let subtitle = isEn ? "Because you listen to this artist" : "Vì bạn thường nghe nghệ sĩ này"
            return (title, subtitle, dedup)
        } catch {
            return ("", nil, [])
        }
    }

    // MARK: - Tier 3: Anti-Repetition Global Trending & Rotating Genres

    private func fetchTrendingCharts(api: SoundCloudAPI) async -> [Track] {
        let offsets = [0, 10, 20]
        let offset = offsets.randomElement() ?? 0
        do {
            let tracks = try await api.getCharts(
                genre: "soundcloud:genres:all-music",
                kind: "trending",
                limit: 30,
                offset: offset
            )
            let dedup = deduplicateTracks(tracks).shuffled()
            if !dedup.isEmpty {
                return dedup
            }
        } catch {
            // Fallback to rotating search queries below
        }

        let fallbackQueries = [
            "Global Top Hits",
            "Trending Worldwide",
            "Top 50 Hits",
            "Today Top Hits"
        ]
        let chosenQuery = fallbackQueries.randomElement() ?? "Global Top Hits"
        let fetched = await safeSearch(api: api, query: chosenQuery, limit: 15, offset: offset)
        return deduplicateTracks(fetched).shuffled()
    }

    private func fetchGenreSection(
        api: SoundCloudAPI,
        genre: GenreCategory
    ) async -> (title: String, tracks: [Track]) {
        let isEn = AppSettings.shared.language == .english
        let title = isEn ? genre.nameEN : genre.nameVI
        let offset = [0, 10, 20].randomElement() ?? 0
        let tracks = await safeSearch(api: api, query: genre.query, limit: 15, offset: offset)
        return (title, deduplicateTracks(tracks).shuffled())
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
