import Foundation
import TidyMacCore

@MainActor
func runLocalizationTests() {
    print("\n--- Running Localization Tests (8 Languages) ---")
    
    let expectedCodes: Set<String> = ["en", "fr", "de", "ja", "ko", "zh-Hans", "zh-Hant", "es"]
    let actualCodes = Set(AppLanguage.allCases.map(\.rawValue))
    expectEqual(actualCodes, expectedCodes, "Must support exactly the 8 required languages")
    
    let keysToTest = [
        "app.name",
        "app.tagline",
        "nav.overview",
        "nav.cleanup",
        "action.scan",
        "risk.safe",
        "risk.manual",
        "privacy.title"
    ]
    
    for lang in AppLanguage.allCases {
        for key in keysToTest {
            let value = LocalizedStrings.lookup(key: key, language: lang)
            expectNotEqual(value, key, "Missing translation for '\(key)' in \(lang.rawValue)")
            expect(!value.isEmpty, "Translation for '\(key)' in \(lang.rawValue) cannot be empty")
        }
    }
    
    // Language switching test
    let manager = LocalizationManager.shared
    manager.setLanguage(.ja)
    expectEqual(manager.currentLanguage, .ja, "Current language should switch to Japanese")
    expectEqual(localized("action.scan"), "スキャン開始", "Localized string should match Japanese translation")
    
    manager.setLanguage(.en)
    expectEqual(manager.currentLanguage, .en, "Current language should switch back to English")
    expectEqual(localized("action.scan"), "Scan Now", "Localized string should match English translation")
}
