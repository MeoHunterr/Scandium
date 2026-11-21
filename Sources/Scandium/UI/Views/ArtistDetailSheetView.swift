// ArtistDetailSheetView.swift — Artist profile & track list sheet
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import SwiftUI

struct ArtistDetailSheetView: View {
    let artist: SoundCloudUser

    @EnvironmentObject var api: SoundCloudAPI
    @EnvironmentObject var player: AudioPlayerEngine
    @EnvironmentObject var library: LibraryManager
    @EnvironmentObject var scraper: ClientIDScraper

    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.presentationMode) var presentationMode

    @State private var tracks: [Track] = []
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            ZStack {
                ScandiumTheme.bgPrimary.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        artistHeaderView
                            .padding(.top, 10)

                        if !tracks.isEmpty {
                            actionButtonsView
                        }

                        if isLoading && tracks.isEmpty {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: ScandiumTheme.spotifyGreen))
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        } else if let error = errorMessage {
                            errorView(error)
                        } else if tracks.isEmpty {
                            emptyTracksView
                        } else {
                            tracksListView
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(artist.username)
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
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            loadArtistTracks()
        }
    }

    // MARK: - Artist Header

    private var artistHeaderView: some View {
        HStack(spacing: 16) {
            CachedAsyncImage(
                url: artist.highResAvatarURL ?? (artist.avatarURL.flatMap { URL(string: $0) }),
                width: 80,
                height: 80,
                cornerRadius: 40
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(artist.username)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(ScandiumTheme.textPrimary)
                        .lineLimit(1)

                    if artist.verified == true {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 14))
                            .foregroundColor(ScandiumTheme.spotifyGreen)
                    }
                }

                if let fullName = artist.fullName, !fullName.isEmpty, fullName != artist.username {
                    Text(fullName)
                        .font(.system(size: 13))
                        .foregroundColor(ScandiumTheme.subtext)
                        .lineLimit(1)
                }

                HStack(spacing: 12) {
                    if let followers = artist.followersCount {
                        Text("\(formatCount(followers)) \(settings.loc("người theo dõi", "followers"))")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(ScandiumTheme.subtext)
                    }

                    if let count = artist.trackCount {
                        Text("\(formatCount(count)) \(settings.loc("bài hát", "tracks"))")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(ScandiumTheme.subtext)
                    }
                }
            }

            Spacer()
        }
    }

    // MARK: - Action Buttons

    private var actionButtonsView: some View {
        HStack(spacing: 12) {
            Button(action: {
                player.playQueue(tracks, startingAt: 0)
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
                let shuffled = tracks.shuffled()
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

    // MARK: - Tracks List

    private var tracksListView: some View {
        LazyVStack(spacing: 4) {
            ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                GlassTrackRow(
                    track: track,
                    isCurrentlyPlaying: player.currentTrack?.id == track.id,
                    showLikeButton: true,
                    onTap: {
                        player.playQueue(tracks, startingAt: index)
                    }
                )
            }
        }
    }

    // MARK: - Error & Empty Views

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(settings.loc("Không thể tải danh sách bài hát", "Unable to load tracks"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(ScandiumTheme.textPrimary)

            Text(message)
                .font(.system(size: 13))
                .foregroundColor(ScandiumTheme.subtext)
                .multilineTextAlignment(.center)

            Button(action: loadArtistTracks) {
                Text(settings.loc("Thử lại", "Retry"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ScandiumTheme.textPrimary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(ScandiumTheme.surfaceElevated)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private var emptyTracksView: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(ScandiumTheme.subtext.opacity(0.4))
            Text(settings.loc("Nghệ sĩ chưa đăng tải bài hát nào", "No tracks published by this artist"))
                .font(.system(size: 14))
                .foregroundColor(ScandiumTheme.subtext)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Loading

    private func loadArtistTracks() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let fetched = try await api.getUserTracks(userID: artist.id, limit: 50)
                await MainActor.run {
                    self.tracks = fetched
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

    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000.0)
        } else {
            return "\(count)"
        }
    }
}
