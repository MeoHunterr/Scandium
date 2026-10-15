// SettingsSheetView.swift — Dedicated Settings & Preferences Modal
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import SwiftUI

struct SettingsSheetView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var storage = StorageManager.shared
    @Environment(\.presentationMode) var presentationMode

    @State private var showClearCacheAlert: Bool = false
    @State private var toastMessage: String?

    init() {}

    var body: some View {
        NavigationView {
            ZStack {
                ScandiumTheme.bgPrimary.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        // 1. Theme / Appearance Section
                        themeSection

                        // 2. Language Section
                        languageSection

                        // 3. Audio Streaming Quality
                        audioQualitySection

                        // 4. Playback Experience
                        playbackSection

                        // 5. Storage & Cache
                        storageSection

                        // 6. About Section (Without build platform)
                        aboutSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(settings.loc("Cài đặt", "Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Text(settings.loc("Xong", "Done"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(ScandiumTheme.spotifyGreen)
                    }
                }
            }
            .alert(isPresented: $showClearCacheAlert) {
                Alert(
                    title: Text(settings.loc("Xóa bộ nhớ đệm?", "Clear cache?")),
                    message: Text(settings.loc("Giải phóng ảnh bìa và file tạm thời. Danh sách bài hát của bạn sẽ được giữ nguyên.", "Frees cached artwork and temp audio. Your library is kept safe.")),
                    primaryButton: .destructive(Text(settings.loc("Xóa ngay", "Clear Now"))) {
                        storage.clearCache()
                        ImageCacheStore.shared.clear()
                        showToast(settings.loc("Đã dọn dẹp bộ nhớ đệm!", "Cache cleared successfully!"))
                    },
                    secondaryButton: .cancel(Text(settings.loc("Hủy", "Cancel")))
                )
            }
            .overlay(
                toastOverlay
            )
        }
        .preferredColorScheme(settings.themeMode.colorScheme)
    }

    // MARK: - 1. Theme Section

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: settings.loc("GIAO DIỆN & MÀU SẮC", "APPEARANCE & THEME"))

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    themeOptionButton(
                        mode: .dark,
                        icon: "moon.stars.fill",
                        title: settings.loc("Tối (OLED)", "Dark (OLED)")
                    )

                    themeOptionButton(
                        mode: .light,
                        icon: "sun.max.fill",
                        title: settings.loc("Sáng", "Light")
                    )

                    themeOptionButton(
                        mode: .system,
                        icon: "gearshape.fill",
                        title: settings.loc("Hệ thống", "System")
                    )
                }
                .padding(12)
            }
            .background(ScandiumTheme.surfaceDark)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func themeOptionButton(mode: AppThemeMode, icon: String, title: String) -> some View {
        let isSelected = settings.themeMode == mode

        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                settings.themeMode = mode
            }
        }) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(isSelected ? ScandiumTheme.spotifyGreen : ScandiumTheme.subtext)

                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? ScandiumTheme.textPrimary : ScandiumTheme.subtext)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isSelected ? ScandiumTheme.surfaceElevated : ScandiumTheme.surfaceElevated.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? ScandiumTheme.spotifyGreen : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - 2. Language Section

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: settings.loc("NGÔN NGỮ HIỂN THỊ", "DISPLAY LANGUAGE"))

            VStack(spacing: 0) {
                ForEach(AppLanguage.allCases) { lang in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            settings.language = lang
                        }
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(lang.displayName)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(ScandiumTheme.textPrimary)
                                Text(lang == .vietnamese ? "Giao diện Tiếng Việt" : "English Interface")
                                    .font(.system(size: 12))
                                    .foregroundColor(ScandiumTheme.subtext)
                            }

                            Spacer()

                            if settings.language == lang {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(ScandiumTheme.spotifyGreen)
                            } else {
                                Circle()
                                    .stroke(ScandiumTheme.subtext.opacity(0.4), lineWidth: 1.5)
                                    .frame(width: 18, height: 18)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(PlainButtonStyle())

                    if lang != AppLanguage.allCases.last {
                        HairlineDivider(leadingPadding: 16)
                    }
                }
            }
            .background(ScandiumTheme.surfaceDark)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - 3. Audio Streaming Quality

    private var audioQualitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: settings.loc("CHẤT LƯỢNG PHÁT TRỰC TUYẾN", "AUDIO STREAMING QUALITY"))

            VStack(spacing: 0) {
                ForEach(AudioQualitySetting.allCases) { q in
                    Button(action: {
                        settings.audioQuality = q
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(q.title(language: settings.language))
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(ScandiumTheme.textPrimary)
                            }

                            Spacer()

                            if settings.audioQuality == q {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(ScandiumTheme.spotifyGreen)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(PlainButtonStyle())

                    if q != AudioQualitySetting.allCases.last {
                        HairlineDivider(leadingPadding: 16)
                    }
                }
            }
            .background(ScandiumTheme.surfaceDark)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - 4. Playback Experience

    private var playbackSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: settings.loc("TRẢI NGHIỆM PHÁT NHẠC", "PLAYBACK EXPERIENCE"))

            VStack(spacing: 0) {
                // Autoplay
                Toggle(isOn: $settings.autoPlayRelated) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(settings.loc("Tự động phát bài liên quan", "Autoplay Related Tracks"))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(ScandiumTheme.textPrimary)
                        Text(settings.loc("Tiếp tục phát nhạc tương tự khi hết danh sách", "Keep playing similar tracks when queue ends"))
                            .font(.system(size: 12))
                            .foregroundColor(ScandiumTheme.subtext)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: ScandiumTheme.spotifyGreen))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                HairlineDivider(leadingPadding: 16)

                // Keep Awake
                Toggle(isOn: $settings.keepScreenAwake) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(settings.loc("Giữ màn hình luôn sáng", "Keep Screen Awake"))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(ScandiumTheme.textPrimary)
                        Text(settings.loc("Không khóa màn hình khi đang ở màn hình Full Player", "Prevent auto-lock during full player display"))
                            .font(.system(size: 12))
                            .foregroundColor(ScandiumTheme.subtext)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: ScandiumTheme.spotifyGreen))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(ScandiumTheme.surfaceDark)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - 5. Storage & Cache

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: settings.loc("BỘ NHỚ & DỮ LIỆU ĐỆM", "STORAGE & CACHE"))

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(settings.loc("Dung lượng bộ nhớ đệm", "Current Cache Usage"))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(ScandiumTheme.textPrimary)
                        Text(storage.formattedTotal)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(ScandiumTheme.spotifyGreen)
                    }

                    Spacer()

                    Button(action: {
                        showClearCacheAlert = true
                    }) {
                        Text(settings.loc("Xóa đệm", "Clear"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.orange.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(ScandiumTheme.surfaceDark)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - 6. About Section (No Build Platform)

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: settings.loc("THÔNG TIN", "ABOUT"))

            VStack(spacing: 0) {
                // App Emblem Row
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(ScandiumTheme.surfaceElevated)
                            .frame(width: 44, height: 44)
                        Text("21")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(ScandiumTheme.spotifyGreen)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scandium")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(ScandiumTheme.textPrimary)
                        Text("SoundCloud Music Client • iOS 15+")
                            .font(.system(size: 12))
                            .foregroundColor(ScandiumTheme.subtext)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                HairlineDivider(leadingPadding: 16)

                // Version
                HStack {
                    Text(settings.loc("Phiên bản", "Version"))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(ScandiumTheme.textPrimary)
                    Spacer()
                    Text("1.1.0")
                        .font(.system(size: 13))
                        .foregroundColor(ScandiumTheme.subtext)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                HairlineDivider(leadingPadding: 16)

                // Author
                HStack {
                    Text(settings.loc("Tác giả", "Author"))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(ScandiumTheme.textPrimary)
                    Spacer()
                    Text("MeoHunter")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ScandiumTheme.textPrimary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
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
                        .padding(.bottom, 30)
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
}
