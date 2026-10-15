// LibraryView.swift — Spotify-style user library (Liked tracks, Playlists, Albums, Following & Recently played)
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import SwiftUI

enum LibraryTab: Int, CaseIterable, Identifiable {
    case liked = 0
    case playlists = 1
    case albums = 2
    case following = 3
    case recent = 4

    var id: Int { rawValue }

    func title(settings: AppSettings, library: LibraryManager, auth: SoundCloudAuthManager) -> String {
        switch self {
        case .liked:
            let count = library.likedTracks.count
            return "\(settings.loc("Đã thích", "Liked")) (\(count))"
        case .playlists:
            let count = auth.userPlaylists.count
            return "\(settings.loc("Danh sách phát", "Playlists")) (\(count))"
        case .albums:
            let count = auth.userAlbums.count
            return "\(settings.loc("Album", "Albums")) (\(count))"
        case .following:
            let count = auth.userFollowings.count
            return "\(settings.loc("Đang theo dõi", "Following")) (\(count))"
        case .recent:
            let count = library.recentlyPlayed.count
            return "\(settings.loc("Gần đây", "Recent")) (\(count))"
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject var library: LibraryManager
    @EnvironmentObject var player: AudioPlayerEngine
    @EnvironmentObject var api: SoundCloudAPI
    @ObservedObject private var auth = SoundCloudAuthManager.shared
    @ObservedObject private var settings = AppSettings.shared

    @State private var selectedTab: LibraryTab = .liked
    @State private var selectedPlaylist: SoundCloudPlaylist?

    init() {}

    var body: some View {
        VStack(spacing: 0) {
            headerView

            horizontalTabsBar
                .padding(.vertical, 10)

            contentView
        }
        .background(ScandiumTheme.bgPrimary.ignoresSafeArea())
        .sheet(item: $selectedPlaylist) { playlist in
            PlaylistDetailSheet(playlist: playlist)
                .environmentObject(player)
                .environmentObject(api)
                .environmentObject(library)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text(settings.loc("Thư viện", "Library"))
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(ScandiumTheme.textPrimary)

            Spacer()

            if auth.isAuthenticated {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 13))
                        .foregroundColor(ScandiumTheme.spotifyGreen)
                    Text(auth.currentUser?.username ?? settings.loc("Đã kết nối", "Connected"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(ScandiumTheme.subtext)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Horizontal Filter Tabs Bar

    private var horizontalTabsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LibraryTab.allCases) { tab in
                    Button(action: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            selectedTab = tab
                        }
                    }) {
                        Text(tab.title(settings: settings, library: library, auth: auth))
                            .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .medium))
                            .foregroundColor(selectedTab == tab ? (ScandiumTheme.isDark ? .black : .white) : ScandiumTheme.textPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(selectedTab == tab ? ScandiumTheme.textPrimary : ScandiumTheme.surfaceElevated)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Content

    private var contentView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                switch selectedTab {
                case .liked:
                    likedTracksSection
                case .playlists:
                    playlistsSection
                case .albums:
                    albumsSection
                case .following:
                    followingsSection
                case .recent:
                    recentlyPlayedSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 130)
        }
        .refreshable {
            if auth.isAuthenticated {
                await auth.syncLibrary()
            }
        }
    }

    // MARK: - Liked Tracks Section

    @ViewBuilder
    private var likedTracksSection: some View {
        if library.likedTracks.isEmpty {
            emptyStateView(
                icon: "heart.slash",
                title: settings.loc("Chưa có bài hát yêu thích", "No liked songs yet"),
                message: settings.loc("Nhấn nút hình trái tim trên bài hát bất kỳ để lưu vào thư viện.", "Tap the heart icon on any song to save it to your library.")
            )
        } else {
            HStack(spacing: 12) {
                Button(action: {
                    player.playQueue(library.likedTracks, startingAt: 0)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13))
                        Text(settings.loc("Phát tất cả", "Play All"))
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(ScandiumTheme.spotifyGreen)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: {
                    let shuffled = library.likedTracks.shuffled()
                    player.playQueue(shuffled, startingAt: 0)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "shuffle")
                            .font(.system(size: 13, weight: .bold))
                        Text(settings.loc("Trộn bài", "Shuffle"))
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(ScandiumTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(ScandiumTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.bottom, 6)

            LazyVStack(spacing: 4) {
                ForEach(library.likedTracks) { track in
                    GlassTrackRow(
                        track: track,
                        isCurrentlyPlaying: player.currentTrack?.id == track.id,
                        onTap: {
                            player.play(track: track)
                        }
                    )
                }
            }
        }
    }

    // MARK: - Playlists Section

    @ViewBuilder
    private var playlistsSection: some View {
        if !auth.isAuthenticated {
            emptyStateView(
                icon: "music.note.list",
                title: settings.loc("Chưa đăng nhập SoundCloud", "SoundCloud Not Logged In"),
                message: settings.loc("Đăng nhập SoundCloud trong mục Cá nhân để tải playlist của bạn.", "Sign in with SoundCloud in Profile to load your playlists.")
            )
        } else if auth.userPlaylists.isEmpty {
            emptyStateView(
                icon: "music.note.list",
                title: settings.loc("Không tìm thấy playlist", "No playlists found"),
                message: settings.loc("Kéo xuống để tải lại hoặc tạo playlist mới trên SoundCloud.", "Pull down to reload or create new playlists on SoundCloud.")
            )
        } else {
            LazyVStack(spacing: 8) {
                ForEach(auth.userPlaylists) { pl in
                    playlistRow(playlist: pl)
                }
            }
        }
    }

    // MARK: - Albums Section

    @ViewBuilder
    private var albumsSection: some View {
        if !auth.isAuthenticated {
            emptyStateView(
                icon: "opticaldisc",
                title: settings.loc("Chưa đăng nhập SoundCloud", "SoundCloud Not Logged In"),
                message: settings.loc("Đăng nhập SoundCloud để duyệt album và EP của bạn.", "Sign in with SoundCloud to browse your albums and EPs.")
            )
        } else if auth.userAlbums.isEmpty {
            emptyStateView(
                icon: "opticaldisc",
                title: settings.loc("Không có album nào", "No albums found"),
                message: settings.loc("Các album hoặc playlist có nhiều hơn 5 bài hát sẽ hiển thị tại đây.", "Albums or playlists with 5+ tracks will appear here.")
            )
        } else {
            LazyVStack(spacing: 8) {
                ForEach(auth.userAlbums) { pl in
                    playlistRow(playlist: pl)
                }
            }
        }
    }

    private func playlistRow(playlist: SoundCloudPlaylist) -> some View {
        Button(action: {
            selectedPlaylist = playlist
        }) {
            HStack(spacing: 12) {
                CachedAsyncImage(
                    url: playlist.highResArtworkURL,
                    width: 54,
                    height: 54,
                    cornerRadius: 8
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(playlist.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(ScandiumTheme.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(playlist.user?.username ?? "SoundCloud")
                            .font(.system(size: 12))
                            .foregroundColor(ScandiumTheme.subtext)

                        Text("•")
                            .font(.system(size: 12))
                            .foregroundColor(ScandiumTheme.subtext)

                        Text("\(playlist.trackCount ?? 0) \(settings.loc("bài hát", "tracks"))")
                            .font(.system(size: 12))
                            .foregroundColor(ScandiumTheme.subtext)
                    }
                    .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ScandiumTheme.subtext)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(ScandiumTheme.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: ScandiumTheme.cornerRadiusMedium, style: .continuous))
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Followings Section

    @ViewBuilder
    private var followingsSection: some View {
        if !auth.isAuthenticated {
            emptyStateView(
                icon: "person.crop.circle.badge.plus",
                title: settings.loc("Chưa đăng nhập SoundCloud", "SoundCloud Not Logged In"),
                message: settings.loc("Đăng nhập để xem danh sách nghệ sĩ bạn đang theo dõi.", "Sign in to see artists you are following.")
            )
        } else if auth.userFollowings.isEmpty {
            emptyStateView(
                icon: "person.2",
                title: settings.loc("Chưa theo dõi nghệ sĩ nào", "No followed artists"),
                message: settings.loc("Kéo xuống để đồng bộ các nghệ sĩ bạn theo dõi trên SoundCloud.", "Pull down to sync artists you follow on SoundCloud.")
            )
        } else {
            LazyVStack(spacing: 8) {
                ForEach(auth.userFollowings) { user in
                    HStack(spacing: 12) {
                        CachedAsyncImage(
                            url: URL(string: user.avatarURL ?? ""),
                            width: 50,
                            height: 50,
                            cornerRadius: 25
                        )

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 4) {
                                Text(user.username)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(ScandiumTheme.textPrimary)
                                    .lineLimit(1)

                                if user.verified == true {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(ScandiumTheme.spotifyGreen)
                                }
                            }

                            if let followers = user.followersCount {
                                Text("\(followers) \(settings.loc("người theo dõi", "followers"))")
                                    .font(.system(size: 12))
                                    .foregroundColor(ScandiumTheme.subtext)
                            }
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(ScandiumTheme.surfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: ScandiumTheme.cornerRadiusMedium, style: .continuous))
                }
            }
        }
    }

    // MARK: - Recently Played Section

    @ViewBuilder
    private var recentlyPlayedSection: some View {
        if library.recentlyPlayed.isEmpty {
            emptyStateView(
                icon: "clock.arrow.circlepath",
                title: settings.loc("Chưa có lịch sử nghe nhạc", "No listening history yet"),
                message: settings.loc("Các bài hát bạn phát sẽ tự động xuất hiện ở đây.", "Tracks you play will automatically appear here.")
            )
        } else {
            HStack {
                Text(settings.loc("\(library.recentlyPlayed.count) bài đã nghe gần đây", "\(library.recentlyPlayed.count) recently played tracks"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(ScandiumTheme.subtext)
                Spacer()
                Button(settings.loc("Xóa lịch sử", "Clear History")) {
                    library.clearRecentlyPlayed()
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(ScandiumTheme.subtext)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)

            LazyVStack(spacing: 4) {
                ForEach(library.recentlyPlayed) { track in
                    GlassTrackRow(
                        track: track,
                        isCurrentlyPlaying: player.currentTrack?.id == track.id,
                        onTap: {
                            player.play(track: track)
                        }
                    )
                }
            }
        }
    }

    // MARK: - Empty State View

    private func emptyStateView(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 38, weight: .light))
                .foregroundColor(ScandiumTheme.subtext.opacity(0.5))
                .padding(.top, 40)

            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(ScandiumTheme.textPrimary)

            Text(message)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(ScandiumTheme.subtext)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
}

// MARK: - Playlist Detail Sheet

struct PlaylistDetailSheet: View {
    let playlist: SoundCloudPlaylist
    @EnvironmentObject var player: AudioPlayerEngine
    @EnvironmentObject var api: SoundCloudAPI
    @EnvironmentObject var library: LibraryManager
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.presentationMode) var presentationMode

    @State private var detailedPlaylist: SoundCloudPlaylist?
    @State private var isLoading: Bool = true

    init(playlist: SoundCloudPlaylist) {
        self.playlist = playlist
    }

    private var displayTracks: [Track] {
        detailedPlaylist?.tracks ?? playlist.tracks ?? []
    }

    var body: some View {
        NavigationView {
            ZStack {
                ScandiumTheme.bgPrimary.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        // Artwork & Metadata
                        HStack(spacing: 16) {
                            CachedAsyncImage(
                                url: playlist.highResArtworkURL,
                                width: 110,
                                height: 110,
                                cornerRadius: 10
                            )

                            VStack(alignment: .leading, spacing: 6) {
                                Text(playlist.title)
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(ScandiumTheme.textPrimary)
                                    .lineLimit(2)

                                Text(playlist.user?.username ?? "SoundCloud")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(ScandiumTheme.subtext)

                                Text("\(displayTracks.count) \(settings.loc("bài hát", "tracks"))")
                                    .font(.system(size: 13))
                                    .foregroundColor(ScandiumTheme.subtext)
                            }
                        }
                        .padding(.top, 10)

                        // Action buttons
                        if !displayTracks.isEmpty {
                            HStack(spacing: 12) {
                                Button(action: {
                                    player.playQueue(displayTracks, startingAt: 0)
                                    presentationMode.wrappedValue.dismiss()
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 14))
                                        Text(settings.loc("Phát tất cả", "Play All"))
                                            .font(.system(size: 14, weight: .semibold))
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 40)
                                    .background(ScandiumTheme.spotifyGreen)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                                .buttonStyle(PlainButtonStyle())

                                Button(action: {
                                    let shuffled = displayTracks.shuffled()
                                    player.playQueue(shuffled, startingAt: 0)
                                    presentationMode.wrappedValue.dismiss()
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "shuffle")
                                            .font(.system(size: 14, weight: .bold))
                                        Text(settings.loc("Trộn bài", "Shuffle"))
                                            .font(.system(size: 14, weight: .semibold))
                                    }
                                    .foregroundColor(ScandiumTheme.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 40)
                                    .background(ScandiumTheme.surfaceElevated)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }

                        if isLoading && displayTracks.isEmpty {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: ScandiumTheme.spotifyGreen))
                                .frame(maxWidth: .infinity)
                                .padding(.top, 30)
                        } else {
                            LazyVStack(spacing: 4) {
                                ForEach(displayTracks) { track in
                                    GlassTrackRow(
                                        track: track,
                                        isCurrentlyPlaying: player.currentTrack?.id == track.id,
                                        onTap: {
                                            player.playQueue(displayTracks, startingAt: displayTracks.firstIndex(of: track) ?? 0)
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(playlist.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(settings.loc("Đóng", "Close")) {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(ScandiumTheme.spotifyGreen)
                }
            }
        }
        .onAppear {
            loadTracks()
        }
    }

    private func loadTracks() {
        if playlist.tracks != nil && !(playlist.tracks?.isEmpty ?? true) {
            isLoading = false
            return
        }

        Task {
            do {
                let full = try await api.getPlaylist(id: playlist.id, oauthToken: SoundCloudAuthManager.shared.oauthToken)
                await MainActor.run {
                    self.detailedPlaylist = full
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
}
