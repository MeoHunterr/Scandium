// LibraryView.swift — Spotify-style user library (Liked tracks & Recently played)
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var library: LibraryManager
    @EnvironmentObject var player: AudioPlayerEngine
    @ObservedObject private var auth = SoundCloudAuthManager.shared

    @State private var selectedTab: Int = 0 // 0: Liked, 1: Recently Played, 2: SoundCloud

    init() {}

    var body: some View {
        VStack(spacing: 0) {
            headerView

            segmentedPickerView
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)

            contentView
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text("Thư viện")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.white)

            Spacer()

            if auth.isAuthenticated {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 13))
                        .foregroundColor(ScandiumTheme.spotifyGreen)
                    Text(auth.currentUser?.username ?? "Đã kết nối")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(ScandiumTheme.subtext)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Segmented Picker

    private var segmentedPickerView: some View {
        HStack(spacing: 8) {
            segmentButton(title: "Đã thích (\(library.likedTracks.count))", index: 0)
            segmentButton(title: "Gần đây (\(library.recentlyPlayed.count))", index: 1)
            if auth.isAuthenticated {
                segmentButton(title: "SoundCloud (\(auth.userLikedTracks.count))", index: 2)
            }
        }
        .padding(3)
        .background(ScandiumTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: ScandiumTheme.cornerRadiusMedium, style: .continuous))
    }

    private func segmentButton(title: String, index: Int) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedTab = index
            }
        }) {
            Text(title)
                .font(.system(size: 13, weight: selectedTab == index ? .semibold : .regular))
                .foregroundColor(selectedTab == index ? .white : ScandiumTheme.subtext)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    Group {
                        if selectedTab == index {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(ScandiumTheme.surfaceCard)
                                .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
                        }
                    }
                )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Content

    private var contentView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                if selectedTab == 0 {
                    likedTracksSection
                } else if selectedTab == 1 {
                    recentlyPlayedSection
                } else {
                    soundcloudSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 130)
        }
    }

    // MARK: - Liked Tracks Section

    @ViewBuilder
    private var likedTracksSection: some View {
        if library.likedTracks.isEmpty {
            emptyStateView(
                icon: "heart.slash",
                title: "Chưa có bài hát yêu thích",
                message: "Nhấn nút hình trái tim trên bài hát bất kỳ để lưu vào thư viện."
            )
        } else {
            // Action buttons
            HStack(spacing: 12) {
                Button(action: {
                    player.playQueue(library.likedTracks, startingAt: 0)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13))
                        Text("Phát tất cả")
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
                        Text("Trộn bài")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(ScandiumTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.bottom, 6)

            // Tracks list
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

    // MARK: - Recently Played Section

    @ViewBuilder
    private var recentlyPlayedSection: some View {
        if library.recentlyPlayed.isEmpty {
            emptyStateView(
                icon: "clock.arrow.circlepath",
                title: "Chưa có lịch sử nghe nhạc",
                message: "Các bài hát bạn phát sẽ tự động xuất hiện ở đây."
            )
        } else {
            HStack {
                Text("\(library.recentlyPlayed.count) bài đã nghe gần đây")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(ScandiumTheme.subtext)
                Spacer()
                Button("Xóa lịch sử") {
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

    // MARK: - SoundCloud Account Section

    @ViewBuilder
    private var soundcloudSection: some View {
        if auth.userLikedTracks.isEmpty {
            emptyStateView(
                icon: "arrow.triangle.2.circlepath",
                title: "Chưa đồng bộ bài hát",
                message: "Vào mục Cá nhân để tải danh sách bài hát từ tài khoản SoundCloud của bạn."
            )
        } else {
            HStack {
                Text("\(auth.userLikedTracks.count) bài đã thích trên SoundCloud")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(ScandiumTheme.subtext)
                Spacer()
                Button(action: {
                    Task {
                        await auth.syncLibrary()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(ScandiumTheme.spotifyGreen)
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)

            LazyVStack(spacing: 4) {
                ForEach(auth.userLikedTracks) { track in
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
                .foregroundColor(.white)

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
