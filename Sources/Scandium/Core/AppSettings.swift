// AppSettings.swift — Global user preferences and configuration manager
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import SwiftUI

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

public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    // MARK: - Published Properties

    @Published public var themeMode: AppThemeMode {
        didSet {
            UserDefaults.standard.set(themeMode.rawValue, forKey: "scandium_theme_mode")
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

    // MARK: - Init

    private init() {
        let savedTheme = UserDefaults.standard.string(forKey: "scandium_theme_mode") ?? AppThemeMode.dark.rawValue
        self.themeMode = AppThemeMode(rawValue: savedTheme) ?? .dark

        let savedLang = UserDefaults.standard.string(forKey: "scandium_language") ?? AppLanguage.vietnamese.rawValue
        self.language = AppLanguage(rawValue: savedLang) ?? .vietnamese

        let savedQuality = UserDefaults.standard.string(forKey: "scandium_audio_quality") ?? AudioQualitySetting.high.rawValue
        self.audioQuality = AudioQualitySetting(rawValue: savedQuality) ?? .high

        self.autoPlayRelated = UserDefaults.standard.object(forKey: "scandium_autoplay_related") as? Bool ?? true

        let awake = UserDefaults.standard.bool(forKey: "scandium_keep_screen_awake")
        self.keepScreenAwake = awake
        if awake {
            UIApplication.shared.isIdleTimerDisabled = true
        }
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
