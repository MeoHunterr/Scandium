// SettingsSheetView.swift — Dedicated Settings & Preferences Modal
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import SwiftUI

struct SettingsSheetView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var storage = StorageManager.shared
    @Environment(\.presentationMode) var presentationMode

    @State private var showClearAllCacheAlert: Bool = false
    @State private var showClearImageAlert: Bool = false
    @State private var showClearAudioAlert: Bool = false
    @State private var toastMessage: String?

    init() {}

    var body: some View {
        NavigationView {
            ZStack {
                ScandiumTheme.bgPrimary.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        themeSection
                        accentColorSection
                        appIconSection
                        languageSection
                        audioQualitySection
                        playbackSection
                        sleepTimerSection
                        storageSection
                        aboutSection
                        fossDisclaimerView
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
                        settings.triggerHaptic()
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Text(settings.loc("Xong", "Done"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(ScandiumTheme.spotifyGreen)
                    }
                }
            }
            .alert(isPresented: $showClearAllCacheAlert) {
                Alert(
                    title: Text(settings.loc("Dọn sạch toàn bộ cache?", "Clear all temporary cache?")),
                    message: Text(settings.loc("Giải phóng ảnh bìa và file âm thanh tạm thời. Danh sách bài hát của bạn sẽ được giữ nguyên.", "Frees cached artwork and temp audio. Your library is kept safe.")),
                    primaryButton: .destructive(Text(settings.loc("Dọn sạch ngay", "Clear Now"))) {
                        storage.clearCache()
                        ImageCacheStore.shared.clear()
                        showToast(settings.loc("Đã dọn sạch toàn bộ cache tạm!", "All temporary cache cleared!"))
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
            sectionHeader(title: settings.loc("Giao diện & Chế độ tối", "Appearance & Dark Mode"))

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
            settings.triggerHaptic()
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

    // MARK: - 2. Accent Color Section

    private var accentColorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: settings.loc("Màu nhấn chủ đạo", "Accent Color"))

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    ForEach(AppAccentColor.allCases) { accent in
                        let isSelected = settings.accentColor == accent
                        Button(action: {
                            settings.triggerHaptic()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                settings.accentColor = accent
                            }
                        }) {
                            VStack(spacing: 6) {
                                Circle()
                                    .fill(accent.color)
                                    .frame(width: 26, height: 26)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(isSelected ? 0.9 : 0), lineWidth: 2)
                                    )

                                Text(accent.title(language: settings.language))
                                    .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                                    .foregroundColor(isSelected ? ScandiumTheme.textPrimary : ScandiumTheme.subtext)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(isSelected ? ScandiumTheme.surfaceElevated : ScandiumTheme.surfaceElevated.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(isSelected ? accent.color : Color.clear, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(12)
            }
            .background(ScandiumTheme.surfaceDark)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - App Icon Section

    private var appIconSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: settings.loc("Biểu tượng ứng dụng", "App Icon"))

            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(AppIconOption.allCases) { option in
                            let isSelected = settings.currentAppIcon == option
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    settings.setAppIcon(option) { success, message in
                                        if let message = message {
                                            showToast(message)
                                        }
                                    }
                                }
                            }) {
                                VStack(spacing: 8) {
                                    iconThumbnail(for: option)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                                .stroke(isSelected ? settings.accentColor.color : Color.clear, lineWidth: 2)
                                        )

                                    Text(option.title(language: settings.language))
                                        .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                        .foregroundColor(isSelected ? ScandiumTheme.textPrimary : ScandiumTheme.subtext)
                                        .lineLimit(1)
                                        .frame(maxWidth: 86)

                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(settings.accentColor.color)
                                    } else {
                                        Circle()
                                            .stroke(ScandiumTheme.subtext.opacity(0.3), lineWidth: 1)
                                            .frame(width: 13, height: 13)
                                    }
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 8)
                                .background(isSelected ? ScandiumTheme.surfaceElevated : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(12)
                }
            }
            .background(ScandiumTheme.surfaceDark)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func iconThumbnail(for option: AppIconOption) -> some View {
        Group {
            if let path = Bundle.main.path(forResource: option.previewImageName + "@2x", ofType: "png") ??
                          Bundle.main.path(forResource: option.previewImageName + "60x60@2x", ofType: "png") ??
                          Bundle.main.path(forResource: option.previewImageName, ofType: "png") ??
                          Bundle.main.path(forResource: option.rawValue, ofType: "png") ??
                          (option == .default ? Bundle.main.path(forResource: "icon", ofType: "png") : nil),
               let uiImage = UIImage(contentsOfFile: path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
            } else {
                ZStack {
                    Color(red: 0.08, green: 0.08, blue: 0.10)
                    Text("21")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(option.previewColor)
                }
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - 3. Language Section

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: settings.loc("Ngôn ngữ hiển thị", "Display Language"))

            VStack(spacing: 0) {
                ForEach(AppLanguage.allCases) { lang in
                    Button(action: {
                        settings.triggerHaptic()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            settings.language = lang
                        }
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(lang.displayName)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(ScandiumTheme.textPrimary)
                                Text(lang == .vietnamese ? settings.loc("Giao diện Tiếng Việt", "Vietnamese Interface") : settings.loc("Giao diện Tiếng Anh", "English Interface"))
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

    // MARK: - 4. Audio Streaming Quality

    private var audioQualitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: settings.loc("Chất lượng âm thanh", "Audio Quality"))

            VStack(spacing: 0) {
                ForEach(AudioQualitySetting.allCases) { q in
                    Button(action: {
                        settings.triggerHaptic()
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

    // MARK: - 5. Playback Experience

    private var playbackSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: settings.loc("Trải nghiệm phát nhạc & Điều khiển", "Playback & Audio Controls"))

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

                // Pause on Headphone Disconnect
                Toggle(isOn: $settings.pauseOnHeadphoneDisconnect) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(settings.loc("Tự dừng khi rút tai nghe", "Pause on Disconnect"))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(ScandiumTheme.textPrimary)
                        Text(settings.loc("Tự động tạm dừng khi ngắt kết nối tai nghe hoặc AirPods", "Automatically pause audio when headphones or AirPods unplug"))
                            .font(.system(size: 12))
                            .foregroundColor(ScandiumTheme.subtext)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: ScandiumTheme.spotifyGreen))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                HairlineDivider(leadingPadding: 16)

                // Auto-skip on Error
                Toggle(isOn: $settings.autoSkipOnError) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(settings.loc("Tự chuyển bài khi gặp lỗi stream", "Auto-Skip on Stream Error"))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(ScandiumTheme.textPrimary)
                        Text(settings.loc("Tự động nhảy sang bài tiếp theo nếu bài hiện tại bị chặn hoặc lỗi mạng", "Skip to next track if current stream fails or is restricted"))
                            .font(.system(size: 12))
                            .foregroundColor(ScandiumTheme.subtext)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: ScandiumTheme.spotifyGreen))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                HairlineDivider(leadingPadding: 16)

                // Waveform Display
                Toggle(isOn: $settings.showWaveform) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(settings.loc("Hiển thị sóng âm thanh (Waveform)", "Display Waveform Scrubber"))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(ScandiumTheme.textPrimary)
                        Text(settings.loc("Thanh trượt dạng đồ thị sóng âm thanh đặc trưng SoundCloud", "Visual sound wave scrubber bar in Now Playing"))
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

                HairlineDivider(leadingPadding: 16)

                // Haptic Feedback
                Toggle(isOn: $settings.enableHaptics) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(settings.loc("Phản hồi rung nhẹ (Haptics)", "Haptic Feedback"))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(ScandiumTheme.textPrimary)
                        Text(settings.loc("Rung phản hồi nhẹ khi chạm nút điều khiển", "Gentle vibration on player and button taps"))
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

    // MARK: - 6. Sleep Timer Section

    private var sleepTimerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: settings.loc("Hẹn giờ tắt nhạc (Sleep Timer)", "Sleep Timer"))

            VStack(spacing: 0) {
                ForEach(SleepTimerOption.allCases) { opt in
                    Button(action: {
                        settings.triggerHaptic()
                        AudioPlayerEngineWrapper.sharedEngine?.setSleepTimer(opt)
                        settings.sleepTimerOption = opt
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(opt.title(language: settings.language))
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(ScandiumTheme.textPrimary)
                            }

                            Spacer()

                            if settings.sleepTimerOption == opt {
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
                        .padding(.vertical, 13)
                    }
                    .buttonStyle(PlainButtonStyle())

                    if opt != SleepTimerOption.allCases.last {
                        HairlineDivider(leadingPadding: 16)
                    }
                }
            }
            .background(ScandiumTheme.surfaceDark)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - 7. Storage & Cache

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: settings.loc("Bộ nhớ đệm & Dữ liệu", "Storage & Cache"))

            VStack(spacing: 0) {
                // Total Storage Row
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(settings.loc("Tổng bộ nhớ đệm sử dụng", "Total Cache Usage"))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(ScandiumTheme.textPrimary)
                        Text(storage.formattedTotal)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(ScandiumTheme.spotifyGreen)
                    }

                    Spacer()

                    Button(action: {
                        showClearAllCacheAlert = true
                    }) {
                        Text(settings.loc("Dọn tất cả", "Clear All"))
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

                HairlineDivider(leadingPadding: 16)

                // Clear Artwork Only
                Button(action: {
                    storage.clearImageCacheOnly()
                    showToast(settings.loc("Đã dọn sạch ảnh bìa tạm!", "Artwork cache cleared!"))
                }) {
                    HStack {
                        Image(systemName: "photo")
                            .font(.system(size: 15))
                            .foregroundColor(ScandiumTheme.subtext)
                        Text(settings.loc("Dọn cache ảnh bìa", "Clear Artwork Cache"))
                            .font(.system(size: 14))
                            .foregroundColor(ScandiumTheme.textPrimary)
                        Spacer()
                        Text(storage.formattedImageCache)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(ScandiumTheme.subtext)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(PlainButtonStyle())

                HairlineDivider(leadingPadding: 16)

                // Clear Audio Only
                Button(action: {
                    storage.clearAudioCacheOnly()
                    showToast(settings.loc("Đã dọn sạch file âm thanh tạm!", "Audio cache cleared!"))
                }) {
                    HStack {
                        Image(systemName: "waveform")
                            .font(.system(size: 15))
                            .foregroundColor(ScandiumTheme.subtext)
                        Text(settings.loc("Dọn cache âm thanh & stream tạm", "Clear Audio & Stream Cache"))
                            .font(.system(size: 14))
                            .foregroundColor(ScandiumTheme.textPrimary)
                        Spacer()
                        Text(storage.formattedAudioNetwork)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(ScandiumTheme.subtext)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .background(ScandiumTheme.surfaceDark)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - 8. About Section

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: settings.loc("Thông tin ứng dụng", "About Scandium"))

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
                        Text("Scandium [21 Sc]")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(ScandiumTheme.textPrimary)
                        Text(settings.loc("Client bên thứ ba cho SoundCloud • iOS 15+", "Unofficial Client for SoundCloud • iOS 15+"))
                            .font(.system(size: 12))
                            .foregroundColor(ScandiumTheme.subtext)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                HairlineDivider(leadingPadding: 16)

                // Version 1.3.0
                HStack {
                    Text(settings.loc("Phiên bản", "Version"))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(ScandiumTheme.textPrimary)
                    Spacer()
                    Text("1.3.0")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(ScandiumTheme.spotifyGreen)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                HairlineDivider(leadingPadding: 16)

                // License
                HStack {
                    Text(settings.loc("Giấy phép", "License"))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(ScandiumTheme.textPrimary)
                    Spacer()
                    Text("GNU GPL v3.0 (Open Source)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(ScandiumTheme.spotifyGreen)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                HairlineDivider(leadingPadding: 16)

                // Source Code
                HStack {
                    Text(settings.loc("Mã nguồn", "Source Code"))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(ScandiumTheme.textPrimary)
                    Spacer()
                    Text("github.com/MeoHunterr/Scandium")
                        .font(.system(size: 12, design: .monospaced))
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

    // MARK: - 9. FOSS Disclaimer

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

// MARK: - Global Shared AudioPlayerEngine Reference Helper

enum AudioPlayerEngineWrapper {
    static weak var sharedEngine: AudioPlayerEngine?
}
