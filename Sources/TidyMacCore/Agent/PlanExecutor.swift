import Foundation

/// Result of evaluating a file against plan criteria during dry run.
public struct PlanMatchResult: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let item: FileItem
    public let action: PlannedAction
    public let destinationFolder: String?
    public let explanation: String
    public var isSelected: Bool
    public var canExecute: Bool
    
    public init(
        id: UUID = UUID(),
        item: FileItem,
        action: PlannedAction,
        destinationFolder: String? = nil,
        explanation: String,
        isSelected: Bool = true
    ) {
        self.id = id
        self.item = item
        self.action = action
        self.destinationFolder = destinationFolder
        self.explanation = explanation
        let isMove = (action == .move)
        // Organization moves are non-destructive, so items can be selected and executed.
        // Trashing/cleaning strictly prevents manual-risk items from being selected or executed.
        self.isSelected = (isMove || item.riskLabel != .manual) && isSelected
        self.canExecute = isMove || (item.riskLabel != .manual)
    }
}

/// Execution summary returned after confirmed plan execution.
public struct PlanExecutionSummary: Sendable, Equatable {
    public let batchId: UUID
    public let itemsProcessed: Int
    public let bytesReclaimed: Int64
    public let timestamp: Date
    
    public init(batchId: UUID, itemsProcessed: Int, bytesReclaimed: Int64, timestamp: Date = Date()) {
        self.batchId = batchId
        self.itemsProcessed = itemsProcessed
        self.bytesReclaimed = bytesReclaimed
        self.timestamp = timestamp
    }
}

/// Evaluates dry-run candidate matches and executes confirmed actions safely.
public actor PlanExecutor {
    public static let shared = PlanExecutor()
    
    private let trashMover: TrashMover
    
    public init(trashMover: TrashMover = .shared) {
        self.trashMover = trashMover
    }
    
    /// Evaluates candidate files against plan steps without modifying disk (DRY RUN).
    public func dryRun(plan: CleaningPlan, candidates: [FileItem]) -> [PlanMatchResult] {
        var results: [PlanMatchResult] = []
        let now = Date()
        
        for candidate in candidates {
            for step in plan.steps {
                if matches(file: candidate, filter: step.filter, relativeTo: now) {
                    let isMove = (step.action == .move)
                    let result = PlanMatchResult(
                        item: candidate,
                        action: step.action,
                        destinationFolder: step.destinationFolder,
                        explanation: step.explanation,
                        isSelected: isMove ? true : (candidate.riskLabel == .safe)
                    )
                    results.append(result)
                    break // First matching step takes precedence
                }
            }
        }
        
        return results
    }
    
    /// Executes confirmed plan actions. All trashes and moves are journaled for full undo.
    public func execute(
        matches: [PlanMatchResult],
        journal: UndoJournal = .shared,
        allowedRoots: [URL] = []
    ) async throws -> PlanExecutionSummary {
        let batchId = UUID()
        var processedCount = 0
        var totalBytesReclaimed: Int64 = 0
        
        let actionableMatches = matches.filter { $0.isSelected && $0.canExecute }
        
        for match in actionableMatches {
            let fileURL = match.item.url
            
            // Re-validate safety invariants
            guard PathValidator.isPathAllowed(fileURL, allowedRoots: allowedRoots) else {
                continue
            }
            
            switch match.action {
            case .trash:
                do {
                    let trashedURL = try await trashMover.moveToTrash(at: fileURL, allowedRoots: allowedRoots)
                    let entry = JournalEntry(
                        runId: batchId,
                        originalURL: fileURL,
                        trashedURL: trashedURL,
                        fileSize: match.item.fileSize,
                        action: .trashed
                    )
                    await journal.record(entry: entry)
                    processedCount += 1
                    totalBytesReclaimed += match.item.fileSize
                } catch {
                    // Safe skip on error
                }
                
            case .move:
                guard let destDir = match.destinationFolder else { continue }
                let destFolderURL = URL(fileURLWithPath: destDir)
                
                // If destination folder is the target folder itself (organizing in-place),
                // categorize the file into its category subfolder (e.g. Downloads/Documents/PDFs)
                let categoryDestFolder: URL
                if fileURL.deletingLastPathComponent().standardizedFileURL == destFolderURL.standardizedFileURL ||
                   destFolderURL.standardizedFileURL.path == fileURL.deletingLastPathComponent().path {
                    let ext = fileURL.pathExtension.lowercased()
                    let categoryName = FolderOrganizerEngine.defaultCategoryName(forExtension: ext, filename: fileURL.lastPathComponent)
                    categoryDestFolder = destFolderURL.appendingPathComponent(categoryName)
                } else {
                    categoryDestFolder = destFolderURL
                }
                
                // If file is already inside its destination folder, skip
                if fileURL.deletingLastPathComponent().standardizedFileURL == categoryDestFolder.standardizedFileURL {
                    continue
                }
                
                try? FileManager.default.createDirectory(at: categoryDestFolder, withIntermediateDirectories: true)
                let targetURL = resolveCollision(for: fileURL.lastPathComponent, in: categoryDestFolder)
                
                do {
                    try FileManager.default.moveItem(at: fileURL, to: targetURL)
                    let entry = JournalEntry(
                        runId: batchId,
                        originalURL: fileURL,
                        trashedURL: targetURL,
                        fileSize: match.item.fileSize,
                        action: .moved
                    )
                    await journal.record(entry: entry)
                    processedCount += 1
                } catch {
                    // Continue with remaining items
                }
                
            case .review:
                // Review items are non-destructive and left intact
                break
            }
        }
        
        return PlanExecutionSummary(
            batchId: batchId,
            itemsProcessed: processedCount,
            bytesReclaimed: totalBytesReclaimed
        )
    }
    
    private func matches(file: FileItem, filter: CleaningFilter, relativeTo now: Date) -> Bool {
        // Category check
        if let categories = filter.categories, !categories.isEmpty {
            if !categories.contains(file.category) {
                return false
            }
        }
        
        // Extension check
        if let extensions = filter.extensions, !extensions.isEmpty {
            let ext = file.url.pathExtension.lowercased()
            if !extensions.map({ $0.lowercased() }).contains(ext) {
                return false
            }
        }
        
        // Age check
        if let minAge = filter.minimumAgeDays {
            let referenceDate = file.lastModifiedDate
            let ageDays = Calendar.current.dateComponents([.day], from: referenceDate, to: now).day ?? 0
            if ageDays < minAge {
                return false
            }
        }
        
        // Size check
        if let minSize = filter.minimumSizeBytes {
            if file.fileSize < minSize {
                return false
            }
        }
        
        // Name contains check
        if let nameSub = filter.nameContains, !nameSub.isEmpty {
            if !file.url.lastPathComponent.localizedCaseInsensitiveContains(nameSub) {
                return false
            }
        }
        
        return true
    }
    
    private func resolveCollision(for filename: String, in destination: URL) -> URL {
        var target = destination.appendingPathComponent(filename)
        var counter = 1
        let nameWithoutExt = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        
        while FileManager.default.fileExists(atPath: target.path) {
            let newName = ext.isEmpty ? "\(nameWithoutExt) (\(counter))" : "\(nameWithoutExt) (\(counter)).\(ext)"
            target = destination.appendingPathComponent(newName)
            counter += 1
        }
        return target
    }
}
