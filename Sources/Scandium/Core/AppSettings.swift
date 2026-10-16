// AppSettings.swift — Global user preferences and configuration manager
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import SwiftUI
import UIKit

public enum AppThemeMode: String, CaseIterable, Identifiable {
    case dark = "dark"
    case light = "light"
    case system = "system"

    public var id: String { rawValue }

    public func title(language: AppLanguage) -> String {
        switch (self, language) {
        case (.dark, .vietnamese): return "Tối (OLED Black)"
        case (.dark, .english):    return "Dark (OLED Black)"
        case (.light, .vietnamese): return "Sáng (Light)"
        case (.light, .english):   return "Light"
        case (.system, .vietnamese): return "Theo hệ thống"
        case (.system, .english):   return "System Default"
        }
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
    }
}

public enum AppAccentColor: String, CaseIterable, Identifiable {
    case green = "green"
    case orange = "orange"
    case cyan = "cyan"
    case purple = "purple"

    public var id: String { rawValue }

    public init?(rawValue: String) {
        switch rawValue {
        case "green", "spotifyGreen": self = .green
        case "orange", "soundcloudOrange": self = .orange
        case "cyan", "neonCyan": self = .cyan
        case "purple", "violetPurple": self = .purple
        default: return nil
        }
    }

    // Backwards-compatible aliases
    public static let spotifyGreen = AppAccentColor.green
    public static let soundcloudOrange = AppAccentColor.orange
    public static let neonCyan = AppAccentColor.cyan
    public static let violetPurple = AppAccentColor.purple

    public func title(language: AppLanguage) -> String {
        switch (self, language) {
        case (.green, .vietnamese):   return "Xanh lục"
        case (.green, .english):      return "Emerald Green"
        case (.orange, .vietnamese):  return "Cam"
        case (.orange, .english):     return "Amber Orange"
        case (.cyan, .vietnamese):    return "Xanh lam"
        case (.cyan, .english):       return "Neon Cyan"
        case (.purple, .vietnamese):  return "Tím"
        case (.purple, .english):     return "Violet Purple"
        }
    }

    public var color: Color {
        switch self {
        case .green:   return Color(red: 29/255, green: 185/255, blue: 84/255)
        case .orange:  return Color(red: 255/255, green: 85/255, blue: 0/255)
        case .cyan:    return Color(red: 0/255, green: 229/255, blue: 255/255)
        case .purple:  return Color(red: 187/255, green: 134/255, blue: 252/255)
        }
    }
}

public enum AppIconOption: String, CaseIterable, Identifiable {
    case `default` = "default"
    case orange = "AppIcon-Orange"
    case cyan = "AppIcon-Cyan"
    case purple = "AppIcon-Purple"
    case monochrome = "AppIcon-Monochrome"

    public var id: String { rawValue }

    public var iconName: String? {
        switch self {
        case .default: return nil
        case .orange: return "AppIcon-Orange"
        case .cyan: return "AppIcon-Cyan"
        case .purple: return "AppIcon-Purple"
        case .monochrome: return "AppIcon-Monochrome"
        }
    }

    public func title(language: AppLanguage) -> String {
        switch (self, language) {
        case (.default, .vietnamese):    return "Scandium Mặc định (Lục)"
        case (.default, .english):       return "Scandium Default (Green)"
        case (.orange, .vietnamese):     return "Cam Kim loại"
        case (.orange, .english):        return "Amber Orange"
        case (.cyan, .vietnamese):       return "Xanh Lam Điện tử"
        case (.cyan, .english):          return "Electric Cyan"
        case (.purple, .vietnamese):     return "Tím Huyền bí"
        case (.purple, .english):        return "Violet Aura"
        case (.monochrome, .vietnamese): return "Trắng Đen Đơn sắc"
        case (.monochrome, .english):    return "Pure Monochrome"
        }
    }

    public var previewColor: Color {
        switch self {
        case .default:    return Color(red: 29/255, green: 185/255, blue: 84/255)
        case .orange:     return Color(red: 255/255, green: 120/255, blue: 20/255)
        case .cyan:       return Color(red: 0/255, green: 210/255, blue: 255/255)
        case .purple:     return Color(red: 180/255, green: 100/255, blue: 255/255)
        case .monochrome: return Color(red: 220/255, green: 225/255, blue: 235/255)
        }
    }

    public var previewImageName: String {
        switch self {
        case .default: return "AppIcon"
        case .orange: return "AppIcon-Orange"
        case .cyan: return "AppIcon-Cyan"
        case .purple: return "AppIcon-Purple"
        case .monochrome: return "AppIcon-Monochrome"
        }
    }
}

public enum AppLanguage: String, CaseIterable, Identifiable {
    case vietnamese = "vi"
    case english = "en"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .vietnamese: return "Tiếng Việt"
        case .english: return "English"
        }
    }
}

public enum AudioQualitySetting: String, CaseIterable, Identifiable {
    case high = "high"
    case standard = "standard"
    case saver = "saver"

    public var id: String { rawValue }

    public func title(language: AppLanguage) -> String {
        switch (self, language) {
        case (.high, .vietnamese): return "Chất lượng cao (HLS 256kbps)"
        case (.high, .english):    return "High Quality (HLS 256kbps)"
        case (.standard, .vietnamese): return "Tiêu chuẩn (128kbps MP3)"
        case (.standard, .english):   return "Standard (128kbps MP3)"
        case (.saver, .vietnamese): return "Tiết kiệm dữ liệu (64kbps)"
        case (.saver, .english):   return "Data Saver (64kbps)"
        }
    }
}

public enum SleepTimerOption: Int, CaseIterable, Identifiable {
    case off = 0
    case min15 = 15
    case min30 = 30
    case min45 = 45
    case min60 = 60
    case endOfTrack = -1

    public var id: Int { rawValue }

    public func title(language: AppLanguage) -> String {
        switch (self, language) {
        case (.off, .vietnamese):        return "Tắt"
        case (.off, .english):           return "Off"
        case (.min15, .vietnamese):      return "15 phút"
        case (.min15, .english):         return "15 minutes"
        case (.min30, .vietnamese):      return "30 phút"
        case (.min30, .english):         return "30 minutes"
        case (.min45, .vietnamese):      return "45 phút"
        case (.min45, .english):         return "45 minutes"
        case (.min60, .vietnamese):      return "60 phút (1 giờ)"
        case (.min60, .english):         return "60 minutes (1 hr)"
        case (.endOfTrack, .vietnamese): return "Hết bài hát hiện tại"
        case (.endOfTrack, .english):    return "End of current track"
        }
    }
}

public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    // MARK: - Published Properties

    @Published public var themeMode: AppThemeMode {
        didSet {
            UserDefaults.standard.set(themeMode.rawValue, forKey: "scandium_theme_mode")
        }
    }

    @Published public var accentColor: AppAccentColor {
        didSet {
            UserDefaults.standard.set(accentColor.rawValue, forKey: "scandium_accent_color")
        }
    }

    @Published public var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "scandium_language")
        }
    }

    @Published public var audioQuality: AudioQualitySetting {
        didSet {
            UserDefaults.standard.set(audioQuality.rawValue, forKey: "scandium_audio_quality")
        }
    }

    @Published public var autoPlayRelated: Bool {
        didSet {
            UserDefaults.standard.set(autoPlayRelated, forKey: "scandium_autoplay_related")
        }
    }

    @Published public var keepScreenAwake: Bool {
        didSet {
            UserDefaults.standard.set(keepScreenAwake, forKey: "scandium_keep_screen_awake")
            UIApplication.shared.isIdleTimerDisabled = keepScreenAwake
        }
    }

    @Published public var pauseOnHeadphoneDisconnect: Bool {
        didSet {
            UserDefaults.standard.set(pauseOnHeadphoneDisconnect, forKey: "scandium_pause_on_headphone_disconnect")
        }
    }

    @Published public var autoSkipOnError: Bool {
        didSet {
            UserDefaults.standard.set(autoSkipOnError, forKey: "scandium_auto_skip_on_error")
        }
    }

    @Published public var showWaveform: Bool {
        didSet {
            UserDefaults.standard.set(showWaveform, forKey: "scandium_show_waveform")
        }
    }

    @Published public var enableHaptics: Bool {
        didSet {
            UserDefaults.standard.set(enableHaptics, forKey: "scandium_enable_haptics")
        }
    }

    @Published public var currentAppIcon: AppIconOption {
        didSet {
            UserDefaults.standard.set(currentAppIcon.rawValue, forKey: "scandium_app_icon")
        }
    }

    @Published public var sleepTimerOption: SleepTimerOption = .off

    // MARK: - Init

    private init() {
        let savedTheme = UserDefaults.standard.string(forKey: "scandium_theme_mode") ?? AppThemeMode.dark.rawValue
        self.themeMode = AppThemeMode(rawValue: savedTheme) ?? .dark

        let savedAccent = UserDefaults.standard.string(forKey: "scandium_accent_color") ?? AppAccentColor.green.rawValue
        self.accentColor = AppAccentColor(rawValue: savedAccent) ?? .green

        let savedIcon = UserDefaults.standard.string(forKey: "scandium_app_icon") ?? AppIconOption.default.rawValue
        self.currentAppIcon = AppIconOption(rawValue: savedIcon) ?? .default

        let savedLang = UserDefaults.standard.string(forKey: "scandium_language") ?? AppLanguage.english.rawValue
        self.language = AppLanguage(rawValue: savedLang) ?? .english

        let savedQuality = UserDefaults.standard.string(forKey: "scandium_audio_quality") ?? AudioQualitySetting.high.rawValue
        self.audioQuality = AudioQualitySetting(rawValue: savedQuality) ?? .high

        self.autoPlayRelated = UserDefaults.standard.object(forKey: "scandium_autoplay_related") as? Bool ?? true

        let awake = UserDefaults.standard.bool(forKey: "scandium_keep_screen_awake")
        self.keepScreenAwake = awake
        if awake {
            UIApplication.shared.isIdleTimerDisabled = true
        }

        self.pauseOnHeadphoneDisconnect = UserDefaults.standard.object(forKey: "scandium_pause_on_headphone_disconnect") as? Bool ?? true
        self.autoSkipOnError = UserDefaults.standard.object(forKey: "scandium_auto_skip_on_error") as? Bool ?? true
        self.showWaveform = UserDefaults.standard.object(forKey: "scandium_show_waveform") as? Bool ?? true
        self.enableHaptics = UserDefaults.standard.object(forKey: "scandium_enable_haptics") as? Bool ?? true
    }

    // MARK: - App Icon Switcher

    public func setAppIcon(_ option: AppIconOption, completion: ((Bool, String?) -> Void)? = nil) {
        currentAppIcon = option
        triggerHaptic()

        DispatchQueue.main.async {
            guard UIApplication.shared.supportsAlternateIcons else {
                let msg = self.loc(
                    "Thiết bị hoặc môi trường hiện tại không hỗ trợ đổi biểu tượng trực tiếp.",
                    "Alternate icons are not supported in this device environment."
                )
                print("[AppSettings] \(msg)")
                completion?(false, msg)
                return
            }

            let targetName = option.iconName
            if UIApplication.shared.alternateIconName == targetName {
                let msg = self.loc("Biểu tượng này đang được kích hoạt.", "This icon is already active.")
                completion?(true, msg)
                return
            }

            UIApplication.shared.setAlternateIconName(targetName) { error in
                DispatchQueue.main.async {
                    if let error = error {
                        let nsError = error as NSError
                        if nsError.domain == NSOSStatusErrorDomain && nsError.code == -54 {
                            let tipMsg = self.loc(
                                "Đã lưu cài đặt biểu tượng! (Nếu chưa đổi trên màn hình chính, hãy Rebuild Icon Cache trong TrollStore)",
                                "App icon saved! (If not updated on home screen, use Rebuild Icon Cache in TrollStore)"
                            )
                            print("[AppSettings] OSStatus -54 handled: \(tipMsg)")
                            completion?(true, tipMsg)
                        } else {
                            let errMsg = "\(self.loc("Lỗi đổi biểu tượng", "Error setting icon")): \(error.localizedDescription)"
                            print("[AppSettings] \(errMsg)")
                            completion?(false, errMsg)
                        }
                    } else {
                        let okMsg = self.loc("Đã đổi biểu tượng ứng dụng thành công!", "App icon changed successfully!")
                        print("[AppSettings] \(okMsg)")
                        completion?(true, okMsg)
                    }
                }
            }
        }
    }

    // MARK: - Haptic Feedback Helper

    public func triggerHaptic() {
        guard enableHaptics else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Dark Mode Detection

    public var isDark: Bool {
        switch themeMode {
        case .dark:
            return true
        case .light:
            return false
        case .system:
            if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
               let keyWindow = scene.windows.first(where: { $0.isKeyWindow }) {
                return keyWindow.traitCollection.userInterfaceStyle != .light
            }
            return UITraitCollection.current.userInterfaceStyle != .light
        }
    }

    // MARK: - Localization Helper

    public func loc(_ vi: String, _ en: String) -> String {
        return language == .vietnamese ? vi : en
    }
}
