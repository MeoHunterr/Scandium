// LiquidGlassModifier.swift — Design System: Threads (Meta) x Spotify (Natural, Dark, Sleek)
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import SwiftUI

// MARK: - Design Tokens (Threads x Spotify)

enum ScandiumTheme {
    // True OLED Black & Deep Charcoal Surfaces
    static let bgPrimary = Color.black                                      // #000000
    static let surfaceDark = Color(red: 0.071, green: 0.071, blue: 0.071)   // #121212
    static let surfaceCard = Color(red: 0.094, green: 0.094, blue: 0.094)   // #181818
    static let surfaceElevated = Color(red: 0.110, green: 0.110, blue: 0.118) // #1C1C1E

    // Hairline divider
    static let hairline = Color.white.opacity(0.08)
    static let hairlinewidth: CGFloat = 0.5

    // Accents
    static let spotifyGreen = Color(red: 29/255, green: 185/255, blue: 84/255) // #1DB954
    static let accentOrange = Color(red: 1.0, green: 0.35, blue: 0.12)
    static let subtext = Color(red: 0.655, green: 0.655, blue: 0.655)        // #A7A7A7
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
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = UIImage(data: data) {
                    ImageCacheStore.shared.set(image, for: url)
                    await MainActor.run {
                        withAnimation(.easeIn(duration: 0.2)) {
                            self.loadedImage = image
                        }
                        self.isLoading = false
                    }
                }
            } catch {
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

// MARK: - Image Cache (Thread-Safe NSCache)

final class ImageCacheStore {
    static let shared = ImageCacheStore()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 200
        cache.totalCostLimit = 120 * 1024 * 1024 // 120 MB
    }

    func get(for url: URL) -> UIImage? {
        cache.object(forKey: url.absoluteString as NSString)
    }

    func set(_ image: UIImage, for url: URL) {
        let cost = image.jpegData(compressionQuality: 0.9)?.count ?? 0
        cache.setObject(image, forKey: url.absoluteString as NSString, cost: cost)
    }

    func clear() {
        cache.removeAllObjects()
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
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String?
    let showDivider: Bool
    let trailingContent: TrailingContent

    init(
        icon: String,
        iconColor: Color = .white,
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
                        .foregroundColor(.white)
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
        iconColor: Color = .white,
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
