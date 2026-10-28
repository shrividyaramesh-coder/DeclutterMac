import Foundation

/// User settings for always-on organizing of Desktop, Downloads and other chosen folders.
public struct AutoOrganizeSettings: Codable, Sendable, Equatable {
    public var isEnabled: Bool
    /// New files wait in Recents for this many days before being sorted.
    public var recentsDays: Int
    /// Absolute paths of the folders kept tidy.
    public var folderPaths: [String]
    /// Sort into AI topic folders when Apple's on-device model is available; file-type folders otherwise.
    public var useAITopics: Bool
    public var lastRunDate: Date?
    public var lastRunMovedCount: Int

    public static let recentsDayRange = 1...30

    public static var defaultFolderPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [home.appendingPathComponent("Desktop").path, home.appendingPathComponent("Downloads").path]
    }

    public init(
        isEnabled: Bool = false,
        recentsDays: Int = 3,
        folderPaths: [String] = AutoOrganizeSettings.defaultFolderPaths,
        useAITopics: Bool = true,
        lastRunDate: Date? = nil,
        lastRunMovedCount: Int = 0
    ) {
        self.isEnabled = isEnabled
        self.recentsDays = recentsDays
        self.folderPaths = folderPaths
        self.useAITopics = useAITopics
        self.lastRunDate = lastRunDate
        self.lastRunMovedCount = lastRunMovedCount
    }

    public var folderURLs: [URL] {
        folderPaths.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }
}

/// Persists `AutoOrganizeSettings`.
public actor AutoOrganizeSettingsStore {
    public static let shared = AutoOrganizeSettingsStore()

    private let storageKey = "TidyMacAutoOrganizeSettings"
    private let defaults: UserDefaults
    private var settings: AutoOrganizeSettings

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let stored = try? JSONDecoder().decode(AutoOrganizeSettings.self, from: data) {
            self.settings = stored
        } else {
            self.settings = AutoOrganizeSettings()
        }
    }

    public func get() -> AutoOrganizeSettings {
        settings
    }

    public func update(_ newSettings: AutoOrganizeSettings) {
        var clamped = newSettings
        clamped.recentsDays = min(max(clamped.recentsDays, AutoOrganizeSettings.recentsDayRange.lowerBound), AutoOrganizeSettings.recentsDayRange.upperBound)
        settings = clamped
        if let data = try? JSONEncoder().encode(clamped) {
            defaults.set(data, forKey: storageKey)
        }
    }

    /// Auto-organizing is included with the trial and the lifetime license.
    public static func isAllowed(by status: LicenseStatus) -> Bool {
        switch status {
        case .unlocked: return true
        case .trial(let daysRemaining): return daysRemaining > 0
        case .freeTier: return false
        }
    }
}
