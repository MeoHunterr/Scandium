// LiquidGlassModifier.swift — Design tokens and liquid glass modifiers for Scandium
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import SwiftUI

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

// MARK: - Ambient Canvas Background (True OLED Black + Subtle Soft Artwork Glow)

struct AmbientCanvasBackground: View {
    let artworkURL: URL?
    @ObservedObject private var settings = AppSettings.shared
    @State private var loadedImage: UIImage?

    init(artworkURL: URL? = nil) {
        self.artworkURL = artworkURL
    }

    var body: some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width)
            let h = max(1, geo.size.height)

            ZStack {
                // True OLED Black base
                ScandiumTheme.bgPrimary

                // Subtle, non-intrusive soft glow from artwork when playing.
                // Fixed dimensions and strictly clipped to prevent expanding parent containers.
                if let image = loadedImage {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: w, height: h)
                        .clipped()
                        .blur(radius: 60)
                        .opacity(0.18)
                }
            }
            .frame(width: w, height: h)
            .clipped()
            .contentShape(Rectangle())
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .onAppear {
            loadArtwork(artworkURL)
        }
        .onChange(of: artworkURL?.absoluteString) { _ in
            loadArtwork(artworkURL)
        }
    }

    private func loadArtwork(_ url: URL?) {
        guard let url = url else {
            withAnimation(.easeOut(duration: 0.3)) {
                self.loadedImage = nil
            }
            return
        }

        if let cached = ImageCacheStore.shared.get(for: url) {
            withAnimation(.easeInOut(duration: 0.35)) {
                self.loadedImage = cached
            }
            return
        }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = UIImage(data: data) {
                    ImageCacheStore.shared.set(image, for: url)
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            self.loadedImage = image
                        }
                    }
                }
            } catch {
                // Silently fallback to pure black
            }
        }
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
                    .onAppear {
                        loadImage()
                    }
            }
        }
        .onAppear {
            if loadedImage == nil {
                loadImage()
            }
        }
        .onChange(of: url?.absoluteString) { _ in
            loadedImage = nil
            loadImage()
        }
    }

    private func loadImage() {
        guard let url = url, !isLoading else { return }

        if let cached = ImageCacheStore.shared.get(for: url) {
            self.loadedImage = cached
            return
        }

        isLoading = true
        Task {
            // Check memory cache first
            if let cached = ImageCacheStore.shared.get(for: url) {
                await MainActor.run {
                    self.loadedImage = cached
                    self.isLoading = false
                }
                return
            }

            // Download with user-agent and timeout
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 10

            var fetchedImage: UIImage? = nil
            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                fetchedImage = UIImage(data: data)
            } catch {
                // Quick retry once on error
                try? await Task.sleep(nanoseconds: 500_000_000)
                if let (retryData, _) = try? await URLSession.shared.data(for: request) {
                    fetchedImage = UIImage(data: retryData)
                }
            }

            if let img = fetchedImage {
                ImageCacheStore.shared.set(img, for: url)
                await MainActor.run {
                    withAnimation(.easeIn(duration: 0.2)) {
                        self.loadedImage = img
                    }
                    self.isLoading = false
                }
            } else {
                await MainActor.run {
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
        let raw = url.absoluteString
        let hash = raw.utf8.reduce(5381) { ($0 << 5) &+ $0 &+ Int($1) }
        return "img_\(abs(hash)).jpg"
    }

    func get(for url: URL) -> UIImage? {
        let key = url.absoluteString as NSString
        if let mem = memoryCache.object(forKey: key) {
            return mem
        }

        guard let dir = diskCacheDir else { return nil }
        let fileURL = dir.appendingPathComponent(diskKey(for: url))
        if let data = try? Data(contentsOf: fileURL), let diskImg = UIImage(data: data) {
            memoryCache.setObject(diskImg, forKey: key, cost: data.count)
            return diskImg
        }
        return nil
    }

    func set(_ image: UIImage, for url: URL) {
        let key = url.absoluteString as NSString
        let data = image.jpegData(compressionQuality: 0.85)
        let cost = data?.count ?? 0
        memoryCache.setObject(image, forKey: key, cost: cost)

        if let data = data, let dir = diskCacheDir {
            let fileURL = dir.appendingPathComponent(diskKey(for: url))
            DispatchQueue.global(qos: .utility).async {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }

    func clear() {
        memoryCache.removeAllObjects()
        if let dir = diskCacheDir,
           let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for f in files {
                try? FileManager.default.removeItem(at: f)
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
