// GlassTrackRow.swift — Spotify/Threads clean track row
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import SwiftUI

struct GlassTrackRow: View {
    let track: Track
    let isCurrentlyPlaying: Bool
    var showLikeButton: Bool = true
    var onSelectArtist: ((SoundCloudUser) -> Void)? = nil
    let onTap: () -> Void

    @EnvironmentObject var library: LibraryManager
    @EnvironmentObject var player: AudioPlayerEngine
    @ObservedObject private var settings = AppSettings.shared

    init(
        track: Track,
        isCurrentlyPlaying: Bool,
        showLikeButton: Bool = true,
        onSelectArtist: ((SoundCloudUser) -> Void)? = nil,
        onTap: @escaping () -> Void
    ) {
        self.track = track
        self.isCurrentlyPlaying = isCurrentlyPlaying
        self.showLikeButton = showLikeButton
        self.onSelectArtist = onSelectArtist
        self.onTap = onTap
    }

    var body: some View {
        HStack(spacing: 10) {
            // Main Tappable Area: Artwork + Title + Artist
            Button(action: onTap) {
                HStack(spacing: 12) {
                    CachedAsyncImage(
                        url: track.artworkURL(size: .t120x120) ?? track.artworkImageURL,
                        width: 48,
                        height: 48,
                        cornerRadius: 6
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(isCurrentlyPlaying ? ScandiumTheme.spotifyGreen : ScandiumTheme.textPrimary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: 4) {
                            Text(track.user?.username ?? "Unknown")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(ScandiumTheme.subtext)
                                .lineLimit(1)

                            if let plays = track.formattedPlaybackCount {
                                Text("•")
                                    .font(.system(size: 10))
                                    .foregroundColor(ScandiumTheme.subtext.opacity(0.6))
                                Text(plays)
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundColor(ScandiumTheme.subtext.opacity(0.8))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color.black.opacity(0.001))
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())

            // Right-side indicators and action buttons
            HStack(spacing: 8) {
                if isCurrentlyPlaying {
                    nowPlayingIndicator
                } else {
                    Text(track.formattedDuration)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundColor(ScandiumTheme.subtext)
                }

                if showLikeButton {
                    let isLiked = library.isLiked(track: track)
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            library.toggleLike(track: track)
                        }
                    }) {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(isLiked ? ScandiumTheme.spotifyGreen : ScandiumTheme.subtext.opacity(0.5))
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                trackActionMenu
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.001))
        .contentShape(Rectangle())
        .contextMenu {
            trackContextMenuContent
        }
    }

    // MARK: - Action Menu (Ellipsis ...)

    private var trackActionMenu: some View {
        Menu {
            trackContextMenuContent
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(ScandiumTheme.subtext.opacity(0.75))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
    }

    // MARK: - Menu Content

    @ViewBuilder
    private var trackContextMenuContent: some View {
        if let user = track.user, onSelectArtist != nil {
            Button(action: {
                onSelectArtist?(user)
            }) {
                Label(settings.loc("Xem nghệ sĩ", "Go to Artist"), systemImage: "person.circle")
            }
        }

        Button(action: {
            player.playNext(track)
        }) {
            Label(settings.loc("Phát tiếp theo", "Play Next"), systemImage: "text.insert")
        }

        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                library.toggleLike(track: track)
            }
        }) {
            let isLiked = library.isLiked(track: track)
            Label(
                isLiked ? settings.loc("Bỏ thích", "Unlike") : settings.loc("Thích", "Like"),
                systemImage: isLiked ? "heart.slash" : "heart"
            )
        }

        if let link = track.permalinkURL ?? track.uri {
            Button(action: {
                UIPasteboard.general.string = link
            }) {
                Label(settings.loc("Sao chép liên kết", "Copy Link"), systemImage: "link")
            }
        }
    }

    // MARK: - Now Playing Indicator

    private var nowPlayingIndicator: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                NowPlayingBar(index: index)
            }
        }
        .frame(width: 14, height: 14)
    }
}

// MARK: - Animated Now Playing Bars

private struct NowPlayingBar: View {
    let index: Int
    @State private var height: CGFloat = 4

    init(index: Int) {
        self.index = index
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(ScandiumTheme.spotifyGreen)
            .frame(width: 2.5, height: height)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.4 + Double(index) * 0.15)
                    .repeatForever(autoreverses: true)
                ) {
                    height = CGFloat.random(in: 6...14)
                }
            }
    }
}
