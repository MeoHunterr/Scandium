// MainContainerView.swift — Root container with 4-tab system, glass tab bar & floating mini-player
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import SwiftUI

enum ScandiumTab: Int, CaseIterable {
    case home = 0
    case search = 1
    case library = 2
    case profile = 3

    var title: String {
        switch self {
        case .home: return "Trang chủ"
        case .search: return "Tìm kiếm"
        case .library: return "Thư viện"
        case .profile: return "Cá nhân"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .search: return "magnifyingglass"
        case .library: return "books.vertical"
        case .profile: return "person"
        }
    }
}

struct MainContainerView: View {
    @EnvironmentObject var player: AudioPlayerEngine
    @EnvironmentObject var api: SoundCloudAPI
    @EnvironmentObject var scraper: ClientIDScraper
    @EnvironmentObject var library: LibraryManager

    @State private var selectedTab: ScandiumTab = .home
    @State private var showFullPlayer: Bool = false

    init() {}

    var body: some View {
        ZStack(alignment: .bottom) {
            // True OLED Black base background with subtle artwork blur
            AmbientCanvasBackground(
                artworkURL: player.currentTrack?.artworkURL(size: .t500x500)
            )

            // Current Tab Content (Properly constrained inside top Safe Area)
            tabContentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Floating Mini Player & Bottom TabBar (Seamless at bottom Home Indicator)
            VStack(spacing: 0) {
                if player.currentTrack != nil {
                    FloatingMiniPlayer(onTap: {
                        showFullPlayer = true
                    })
                }

                bottomTabBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .ignoresSafeArea(.container, edges: .bottom)
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showFullPlayer) {
            FullPlayerView()
                .environmentObject(player)
                .environmentObject(api)
                .environmentObject(scraper)
                .environmentObject(library)
        }
        .onAppear {
            initializeClientID()
            SoundCloudAuthManager.shared.setAPI(api)
        }
    }

    // MARK: - Tab Content Switcher

    @ViewBuilder
    private var tabContentView: some View {
        switch selectedTab {
        case .home:
            DiscoverView(
                onNavigateToSearch: {
                    selectedTab = .search
                },
                onNavigateToLibrary: {
                    selectedTab = .library
                }
            )
        case .search:
            SearchView()
        case .library:
            LibraryView()
        case .profile:
            ProfileView()
        }
    }

    // MARK: - Bottom TabBar (Seamless dark translucent with thin SF symbols)

    private var bottomTabBar: some View {
        VStack(spacing: 0) {
            // Hairline top border
            HairlineDivider()

            HStack(spacing: 0) {
                ForEach(ScandiumTab.allCases, id: \.rawValue) { tab in
                    Button(action: {
                        selectedTab = tab
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 20, weight: selectedTab == tab ? .semibold : .light))
                                .foregroundColor(selectedTab == tab ? .white : ScandiumTheme.subtext)

                            Text(tab.title)
                                .font(.system(size: 10, weight: selectedTab == tab ? .semibold : .regular))
                                .foregroundColor(selectedTab == tab ? .white : ScandiumTheme.subtext)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                        .padding(.bottom, 24) // Extra bottom padding for iPhone 11 Home indicator
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .background(
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                Rectangle()
                    .fill(Color.black.opacity(0.85))
            }
        )
    }

    // MARK: - Initialization

    private func initializeClientID() {
        Task {
            _ = try? await scraper.getClientID()
        }
    }
}
