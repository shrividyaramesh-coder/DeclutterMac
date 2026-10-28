import Foundation

/// Fast, fully local offline natural language parser for cleanup intents.
/// Requires zero network connection and no API keys.
public struct OfflineHeuristicParser: Sendable {

    public init() {}

    public func parse(prompt: String, defaultManagedFolder: URL? = nil) -> CleaningPlan {
        let text = prompt.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultPath = defaultManagedFolder?.path ?? (("~/Downloads" as NSString).expandingTildeInPath)

        // Match whole words only, so "folder" never reads as "old", "logo" as "log", or "today" as "day".
        let words = Set(text.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        func has(_ keywords: String...) -> Bool { keywords.contains(where: words.contains) }

        var steps: [CleaningPlanStep] = []
        var detectedSummary: String = "Structured cleanup plan generated via offline heuristics."

        // 1. Target Folder Detection
        var targetFolder = defaultPath
        if has("download", "downloads") {
            targetFolder = (("~/Downloads" as NSString).expandingTildeInPath)
        } else if has("desktop") {
            targetFolder = (("~/Desktop" as NSString).expandingTildeInPath)
        } else if has("document", "documents") {
            targetFolder = (("~/Documents" as NSString).expandingTildeInPath)
        } else if has("picture", "pictures", "photo", "photos") {
            targetFolder = (("~/Pictures" as NSString).expandingTildeInPath)
        } else if has("cache", "caches") {
            targetFolder = (("~/Library/Caches" as NSString).expandingTildeInPath)
        } else if has("log", "logs") {
            targetFolder = (("~/Library/Logs" as NSString).expandingTildeInPath)
        }

        // 2. Age parsing ("30 days", "a month", "two weeks"; bare "old"/"stale" means a month)
        var minAgeDays: Int? = nil
        if let (count, unit) = extractQuantity(units: ["day", "week", "month", "year"], in: text) {
            let multiplier = ["day": 1, "week": 7, "month": 30, "year": 365][unit] ?? 1
            minAgeDays = count * multiplier
        } else if has("old", "older", "stale") {
            minAgeDays = 30
        }

        // 3. Size parsing ("2 GB", "500mb"; bare "huge"/"large" means 500 MB)
        var minSizeBytes: Int64? = nil
        if let (count, unit) = extractQuantity(units: ["gb", "gig", "gigabyte", "mb", "meg", "megabyte"], in: text) {
            let isGigabytes = unit.hasPrefix("g")
            minSizeBytes = Int64(count) * 1024 * 1024 * (isGigabytes ? 1024 : 1)
        } else if has("gb", "gigabyte", "gigabytes") {
            minSizeBytes = 1024 * 1024 * 1024 // 1 GB
        } else if has("mb", "megabyte", "megabytes") {
            minSizeBytes = 100 * 1024 * 1024 // 100 MB
        } else if has("huge", "large", "big") {
            minSizeBytes = 500 * 1024 * 1024 // 500 MB default for "huge"
        }

        // 4. Intent and Category Detection
        // The action is decided before the file type, so "organize my screenshots" moves them instead of trashing them.
        let isScreenshot = has("screenshot", "screenshots") || text.contains("screen shot")
        let isInstaller = has("installer", "installers", "dmg", "dmgs", "pkg", "pkgs")
        let isCache = has("cache", "caches")
        let isLog = has("log", "logs")
        let isOrganize = has("organize", "organise", "sort", "tidy", "arrange", "categorize", "categorise", "group")
        let isRemoval = has("delete", "trash", "remove", "clean", "clear", "purge", "free")

        if isOrganize && !isRemoval {
            var categories: [ScanCategory]? = nil
            var extensions: [String]? = nil
            if isScreenshot {
                categories = [.screenshots]
                extensions = ["png", "jpg", "jpeg"]
            } else if isInstaller {
                extensions = ["dmg", "pkg", "iso"]
            }
            let filter = CleaningFilter(
                categories: categories,
                extensions: extensions,
                minimumAgeDays: minAgeDays,
                minimumSizeBytes: minSizeBytes,
                nameContains: nil
            )
            let destFolder = targetFolder
            let folderName = URL(fileURLWithPath: targetFolder).lastPathComponent
            steps.append(CleaningPlanStep(
                targetFolder: targetFolder,
                filter: filter,
                action: .move,
                destinationFolder: destFolder,
                explanation: "Organize files directly into categorized subfolders inside \(folderName)."
            ))
            detectedSummary = "Organize \(folderName) into structured categories."
        } else if isScreenshot {
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
        } else {
            // General cleanup or large file review
            let filter = CleaningFilter(
                categories: minSizeBytes != nil ? [.largeFiles] : nil,
                extensions: nil,
                minimumAgeDays: minAgeDays,
                minimumSizeBytes: minSizeBytes ?? (minAgeDays != nil ? nil : 200 * 1024 * 1024),
                nameContains: nil
            )
            // Only trash when the user named what to remove (an age or size); "clean up my folder" alone is a review.
            let hasCriteria = minAgeDays != nil || minSizeBytes != nil
            let action: PlannedAction = (isRemoval && hasCriteria) ? .trash : .review
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

    /// Finds the first "<number> <unit>" phrase, e.g. "30 days", "a month", "2gb". Returns the count and the matched unit.
    private func extractQuantity(units: [String], in text: String) -> (Int, String)? {
        let numberWords = ["a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
                           "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10]
        let numberPattern = "\\d+|" + numberWords.keys.sorted { $0.count > $1.count }.joined(separator: "|")
        let unitPattern = units.sorted { $0.count > $1.count }.joined(separator: "|")
        let pattern = "\\b(\(numberPattern))\\s*(\(unitPattern))s?\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let numberRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text) else {
            return nil
        }
        let numberText = String(text[numberRange])
        guard let count = Int(numberText) ?? numberWords[numberText], count > 0 else { return nil }
        return (count, String(text[unitRange]))
    }
}
