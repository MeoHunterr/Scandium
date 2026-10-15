// AudioPlayerEngine.swift — AVPlayer wrapper with background audio & system media integration
// Project: Scandium | Author: MeoHunter | License: GPL-3.0
//
// Manages a single persistent AVPlayer instance for streaming playback,
// background audio session, MPNowPlayingInfoCenter updates, and MPRemoteCommandCenter handlers.

import Foundation
import AVFoundation
import MediaPlayer
import Combine

final class AudioPlayerEngine: ObservableObject {

    // MARK: - Playback State Enum

    enum PlaybackState: Equatable {
        case idle
        case loading
        case playing
        case paused
        case failed(String)

        var isPlaying: Bool {
            self == .playing
        }
    }

    // MARK: - Published Properties

    @Published private(set) var playbackState: PlaybackState = .idle
    @Published private(set) var currentTrack: Track?
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var bufferedTime: TimeInterval = 0
    @Published private(set) var playbackVolume: Float = 1.0
    @Published var playbackRate: Float = 1.0

    // MARK: - Queue & Playback Modes

    @Published var queue: [Track] = []
    @Published private(set) var currentIndex: Int = 0
    @Published var isShuffleEnabled: Bool = false
    @Published var isRepeatEnabled: Bool = false

    // MARK: - Private Properties

    /// Single persistent AVPlayer instance across the entire app lifecycle
    private let player = AVPlayer()
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var artworkImage: UIImage?

    /// Guards against running heavy setup more than once
    private var isSetup: Bool = false

    // MARK: - Dependencies

    private let api: SoundCloudAPI

    // MARK: - Init / Deinit

    init(api: SoundCloudAPI) {
        self.api = api
        self.player.volume = playbackVolume
        // Heavy setup is deliberately deferred to setupIfNeeded().
        // AVAudioSession.setActive() and MPRemoteCommandCenter must NOT be called
        // before the window is ready (i.e. before the first play() invocation).
    }

    deinit {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
        cancellables.removeAll()
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    // MARK: - Lazy One-Time Setup

    /// Called once at the start of the first play(track:) invocation.
    /// Activating AVAudioSession and registering MPRemoteCommandCenter targets
    /// before UIWindowScene is ready causes a crash on iOS 15.
    private func setupIfNeeded() {
        guard !isSetup else { return }
        isSetup = true
        configureAudioSession()
        setupPersistentTimeObserver()
        setupRemoteCommandCenter()
    }

    // MARK: - Audio Session Configuration

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            print("[Scandium] Failed to configure audio session: \(error.localizedDescription)")
        }
    }

    // MARK: - Persistent Time Observer (Registered Once)

    private func setupPersistentTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            let seconds = CMTimeGetSeconds(time)
            if seconds.isFinite && seconds >= 0 {
                self.currentTime = seconds
            }
            self.updateBufferedTime()
        }
    }

    // MARK: - Play Track

    /// Plays a track by resolving its stream URL and replacing the player's current item.
    func play(track: Track) {
        setupIfNeeded()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.currentTrack = track
            self.playbackState = .loading
            self.currentTime = 0
            self.duration = track.durationInSeconds
            self.bufferedTime = 0
            self.artworkImage = nil
        }

        LibraryManager.shared.addToRecentlyPlayed(track: track)

        Task { [weak self] in
            guard let self = self else { return }
            do {
                let streamURL = try await self.api.resolveStreamURL(for: track)
                await MainActor.run {
                    self.startPlayback(url: streamURL, track: track)
                }
            } catch {
                await MainActor.run {
                    self.playbackState = .failed(error.localizedDescription)
                }
            }
        }

        fetchArtworkForNowPlaying(track: track)
    }

    /// Plays a track from the queue at a specific index.
    func play(at index: Int) {
        guard index >= 0, index < queue.count else { return }
        currentIndex = index
        play(track: queue[index])
    }

    /// Sets the queue and starts playing from the first track (or a specified index).
    func playQueue(_ tracks: [Track], startingAt index: Int = 0) {
        queue = tracks
        currentIndex = max(0, min(index, tracks.count - 1))
        if !tracks.isEmpty {
            play(track: tracks[currentIndex])
        }
    }

    // MARK: - Internal Playback Setup

    private func startPlayback(url: URL, track: Track) {
        // 1. Invalidate / cancel observers of old item before replacing
        cancellables.removeAll()

        // 2. Create new item
        let newItem = AVPlayerItem(url: url)
        self.playerItem = newItem

        // 3. Attach observers to new item
        setupItemObservers(item: newItem)

        // 4. Replace current item in the persistent player and play
        player.replaceCurrentItem(with: newItem)
        player.play()
        if playbackRate != 1.0 {
            player.rate = playbackRate
        }
        playbackState = .playing

        updateNowPlayingInfo(track: track)
    }

    // MARK: - Item Observers (KVO via Combine)

    private func setupItemObservers(item: AVPlayerItem) {
        item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self = self else { return }
                switch status {
                case .readyToPlay:
                    let itemDuration = CMTimeGetSeconds(item.duration)
                    if itemDuration.isFinite && itemDuration > 0 {
                        self.duration = itemDuration
                    }
                case .failed:
                    let errorMsg = item.error?.localizedDescription ?? "Playback failed"
                    self.playbackState = .failed(errorMsg)
                default:
                    break
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handlePlaybackFinished()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handlePlaybackFailed(notification)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleAudioInterruption(notification)
            }
            .store(in: &cancellables)
    }

    // MARK: - Playback Controls

    func resume() {
        player.play()
        if playbackRate != 1.0 {
            player.rate = playbackRate
        }
        playbackState = .playing
        updateNowPlayingElapsedTime()
    }

    func pause() {
        player.pause()
        playbackState = .paused
        updateNowPlayingElapsedTime()
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        if playbackState == .playing {
            player.rate = rate
        }
        updateNowPlayingElapsedTime()
    }

    func togglePlayPause() {
        switch playbackState {
        case .playing:
            pause()
        case .paused:
            resume()
        case .idle:
            if let track = currentTrack {
                play(track: track)
            } else if !queue.isEmpty {
                play(at: currentIndex)
            }
        default:
            break
        }
    }

    func setPlaybackVolume(_ volume: Float) {
        let clamped = min(max(volume, 0), 1)
        player.volume = clamped
        playbackVolume = clamped
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        cancellables.removeAll()
        playerItem = nil
        playbackState = .idle
        currentTime = 0
        duration = 0
        bufferedTime = 0
        clearNowPlayingInfo()
    }

    /// Seeks to a specific time in seconds.
    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            if finished {
                DispatchQueue.main.async {
                    self?.currentTime = time
                    self?.updateNowPlayingElapsedTime()
                }
            }
        }
    }

    /// Seeks to a normalized position (0.0 – 1.0).
    func seekToFraction(_ fraction: Double) {
        let targetTime = duration * max(0, min(1, fraction))
        seek(to: targetTime)
    }

    // MARK: - Queue Navigation

    func toggleShuffle() {
        isShuffleEnabled.toggle()
    }

    func toggleRepeat() {
        isRepeatEnabled.toggle()
    }

    func nextTrack() {
        guard !queue.isEmpty else { return }
        if isShuffleEnabled && queue.count > 1 {
            var randomIndex = Int.random(in: 0..<queue.count)
            if randomIndex == currentIndex {
                randomIndex = (randomIndex + 1) % queue.count
            }
            currentIndex = randomIndex
            play(track: queue[randomIndex])
            return
        }

        let nextIndex = currentIndex + 1
        if nextIndex < queue.count {
            currentIndex = nextIndex
            play(track: queue[nextIndex])
        } else if isRepeatEnabled {
            currentIndex = 0
            play(track: queue[0])
        } else {
            currentIndex = 0
            pause()
            seek(to: 0)
        }
    }

    func previousTrack() {
        if currentTime > 3.0 {
            seek(to: 0)
            return
        }
        guard !queue.isEmpty else { return }
        let prevIndex = currentIndex - 1
        if prevIndex >= 0 {
            currentIndex = prevIndex
            play(track: queue[prevIndex])
        } else {
            currentIndex = queue.count - 1
            play(track: queue[currentIndex])
        }
    }

    /// Appends a track to the end of the queue.
    func enqueue(_ track: Track) {
        queue.append(track)
    }

    /// Inserts a track to play next in the queue.
    func playNext(_ track: Track) {
        let insertIndex = min(currentIndex + 1, queue.count)
        queue.insert(track, at: insertIndex)
    }

    // MARK: - Buffered Time

    private func updateBufferedTime() {
        guard let item = playerItem else { return }
        if let range = item.loadedTimeRanges.first?.timeRangeValue {
            let buffered = CMTimeGetSeconds(range.start) + CMTimeGetSeconds(range.duration)
            if buffered.isFinite {
                bufferedTime = buffered
            }
        }
    }

    // MARK: - Playback Finished & Failed Handlers

    private func handlePlaybackFinished() {
        if isRepeatEnabled && queue.count <= 1 {
            seek(to: 0)
            resume()
            return
        }
        if currentIndex + 1 < queue.count || isShuffleEnabled {
            nextTrack()
        } else if AppSettings.shared.autoPlayRelated, let current = currentTrack {
            Task {
                var newTracks: [Track] = []
                // Attempt 1: Fetch related tracks
                if let related = try? await api.getRelatedTracks(trackID: current.id, limit: 10) {
                    let existingIDs = Set(self.queue.map { $0.id })
                    let filtered = related.filter { !existingIDs.contains($0.id) }
                    newTracks = filtered
                }
                // Attempt 2: If related tracks empty, fallback search by genre or artist
                if newTracks.isEmpty {
                    let query = current.genre ?? current.user?.username ?? "Chill Hits"
                    if let searchRes = try? await api.searchTracks(query: query, limit: 10, offset: 0) {
                        let existingIDs = Set(self.queue.map { $0.id })
                        newTracks = searchRes.collection.filter { !existingIDs.contains($0.id) }
                    }
                }

                if !newTracks.isEmpty {
                    let tracksToEnqueue = newTracks
                    await MainActor.run {
                        for t in tracksToEnqueue {
                            self.enqueue(t)
                        }
                        self.nextTrack()
                    }
                } else {
                    await MainActor.run {
                        self.playbackState = .paused
                        self.currentTime = self.duration
                        self.updateNowPlayingElapsedTime()
                    }
                }
            }
        } else {
            playbackState = .paused
            currentTime = duration
            updateNowPlayingElapsedTime()
        }
    }

    private func handlePlaybackFailed(_ notification: Notification) {
        var message = "Playback failed"
        if let userInfo = notification.userInfo {
            for (_, value) in userInfo {
                if let err = value as? Error {
                    message = err.localizedDescription
                    break
                }
            }
        }
        self.playbackState = .failed(message)
    }

    // MARK: - Audio Interruption Handling

    private func handleAudioInterruption(_ notification: Notification) {
        guard let dict = notification.userInfo else { return }

        var typeRaw: UInt?
        var optionsRaw: UInt?

        for (key, val) in dict {
            let keyStr = String(describing: key)
            if keyStr.contains("InterruptionType") {
                if let num = val as? NSNumber {
                    typeRaw = num.uintValue
                } else if let u = val as? UInt {
                    typeRaw = u
                }
            } else if keyStr.contains("InterruptionOption") {
                if let num = val as? NSNumber {
                    optionsRaw = num.uintValue
                } else if let u = val as? UInt {
                    optionsRaw = u
                }
            }
        }

        guard let raw = typeRaw, let type = AVAudioSession.InterruptionType(rawValue: raw) else {
            return
        }

        switch type {
        case .began:
            pause()
        case .ended:
            if let opt = optionsRaw {
                let options = AVAudioSession.InterruptionOptions(rawValue: opt)
                if options.contains(.shouldResume) {
                    resume()
                }
            }
        @unknown default:
            break
        }
    }

    // MARK: - Now Playing Info (Lock Screen & Control Center)

    private func updateNowPlayingInfo(track: Track) {
        var info = [String: Any]()

        info[MPMediaItemPropertyTitle] = track.title
        info[MPMediaItemPropertyArtist] = track.user?.username ?? "Unknown Artist"
        info[MPMediaItemPropertyPlaybackDuration] = track.durationInSeconds
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = 1.0

        if let albumTitle = track.publisherMetadata?.albumTitle {
            info[MPMediaItemPropertyAlbumTitle] = albumTitle
        }

        if let artwork = artworkImage {
            let mediaArtwork = MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork }
            info[MPMediaItemPropertyArtwork] = mediaArtwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingElapsedTime() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = playbackState.isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Artwork Fetching for Now Playing

    private func fetchArtworkForNowPlaying(track: Track) {
        guard let artworkURL = track.highResArtworkURL else { return }

        Task { [weak self] in
            guard let self = self else { return }
            do {
                let (data, _) = try await URLSession.shared.data(from: artworkURL)
                guard let image = UIImage(data: data) else { return }
                await MainActor.run {
                    self.artworkImage = image
                    if self.currentTrack?.id == track.id {
                        self.updateNowPlayingInfo(track: track)
                    }
                }
            } catch {
                print("[Scandium] Failed to fetch artwork for Now Playing: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Remote Command Center

    private func setupRemoteCommandCenter() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            if !self.queue.isEmpty {
                self.nextTrack()
                return .success
            }
            return .noActionableNowPlayingItem
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.previousTrack()
            return .success
        }

        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self,
                  let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self.seek(to: positionEvent.positionTime)
            return .success
        }
    }

    // MARK: - Computed Helpers

    /// Normalized progress (0.0 – 1.0).
    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(currentTime / duration, 1.0)
    }

    /// Normalized buffer progress (0.0 – 1.0).
    var bufferProgress: Double {
        guard duration > 0 else { return 0 }
        return min(bufferedTime / duration, 1.0)
    }

    /// Whether there is a next track in the queue.
    var hasNextTrack: Bool {
        !queue.isEmpty && currentIndex + 1 < queue.count
    }

    /// Whether there is a previous track in the queue (or current time > 3s to restart).
    var hasPreviousTrack: Bool {
        currentTime > 3.0 || (!queue.isEmpty && currentIndex > 0)
    }

    /// Formatted current time string.
    var formattedCurrentTime: String {
        Track.formatDuration(currentTime)
    }

    /// Formatted remaining time string.
    var formattedRemainingTime: String {
        let remaining = max(0, duration - currentTime)
        return "-" + Track.formatDuration(remaining)
    }

    /// Formatted total duration string.
    var formattedDuration: String {
        Track.formatDuration(duration)
    }
}
