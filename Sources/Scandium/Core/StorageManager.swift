// StorageManager.swift — Disk cache and storage accounting for Scandium
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import Foundation

final class StorageManager: ObservableObject {
    static let shared = StorageManager()

    // MARK: - Published Sizes (in Bytes)

    @Published private(set) var imageCacheBytes: Int64 = 0
    @Published private(set) var audioNetworkBytes: Int64 = 0
    @Published private(set) var userDataBytes: Int64 = 0
    @Published private(set) var totalBytes: Int64 = 0

    private init() {
        // Storage values start at 0; refreshUsage() is called lazily from ProfileView.onAppear
    }

    // MARK: - Formatters

    var formattedTotal: String {
        formatBytes(totalBytes)
    }

    var formattedImageCache: String {
        formatBytes(imageCacheBytes)
    }

    var formattedAudioNetwork: String {
        formatBytes(audioNetworkBytes)
    }

    var formattedUserData: String {
        formatBytes(userDataBytes)
    }

    /// Ratio (0.0 ... 1.0) for visual distribution bar
    var imageRatio: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(imageCacheBytes) / Double(totalBytes)
    }

    var audioRatio: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(audioNetworkBytes) / Double(totalBytes)
    }

    var userRatio: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(userDataBytes) / Double(totalBytes)
    }

    // MARK: - Calculate Usage

    func refreshUsage() {
        let fileManager = FileManager.default

        // 1. Image cache: from URLCache currentDiskUsage
        let urlCacheDisk = Int64(URLCache.shared.currentDiskUsage)

        // 2. Audio & temporary network cache: tmp directory + Caches folder
        var tmpBytes: Int64 = 0
        let tmpDir = NSTemporaryDirectory()
        tmpBytes += directorySize(url: URL(fileURLWithPath: tmpDir))

        if let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let totalCaches = directorySize(url: cachesURL)
            // Anything beyond URLCache in caches
            let nonURLCache = max(0, totalCaches - urlCacheDisk)
            tmpBytes += nonURLCache
        }

        // 3. User data: UserDefaults plist files + Application Support
        var userBytes: Int64 = 0
        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            userBytes += directorySize(url: appSupport)
        }
        // Account for likedTracks and recentlyPlayed JSON stored in UserDefaults
        if let likedData = UserDefaults.standard.data(forKey: "scandium_liked_tracks") {
            userBytes += Int64(likedData.count)
        }
        if let recentData = UserDefaults.standard.data(forKey: "scandium_recently_played") {
            userBytes += Int64(recentData.count)
        }
        if userBytes == 0 {
            userBytes = 4096 // Base minimum for profile & preferences
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.imageCacheBytes = max(urlCacheDisk, 0)
            self.audioNetworkBytes = max(tmpBytes, 0)
            self.userDataBytes = userBytes
            self.totalBytes = self.imageCacheBytes + self.audioNetworkBytes + self.userDataBytes
        }
    }

    // MARK: - Clear Cache

    /// Wipes image cache, URL cache, and temporary stream files. Liked tracks and settings are preserved.
    func clearCache() {
        // Clear URLCache and memory cache
        URLCache.shared.removeAllCachedResponses()

        let fileManager = FileManager.default

        // Clear NSTemporaryDirectory()
        let tmpDir = NSTemporaryDirectory()
        if let tmpFiles = try? fileManager.contentsOfDirectory(atPath: tmpDir) {
            for file in tmpFiles {
                let fullPath = (tmpDir as NSString).appendingPathComponent(file)
                try? fileManager.removeItem(atPath: fullPath)
            }
        }

        // Clear Caches directory contents
        if let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first,
           let cacheItems = try? fileManager.contentsOfDirectory(at: cachesURL, includingPropertiesForKeys: nil) {
            for item in cacheItems {
                try? fileManager.removeItem(at: item)
            }
        }

        refreshUsage()
    }

    // MARK: - Private Helpers

    private func directorySize(url: URL) -> Int64 {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                  let isDirectory = resourceValues.isDirectory,
                  !isDirectory,
                  let fileSize = resourceValues.fileSize else {
                continue
            }
            total += Int64(fileSize)
        }
        return total
    }

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            let kb = Double(bytes) / 1024.0
            return String(format: "%.1f KB", kb)
        } else if bytes < 1024 * 1024 * 1024 {
            let mb = Double(bytes) / (1024.0 * 1024.0)
            return String(format: "%.1f MB", mb)
        } else {
            let gb = Double(bytes) / (1024.0 * 1024.0 * 1024.0)
            return String(format: "%.2f GB", gb)
        }
    }
}
