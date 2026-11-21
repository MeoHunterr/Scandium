// LiquidGlassModifier.swift — Design tokens and liquid glass modifiers for Scandium
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Design Tokens

enum ScandiumTheme {
    static var isDark: Bool {
        AppSettings.shared.isDark
    }

    // Dynamic surfaces based on theme
    static var bgPrimary: Color {
        isDark ? Color.black : Color(red: 0.95, green: 0.95, blue: 0.97)
    }

    static var surfaceDark: Color {
        isDark ? Color(red: 0.071, green: 0.071, blue: 0.071) : Color(red: 0.91, green: 0.91, blue: 0.93)
    }

    static var surfaceCard: Color {
        isDark ? Color(red: 0.094, green: 0.094, blue: 0.094) : Color.white
    }

    static var surfaceElevated: Color {
        isDark ? Color(red: 0.110, green: 0.110, blue: 0.118) : Color(red: 0.88, green: 0.88, blue: 0.90)
    }

    // Dynamic text
    static var textPrimary: Color {
        isDark ? Color.white : Color(red: 0.1, green: 0.1, blue: 0.1)
    }

    static var subtext: Color {
        isDark ? Color(red: 0.655, green: 0.655, blue: 0.655) : Color(red: 0.45, green: 0.45, blue: 0.48)
    }

    // Hairline divider
    static var hairline: Color {
        isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.10)
    }
    static let hairlinewidth: CGFloat = 0.5

    // Accents
    static var accent: Color {
        AppSettings.shared.accentColor.color
    }
    static var spotifyGreen: Color {
        accent
    }
    static let defaultGreen = Color(red: 29/255, green: 185/255, blue: 84/255)
    static let accentOrange = Color(red: 1.0, green: 0.35, blue: 0.12)
    static let pureWhite = Color.white

    // Dimensions
    static let cornerRadiusSmall: CGFloat = 6
    static let cornerRadiusMedium: CGFloat = 8
    static let cornerRadiusCard: CGFloat = 12
    static let cornerRadiusLarge: CGFloat = 16
    static let miniPlayerHeight: CGFloat = 56
    static let tabBarHeight: CGFloat = 49
}

// Keep LiquidGlass alias for backward compatibility
typealias LiquidGlass = ScandiumTheme

// MARK: - Hairline Divider

struct HairlineDivider: View {
    var leadingPadding: CGFloat = 0

    init(leadingPadding: CGFloat = 0) {
        self.leadingPadding = leadingPadding
    }

    var body: some View {
        Rectangle()
            .fill(ScandiumTheme.hairline)
            .frame(height: ScandiumTheme.hairlinewidth)
            .padding(.leading, leadingPadding)
    }
}

// MARK: - Specular Rim Border Gradient

struct SpecularBorderGradient: View {
    var cornerRadius: CGFloat = ScandiumTheme.cornerRadiusCard
    var lineWidth: CGFloat = ScandiumTheme.hairlinewidth

    init(cornerRadius: CGFloat = ScandiumTheme.cornerRadiusCard, lineWidth: CGFloat = ScandiumTheme.hairlinewidth) {
        self.cornerRadius = cornerRadius
        self.lineWidth = lineWidth
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(Color.white.opacity(0.12), lineWidth: lineWidth)
    }
}

// MARK: - Ambient Canvas Background (GPU-Optimized: pre-blurred via CoreImage on background thread)

// File-scope bounded LRU blur cache (max 30 entries, thread-safe via barrier writes)
private final class BlurredArtworkLRUCache {
    static let shared = BlurredArtworkLRUCache()

    private let maxEntries = 30
    private var storage = [String: UIImage]()
    private var order = [String]()
    private let queue = DispatchQueue(label: "com.scandium.blurCache", attributes: .concurrent)

    func get(_ key: String) -> UIImage? {
        var result: UIImage?
        queue.sync(flags: .barrier) {
            if let img = storage[key] {
                result = img
                if let idx = order.firstIndex(of: key) {
                    order.remove(at: idx)
                    order.append(key)
                }
            }
        }
        return result
    }

    func set(_ image: UIImage, for key: String) {
        queue.async(flags: .barrier) {
            self.storage[key] = image
            if let idx = self.order.firstIndex(of: key) {
                self.order.remove(at: idx)
            }
            self.order.append(key)
            while self.order.count > self.maxEntries {
                let evictedKey = self.order.removeFirst()
                self.storage.removeValue(forKey: evictedKey)
            }
        }
    }
}

struct AmbientCanvasBackground: View {
    let artworkURL: URL?
    @ObservedObject private var settings = AppSettings.shared
    @State private var blurredImage: UIImage?
    @State private var loadTask: Task<Void, Never>?

    init(artworkURL: URL? = nil) {
        self.artworkURL = artworkURL
    }

    var body: some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width)
            let h = max(1, geo.size.height)

            ZStack {
                ScandiumTheme.bgPrimary
                if let image = blurredImage {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: w, height: h)
                        .clipped()
                        .opacity(0.35)
                }
            }
            .frame(width: w, height: h)
            .clipped()
            .contentShape(Rectangle())
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .onAppear { loadBlurredArtwork(artworkURL) }
        .onChange(of: artworkURL?.absoluteString) { _ in loadBlurredArtwork(artworkURL) }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }

    private func loadBlurredArtwork(_ url: URL?) {
        loadTask?.cancel()
        loadTask = nil

        guard let url = url else {
            withAnimation(.easeOut(duration: 0.3)) { self.blurredImage = nil }
            return
        }
        let key = url.absoluteString

        // 1. Check bounded LRU blur cache first
        if let cached = BlurredArtworkLRUCache.shared.get(key) {
            withAnimation(.easeInOut(duration: 0.35)) { self.blurredImage = cached }
            return
        }

        // 2. Fetch raw image (cache or network) and blur off main thread
        loadTask = Task {
            var sourceImage = await ImageCacheStore.shared.get(for: url)
            if Task.isCancelled { return }

            if sourceImage == nil {
                var request = URLRequest(url: url)
                request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
                request.timeoutInterval = 10

                if let (data, _) = try? await URLSession.shared.data(for: request),
                   !Task.isCancelled,
                   let downloaded = UIImage(data: data) {
                    ImageCacheStore.shared.set(downloaded, for: url)
                    sourceImage = downloaded
                }
            }

            guard !Task.isCancelled, let source = sourceImage else { return }

            let blurred: UIImage? = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: Self.createBlurredImage(from: source))
                }
            }

            guard !Task.isCancelled, let blurredImage = blurred else { return }
            BlurredArtworkLRUCache.shared.set(blurredImage, for: key)

            await MainActor.run {
                guard !Task.isCancelled, self.artworkURL?.absoluteString == key else { return }
                withAnimation(.easeInOut(duration: 0.35)) { self.blurredImage = blurredImage }
            }
        }
    }

    private static let sharedCIContext = CIContext(options: [.useSoftwareRenderer: false])

    // Uses CoreImage CIGaussianBlur — runs on background thread, GPU-accelerated
    private static func createBlurredImage(from source: UIImage) -> UIImage? {
        // Downsample to 48×48 before blurring for GPU efficiency
        let targetSize = CGSize(width: 48, height: 48)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let smallImage = renderer.image { _ in
            source.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        guard let cgImage = smallImage.cgImage else { return nil }

        let ciImage = CIImage(cgImage: cgImage)
        guard let blurFilter = CIFilter(name: "CIGaussianBlur") else { return nil }
        blurFilter.setValue(ciImage, forKey: kCIInputImageKey)
        blurFilter.setValue(12.0, forKey: kCIInputRadiusKey)
        guard let outputImage = blurFilter.outputImage,
              let cgOutput = Self.sharedCIContext.createCGImage(outputImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgOutput)
    }
}

// MARK: - Cached Async Image (Strictly Locked Frames & Clipped)

struct CachedAsyncImage<Placeholder: View>: View {
    let url: URL?
    let width: CGFloat?
    let height: CGFloat?
    let cornerRadius: CGFloat
    let contentMode: ContentMode
    let placeholder: () -> Placeholder

    @State private var loadedImage: UIImage?
    @State private var isLoading = false
    @State private var loadTask: Task<Void, Never>?

    init(
        url: URL?,
        width: CGFloat? = nil,
        height: CGFloat? = nil,
        cornerRadius: CGFloat = 0,
        contentMode: ContentMode = .fill,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
        self.contentMode = contentMode
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .frame(width: width, height: height)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                placeholder()
                    .frame(width: width, height: height)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        }
        .onAppear {
            if loadedImage == nil {
                loadImage()
            }
        }
        .onChange(of: url?.absoluteString) { _ in
            loadTask?.cancel()
            loadTask = nil
            loadedImage = nil
            isLoading = false
            loadImage()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
            isLoading = false
        }
    }

    private func loadImage() {
        loadTask?.cancel()
        loadTask = nil

        guard let targetURL = url else {
            loadedImage = nil
            isLoading = false
            return
        }
        let targetKey = targetURL.absoluteString

        // Fast synchronous memory cache check
        if let cached = ImageCacheStore.shared.getFromMemory(for: targetURL) {
            self.loadedImage = cached
            self.isLoading = false
            return
        }

        isLoading = true
        loadTask = Task {
            // Check disk cache on background queue
            if let diskCached = await ImageCacheStore.shared.get(for: targetURL) {
                await MainActor.run {
                    guard !Task.isCancelled, self.url?.absoluteString == targetKey else { return }
                    self.loadedImage = diskCached
                    self.isLoading = false
                }
                return
            }

            guard !Task.isCancelled else { return }

            // Download with user-agent and timeout
            var request = URLRequest(url: targetURL)
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 10

            var fetchedImage: UIImage? = nil
            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                if !Task.isCancelled {
                    fetchedImage = UIImage(data: data)
                }
            } catch {
                if !Task.isCancelled {
                    // Quick retry once on non-cancelled error
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    if !Task.isCancelled, let (retryData, _) = try? await URLSession.shared.data(for: request) {
                        fetchedImage = UIImage(data: retryData)
                    }
                }
            }

            guard !Task.isCancelled else { return }

            if let img = fetchedImage {
                ImageCacheStore.shared.set(img, for: targetURL)
                await MainActor.run {
                    guard !Task.isCancelled, self.url?.absoluteString == targetKey else { return }
                    withAnimation(.easeIn(duration: 0.2)) {
                        self.loadedImage = img
                    }
                    self.isLoading = false
                }
            } else {
                await MainActor.run {
                    guard !Task.isCancelled, self.url?.absoluteString == targetKey else { return }
                    self.isLoading = false
                }
            }
        }
    }
}

// Convenience init for CachedAsyncImage with default placeholder
extension CachedAsyncImage where Placeholder == ShimmerView {
    init(
        url: URL?,
        width: CGFloat? = nil,
        height: CGFloat? = nil,
        cornerRadius: CGFloat = 0,
        contentMode: ContentMode = .fill
    ) {
        self.init(
            url: url,
            width: width,
            height: height,
            cornerRadius: cornerRadius,
            contentMode: contentMode,
            placeholder: { ShimmerView() }
        )
    }
}

// MARK: - Image Cache (Memory + Disk)

final class ImageCacheStore {
    static let shared = ImageCacheStore()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let diskCacheDir: URL?
    private let ioQueue = DispatchQueue(label: "com.scandium.imageCache.io", qos: .utility)
    private var writesSinceLastEviction: Int = 0
    private var lastEvictionDate: Date = .distantPast
    private static let evictionWriteThreshold: Int = 25
    private static let evictionMinInterval: TimeInterval = 60

    private init() {
        memoryCache.countLimit = 300
        memoryCache.totalCostLimit = 150 * 1024 * 1024

        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        if let base = paths.first {
            let dir = base.appendingPathComponent("scandium_image_cache", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.diskCacheDir = dir
        } else {
            self.diskCacheDir = nil
        }
    }

    private func diskKey(for url: URL) -> String {
        let bytes = url.absoluteString.utf8
        var djb2: UInt64 = 5381
        var fnv: UInt64 = 14695981039346656037
        for b in bytes {
            djb2 = ((djb2 << 5) &+ djb2) &+ UInt64(b)
            fnv ^= UInt64(b)
            fnv = fnv &* 1099511628211
        }
        return String(format: "img_%016llx%016llx.jpg", djb2, fnv)
    }

    func getFromMemory(for url: URL) -> UIImage? {
        let key = url.absoluteString as NSString
        return memoryCache.object(forKey: key)
    }

    func get(for url: URL) async -> UIImage? {
        let key = url.absoluteString as NSString
        if let mem = memoryCache.object(forKey: key) {
            return mem
        }

        guard let dir = diskCacheDir else { return nil }
        let fileURL = dir.appendingPathComponent(diskKey(for: url))
        let loaded: (UIImage, Int)? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                if let data = try? Data(contentsOf: fileURL), let diskImg = UIImage(data: data) {
                    continuation.resume(returning: (diskImg, data.count))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
        if let (diskImg, cost) = loaded {
            memoryCache.setObject(diskImg, forKey: key, cost: cost)
            ioQueue.async {
                try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
            }
            return diskImg
        }
        return nil
    }

    func set(_ image: UIImage, for url: URL) {
        let key = url.absoluteString as NSString
        let cost = Int(image.size.width * image.scale * image.size.height * image.scale * 4)
        memoryCache.setObject(image, forKey: key, cost: cost)

        if let dir = diskCacheDir {
            let fileURL = dir.appendingPathComponent(diskKey(for: url))
            ioQueue.async { [weak self] in
                guard let self = self else { return }
                if let data = image.jpegData(compressionQuality: 0.85) {
                    try? data.write(to: fileURL, options: .atomic)
                    self.writesSinceLastEviction += 1
                    let now = Date()
                    if self.writesSinceLastEviction >= Self.evictionWriteThreshold ||
                       now.timeIntervalSince(self.lastEvictionDate) >= Self.evictionMinInterval {
                        self.writesSinceLastEviction = 0
                        self.lastEvictionDate = now
                        self._evictOnIOQueue(in: dir)
                    }
                }
            }
        }
    }

    // MARK: - LRU Disk Cache Eviction

    private static let maxDiskCacheBytes: Int64 = 250 * 1024 * 1024 // 250 MB
    private static let targetDiskCacheBytes: Int64 = Int64(Double(maxDiskCacheBytes) * 0.8) // 200 MB

    func evictIfNeeded() {
        guard let dir = diskCacheDir else { return }
        ioQueue.async { [weak self] in
            self?._evictOnIOQueue(in: dir)
        }
    }

    private func _evictOnIOQueue(in dir: URL) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .contentAccessDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        // Calculate total size
        var totalSize: Int64 = 0
        var fileInfos: [(url: URL, size: Int64, recencyDate: Date)] = []
        for fileURL in files {
            guard let attrs = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .contentAccessDateKey]),
                  let size = attrs.fileSize else { continue }
            let recencyDate = attrs.contentModificationDate ?? attrs.contentAccessDate ?? Date.distantPast
            let s = Int64(size)
            totalSize += s
            fileInfos.append((url: fileURL, size: s, recencyDate: recencyDate))
        }

        guard totalSize > ImageCacheStore.maxDiskCacheBytes else { return }

        fileInfos.sort { $0.recencyDate < $1.recencyDate }

        for info in fileInfos {
            guard totalSize > ImageCacheStore.targetDiskCacheBytes else { break }
            try? fm.removeItem(at: info.url)
            totalSize -= info.size
        }
    }

    func clear() {
        memoryCache.removeAllObjects()
        guard let dir = diskCacheDir else { return }
        ioQueue.async { [weak self] in
            self?.writesSinceLastEviction = 0
            if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                for f in files {
                    try? FileManager.default.removeItem(at: f)
                }
            }
        }
    }
}

// MARK: - Shimmer Placeholder

struct ShimmerView: View {
    @State private var phase: CGFloat = 0

    init() {}

    var body: some View {
        ZStack {
            ScandiumTheme.surfaceDark
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color.white.opacity(0.02), location: max(0, phase - 0.25)),
                    .init(color: Color.white.opacity(0.08), location: phase),
                    .init(color: Color.white.opacity(0.02), location: min(1, phase + 0.25))
                ]),
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        .onAppear {
            withAnimation(
                .linear(duration: 1.5)
                .repeatForever(autoreverses: false)
            ) {
                phase = 1.2
            }
        }
    }
}

// MARK: - Threads Flat Row Item (Meta Threads Style)

struct ThreadsRow<TrailingContent: View>: View {
    @ObservedObject private var settings = AppSettings.shared
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String?
    let showDivider: Bool
    let trailingContent: TrailingContent

    init(
        icon: String,
        iconColor: Color = ScandiumTheme.textPrimary,
        title: String,
        subtitle: String? = nil,
        showDivider: Bool = true,
        @ViewBuilder trailingContent: () -> TrailingContent
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.showDivider = showDivider
        self.trailingContent = trailingContent()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .regular))
                    .foregroundColor(iconColor)
                    .frame(width: 24, height: 24, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(ScandiumTheme.textPrimary)
                        .lineLimit(1)
                    if let subtitle = subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundColor(ScandiumTheme.subtext)
                            .lineLimit(1)
                    }
                }

                Spacer()

                trailingContent
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())

            if showDivider {
                HairlineDivider(leadingPadding: 56)
            }
        }
    }
}

extension ThreadsRow where TrailingContent == AnyView {
    init(
        icon: String,
        iconColor: Color = ScandiumTheme.textPrimary,
        title: String,
        subtitle: String? = nil,
        showDivider: Bool = true
    ) {
        self.init(
            icon: icon,
            iconColor: iconColor,
            title: title,
            subtitle: subtitle,
            showDivider: showDivider,
            trailingContent: {
                AnyView(
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ScandiumTheme.subtext.opacity(0.6))
                )
            }
        )
    }
}

// MARK: - Common View Extensions

extension View {
    func lockedFrame(width: CGFloat, height: CGFloat, cornerRadius: CGFloat = 0) -> some View {
        self
            .frame(width: width, height: height)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    func threadsCardStyle() -> some View {
        self
            .background(ScandiumTheme.surfaceDark)
            .clipShape(RoundedRectangle(cornerRadius: ScandiumTheme.cornerRadiusLarge, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ScandiumTheme.cornerRadiusLarge, style: .continuous)
                    .stroke(ScandiumTheme.hairline, lineWidth: ScandiumTheme.hairlinewidth)
            )
    }
}
