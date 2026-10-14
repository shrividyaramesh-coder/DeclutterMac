import Foundation
import os

/// Supported languages across Tidy Mac.
public enum AppLanguage: String, Sendable, Codable, CaseIterable, Identifiable {
    case en = "en"
    case fr = "fr"
    case de = "de"
    case ja = "ja"
    case ko = "ko"
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case es = "es"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .en: return "English"
        case .fr: return "Français"
        case .de: return "Deutsch"
        case .ja: return "日本語"
        case .ko: return "한국어"
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .es: return "Español"
        }
    }
}

/// Thread-safe storage for active language state allowing non-isolated synchronous lookup.
private final class ThreadSafeLanguageStore: @unchecked Sendable {
    static let shared = ThreadSafeLanguageStore()
    private var lock = os_unfair_lock_s()
    private var _currentLanguage: AppLanguage = .en

    private init() {
        if let saved = UserDefaults.standard.string(forKey: "TidyMacSelectedLanguage"),
           let lang = AppLanguage(rawValue: saved) {
            _currentLanguage = lang
        }
    }

    var currentLanguage: AppLanguage {
        get {
            os_unfair_lock_lock(&lock)
            defer { os_unfair_lock_unlock(&lock) }
            return _currentLanguage
        }
        set {
            os_unfair_lock_lock(&lock)
            _currentLanguage = newValue
            os_unfair_lock_unlock(&lock)
            UserDefaults.standard.set(newValue.rawValue, forKey: "TidyMacSelectedLanguage")
        }
    }
}

/// Centralized manager for in-app language switching and localized string resolution.
@MainActor
public final class LocalizationManager: ObservableObject {
    public static let shared = LocalizationManager()

    @Published public private(set) var currentLanguage: AppLanguage

    private init() {
        self.currentLanguage = ThreadSafeLanguageStore.shared.currentLanguage
    }

    public func setLanguage(_ language: AppLanguage) {
        ThreadSafeLanguageStore.shared.currentLanguage = language
        self.currentLanguage = language
    }

    /// Retrieve localized string for a specific key in the currently active language.
    public func string(for key: String) -> String {
        LocalizedStrings.lookup(key: key, language: currentLanguage)
    }
}

/// Non-isolated synchronous helper shorthand for localized string lookup.
public func localized(_ key: String) -> String {
    let language = ThreadSafeLanguageStore.shared.currentLanguage
    return LocalizedStrings.lookup(key: key, language: language)
}
