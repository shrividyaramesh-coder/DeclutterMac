import Foundation

/// Actor managing cleanup rules, rule persistence, rule matching evaluation, and atomic reversible execution.
public actor RuleEngine {
    public static let shared = RuleEngine()
    
    private let storageKey = "TidyMacCleanupRules"
    private var rules: [CleanupRule] = []
    private let trashMover: TrashMover
    private let journal: UndoJournal
    private let fileManager: FileManager
    
    public init(
        trashMover: TrashMover = .shared,
        journal: UndoJournal = .shared,
        fileManager: FileManager = .default
    ) {
        self.trashMover = trashMover
        self.journal = journal
        self.fileManager = fileManager
        self.rules = Self.loadStoredRules()
    }
    
    private static func loadStoredRules() -> [CleanupRule] {
        if let data = UserDefaults.standard.data(forKey: "TidyMacCleanupRules"),
           let decoded = try? JSONDecoder().decode([CleanupRule].self, from: data) {
            return decoded
        }
        return BuiltInRuleTemplates.defaultRules()
    }
    
    private func saveRules() {
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    
    public func getRules() -> [CleanupRule] {
        rules
    }
    
    public func addOrUpdateRule(_ rule: CleanupRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
        } else {
            rules.append(rule)
        }
        saveRules()
    }
    
    public func deleteRule(id: UUID) {
        rules.removeAll { $0.id == id && !$0.isBuiltIn }
        saveRules()
    }
    
    public func toggleRule(id: UUID, isEnabled: Bool) {
        if let index = rules.firstIndex(where: { $0.id == id }) {
            rules[index].isEnabled = isEnabled
            saveRules()
        }
    }
    
    public func resetToDefaults() {
        rules = BuiltInRuleTemplates.defaultRules()
        saveRules()
    }
    
    /// Evaluates whether a file item satisfies a rule's trigger criteria.
    public func matches(file: FileItem, trigger: RuleTrigger, relativeTo now: Date = Date()) -> Bool {
        // 1. Invariant: Manual items are strictly protected and never actionable
        guard file.riskLabel != .manual else { return false }
        
        // 2. Folder match
        if let folder = trigger.folderPath, !folder.isEmpty {
            let expandedFolder = (folder as NSString).expandingTildeInPath
            if !file.url.path.hasPrefix(expandedFolder) {
                return false
            }
        }
        
        // 3. Category match
        if let categories = trigger.categories, !categories.isEmpty {
            if !categories.contains(file.category) {
                return false
            }
        }
        
        // 4. File extension match
        if let extensions = trigger.fileExtensions, !extensions.isEmpty {
            let ext = file.url.pathExtension.lowercased()
            if !extensions.map({ $0.lowercased() }).contains(ext) {
                return false
            }
        }
        
        // 5. Minimum age match
        if let minAge = trigger.minimumAgeDays {
            let ageDays = Calendar.current.dateComponents([.day], from: file.lastModifiedDate, to: now).day ?? 0
            if ageDays < minAge {
                return false
            }
        }
        
        // 6. Minimum size match
        if let minSize = trigger.minimumSizeBytes {
            if file.fileSize < minSize {
                return false
            }
        }
        
        // 7. Name pattern match
        if let pattern = trigger.namePattern, !pattern.isEmpty {
            if !file.url.lastPathComponent.localizedCaseInsensitiveContains(pattern) {
                return false
            }
        }
        
        return true
    }
    
    /// Executes a list of rules against candidate files with full safety invariants and undo journaling.
    public func executeRules(
        rulesToRun: [CleanupRule],
        candidates: [FileItem],
        allowedRoots: [URL] = []
    ) async throws -> PlanExecutionSummary {
        let batchId = UUID()
        var processedCount = 0
        var totalBytesReclaimed: Int64 = 0
        let now = Date()
        
        for rule in rulesToRun where rule.isEnabled {
            for file in candidates {
                guard matches(file: file, trigger: rule.trigger, relativeTo: now) else {
                    continue
                }
                
                let fileURL = file.url
                guard PathValidator.isPathAllowed(fileURL, allowedRoots: allowedRoots) else {
                    continue
                }
                
                switch rule.action {
                case .moveToTrash:
                    do {
                        let trashedURL = try await trashMover.moveToTrash(at: fileURL, allowedRoots: allowedRoots)
                        let entry = JournalEntry(
                            runId: batchId,
                            originalURL: fileURL,
                            trashedURL: trashedURL,
                            fileSize: file.fileSize,
                            action: .trashed
                        )
                        await journal.record(entry: entry)
                        processedCount += 1
                        totalBytesReclaimed += file.fileSize
                    } catch {
                        // Skip failed trashing
                    }
                    
                case .moveToFolder(let destPath):
                    let expandedDest = (destPath as NSString).expandingTildeInPath
                    let destFolderURL = URL(fileURLWithPath: expandedDest)
                    try? fileManager.createDirectory(at: destFolderURL, withIntermediateDirectories: true)
                    
                    let targetURL = resolveCollisionSafeTarget(for: fileURL.lastPathComponent, in: destFolderURL)
                    do {
                        try fileManager.moveItem(at: fileURL, to: targetURL)
                        let entry = JournalEntry(
                            runId: batchId,
                            originalURL: fileURL,
                            trashedURL: targetURL,
                            fileSize: file.fileSize,
                            action: .moved
                        )
                        await journal.record(entry: entry)
                        processedCount += 1
                    } catch {
                        // Skip failed move
                    }
                    
                case .reviewOnly:
                    // Non-destructive review action
                    break
                }
            }
        }
        
        return PlanExecutionSummary(
            batchId: batchId,
            itemsProcessed: processedCount,
            bytesReclaimed: totalBytesReclaimed
        )
    }
    
    private func resolveCollisionSafeTarget(for filename: String, in destination: URL) -> URL {
        var target = destination.appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: target.path) else { return target }
        
        let nameWithoutExt = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var counter = 1
        
        while fileManager.fileExists(atPath: target.path) {
            let newName = ext.isEmpty ? "\(nameWithoutExt) (\(counter))" : "\(nameWithoutExt) (\(counter)).\(ext)"
            target = destination.appendingPathComponent(newName)
            counter += 1
        }
        return target
    }
}
