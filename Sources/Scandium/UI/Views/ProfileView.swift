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

                // 1. Account Sync Section
                accountSection

                // 2. Service Token / Client ID Section
                clientIDSection

                // 3. Storage & Cache Section (Live calculation & distribution bar)
                storageSection

                // 4. Audio Quality Section
                audioQualitySection

                // 5. About Section
                aboutSection

                // 6. FOSS Open Source Disclaimer
                fossDisclaimerView
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
                        showToast(settings.loc("Đồng bộ tài khoản thành công!", "Account synchronized successfully!"))
                    }
                },
                onProfileSubmitted: { profile in
                    Task {
                        await auth.handleProfileURL(profile)
                        showToast(settings.loc("Đã kết nối tài khoản qua link hồ sơ!", "Connected account via profile link!"))
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
                title: Text(settings.loc("Dọn sạch cache tạm?", "Clear temporary cache?")),
                message: Text(settings.loc("Hệ thống sẽ xóa ảnh bìa và file âm thanh tạm. Bài hát đã thích và thiết lập của bạn sẽ được giữ nguyên.", "Cached artwork and temporary audio files will be deleted. Your liked tracks and settings will be preserved.")),
                primaryButton: .destructive(Text(settings.loc("Dọn sạch ngay", "Clear Now"))) {
                    storage.clearCache()
                    ImageCacheStore.shared.clear()
                    showToast(settings.loc("Đã dọn sạch cache tạm!", "Temporary cache cleared!"))
                },
                secondaryButton: .cancel(Text(settings.loc("Hủy", "Cancel")))
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
                    Text(user.fullName ?? settings.loc("Tài khoản dịch vụ (SoundCloud)", "Service Account (SoundCloud)"))
                        .font(.system(size: 12))
                        .foregroundColor(ScandiumTheme.subtext)
                } else {
                    HStack(spacing: 6) {
                        Text("Scandium [21 Sc]")
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
                    Text(settings.loc("Tác giả: MeoHunter • GNU GPL v3.0 (Open Source)", "Author: MeoHunter • GNU GPL v3.0 (Open Source)"))
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
            sectionHeader(title: settings.loc("Đồng bộ tài khoản (SoundCloud)", "Account Sync (SoundCloud)"))

            VStack(spacing: 0) {
                if !auth.isAuthenticated {
                    // Sign in Web
                    Button(action: { showWebLogin = true }) {
                        ThreadsRow(
                            icon: "globe",
                            iconColor: ScandiumTheme.spotifyGreen,
                            title: settings.loc("Đồng bộ tài khoản SoundCloud", "Sync SoundCloud Account"),
                            subtitle: settings.loc("Dán link hồ sơ công khai hoặc sử dụng Token dịch vụ", "Paste public profile link or use Service Token")
                        )
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Manual token / Profile link
                    Button(action: { showManualAuthModal = true }) {
                        ThreadsRow(
                            icon: "link",
                            title: settings.loc("Nhập Token dịch vụ hoặc Link hồ sơ", "Enter Service Token or Profile Link"),
                            subtitle: settings.loc("Dán mã OAuth token hoặc đường dẫn soundcloud.com/user", "Paste OAuth token or soundcloud.com/user link"),
                            showDivider: false
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    // Sync library
                    Button(action: {
                        Task {
                            await auth.syncLibrary()
                            showToast(settings.loc("Đã đồng bộ bài hát từ tài khoản!", "Synced library from account!"))
                        }
                    }) {
                        ThreadsRow(
                            icon: "arrow.triangle.2.circlepath",
                            iconColor: ScandiumTheme.spotifyGreen,
                            title: settings.loc("Đồng bộ thư viện tài khoản", "Sync Account Library"),
                            subtitle: "\(auth.userLikedTracks.count) \(settings.loc("bài hát", "tracks")) • \(auth.userPlaylists.count) playlist"
                        )
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Sign out
                    Button(action: {
                        auth.logout()
                        showToast(settings.loc("Đã hủy đồng bộ tài khoản", "Account disconnected"))
                    }) {
                        ThreadsRow(
                            icon: "rectangle.portrait.and.arrow.right",
                            iconColor: Color.red,
                            title: settings.loc("Hủy đồng bộ tài khoản", "Disconnect Account"),
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
            sectionHeader(title: settings.loc("Service Token / Client ID (SoundCloud)", "Service Token / Client ID (SoundCloud)"))

            VStack(spacing: 0) {
                // Status Row
                ThreadsRow(
                    icon: "key",
                    iconColor: scraper.lastError == nil ? ScandiumTheme.spotifyGreen : Color.orange,
                    title: scraper.lastError == nil ? settings.loc("Trạng thái Token: Đang kích hoạt", "Token Status: Active") : settings.loc("Trạng thái Token: Cần kiểm tra", "Token Status: Attention Needed")
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
                                showToast(settings.loc("Làm mới Client ID thành công!", "Client ID refreshed successfully!"))
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
                        title: settings.loc("Tự động làm mới Client ID", "Auto-Refresh Client ID"),
                        subtitle: settings.loc("Quét mã JavaScript mới nhất từ dịch vụ mạng", "Scan latest JavaScript bundle from network service")
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
                        subtitle: settings.loc("Cách lấy mã 32 ký tự trên máy tính qua DevTools", "Extract 32-char key on PC via DevTools"),
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
            sectionHeader(title: settings.loc("Bộ nhớ đệm & Dữ liệu", "Storage & Cache"))

            VStack(spacing: 14) {
                // Visual Distribution Bar
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(settings.loc("Bộ nhớ đệm & Dữ liệu", "Storage & Cache"))
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
                        Text(settings.loc("Dọn sạch cache tạm", "Clear Temporary Cache"))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(ScandiumTheme.textPrimary)
                        Spacer()
                        Text(settings.loc("Dọn dẹp", "Clean"))
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
            sectionHeader(title: settings.loc("Chất lượng âm thanh", "Audio Quality"))

            VStack(spacing: 0) {
                ThreadsRow(
                    icon: "waveform",
                    title: settings.loc("Chất lượng âm thanh", "Audio Quality"),
                    subtitle: settings.loc("128 kbps MP3 / 256 kbps AAC khi có sẵn", "128 kbps MP3 / 256 kbps AAC when available"),
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
            sectionHeader(title: settings.loc("Thông tin ứng dụng", "About Scandium"))

            VStack(spacing: 0) {
                ThreadsRow(
                    icon: "app.badge",
                    title: settings.loc("Tên ứng dụng", "Application"),
                    showDivider: true
                ) {
                    Text("Scandium [21 Sc]")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(ScandiumTheme.textPrimary)
                }

                ThreadsRow(
                    icon: "info.circle",
                    title: settings.loc("Phiên bản", "Version"),
                    showDivider: true
                ) {
                    Text("1.2.0")
                        .font(.system(size: 13))
                        .foregroundColor(ScandiumTheme.subtext)
                }

                ThreadsRow(
                    icon: "doc.text",
                    title: settings.loc("Giấy phép", "License"),
                    showDivider: true
                ) {
                    Text("GNU GPL v3.0 (Open Source)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(ScandiumTheme.spotifyGreen)
                }

                ThreadsRow(
                    icon: "chevron.left.forwardslash.chevron.right",
                    title: settings.loc("Mã nguồn", "Source Code"),
                    showDivider: true
                ) {
                    Text("github.com/MeoHunterr/Scandium")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(ScandiumTheme.subtext)
                }

                ThreadsRow(
                    icon: "person.circle",
                    title: settings.loc("Tác giả", "Author"),
                    showDivider: true
                ) {
                    Text("MeoHunter")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(ScandiumTheme.textPrimary)
                }

                ThreadsRow(
                    icon: "network",
                    title: settings.loc("Loại ứng dụng", "Client Type"),
                    showDivider: false
                ) {
                    Text(settings.loc("Client bên thứ ba", "Unofficial Client"))
                        .font(.system(size: 12))
                        .foregroundColor(ScandiumTheme.subtext)
                }
            }
            .background(ScandiumTheme.surfaceDark)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - FOSS Disclaimer View

    private var fossDisclaimerView: some View {
        Text(settings.loc(
            "Scandium là phần mềm mã nguồn mở độc lập, không liên kết hay được chứng thực bởi SoundCloud Global Limited & Co. KG.",
            "Scandium is an independent open-source software, not affiliated with or endorsed by SoundCloud Global Limited & Co. KG."
        ))
        .font(.system(size: 11))
        .foregroundColor(ScandiumTheme.subtext.opacity(0.75))
        .multilineTextAlignment(.center)
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    // MARK: - Section Header

    private func sectionHeader(title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(ScandiumTheme.subtext)
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
                    Text(settings.loc(
                        "Nhập mã OAuth Token hoặc dán đường dẫn trang cá nhân công khai (ví dụ: soundcloud.com/user).",
                        "Enter OAuth Token or paste public profile link (e.g. soundcloud.com/user)."
                    ))
                    .font(.system(size: 14))
                    .foregroundColor(ScandiumTheme.subtext)

                    TextField(settings.loc("OAuth Token hoặc link hồ sơ...", "OAuth Token or profile link..."), text: $manualAuthInput)
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
                            showToast(settings.loc("Đã cập nhật thông tin tài khoản!", "Account info updated!"))
                        }
                    }) {
                        Text(settings.loc("Lưu & Kết nối", "Save & Connect"))
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
                            Text(settings.loc("Xem hướng dẫn lấy OAuth Token trên PC & iOS", "Guide to obtain OAuth Token on PC & iOS"))
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(ScandiumTheme.subtext)
                        .padding(.top, 4)
                    }

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle(settings.loc("Đồng bộ tài khoản", "Account Sync"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(settings.loc("Đóng", "Close")) {
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
                    Text(settings.loc(
                        "Nhập chuỗi 32 ký tự Service Token / Client ID để sử dụng riêng cho app.",
                        "Enter 32-character Service Token / Client ID for the app."
                    ))
                    .font(.system(size: 14))
                    .foregroundColor(ScandiumTheme.subtext)

                    TextField(settings.loc("Chuỗi 32 ký tự...", "32-character key..."), text: $manualClientIDInput)
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundColor(ScandiumTheme.textPrimary)
                        .padding(12)
                        .background(ScandiumTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    HStack(spacing: 12) {
                        Button(action: {
                            scraper.setManualClientID(manualClientIDInput)
                            showManualIDModal = false
                            showToast(settings.loc("Đã lưu Client ID thủ công!", "Manual Client ID saved!"))
                        }) {
                            Text(settings.loc("Lưu Client ID", "Save Client ID"))
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
                                showToast(settings.loc("Đã khôi phục Client ID tự động", "Auto Client ID restored"))
                            }) {
                                Text(settings.loc("Khôi phục", "Reset"))
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
            .navigationTitle(settings.loc("Cấu hình Client ID", "Client ID Configuration"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(settings.loc("Đóng", "Close")) {
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
                        Text(settings.loc("Hướng dẫn lấy Client ID thủ công", "Manual Client ID Guide"))
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(ScandiumTheme.textPrimary)

                        Text(settings.loc(
                            "Nếu việc đồng bộ tự động gặp sự cố do mạng chặn, bạn có thể tự lấy Client ID từ máy tính theo 4 bước sau:",
                            "If automatic sync is blocked by network, you can extract Client ID from PC in 4 simple steps:"
                        ))
                        .font(.system(size: 14))
                        .foregroundColor(ScandiumTheme.subtext)

                        VStack(spacing: 16) {
                            stepRow(
                                stepNumber: "1",
                                title: settings.loc("Mở SoundCloud trên trình duyệt máy tính", "Open SoundCloud in PC browser"),
                                desc: settings.loc("Dùng Chrome, Safari, Firefox hoặc Edge truy cập trang soundcloud.com.", "Use Chrome, Safari, Firefox or Edge to visit soundcloud.com.")
                            )

                            stepRow(
                                stepNumber: "2",
                                title: settings.loc("Mở DevTools & tab Network", "Open DevTools & Network tab"),
                                desc: settings.loc("Nhấn F12 (hoặc Ctrl+Shift+I / Cmd+Option+I), chuyển sang tab Network và gõ 'client_id' vào ô lọc.", "Press F12 (or Ctrl+Shift+I / Cmd+Option+I), switch to Network tab and filter 'client_id'.")
                            )

                            stepRow(
                                stepNumber: "3",
                                title: settings.loc("Bấm phát một bài nhạc bất kỳ", "Play any track"),
                                desc: settings.loc("Bấm Play bài hát bất kỳ trên web, các request gọi đến dịch vụ mạng (Public API) sẽ xuất hiện kèm tham số '?client_id=...'.", "Play any track on web; requests to public network API will appear with '?client_id=...'.")
                            )

                            stepRow(
                                stepNumber: "4",
                                title: settings.loc("Sao chép chuỗi 32 ký tự và dán vào Scandium", "Copy 32-character key and paste into Scandium"),
                                desc: settings.loc("Sao chép chuỗi 32 ký tự chữ và số, quay lại Scandium và dán vào mục 'Cấu hình Client ID thủ công'.", "Copy the 32-character alphanumeric key, return to Scandium and paste into manual configuration.")
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
                    Button(settings.loc("Đã hiểu", "Got it")) {
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
