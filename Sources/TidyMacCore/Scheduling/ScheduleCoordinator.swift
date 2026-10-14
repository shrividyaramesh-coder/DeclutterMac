import Foundation

/// Scheduling frequency options for continuous background cleanup.
public enum ScheduleFrequency: Codable, Sendable, Equatable {
    case daily
    case weekly
    case monthly
    case onLowDiskSpace(thresholdGB: Int)
    
    public var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .onLowDiskSpace(let gb): return "When Free Space < \(gb) GB"
        }
    }
}

/// Persistent settings configuration for continuous cleanup.
public struct ScheduleSettings: Codable, Sendable, Equatable {
    public var isEnabled: Bool
    public var frequency: ScheduleFrequency
    public var runApprovedRulesOnly: Bool
    public var lastRunDate: Date?
    
    public init(
        isEnabled: Bool = false,
        frequency: ScheduleFrequency = .weekly,
        runApprovedRulesOnly: Bool = true,
        lastRunDate: Date? = nil
    ) {
        self.isEnabled = isEnabled
        self.frequency = frequency
        self.runApprovedRulesOnly = runApprovedRulesOnly
        self.lastRunDate = lastRunDate
    }
}

/// Actor coordinating continuous cleanup execution on a schedule or when disk space is low.
public actor ScheduleCoordinator {
    public static let shared = ScheduleCoordinator()
    
    private let storageKey = "TidyMacScheduleSettings"
    private var settings: ScheduleSettings
    private let ruleEngine: RuleEngine
    private let fileAccessService: FileAccessService
    private let notificationService: UserNotificationService
    
    public init(
        ruleEngine: RuleEngine = .shared,
        fileAccessService: FileAccessService = .shared,
        notificationService: UserNotificationService = .shared
    ) {
        self.ruleEngine = ruleEngine
        self.fileAccessService = fileAccessService
        self.notificationService = notificationService
        
        if let data = UserDefaults.standard.data(forKey: "TidyMacScheduleSettings"),
           let loaded = try? JSONDecoder().decode(ScheduleSettings.self, from: data) {
            self.settings = loaded
        } else {
            self.settings = ScheduleSettings()
        }
    }
    
    public func getSettings() -> ScheduleSettings {
        settings
    }
    
    public func updateSettings(_ newSettings: ScheduleSettings) {
        self.settings = newSettings
        if let data = try? JSONEncoder().encode(newSettings) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    
    /// Determines whether a scheduled cleanup run is due based on frequency or disk threshold.
    public func isRunDue(currentFreeBytes: Int64? = nil) -> Bool {
        guard settings.isEnabled else { return false }
        
        // 1. Check low disk space trigger if configured
        if case .onLowDiskSpace(let thresholdGB) = settings.frequency {
            if let free = currentFreeBytes {
                let thresholdBytes = Int64(thresholdGB) * 1024 * 1024 * 1024
                return free < thresholdBytes
            }
        }
        
        // 2. Check time interval elapsed
        guard let lastRun = settings.lastRunDate else {
            return true // Never run before
        }
        
        let now = Date()
        let calendar = Calendar.current
        
        switch settings.frequency {
        case .daily:
            let days = calendar.dateComponents([.day], from: lastRun, to: now).day ?? 0
            return days >= 1
        case .weekly:
            let days = calendar.dateComponents([.day], from: lastRun, to: now).day ?? 0
            return days >= 7
        case .monthly:
            let days = calendar.dateComponents([.day], from: lastRun, to: now).day ?? 0
            return days >= 30
        case .onLowDiskSpace:
            return false
        }
    }
    
    /// Executes a continuous cleanup run in the background, only running approved rules.
    public func executeScheduledRun() async throws -> PlanExecutionSummary {
        let allRules = await ruleEngine.getRules()
        // Invariant: Scheduled runs only execute rules the user has previously enabled / approved
        let activeRules = allRules.filter(\.isEnabled)
        guard !activeRules.isEmpty else {
            return PlanExecutionSummary(batchId: UUID(), itemsProcessed: 0, bytesReclaimed: 0)
        }
        
        let managedFolders = await fileAccessService.getManagedFolderURLs()
        var candidates: [FileItem] = []
        
        for folder in managedFolders {
            if let enumerator = FileManager.default.enumerator(
                at: folder,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) {
                while let fileURL = enumerator.nextObject() as? URL {
                    let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                    let size = Int64(values?.fileSize ?? 0)
                    let modDate = values?.contentModificationDate ?? Date()
                    let category = CategoryClassifier.classify(url: fileURL, fileSize: size, createdDate: modDate)
                    let risk = RiskEvaluator.evaluateRisk(category: category, url: fileURL, fileSize: size, createdDate: modDate)
                    
                    candidates.append(FileItem(
                        url: fileURL,
                        fileSize: size,
                        lastModifiedDate: modDate,
                        category: category,
                        riskLabel: risk
                    ))
                }
            }
        }
        
        let summary = try await ruleEngine.executeRules(
            rulesToRun: activeRules,
            candidates: candidates,
            allowedRoots: managedFolders
        )
        
        // Update last run timestamp
        settings.lastRunDate = Date()
        updateSettings(settings)
        
        // Post notification summary
        notificationService.postCleanupSummary(
            filesCleaned: summary.itemsProcessed,
            bytesReclaimed: summary.bytesReclaimed
        )
        
        return summary
    }
}
