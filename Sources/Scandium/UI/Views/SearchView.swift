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
    @State private var selectedFilter: String = "Tất cả"
    @State private var searchHistory: [String] = []

    private let quickTags = ["Tất cả", "V-Pop", "Chill & Lo-Fi", "EDM Remix", "R&B", "Acoustic", "Podcast"]
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
            Text("Tìm kiếm")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.white)
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
                    Text("Tìm bài hát, nghệ sĩ...")
                        .font(.system(size: 15))
                        .foregroundColor(ScandiumTheme.subtext.opacity(0.6))
                }
                TextField("", text: $searchText)
                    .foregroundColor(.white)
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
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
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
                ForEach(quickTags, id: \.self) { tag in
                    Button(action: {
                        selectedFilter = tag
                        if tag != "Tất cả" {
                            searchText = tag
                            performSearch()
                        }
                    }) {
                        Text(tag)
                            .font(.system(size: 12, weight: selectedFilter == tag ? .bold : .medium))
                            .foregroundColor(selectedFilter == tag ? .black : .white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(selectedFilter == tag ? Color.white : ScandiumTheme.surfaceElevated)
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
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .padding(.vertical, 16)
                Spacer()
            }
        }
    }

    // MARK: - Empty State (Search History & Prompt)

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            if !searchHistory.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Tìm kiếm gần đây")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                        Spacer()
                        Button(action: clearSearchHistory) {
                            Text("Xóa tất cả")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(ScandiumTheme.subtext)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    VStack(spacing: 0) {
                        ForEach(searchHistory, id: \.self) { item in
                            HStack(spacing: 12) {
                                Button(action: {
                                    searchText = item
                                    performSearch()
                                }) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "clock.arrow.circlepath")
                                            .font(.system(size: 14))
                                            .foregroundColor(ScandiumTheme.subtext)

                                        Text(item)
                                            .font(.system(size: 15, weight: .regular))
                                            .foregroundColor(.white)
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
            } else {
                VStack(spacing: 14) {
                    Spacer().frame(height: 40)

                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 42, weight: .light))
                        .foregroundColor(ScandiumTheme.subtext.opacity(0.4))

                    Text("Tìm bài hát yêu thích")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)

                    Text("Nhập từ khóa hoặc chọn một thể loại ở trên để bắt đầu nghe nhạc.")
                        .font(.system(size: 13))
                        .foregroundColor(ScandiumTheme.subtext)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)

                    Spacer().frame(height: 40)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
        }
    }

    // MARK: - No Results

    private var noResultsView: some View {
        VStack(spacing: 12) {
            Spacer().frame(height: 50)

            Image(systemName: "music.note.list")
                .font(.system(size: 38, weight: .light))
                .foregroundColor(ScandiumTheme.subtext.opacity(0.4))

            Text("Không tìm thấy kết quả")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)

            Text("Hãy thử tìm kiếm với tên bài hát hoặc ca sĩ khác.")
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

            Text("Không thể tải kết quả")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)

            Text(message)
                .font(.system(size: 13))
                .foregroundColor(ScandiumTheme.subtext)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button(action: performSearch) {
                Text("Thử lại")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
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
