// SearchView.swift — Spotify-style clean track & artist search screen
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import SwiftUI

struct SearchView: View {
    @EnvironmentObject var api: SoundCloudAPI
    @EnvironmentObject var player: AudioPlayerEngine
    @EnvironmentObject var library: LibraryManager

    @State private var searchText: String = ""
    @State private var tracks: [Track] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var nextHref: String?
    @State private var isLoadingMore: Bool = false
    @State private var hasSearched: Bool = false
    @State private var selectedFilter: String = ""
    @State private var searchHistory: [String] = []

    @ObservedObject private var settings = AppSettings.shared

    struct SearchCategory: Identifiable {
        let id: String
        let title: String
        let query: String
        let icon: String
        let colors: [Color]
    }

    private var quickTags: [String] {
        if settings.language == .english {
            return [
                settings.loc("Tất cả", "All"),
                "Top Hits",
                "Pop",
                "Hip-Hop",
                "EDM & Dance",
                "Chill & Lo-Fi",
                "R&B",
                "Rock",
                "Acoustic",
                "Podcasts"
            ]
        } else {
            return [
                settings.loc("Tất cả", "All"),
                "Thịnh hành",
                "V-Pop",
                "Rap Việt",
                "Chill & Lo-Fi",
                "EDM Remix",
                "R&B",
                "Acoustic",
                "Nhạc Trẻ",
                "Podcast"
            ]
        }
    }

    private var trendingKeywords: [String] {
        if settings.language == .english {
            return [
                "Global Top 50",
                "Viral Hits",
                "The Weeknd",
                "Taylor Swift",
                "Synthwave",
                "Lo-Fi Beats",
                "Dua Lipa",
                "Billie Eilish",
                "Drake",
                "EDM Festival",
                "Workout Energy",
                "Acoustic Sunset"
            ]
        } else {
            return [
                "V-Pop Hot Hits",
                "Sơn Tùng M-TP",
                "Rap Việt",
                "Nhạc Trẻ Remix",
                "Chill Buổi Tối",
                "Vũ",
                "Đen Vâu",
                "Acoustic Buồn",
                "Lo-Fi Việt Nam",
                "Top TikTok Vietnam",
                "Cà Phê Sáng",
                "Indie Việt"
            ]
        }
    }

    private var browseCategories: [SearchCategory] {
        if settings.language == .english {
            return [
                SearchCategory(
                    id: "pop",
                    title: "Pop & Top Hits",
                    query: "Today Top Hits Pop",
                    icon: "music.mic",
                    colors: [Color(red: 0.90, green: 0.20, blue: 0.55), Color(red: 0.60, green: 0.10, blue: 0.75)]
                ),
                SearchCategory(
                    id: "hiphop",
                    title: "Hip-Hop & Rap",
                    query: "Hip Hop Rap Hits",
                    icon: "flame.fill",
                    colors: [Color(red: 0.95, green: 0.40, blue: 0.10), Color(red: 0.85, green: 0.15, blue: 0.20)]
                ),
                SearchCategory(
                    id: "electronic",
                    title: "Dance & EDM",
                    query: "EDM Festival Dance",
                    icon: "bolt.horizontal.fill",
                    colors: [Color(red: 0.05, green: 0.70, blue: 0.90), Color(red: 0.15, green: 0.30, blue: 0.85)]
                ),
                SearchCategory(
                    id: "chill",
                    title: "Chill & Lo-Fi",
                    query: "Lo-Fi Beats Study Chill",
                    icon: "cup.and.saucer.fill",
                    colors: [Color(red: 0.10, green: 0.65, blue: 0.55), Color(red: 0.20, green: 0.80, blue: 0.45)]
                ),
                SearchCategory(
                    id: "rock",
                    title: "Rock & Alternative",
                    query: "Rock Alternative Classic",
                    icon: "guitars.fill",
                    colors: [Color(red: 0.75, green: 0.15, blue: 0.20), Color(red: 0.30, green: 0.10, blue: 0.20)]
                ),
                SearchCategory(
                    id: "rnb",
                    title: "R&B & Soul",
                    query: "R&B Soul Chill",
                    icon: "heart.fill",
                    colors: [Color(red: 0.50, green: 0.15, blue: 0.80), Color(red: 0.70, green: 0.20, blue: 0.65)]
                ),
                SearchCategory(
                    id: "workout",
                    title: "Workout & Energy",
                    query: "Workout Gym Motivation Energy",
                    icon: "figure.run",
                    colors: [Color(red: 0.95, green: 0.50, blue: 0.10), Color(red: 0.90, green: 0.25, blue: 0.10)]
                ),
                SearchCategory(
                    id: "focus",
                    title: "Focus & Ambient",
                    query: "Deep Focus Ambient Piano",
                    icon: "brain.head.profile",
                    colors: [Color(red: 0.25, green: 0.40, blue: 0.80), Color(red: 0.20, green: 0.20, blue: 0.45)]
                ),
                SearchCategory(
                    id: "indie",
                    title: "Indie Discoveries",
                    query: "Indie Pop Folk Discover",
                    icon: "sparkles",
                    colors: [Color(red: 0.65, green: 0.20, blue: 0.70), Color(red: 0.85, green: 0.20, blue: 0.50)]
                ),
                SearchCategory(
                    id: "acoustic",
                    title: "Acoustic & Melodic",
                    query: "Acoustic Guitar Melodic",
                    icon: "waveform",
                    colors: [Color(red: 0.20, green: 0.60, blue: 0.35), Color(red: 0.10, green: 0.40, blue: 0.25)]
                )
            ]
        } else {
            return [
                SearchCategory(
                    id: "vpop",
                    title: "V-Pop Nổi Bật",
                    query: "V-Pop Hot Hits",
                    icon: "music.mic",
                    colors: [Color(red: 0.90, green: 0.20, blue: 0.55), Color(red: 0.60, green: 0.10, blue: 0.75)]
                ),
                SearchCategory(
                    id: "rapviet",
                    title: "Rap Việt Nam",
                    query: "Rap Việt",
                    icon: "flame.fill",
                    colors: [Color(red: 0.95, green: 0.40, blue: 0.10), Color(red: 0.85, green: 0.15, blue: 0.20)]
                ),
                SearchCategory(
                    id: "vinahouse",
                    title: "EDM & Remix",
                    query: "Nhạc Trẻ Remix EDM",
                    icon: "bolt.horizontal.fill",
                    colors: [Color(red: 0.05, green: 0.70, blue: 0.90), Color(red: 0.15, green: 0.30, blue: 0.85)]
                ),
                SearchCategory(
                    id: "chillvn",
                    title: "Chill & Lo-Fi",
                    query: "Lo-Fi Việt Nam Chill",
                    icon: "cup.and.saucer.fill",
                    colors: [Color(red: 0.10, green: 0.65, blue: 0.55), Color(red: 0.20, green: 0.80, blue: 0.45)]
                ),
                SearchCategory(
                    id: "ballad",
                    title: "Ballad Tình Cảm",
                    query: "Nhạc Trẻ Ballad Buồn",
                    icon: "heart.fill",
                    colors: [Color(red: 0.50, green: 0.15, blue: 0.80), Color(red: 0.70, green: 0.20, blue: 0.65)]
                ),
                SearchCategory(
                    id: "acousticvn",
                    title: "Acoustic Mộc Mạc",
                    query: "Acoustic Guitar Việt",
                    icon: "waveform",
                    colors: [Color(red: 0.20, green: 0.60, blue: 0.35), Color(red: 0.10, green: 0.40, blue: 0.25)]
                ),
                SearchCategory(
                    id: "indievn",
                    title: "Indie Việt",
                    query: "Indie Việt Nam",
                    icon: "sparkles",
                    colors: [Color(red: 0.65, green: 0.20, blue: 0.70), Color(red: 0.85, green: 0.20, blue: 0.50)]
                ),
                SearchCategory(
                    id: "taptrung",
                    title: "Tập Trung & Thư Giãn",
                    query: "Nhạc Tập Trung Làm Việc Học Bài",
                    icon: "brain.head.profile",
                    colors: [Color(red: 0.25, green: 0.40, blue: 0.80), Color(red: 0.20, green: 0.20, blue: 0.45)]
                ),
                SearchCategory(
                    id: "caphe",
                    title: "Quán Cà Phê",
                    query: "Cà Phê Sáng Chill Acoustic",
                    icon: "cup.and.saucer",
                    colors: [Color(red: 0.80, green: 0.45, blue: 0.25), Color(red: 0.55, green: 0.25, blue: 0.15)]
                ),
                SearchCategory(
                    id: "gymvn",
                    title: "Gym & Năng Lượng",
                    query: "Workout Bass Boosted Remix",
                    icon: "figure.run",
                    colors: [Color(red: 0.95, green: 0.50, blue: 0.10), Color(red: 0.90, green: 0.25, blue: 0.10)]
                )
            ]
        }
    }

    private static let searchHistoryKey = "scandium_search_history_v1"
    private static let maxSearchHistory = 12

    init() {}

    var body: some View {
        VStack(spacing: 0) {
            headerView
            searchBarView
            quickFilterTagsView
            contentView
        }
        .onAppear {
            loadSearchHistory()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text(settings.loc("Tìm kiếm", "Search"))
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(ScandiumTheme.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Search Bar

    private var searchBarView: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(ScandiumTheme.subtext)

            ZStack(alignment: .leading) {
                if searchText.isEmpty {
                    Text(settings.loc("Tìm bài hát, nghệ sĩ...", "Search songs, artists..."))
                        .font(.system(size: 15))
                        .foregroundColor(ScandiumTheme.subtext.opacity(0.6))
                }
                TextField("", text: $searchText)
                    .foregroundColor(ScandiumTheme.textPrimary)
                    .font(.system(size: 15))
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .submitLabel(.search)
                    .onSubmit {
                        performSearch()
                    }
            }

            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                    tracks = []
                    hasSearched = false
                    errorMessage = nil
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(ScandiumTheme.subtext)
                }
            }

            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: ScandiumTheme.textPrimary))
                    .scaleEffect(0.7)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(ScandiumTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: ScandiumTheme.cornerRadiusMedium, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    // MARK: - Quick Filter Tags

    private var quickFilterTagsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                let tags = quickTags
                let defaultTag = tags.first ?? "All"
                let currentSelection = selectedFilter.isEmpty ? defaultTag : selectedFilter

                ForEach(tags, id: \.self) { tag in
                    Button(action: {
                        selectedFilter = tag
                        if tag != defaultTag {
                            triggerSearchKeyword(tag)
                        } else {
                            searchText = ""
                            tracks = []
                            hasSearched = false
                            errorMessage = nil
                        }
                    }) {
                        Text(tag)
                            .font(.system(size: 12, weight: currentSelection == tag ? .bold : .medium))
                            .foregroundColor(currentSelection == tag ? (ScandiumTheme.isDark ? .black : .white) : ScandiumTheme.textPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(currentSelection == tag ? ScandiumTheme.textPrimary : ScandiumTheme.surfaceElevated)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Content

    private var contentView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 4) {
                if !hasSearched && tracks.isEmpty {
                    emptyStateView
                } else if let error = errorMessage {
                    errorView(error)
                } else if tracks.isEmpty && hasSearched && !isLoading {
                    noResultsView
                } else {
                    trackListView
                }
            }
            .padding(.bottom, 130)
        }
    }

    // MARK: - Track List

    @ViewBuilder
    private var trackListView: some View {
        ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
            GlassTrackRow(
                track: track,
                isCurrentlyPlaying: player.currentTrack?.id == track.id,
                showLikeButton: true,
                onTap: {
                    player.playQueue(tracks, startingAt: index)
                }
            )

            if index == tracks.count - 3 && nextHref != nil && !isLoadingMore {
                Color.clear
                    .frame(height: 1)
                    .onAppear {
                        loadMoreResults()
                    }
            }
        }

        if isLoadingMore {
            HStack {
                Spacer()
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: ScandiumTheme.textPrimary))
                    .padding(.vertical, 16)
                Spacer()
            }
        }
    }

    // MARK: - Empty State (Search Recommendations, Browse Categories & History)

    private var emptyStateView: some View {
        VStack(spacing: 22) {
            if !searchHistory.isEmpty {
                recentSearchesSection
            }

            trendingSearchesSection

            browseCategoriesSection
        }
        .padding(.top, 4)
    }

    private var recentSearchesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(settings.loc("Tìm kiếm gần đây", "Recent Searches"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(ScandiumTheme.textPrimary)
                Spacer()
                Button(action: clearSearchHistory) {
                    Text(settings.loc("Xóa tất cả", "Clear All"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(ScandiumTheme.subtext)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)

            VStack(spacing: 0) {
                ForEach(searchHistory, id: \.self) { item in
                    HStack(spacing: 12) {
                        Button(action: {
                            triggerSearchKeyword(item)
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 14))
                                    .foregroundColor(ScandiumTheme.subtext)

                                Text(item)
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundColor(ScandiumTheme.textPrimary)
                                    .lineLimit(1)

                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())

                        Button(action: {
                            removeSearchHistoryItem(item)
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(ScandiumTheme.subtext.opacity(0.8))
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    HairlineDivider(leadingPadding: 42)
                }
            }
            .background(ScandiumTheme.surfaceDark)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
        }
    }

    private var trendingSearchesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Color.orange)

                Text(settings.loc("Đề xuất thịnh hành", "Trending Searches"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(ScandiumTheme.textPrimary)

                Spacer()
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(trendingKeywords, id: \.self) { keyword in
                        Button(action: {
                            triggerSearchKeyword(keyword)
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 11))
                                    .foregroundColor(ScandiumTheme.subtext)

                                Text(keyword)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(ScandiumTheme.textPrimary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(ScandiumTheme.surfaceElevated)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var browseCategoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 14))
                    .foregroundColor(settings.accentColor.color)

                Text(settings.loc("Khám phá thể loại", "Browse Categories"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(ScandiumTheme.textPrimary)

                Spacer()
            }
            .padding(.horizontal, 16)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                ForEach(browseCategories) { cat in
                    Button(action: {
                        triggerSearchKeyword(cat.query)
                    }) {
                        ZStack(alignment: .bottomTrailing) {
                            LinearGradient(
                                colors: cat.colors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )

                            Image(systemName: cat.icon)
                                .font(.system(size: 42, weight: .bold))
                                .foregroundColor(Color.white.opacity(0.22))
                                .rotationEffect(.degrees(12))
                                .offset(x: 10, y: 10)

                            VStack(alignment: .leading) {
                                Text(cat.title)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                                    .shadow(color: Color.black.opacity(0.35), radius: 2, x: 0, y: 1)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(12)
                        }
                        .frame(height: 78)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func triggerSearchKeyword(_ keyword: String) {
        searchText = keyword
        selectedFilter = ""
        performSearch()
    }

    // MARK: - No Results

    private var noResultsView: some View {
        VStack(spacing: 12) {
            Spacer().frame(height: 50)

            Image(systemName: "music.note.list")
                .font(.system(size: 38, weight: .light))
                .foregroundColor(ScandiumTheme.subtext.opacity(0.4))

            Text(settings.loc("Không tìm thấy kết quả", "No results found"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(ScandiumTheme.textPrimary)

            Text(settings.loc("Hãy thử tìm kiếm với tên bài hát hoặc ca sĩ khác.", "Try searching for a different song or artist."))
                .font(.system(size: 13))
                .foregroundColor(ScandiumTheme.subtext)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer().frame(height: 30)

            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34, weight: .light))
                .foregroundColor(Color.orange)

            Text(settings.loc("Không thể tải kết quả", "Unable to load results"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(ScandiumTheme.textPrimary)

            Text(message)
                .font(.system(size: 13))
                .foregroundColor(ScandiumTheme.subtext)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button(action: performSearch) {
                Text(settings.loc("Thử lại", "Retry"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ScandiumTheme.textPrimary)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 8)
                    .background(ScandiumTheme.surfaceElevated)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Search Actions

    private func performSearch() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        saveSearchHistoryItem(trimmed)

        isLoading = true
        errorMessage = nil
        hasSearched = true

        Task {
            do {
                let response = try await api.searchTracks(query: trimmed)
                await MainActor.run {
                    self.tracks = deduplicateTracks(response.collection)
                    self.nextHref = response.nextHref
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    private func loadMoreResults() {
        guard let href = nextHref, !isLoadingMore else { return }
        isLoadingMore = true

        Task {
            do {
                let response = try await api.searchTracksNextPage(nextHref: href)
                await MainActor.run {
                    self.tracks = deduplicateTracks(self.tracks + response.collection)
                    self.nextHref = response.nextHref
                    self.isLoadingMore = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingMore = false
                }
            }
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

    private func loadSearchHistory() {
        if let items = UserDefaults.standard.array(forKey: Self.searchHistoryKey) as? [String] {
            searchHistory = items
        }
    }

    private func clearSearchHistory() {
        searchHistory = []
        UserDefaults.standard.removeObject(forKey: Self.searchHistoryKey)
    }

    private func removeSearchHistoryItem(_ keyword: String) {
        searchHistory.removeAll { $0.caseInsensitiveCompare(keyword) == .orderedSame }
        UserDefaults.standard.set(searchHistory, forKey: Self.searchHistoryKey)
    }

    private func saveSearchHistoryItem(_ keyword: String) {
        let normalized = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        var history = searchHistory.filter { $0.caseInsensitiveCompare(normalized) != .orderedSame }
        history.insert(normalized, at: 0)
        if history.count > Self.maxSearchHistory {
            history = Array(history.prefix(Self.maxSearchHistory))
        }
        searchHistory = history
        UserDefaults.standard.set(history, forKey: Self.searchHistoryKey)
    }
}
