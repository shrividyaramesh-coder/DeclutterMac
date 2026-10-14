import Foundation

/// Fast, fully local offline natural language parser for cleanup intents.
/// Requires zero network connection and no API keys.
public struct OfflineHeuristicParser: Sendable {
    
    public init() {}
    
    public func parse(prompt: String, defaultManagedFolder: URL? = nil) -> CleaningPlan {
        let text = prompt.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultPath = defaultManagedFolder?.path ?? ("~" as NSString).expandingTildeInPath
        
        var steps: [CleaningPlanStep] = []
        var detectedSummary: String = "Structured cleanup plan generated via offline heuristics."
        
        // 1. Target Folder Detection
        var targetFolder = defaultPath
        if text.contains("download") {
            targetFolder = (("~/Downloads" as NSString).expandingTildeInPath)
        } else if text.contains("desktop") {
            targetFolder = (("~/Desktop" as NSString).expandingTildeInPath)
        } else if text.contains("document") {
            targetFolder = (("~/Documents" as NSString).expandingTildeInPath)
        } else if text.contains("picture") || text.contains("photo") {
            targetFolder = (("~/Pictures" as NSString).expandingTildeInPath)
        } else if text.contains("cache") {
            targetFolder = (("~/Library/Caches" as NSString).expandingTildeInPath)
        } else if text.contains("log") {
            targetFolder = (("~/Library/Logs" as NSString).expandingTildeInPath)
        }
        
        // 2. Age parsing
        var minAgeDays: Int? = nil
        if text.contains("month") {
            if let count = extractLeadingNumber(before: "month", in: text) {
                minAgeDays = count * 30
            } else {
                minAgeDays = 30
            }
        } else if text.contains("week") {
            if let count = extractLeadingNumber(before: "week", in: text) {
                minAgeDays = count * 7
            } else {
                minAgeDays = 7
            }
        } else if text.contains("year") {
            if let count = extractLeadingNumber(before: "year", in: text) {
                minAgeDays = count * 365
            } else {
                minAgeDays = 365
            }
        } else if text.contains("day") {
            if let count = extractLeadingNumber(before: "day", in: text) {
                minAgeDays = count
            } else {
                minAgeDays = 7
            }
        } else if text.contains("old") {
            minAgeDays = 30
        }
        
        // 3. Size parsing
        var minSizeBytes: Int64? = nil
        if text.contains("gb") || text.contains("gig") {
            if let gb = extractLeadingNumber(before: "gb", in: text) ?? extractLeadingNumber(before: "gig", in: text) {
                minSizeBytes = Int64(gb) * 1024 * 1024 * 1024
            } else {
                minSizeBytes = 1024 * 1024 * 1024 // 1 GB
            }
        } else if text.contains("mb") || text.contains("meg") {
            if let mb = extractLeadingNumber(before: "mb", in: text) ?? extractLeadingNumber(before: "meg", in: text) {
                minSizeBytes = Int64(mb) * 1024 * 1024
            } else {
                minSizeBytes = 100 * 1024 * 1024 // 100 MB
            }
        } else if text.contains("huge") || text.contains("large") {
            minSizeBytes = 500 * 1024 * 1024 // 500 MB default for "huge"
        }
        
        // 4. Intent and Category Detection
        let isScreenshot = text.contains("screenshot") || text.contains("screen shot")
        let isInstaller = text.contains("installer") || text.contains("dmg") || text.contains("pkg")
        let isCache = text.contains("cache")
        let isLog = text.contains("log")
        let isOrganize = text.contains("organize") || text.contains("sort")
        
        if isScreenshot {
            let filter = CleaningFilter(
                categories: [.screenshots],
                extensions: ["png", "jpg", "jpeg"],
                minimumAgeDays: minAgeDays ?? 30,
                minimumSizeBytes: minSizeBytes,
                nameContains: nil
            )
            steps.append(CleaningPlanStep(
                targetFolder: targetFolder,
                filter: filter,
                action: .trash,
                explanation: "Move screenshots older than \(minAgeDays ?? 30) days to Trash."
            ))
            detectedSummary = "Find and trash old screenshots."
        } else if isInstaller {
            let filter = CleaningFilter(
                categories: [.oldDownloads],
                extensions: ["dmg", "pkg", "iso", "zip"],
                minimumAgeDays: minAgeDays ?? 7,
                minimumSizeBytes: minSizeBytes,
                nameContains: nil
            )
            steps.append(CleaningPlanStep(
                targetFolder: (("~/Downloads" as NSString).expandingTildeInPath),
                filter: filter,
                action: .trash,
                explanation: "Clean downloaded installer packages (.dmg, .pkg) older than \(minAgeDays ?? 7) days."
            ))
            detectedSummary = "Clean leftover disk images and installer packages."
        } else if isCache || isLog {
            var categories: [ScanCategory] = []
            if isCache { categories.append(.caches) }
            if isLog { categories.append(.logs) }
            
            let filter = CleaningFilter(
                categories: categories,
                extensions: nil,
                minimumAgeDays: minAgeDays,
                minimumSizeBytes: minSizeBytes,
                nameContains: nil
            )
            steps.append(CleaningPlanStep(
                targetFolder: targetFolder,
                filter: filter,
                action: .trash,
                explanation: "Remove safe temporary caches and log files to reclaim disk space."
            ))
            detectedSummary = "Reclaim space from system/user caches and logs."
        } else if isOrganize {
            let filter = CleaningFilter(
                categories: nil,
                extensions: nil,
                minimumAgeDays: minAgeDays,
                minimumSizeBytes: minSizeBytes,
                nameContains: nil
            )
            let destFolder = (("~/Documents/Organized" as NSString).expandingTildeInPath)
            steps.append(CleaningPlanStep(
                targetFolder: targetFolder,
                filter: filter,
                action: .move,
                destinationFolder: destFolder,
                explanation: "Sort and organize files into classified folders."
            ))
            detectedSummary = "Organize files into structured directories."
        } else {
            // General cleanup or large file review
            let filter = CleaningFilter(
                categories: minSizeBytes != nil ? [.largeFiles] : nil,
                extensions: nil,
                minimumAgeDays: minAgeDays,
                minimumSizeBytes: minSizeBytes ?? (minAgeDays != nil ? nil : 200 * 1024 * 1024),
                nameContains: nil
            )
            let action: PlannedAction = (text.contains("delete") || text.contains("trash") || text.contains("remove") || text.contains("clean")) ? .trash : .review
            steps.append(CleaningPlanStep(
                targetFolder: targetFolder,
                filter: filter,
                action: action,
                explanation: action == .trash ? "Trash unneeded files matching query criteria." : "Review candidate files matching query criteria."
            ))
            detectedSummary = "Query candidate files matching criteria for review."
        }
        
        return CleaningPlan(
            userGoal: prompt,
            steps: steps,
            summary: detectedSummary,
            isDryRun: true
        )
    }
    
    private func extractLeadingNumber(before keyword: String, in text: String) -> Int? {
        guard let range = text.range(of: keyword) else { return nil }
        let substring = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        let words = substring.split(separator: " ")
        guard let lastWord = words.last else { return nil }
        
        // Handle word numbers
        switch lastWord {
        case "a", "one", "an": return 1
        case "two": return 2
        case "three": return 3
        case "four": return 4
        case "five": return 5
        case "six": return 6
        case "seven": return 7
        case "eight": return 8
        case "nine": return 9
        case "ten": return 10
        default:
            return Int(lastWord)
        }
    }
}
