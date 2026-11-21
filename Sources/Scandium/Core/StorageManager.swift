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
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.evictAudioTempIfNeeded()
        }
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

    private static let imageCacheFolderName = "scandium_image_cache"
    private static let libraryDBFileName = "scandium_library.db"
    private static let whitelistedTempPrefixes = ["scandium_", "CFNetworkDownload_"]
    private static let whitelistedAudioExtensions: Set<String> = ["mp3", "m4a", "aac", "mp4", "ts", "m3u8"]
    private static let activeTempGraceInterval: TimeInterval = 60

    // MARK: - Calculate Usage

    func refreshUsage() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let fileManager = FileManager.default

            // 1. Image Cache: scandium_image_cache + URLCache disk usage
            var imgBytes = Int64(URLCache.shared.currentDiskUsage)
            if let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
                let imageCacheDir = cachesURL.appendingPathComponent(Self.imageCacheFolderName, isDirectory: true)
                imgBytes += self.directorySize(url: imageCacheDir)
            }

            // 2. Audio Temp Cache: whitelisted audio/stream temp files in NSTemporaryDirectory()
            let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            let audioBytes = self.whitelistedAudioTempSize(in: tmpURL)

            // 3. User Data: SQLite database (scandium_library.db*) + Application Support
            var userBytes: Int64 = 0
            if let docsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
                let dbSuffixes = ["", "-wal", "-shm", "-journal"]
                for suffix in dbSuffixes {
                    let dbFileURL = docsURL.appendingPathComponent(Self.libraryDBFileName + suffix)
                    userBytes += self.fileSize(url: dbFileURL)
                }
            }
            if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                userBytes += self.directorySize(url: appSupport)
            }

            let finalImageBytes = max(imgBytes, 0)
            let finalAudioBytes = max(audioBytes, 0)
            let finalUserBytes = max(userBytes, 0)
            let finalTotal = finalImageBytes + finalAudioBytes + finalUserBytes

            DispatchQueue.main.async {
                self.imageCacheBytes = finalImageBytes
                self.audioNetworkBytes = finalAudioBytes
                self.userDataBytes = finalUserBytes
                self.totalBytes = finalTotal
            }
        }
    }

    // MARK: - Clear Cache

    /// Wipes app-owned image cache, URLCache, and whitelisted temporary stream files.
    /// SQLite library data, settings, and unrelated system/active files are preserved.
    func clearCache() {
        ImageCacheStore.shared.clear()
        URLCache.shared.removeAllCachedResponses()
        removeWhitelistedAudioTempFiles()
        refreshUsage()
    }

    /// Clears only cached artwork images
    func clearImageCacheOnly() {
        ImageCacheStore.shared.clear()
        URLCache.shared.removeAllCachedResponses()
        refreshUsage()
    }

    /// Clears only whitelisted temporary audio and stream buffer files
    func clearAudioCacheOnly() {
        removeWhitelistedAudioTempFiles()
        refreshUsage()
    }

    /// Evicts oldest whitelisted temp audio files using LRU when total exceeds 250 MB
    func evictAudioTempIfNeeded() {
        let maxBytes: Int64 = 250 * 1024 * 1024
        let targetBytes: Int64 = Int64(Double(maxBytes) * 0.8)
        DispatchQueue.global(qos: .background).async {
            let fm = FileManager.default
            let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            guard let files = try? fm.contentsOfDirectory(
                at: tmpURL,
                includingPropertiesForKeys: [.fileSizeKey, .contentAccessDateKey, .contentModificationDateKey, .isDirectoryKey],
                options: .skipsHiddenFiles
            ) else { return }

            var totalSize: Int64 = 0
            var fileInfos: [(url: URL, size: Int64, accessDate: Date)] = []
            let now = Date()

            for fileURL in files where self.isWhitelistedAudioTempItem(fileURL) {
                guard let attrs = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentAccessDateKey, .contentModificationDateKey, .isDirectoryKey]) else {
                    continue
                }
                if let modDate = attrs.contentModificationDate,
                   now.timeIntervalSince(modDate) < Self.activeTempGraceInterval {
                    continue
                }
                let itemSize: Int64
                if attrs.isDirectory == true {
                    itemSize = self.directorySize(url: fileURL)
                } else {
                    itemSize = Int64(attrs.fileSize ?? 0)
                }
                let accessDate = attrs.contentAccessDate ?? attrs.contentModificationDate ?? Date.distantPast
                totalSize += itemSize
                fileInfos.append((url: fileURL, size: itemSize, accessDate: accessDate))
            }

            guard totalSize > maxBytes else { return }
            fileInfos.sort { $0.accessDate < $1.accessDate }
            for info in fileInfos {
                guard totalSize > targetBytes else { break }
                try? fm.removeItem(at: info.url)
                totalSize -= info.size
            }
        }
    }

    // MARK: - Private Helpers

    private func isWhitelistedAudioTempItem(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        if Self.whitelistedTempPrefixes.contains(where: { name.hasPrefix($0) }) {
            return true
        }
        let ext = url.pathExtension.lowercased()
        return Self.whitelistedAudioExtensions.contains(ext)
    }

    private func removeWhitelistedAudioTempFiles() {
        let fm = FileManager.default
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        guard let items = try? fm.contentsOfDirectory(
            at: tmpURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        let now = Date()
        for item in items where isWhitelistedAudioTempItem(item) {
            if let attrs = try? item.resourceValues(forKeys: [.contentModificationDateKey]),
               let modDate = attrs.contentModificationDate,
               now.timeIntervalSince(modDate) < Self.activeTempGraceInterval {
                // Skip recently modified temp files to avoid deleting an active AVPlayer stream buffer
                continue
            }
            try? fm.removeItem(at: item)
        }
    }

    private func whitelistedAudioTempSize(in tmpURL: URL) -> Int64 {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: tmpURL,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return 0 }

        var total: Int64 = 0
        for item in items where isWhitelistedAudioTempItem(item) {
            if let attrs = try? item.resourceValues(forKeys: [.isDirectoryKey]),
               attrs.isDirectory == true {
                total += directorySize(url: item)
            } else {
                total += fileSize(url: item)
            }
        }
        return total
    }

    private func fileSize(url: URL) -> Int64 {
        guard let attrs = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = attrs.fileSize else {
            return 0
        }
        return Int64(size)
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
