// FullPlayerView.swift — Full-screen player (Spotify / Apple Music standard)
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import SwiftUI

struct FullPlayerView: View {
    @EnvironmentObject var player: AudioPlayerEngine
    @EnvironmentObject var api: SoundCloudAPI
    @EnvironmentObject var library: LibraryManager
    @Environment(\.presentationMode) var presentationMode

    @State private var waveformSamples: [Float] = []
    @State private var dragProgress: Double? = nil
    @State private var showQueueSheet: Bool = false
    @State private var dragOffsetY: CGFloat = 0

    private let playbackRates: [Float] = [0.8, 1.0, 1.25, 1.5, 2.0]

    init() {}

    var body: some View {
        GeometryReader { geometry in
            let screenWidth = max(1, geometry.size.width)
            let screenHeight = max(1, geometry.size.height)
            let artSize = max(1, min(screenWidth - 48, screenHeight * 0.38))

            ZStack {
                // True OLED black background with subtle dynamic artwork blur
                AmbientCanvasBackground(
                    artworkURL: player.currentTrack?.highResArtworkURL
                )
                .frame(width: screenWidth, height: screenHeight)
                .clipped()

                // Single non-scrolling vertical screen
                VStack(spacing: 0) {
                    // 1. Grabber bar + "ĐANG PHÁT" header
                    headerSection
                        .padding(.top, 12)
                        .padding(.bottom, 14)

                    Spacer(minLength: 6)

                    // 2. Square Locked Artwork
                    artworkSection(artSize: artSize)

                    Spacer(minLength: 14)

                    // 3. Track Info (Left-aligned Spotify style)
                    trackInfoSection
                        .padding(.horizontal, 24)

                    Spacer(minLength: 12)

                    // 4. Scrubber / Slider (36pt) + Time Labels
                    scrubberSection
                        .padding(.horizontal, 24)

                    Spacer(minLength: 12)

                    // 5. Centered 5-Button Control Cluster
                    controlsSection
                        .padding(.horizontal, 24)

                    Spacer(minLength: 12)

                    // 6. Volume & Queue Bar
                    bottomBarSection
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)
                }
                .frame(width: screenWidth, height: screenHeight)
                .clipped()
            }
            .frame(width: screenWidth, height: screenHeight)
            .clipped()
            .offset(y: max(0, dragOffsetY))
            .gesture(
                DragGesture(minimumDistance: 15)
                    .onChanged { value in
                        if value.translation.height > 0 {
                            dragOffsetY = value.translation.height
                        }
                    }
                    .onEnded { value in
                        if value.translation.height > 120 || value.predictedEndTranslation.height > 250 {
                            withAnimation(.easeOut(duration: 0.2)) {
                                dragOffsetY = screenHeight
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                presentationMode.wrappedValue.dismiss()
                            }
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                dragOffsetY = 0
                            }
                        }
                    }
            )
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onAppear {
            loadWaveform()
        }
        .onChange(of: player.currentTrack?.id) { _ in
            loadWaveform()
        }
        .sheet(isPresented: $showQueueSheet) {
            QueueSheetView()
                .environmentObject(player)
                .environmentObject(library)
        }
    }

    // MARK: - 1. Header Section

    private var headerSection: some View {
        VStack(spacing: 10) {
            // Grabber pill
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.white.opacity(0.3))
                .frame(width: 36, height: 4)

            HStack {
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 36, height: 36)
                }

                Spacer()

                Text(AppSettings.shared.loc("Đang phát", "Now Playing"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ScandiumTheme.subtext)

                Spacer()

                // Mirror spacer for perfect center
                Color.clear
                    .frame(width: 36, height: 36)
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - 2. Artwork Section

    private func artworkSection(artSize: CGFloat) -> some View {
        CachedAsyncImage(
            url: player.currentTrack?.highResArtworkURL,
            width: artSize,
            height: artSize,
            cornerRadius: 12
        )
        .shadow(color: Color.black.opacity(0.45), radius: 20, x: 0, y: 10)
    }

    // MARK: - 3. Track Info (Spotify Left-Aligned)

    private var trackInfoSection: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(player.currentTrack?.title ?? AppSettings.shared.loc("Chưa chọn bài hát", "No track selected"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(player.currentTrack?.user?.username ?? "SoundCloud")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(ScandiumTheme.subtext)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let track = player.currentTrack {
                let isLiked = library.isLiked(track: track)
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        library.toggleLike(track: track)
                    }
                }) {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(isLiked ? ScandiumTheme.spotifyGreen : Color.white.opacity(0.7))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    // MARK: - 4. Scrubber & Time Labels

    private var scrubberSection: some View {
        VStack(spacing: 6) {
            // Scrubber View (36pt height)
            Group {
                if !waveformSamples.isEmpty {
                    WaveformScrubber(
                        samples: waveformSamples,
                        progress: Binding(
                            get: { dragProgress ?? player.progress },
                            set: { dragProgress = $0 }
                        ),
                        bufferedProgress: player.bufferProgress,
                        onSeek: { fraction in
                            dragProgress = nil
                            player.seekToFraction(fraction)
                        }
                    )
                } else {
                    SimpleProgressScrubber(
                        progress: Binding(
                            get: { dragProgress ?? player.progress },
                            set: { dragProgress = $0 }
                        ),
                        bufferedProgress: player.bufferProgress,
                        onSeek: { fraction in
                            dragProgress = nil
                            player.seekToFraction(fraction)
                        }
                    )
                }
            }
            .frame(height: 36)

            // Time Labels
            HStack {
                Text(player.formattedCurrentTime)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(ScandiumTheme.subtext)

                Spacer()

                Text(player.formattedRemainingTime)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(ScandiumTheme.subtext)
            }
        }
    }

    // MARK: - 5. Controls Section (Centered 5-Button Cluster)

    private var controlsSection: some View {
        HStack(spacing: 0) {
            // Shuffle
            Button(action: {
                player.toggleShuffle()
            }) {
                Image(systemName: "shuffle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(player.isShuffleEnabled ? ScandiumTheme.spotifyGreen : Color.white.opacity(0.6))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(PlainButtonStyle())

            Spacer()

            // Previous
            Button(action: {
                player.previousTrack()
            }) {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(PlainButtonStyle())

            Spacer()

            // Large White Play / Pause Circle (64x64)
            Button(action: {
                player.togglePlayPause()
            }) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 64, height: 64)
                        .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)

                    Image(systemName: player.playbackState.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.black)
                        .offset(x: player.playbackState.isPlaying ? 0 : 2)
                }
            }
            .buttonStyle(PlainButtonStyle())

            Spacer()

            // Next
            Button(action: {
                player.nextTrack()
            }) {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(PlainButtonStyle())

            Spacer()

            // Repeat
            Button(action: {
                player.toggleRepeat()
            }) {
                Image(systemName: "repeat")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(player.isRepeatEnabled ? ScandiumTheme.spotifyGreen : Color.white.opacity(0.6))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    // MARK: - 6. Bottom Volume & Queue Section

    private var bottomBarSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 11))
                .foregroundColor(ScandiumTheme.subtext)

            PlayerVolumeSlider(
                value: Binding(
                    get: { Double(player.playbackVolume) },
                    set: { player.setPlaybackVolume(Float($0)) }
                )
            )
                .frame(height: 20)

            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 11))
                .foregroundColor(ScandiumTheme.subtext)

            Spacer(minLength: 8)

            // Speed control button
            Button(action: {
                cyclePlaybackRate()
            }) {
                Text(formatSpeed(player.playbackRate))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(player.playbackRate == 1.0 ? Color.white.opacity(0.8) : ScandiumTheme.spotifyGreen)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(ScandiumTheme.surfaceElevated)
                    .clipShape(Capsule())
            }
            .buttonStyle(PlainButtonStyle())

            // Queue button
            Button(action: {
                showQueueSheet = true
            }) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(player.queue.isEmpty ? Color.white.opacity(0.3) : .white)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private func cyclePlaybackRate() {
        let current = player.playbackRate
        if let idx = playbackRates.firstIndex(where: { abs($0 - current) < 0.05 }) {
            let nextIdx = (idx + 1) % playbackRates.count
            player.setPlaybackRate(playbackRates[nextIdx])
        } else {
            player.setPlaybackRate(1.0)
        }
    }

    private func formatSpeed(_ rate: Float) -> String {
        if rate == Float(Int(rate)) {
            return String(format: "%.0fx", rate)
        } else {
            return String(format: "%.2gx", rate)
        }
    }

    // MARK: - Waveform Loading

    private func loadWaveform() {
        guard let track = player.currentTrack else { return }
        Task {
            do {
                let samples = try await api.getWaveformData(for: track)
                await MainActor.run {
                    self.waveformSamples = samples
                }
            } catch {
                await MainActor.run {
                    self.waveformSamples = []
                }
            }
        }
    }
}

// MARK: - Volume Slider (App Playback Volume)

struct PlayerVolumeSlider: View {
    @Binding var value: Double

    var body: some View {
        Slider(
            value: $value,
            in: 0...1
        )
        .tint(.white)
    }
}

// MARK: - Queue Sheet View

struct QueueSheetView: View {
    @EnvironmentObject var player: AudioPlayerEngine
    @Environment(\.presentationMode) var presentationMode

    init() {}

    var body: some View {
        ZStack {
            ScandiumTheme.bgPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text(AppSettings.shared.loc("Danh sách phát", "Playback Queue"))
                        .font(.headline)
                        .foregroundColor(ScandiumTheme.textPrimary)
                    Spacer()
                    Button(AppSettings.shared.loc("Xong", "Done")) {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(ScandiumTheme.spotifyGreen)
                    .font(.body.weight(.semibold))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

                HairlineDivider()

                if player.queue.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "music.note.list")
                            .font(.system(size: 40))
                            .foregroundColor(ScandiumTheme.subtext.opacity(0.5))
                        Text(AppSettings.shared.loc("Danh sách phát trống", "Queue is empty"))
                            .font(.subheadline)
                            .foregroundColor(ScandiumTheme.subtext)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(Array(player.queue.enumerated()), id: \.offset) { index, track in
                            GlassTrackRow(
                                track: track,
                                isCurrentlyPlaying: index == player.currentIndex,
                                onTap: {
                                    player.play(at: index)
                                }
                            )
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        }
                    }
                    .listStyle(PlainListStyle())
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
