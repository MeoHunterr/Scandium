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
            Text("Chưa tải được dữ liệu")
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

                // Horizontal Carousel: Thịnh hành (Trending)
                carouselSection(
                    title: "Thịnh hành hôm nay",
                    tracks: store.trendingTracks
                )

                // Horizontal Carousel: Chill & R&B
                carouselSection(
                    title: "Chill & R&B",
                    tracks: store.chillTracks
                )

                // Horizontal Carousel: Remix & EDM
                carouselSection(
                    title: "Remix sôi động",
                    tracks: store.remixTracks
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 130) // Ensure content is never hidden behind floating player & tab bar
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
                    .foregroundColor(.white)
            }

            Spacer()

            HStack(spacing: 12) {
                // Search Shortcut
                Button(action: onNavigateToSearch) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.white)
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
                            .foregroundColor(.white.opacity(0.85))
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

                Text("Bài hát đã thích")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
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
                    .foregroundColor(player.currentTrack?.id == track.id ? ScandiumTheme.spotifyGreen : .white)
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

    private func carouselSection(title: String, tracks: [Track]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)

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
                    .foregroundColor(player.currentTrack?.id == track.id ? ScandiumTheme.spotifyGreen : .white)
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
            Text("Chưa có dữ liệu")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(ScandiumTheme.subtext)
                .lineLimit(1)
            Text("Kéo xuống hoặc bấm thử lại")
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
                Text("Thử tải lại")
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
    @Published var trendingTracks: [Track] = []
    @Published var chillTracks: [Track] = []
    @Published var remixTracks: [Track] = []
    @Published var isLoading: Bool = false
    @Published var error: String?

    private var hasLoaded: Bool = false

    private init() {}

    func loadInitialData(api: SoundCloudAPI, force: Bool = false) {
        if hasLoaded && !force && (!quickPicks.isEmpty || !trendingTracks.isEmpty) {
            return
        }
        if isLoading && !force {
            return
        }

        isLoading = true
        error = nil

        Task {
            async let qp = safeSearch(api: api, query: "EDM Hits", limit: 6)
            async let tr = safeSearch(api: api, query: "Top Vietnam", limit: 10)
            async let ch = safeSearch(api: api, query: "Chill R&B", limit: 10)
            async let rm = safeSearch(api: api, query: "Remix Lo-Fi", limit: 10)

            let (qpTracks, trTracks, chTracks, rmTracks) = await (qp, tr, ch, rm)

            await MainActor.run {
                if !qpTracks.isEmpty { self.quickPicks = self.deduplicateTracks(qpTracks) }
                if !trTracks.isEmpty { self.trendingTracks = self.deduplicateTracks(trTracks) }
                if !chTracks.isEmpty { self.chillTracks = self.deduplicateTracks(chTracks) }
                if !rmTracks.isEmpty { self.remixTracks = self.deduplicateTracks(rmTracks) }
                self.isLoading = false
                self.hasLoaded = true

                if self.quickPicks.isEmpty && self.trendingTracks.isEmpty && self.chillTracks.isEmpty && self.remixTracks.isEmpty {
                    self.error = "Không tải được dữ liệu SoundCloud. Hãy thử lại hoặc vào Cấu hình Client ID."
                }
            }
        }
    }

    private func safeSearch(api: SoundCloudAPI, query: String, limit: Int) async -> [Track] {
        do {
            let response = try await api.searchTracks(query: query, limit: limit)
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
                                Text("Trạng thái SoundCloud Client ID")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
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
                                Text("ID hiện hành:")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(ScandiumTheme.subtext)
                                Text(current)
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundColor(.white)
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
                                        statusToast = "Cào mới thành công!"
                                    }
                                } catch {
                                    await MainActor.run {
                                        isRefreshing = false
                                        statusToast = "Lỗi: \(error.localizedDescription)"
                                    }
                                }
                            }
                        }) {
                            HStack {
                                if isRefreshing {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                Text("Tự động cào lại Client ID")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(ScandiumTheme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(PlainButtonStyle())

                        HairlineDivider()

                        // Manual Entry
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Nhập Client ID thủ công")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)

                            TextField("Dán chuỗi 32 ký tự...", text: $inputID)
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(12)
                                .background(ScandiumTheme.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            HStack(spacing: 10) {
                                Button(action: {
                                    scraper.setManualClientID(inputID)
                                    presentationMode.wrappedValue.dismiss()
                                }) {
                                    Text("Lưu Client ID")
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
                                        Text("Khôi phục")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.white)
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
                                Text("Xem hướng dẫn lấy Client ID trên máy tính")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(ScandiumTheme.subtext)
                        }
                        .padding(.top, 4)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Cấu hình SoundCloud")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(.white)
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
        .preferredColorScheme(.dark)
    }
}
