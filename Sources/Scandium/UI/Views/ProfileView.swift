// ProfileView.swift — Settings & Profile screen (Threads by Meta flat list style)
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var scraper: ClientIDScraper
    @EnvironmentObject var library: LibraryManager
    @ObservedObject private var auth = SoundCloudAuthManager.shared
    @ObservedObject private var storage = StorageManager.shared
    @ObservedObject private var settings = AppSettings.shared

    @State private var showSettingsSheet: Bool = false
    @State private var showWebLogin: Bool = false
    @State private var showManualAuthModal: Bool = false
    @State private var showManualIDModal: Bool = false
    @State private var showGuideSheet: Bool = false
    @State private var showOAuthGuideSheet: Bool = false
    @State private var showClearCacheAlert: Bool = false
    @State private var showResetDataAlert: Bool = false
    @State private var toastMessage: String?

    @State private var manualAuthInput: String = ""
    @State private var manualClientIDInput: String = ""
    @State private var isRefreshingID: Bool = false

    init() {}

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 24) {
                // Header (Under Safe Area)
                headerView
                    .padding(.top, 8)

                // User / Author Card
                profileHeaderCard

                // 0. Settings & Preferences Card
                settingsSectionCard

                // 1. SoundCloud Account Section
                accountSection

                // 2. SoundCloud Client ID Section
                clientIDSection

                // 3. Storage & Cache Section (Live calculation & distribution bar)
                storageSection

                // 4. Audio Quality Section
                audioQualitySection

                // 5. About Section
                aboutSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 130)
        }
        .sheet(isPresented: $showWebLogin) {
            SoundCloudWebLoginView(
                isPresented: $showWebLogin,
                onTokenCaptured: { token in
                    Task {
                        await auth.handleOAuthToken(token)
                        showToast("Đã đăng nhập tài khoản SoundCloud thành công!")
                    }
                },
                onProfileSubmitted: { profile in
                    Task {
                        await auth.handleProfileURL(profile)
                        showToast("Đã kết nối tài khoản qua link profile!")
                    }
                }
            )
        }
        .sheet(isPresented: $showGuideSheet) {
            ClientIDGuideSheet()
        }
        .sheet(isPresented: $showManualAuthModal) {
            manualAuthSheet
        }
        .sheet(isPresented: $showManualIDModal) {
            manualClientIDSheet
        }
        .sheet(isPresented: $showOAuthGuideSheet) {
            OAuthTokenGuideSheet()
        }
        .sheet(isPresented: $showSettingsSheet) {
            SettingsSheetView()
        }
        .alert(isPresented: $showClearCacheAlert) {
            Alert(
                title: Text("Dọn sạch bộ nhớ đệm?"),
                message: Text("Hệ thống sẽ xóa ảnh bìa và file âm thanh tạm. Bài hát đã thích và thiết lập của bạn sẽ được giữ nguyên."),
                primaryButton: .destructive(Text("Xóa đệm")) {
                    storage.clearCache()
                    ImageCacheStore.shared.clear()
                    showToast("Đã giải phóng bộ nhớ đệm!")
                },
                secondaryButton: .cancel(Text("Hủy"))
            )
        }
        .overlay(
            toastOverlay
        )
        .onAppear {
            storage.refreshUsage()
            if let manual = scraper.manualClientID {
                manualClientIDInput = manual
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text(settings.loc("Cá nhân", "Profile"))
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(ScandiumTheme.textPrimary)

            Spacer()

            Button(action: { showSettingsSheet = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(ScandiumTheme.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(ScandiumTheme.surfaceElevated)
                    .clipShape(Circle())
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    // MARK: - Settings Section Card

    private var settingsSectionCard: some View {
        Button(action: { showSettingsSheet = true }) {
            ThreadsRow(
                icon: "gearshape.2.fill",
                iconColor: ScandiumTheme.spotifyGreen,
                title: settings.loc("Cài đặt & Tùy biến", "Settings & Appearance"),
                subtitle: settings.loc("Giao diện sáng/tối, ngôn ngữ, âm thanh", "Dark/light theme, language, audio playback"),
                showDivider: false
            ) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ScandiumTheme.subtext.opacity(0.6))
            }
        }
        .buttonStyle(PlainButtonStyle())
        .background(ScandiumTheme.surfaceDark)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Profile / Author Card

    private var profileHeaderCard: some View {
        HStack(spacing: 14) {
            if auth.isAuthenticated, let user = auth.currentUser {
                CachedAsyncImage(
                    url: user.highResAvatarURL,
                    width: 52,
                    height: 52,
                    cornerRadius: 26
                )
            } else {
                ZStack {
                    Circle()
                        .fill(ScandiumTheme.surfaceElevated)
                        .frame(width: 52, height: 52)
                    Text("21")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(ScandiumTheme.spotifyGreen)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                if auth.isAuthenticated, let user = auth.currentUser {
                    HStack(spacing: 6) {
                        Text(user.username)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(ScandiumTheme.textPrimary)
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12))
                            .foregroundColor(ScandiumTheme.spotifyGreen)
                    }
                    Text(user.fullName ?? settings.loc("Tài khoản SoundCloud", "SoundCloud Account"))
                        .font(.system(size: 12))
                        .foregroundColor(ScandiumTheme.subtext)
                } else {
                    HStack(spacing: 6) {
                        Text("Scandium")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(ScandiumTheme.textPrimary)
                        Text("iOS 15+")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(ScandiumTheme.spotifyGreen)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(ScandiumTheme.spotifyGreen.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    Text(settings.loc("Tác giả: MeoHunter • Mã nguồn mở", "Author: MeoHunter • Open Source"))
                        .font(.system(size: 12))
                        .foregroundColor(ScandiumTheme.subtext)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(ScandiumTheme.surfaceDark)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - 1. Account Section (Threads Style)

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(title: settings.loc("TÀI KHOẢN SOUNDCLOUD", "SOUNDCLOUD ACCOUNT"))

            VStack(spacing: 0) {
                if !auth.isAuthenticated {
                    // Sign in Web
                    Button(action: { showWebLogin = true }) {
                        ThreadsRow(
                            icon: "globe",
                            iconColor: ScandiumTheme.spotifyGreen,
                            title: settings.loc("Đăng nhập SoundCloud (Dễ)", "Sign in to SoundCloud (Easy)"),
                            subtitle: settings.loc("Dán link profile hoặc dùng OAuth token nâng cao", "Paste profile link or use advanced OAuth token")
                        )
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Manual token / Profile link
                    Button(action: { showManualAuthModal = true }) {
                        ThreadsRow(
                            icon: "link",
                            title: settings.loc("Nhập Token OAuth hoặc Link Profile", "Enter OAuth Token or Profile Link"),
                            subtitle: settings.loc("Dán mã oauth_token hoặc link soundcloud.com/user", "Paste oauth_token string or soundcloud.com/user link"),
                            showDivider: false
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    // Sync library
                    Button(action: {
                        Task {
                            await auth.syncLibrary()
                            showToast(settings.loc("Đã đồng bộ bài hát từ tài khoản SoundCloud!", "Synced library from SoundCloud!"))
                        }
                    }) {
                        ThreadsRow(
                            icon: "arrow.triangle.2.circlepath",
                            iconColor: ScandiumTheme.spotifyGreen,
                            title: settings.loc("Đồng bộ Thư viện SoundCloud", "Sync SoundCloud Library"),
                            subtitle: "\(auth.userLikedTracks.count) \(settings.loc("bài hát", "tracks")) • \(auth.userPlaylists.count) playlist"
                        )
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Sign out
                    Button(action: {
                        auth.logout()
                        showToast(settings.loc("Đã đăng xuất tài khoản", "Signed out successfully"))
                    }) {
                        ThreadsRow(
                            icon: "rectangle.portrait.and.arrow.right",
                            iconColor: Color.red,
                            title: settings.loc("Đăng xuất tài khoản", "Sign Out"),
                            showDivider: false
                        ) {
                            Text(settings.loc("Đăng xuất", "Sign Out"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.red)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .background(ScandiumTheme.surfaceDark)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - 2. Client ID Section

    private var clientIDSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(title: settings.loc("SOUNDCLOUD CLIENT ID", "SOUNDCLOUD CLIENT ID"))

            VStack(spacing: 0) {
                // Status Row
                ThreadsRow(
                    icon: "key",
                    iconColor: scraper.lastError == nil ? ScandiumTheme.spotifyGreen : Color.orange,
                    title: settings.loc("Trạng thái Client ID", "Client ID Status")
                ) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(scraper.lastError == nil ? ScandiumTheme.spotifyGreen : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(scraper.statusDescription)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(scraper.lastError == nil ? ScandiumTheme.spotifyGreen : Color.orange)
                    }
                }

                // Auto Refresh Scraper
                Button(action: {
                    guard !isRefreshingID else { return }
                    isRefreshingID = true
                    Task {
                        do {
                            try await scraper.refreshClientID()
                            await MainActor.run {
                                isRefreshingID = false
                                showToast(settings.loc("Cào mới Client ID thành công!", "Client ID scraped successfully!"))
                            }
                        } catch {
                            await MainActor.run {
                                isRefreshingID = false
                                showToast("Error: \(error.localizedDescription)")
                            }
                        }
                    }
                }) {
                    ThreadsRow(
                        icon: "arrow.clockwise",
                        title: settings.loc("Tự động cào lại Client ID", "Auto-Scrape Client ID"),
                        subtitle: settings.loc("Quét bundle JS mới nhất từ soundcloud.com", "Scan latest JS bundle from soundcloud.com")
                    ) {
                        if isRefreshingID {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: ScandiumTheme.textPrimary))
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(ScandiumTheme.subtext.opacity(0.6))
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())

                // Manual Input
                Button(action: { showManualIDModal = true }) {
                    ThreadsRow(
                        icon: "keyboard",
                        title: settings.loc("Cấu hình Client ID thủ công", "Manual Client ID Config"),
                        subtitle: scraper.manualClientID == nil ? settings.loc("Chưa thiết lập thủ công", "Not manually configured") : settings.loc("Đang sử dụng ID tùy chỉnh", "Using custom client ID")
                    )
                }
                .buttonStyle(PlainButtonStyle())

                // 4-Step Guide
                Button(action: { showGuideSheet = true }) {
                    ThreadsRow(
                        icon: "questionmark.circle",
                        title: settings.loc("Hướng dẫn lấy Client ID thủ công", "Manual Client ID Guide"),
                        subtitle: settings.loc("Cách lấy mã 32 ký tự trên máy tính qua DevTools", "Extract 32-char ID on PC via DevTools"),
                        showDivider: false
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .background(ScandiumTheme.surfaceDark)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - 3. Storage & Cache Section

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(title: settings.loc("DUNG LƯỢNG & BỘ NHỚ ĐỆM", "STORAGE & CACHE"))

            VStack(spacing: 14) {
                // Visual Distribution Bar
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(settings.loc("Tổng dung lượng chiếm dụng", "Total Storage Used"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(ScandiumTheme.textPrimary)
                        Spacer()
                        Text(storage.formattedTotal)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(ScandiumTheme.spotifyGreen)
                    }

                    // Stacked Distribution Bar
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            // Images (Spotify Green)
                            Rectangle()
                                .fill(ScandiumTheme.spotifyGreen)
                                .frame(width: max(2, geo.size.width * CGFloat(storage.imageRatio)))

                            // Audio & Network tmp (Blue)
                            Rectangle()
                                .fill(Color.blue)
                                .frame(width: max(2, geo.size.width * CGFloat(storage.audioRatio)))

                            // User data (Purple)
                            Rectangle()
                                .fill(Color.purple)
                                .frame(width: max(2, geo.size.width * CGFloat(storage.userRatio)))
                        }
                    }
                    .frame(height: 6)
                    .clipShape(Capsule())

                    // Legend
                    HStack(spacing: 14) {
                        legendItem(color: ScandiumTheme.spotifyGreen, label: "\(settings.loc("Ảnh bìa", "Artwork")): \(storage.formattedImageCache)")
                        legendItem(color: .blue, label: "\(settings.loc("Âm thanh tạm", "Audio Temp")): \(storage.formattedAudioNetwork)")
                        legendItem(color: .purple, label: "\(settings.loc("Dữ liệu", "Data")): \(storage.formattedUserData)")
                    }
                    .padding(.top, 2)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                HairlineDivider()

                // Clear Cache Button
                Button(action: { showClearCacheAlert = true }) {
                    HStack {
                        Image(systemName: "trash")
                            .font(.system(size: 16))
                            .foregroundColor(.orange)
                        Text(settings.loc("Xóa bộ nhớ đệm (Clear Cache)", "Clear Cache"))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(ScandiumTheme.textPrimary)
                        Spacer()
                        Text(settings.loc("Giải phóng", "Free up"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .background(ScandiumTheme.surfaceDark)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10, weight: .regular))
                .foregroundColor(ScandiumTheme.subtext)
        }
    }

    // MARK: - 4. Audio Quality Section

    private var audioQualitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(title: settings.loc("CHẤT LƯỢNG PHÁT TRỰC TUYẾN", "AUDIO STREAMING QUALITY"))

            VStack(spacing: 0) {
                ThreadsRow(
                    icon: "waveform",
                    title: settings.loc("Chất lượng âm thanh", "Audio Quality"),
                    subtitle: settings.loc("Ưu tiên HLS 256kbps khi có sẵn", "Prioritize 256kbps HLS when available"),
                    showDivider: false
                ) {
                    Text(settings.loc("Tự động (Cao)", "Auto (High)"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ScandiumTheme.spotifyGreen)
                }
            }
            .background(ScandiumTheme.surfaceDark)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - 5. About Section

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(title: settings.loc("THÔNG TIN ỨNG DỤNG", "ABOUT SCANDIUM"))

            VStack(spacing: 0) {
                ThreadsRow(
                    icon: "app.badge",
                    title: settings.loc("Phiên bản", "Version"),
                    showDivider: true
                ) {
                    Text("1.0.0 (Build 2026)")
                        .font(.system(size: 13))
                        .foregroundColor(ScandiumTheme.subtext)
                }

                ThreadsRow(
                    icon: "person.circle",
                    title: settings.loc("Tác giả", "Author"),
                    showDivider: false
                ) {
                    Text("MeoHunter")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(ScandiumTheme.textPrimary)
                }
            }
            .background(ScandiumTheme.surfaceDark)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Section Header

    private func sectionHeader(title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(ScandiumTheme.subtext)
            .tracking(1.2)
            .padding(.horizontal, 4)
            .padding(.top, 4)
    }

    // MARK: - Toast Overlay

    private var toastOverlay: some View {
        Group {
            if let message = toastMessage {
                VStack {
                    Spacer()
                    Text(message)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(red: 0.15, green: 0.15, blue: 0.15))
                        .clipShape(Capsule())
                        .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)
                        .padding(.bottom, 100)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    private func showToast(_ msg: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            toastMessage = msg
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeOut(duration: 0.25)) {
                if toastMessage == msg {
                    toastMessage = nil
                }
            }
        }
    }

    // MARK: - Manual Auth Sheet

    private var manualAuthSheet: some View {
        NavigationView {
            ZStack {
                ScandiumTheme.bgPrimary.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 20) {
                    Text("Nhập mã OAuth Token hoặc dán đường dẫn trang cá nhân SoundCloud (ví dụ: soundcloud.com/user).")
                        .font(.system(size: 14))
                        .foregroundColor(ScandiumTheme.subtext)

                    TextField("OAuth Token hoặc link Profile...", text: $manualAuthInput)
                        .font(.system(size: 15))
                        .foregroundColor(ScandiumTheme.textPrimary)
                        .padding(12)
                        .background(ScandiumTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Button(action: {
                        let input = manualAuthInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !input.isEmpty else { return }
                        showManualAuthModal = false

                        Task {
                            if input.contains("soundcloud.com") {
                                await auth.handleProfileURL(input)
                            } else {
                                await auth.handleOAuthToken(input)
                            }
                            showToast("Đã cập nhật thông tin tài khoản!")
                        }
                    }) {
                        Text("Lưu & Kết nối")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    Button(action: {
                        showOAuthGuideSheet = true
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "questionmark.circle")
                            Text("Xem hướng dẫn lấy OAuth Token trên PC & iOS")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(ScandiumTheme.subtext)
                        .padding(.top, 4)
                    }

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Tài khoản SoundCloud")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") {
                        showManualAuthModal = false
                    }
                    .foregroundColor(ScandiumTheme.textPrimary)
                }
            }
        }
        .preferredColorScheme(settings.themeMode.colorScheme)
    }

    // MARK: - Manual Client ID Sheet

    private var manualClientIDSheet: some View {
        NavigationView {
            ZStack {
                ScandiumTheme.bgPrimary.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 20) {
                    Text("Nhập chuỗi 32 ký tự Client ID đã lấy từ SoundCloud để sử dụng riêng cho app.")
                        .font(.system(size: 14))
                        .foregroundColor(ScandiumTheme.subtext)

                    TextField("Chuỗi 32 ký tự...", text: $manualClientIDInput)
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundColor(ScandiumTheme.textPrimary)
                        .padding(12)
                        .background(ScandiumTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    HStack(spacing: 12) {
                        Button(action: {
                            scraper.setManualClientID(manualClientIDInput)
                            showManualIDModal = false
                            showToast("Đã lưu Client ID thủ công!")
                        }) {
                            Text("Lưu Client ID")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(ScandiumTheme.spotifyGreen)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }

                        if scraper.manualClientID != nil {
                            Button(action: {
                                scraper.setManualClientID(nil)
                                manualClientIDInput = ""
                                showManualIDModal = false
                                showToast("Đã khôi phục Client ID tự động")
                            }) {
                                Text("Khôi phục")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(ScandiumTheme.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(ScandiumTheme.surfaceElevated)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Cấu hình Client ID")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") {
                        showManualIDModal = false
                    }
                    .foregroundColor(ScandiumTheme.textPrimary)
                }
            }
        }
        .preferredColorScheme(settings.themeMode.colorScheme)
    }
}

// MARK: - 4-Step Client ID Guide Sheet

struct ClientIDGuideSheet: View {
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.presentationMode) var presentationMode

    init() {}

    var body: some View {
        NavigationView {
            ZStack {
                ScandiumTheme.bgPrimary.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Hướng dẫn lấy Client ID thủ công")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(ScandiumTheme.textPrimary)

                        Text("Nếu việc cào tự động gặp trục trặc do mạng chặn, bạn có thể tự lấy Client ID từ máy tính theo 4 bước cực kỳ đơn giản sau:")
                            .font(.system(size: 14))
                            .foregroundColor(ScandiumTheme.subtext)

                        VStack(spacing: 16) {
                            stepRow(
                                stepNumber: "1",
                                title: "Mở SoundCloud trên trình duyệt máy tính",
                                desc: "Dùng Chrome, Safari, Firefox hoặc Edge truy cập trang soundcloud.com."
                            )

                            stepRow(
                                stepNumber: "2",
                                title: "Mở DevTools & tab Network",
                                desc: "Nhấn F12 (hoặc Ctrl+Shift+I / Cmd+Option+I), chuyển sang tab Network (Mạng) và gõ 'client_id' vào ô tìm kiếm/lọc."
                            )

                            stepRow(
                                stepNumber: "3",
                                title: "Bấm phát 1 bài nhạc bất kỳ",
                                desc: "Bấm Play bài hát bất kỳ trên web, các request gọi đến api-v2.soundcloud.com sẽ xuất hiện kèm tham số '?client_id=XXXXXX...'."
                            )

                            stepRow(
                                stepNumber: "4",
                                title: "Copy chuỗi 32 ký tự và dán vào Scandium",
                                desc: "Copy chuỗi 32 ký tự chữ và số đó, quay lại Scandium và dán vào mục 'Cấu hình Client ID thủ công'."
                            )
                        }

                        Spacer().frame(height: 20)
                    }
                    .padding(20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Đã hiểu") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(ScandiumTheme.spotifyGreen)
                    .font(.body.weight(.semibold))
                }
            }
        }
        .preferredColorScheme(settings.themeMode.colorScheme)
    }

    private func stepRow(stepNumber: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(ScandiumTheme.surfaceElevated)
                    .frame(width: 32, height: 32)
                Text(stepNumber)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(ScandiumTheme.spotifyGreen)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(ScandiumTheme.textPrimary)
                Text(desc)
                    .font(.system(size: 13))
                    .foregroundColor(ScandiumTheme.subtext)
                    .lineLimit(nil)
            }
        }
        .padding(14)
        .background(ScandiumTheme.surfaceDark)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
