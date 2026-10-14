import Foundation

/// Engine responsible for analyzing folder contents, proposing intelligent directory structures,
/// resolving file name collisions non-destructively, and executing atomic reversible moves.
public actor FolderOrganizerEngine {
    public static let shared = FolderOrganizerEngine()
    
    private let preferencesStore: CategoryPreferencesStore
    private let fileManager: FileManager
    
    public init(
        preferencesStore: CategoryPreferencesStore = .shared,
        fileManager: FileManager = .default
    ) {
        self.preferencesStore = preferencesStore
        self.fileManager = fileManager
    }
    
    /// Analyzes files in a folder and generates proposed category groups with collision-safe targets.
    public func analyzeFolder(
        targetFolder: URL,
        baseDestination: URL? = nil
    ) async -> [OrganizationCategoryGroup] {
        let destRoot = baseDestination ?? targetFolder
        var movesByCategory: [String: [ProposedMove]] = [:]
        
        guard let enumerator = fileManager.enumerator(
            at: targetFolder,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }
        
        while let fileURL = enumerator.nextObject() as? URL {
            // Skip directories themselves
            let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if values?.isDirectory == true { continue }
            
            let ext = fileURL.pathExtension.lowercased()
            let size = Int64(values?.fileSize ?? 0)
            
            // 1. Check user-learned category preference
            let categoryName: String
            if let learned = await preferencesStore.preferredCategory(for: ext) {
                categoryName = learned
            } else {
                categoryName = Self.defaultCategoryName(forExtension: ext, filename: fileURL.lastPathComponent)
            }
            
            let categoryDestFolder = destRoot.appendingPathComponent(categoryName)
            
            // Skip files already inside their destination category folder
            let parentDir = fileURL.deletingLastPathComponent().standardizedFileURL
            if parentDir == categoryDestFolder.standardizedFileURL || fileURL.path.hasPrefix(categoryDestFolder.path + "/") {
                continue
            }
            
            // If organizing in-place (baseDestination == nil), skip files that are already
            // inside any recognized category subfolder under targetFolder (except old "Organized" remnants)
            if baseDestination == nil {
                let relativePath = fileURL.path.replacingOccurrences(of: targetFolder.path + "/", with: "")
                let pathParts = relativePath.split(separator: "/")
                if pathParts.count > 1 {
                    let topFolder = String(pathParts[0])
                    let recognizedCategories = ["Documents", "Media", "Archives", "Installers", "Development", "Other"]
                    if recognizedCategories.contains(topFolder) {
                        continue
                    }
                }
            }
            
            let targetURL = resolveCollisionSafeTarget(for: fileURL.lastPathComponent, in: categoryDestFolder)
            
            let move = ProposedMove(
                originalURL: fileURL,
                targetURL: targetURL,
                categoryName: categoryName,
                fileSize: size,
                isSelected: true
            )
            
            var existing = movesByCategory[categoryName, default: []]
            existing.append(move)
            movesByCategory[categoryName] = existing
        }
        
        // Transform dictionary into structured OrganizationCategoryGroups sorted by name
        var groups: [OrganizationCategoryGroup] = []
        for (name, moves) in movesByCategory {
            let groupFolder = destRoot.appendingPathComponent(name)
            groups.append(OrganizationCategoryGroup(
                name: name,
                destinationFolder: groupFolder,
                moves: moves
            ))
        }
        
        return groups.sorted(by: { $0.name < $1.name })
    }
    
    /// Learns a user rename for a category, updating destination paths and saving preferences.
    public func updateCategory(
        groupIndex: Int,
        newName: String,
        groups: [OrganizationCategoryGroup],
        destRoot: URL
    ) async -> [OrganizationCategoryGroup] {
        var updatedGroups = groups
        guard groupIndex >= 0 && groupIndex < updatedGroups.count else { return updatedGroups }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return updatedGroups }
        
        updatedGroups[groupIndex].name = trimmed
        let newDestFolder = destRoot.appendingPathComponent(trimmed)
        updatedGroups[groupIndex].destinationFolder = newDestFolder
        
        for i in 0..<updatedGroups[groupIndex].moves.count {
            let originalName = updatedGroups[groupIndex].moves[i].originalURL.lastPathComponent
            updatedGroups[groupIndex].moves[i].categoryName = trimmed
            updatedGroups[groupIndex].moves[i].targetURL = resolveCollisionSafeTarget(for: originalName, in: newDestFolder)
            
            // Learn preference for this extension
            let ext = updatedGroups[groupIndex].moves[i].originalURL.pathExtension.lowercased()
            if !ext.isEmpty {
                await preferencesStore.rememberPreference(extensionKey: ext, category: trimmed)
            }
        }
        return updatedGroups
    }
    
    /// Executes confirmed file relocations with guaranteed undo recording.
    public func applyMoves(
        groups: [OrganizationCategoryGroup],
        journal: UndoJournal = .shared,
        allowedRoots: [URL] = []
    ) async throws -> PlanExecutionSummary {
        let batchId = UUID()
        var processedCount = 0
        var totalBytesReclaimed: Int64 = 0
        
        for group in groups {
            let actionableMoves = group.moves.filter(\.isSelected)
            guard !actionableMoves.isEmpty else { continue }
            
            // Create target directory if needed
            try? fileManager.createDirectory(at: group.destinationFolder, withIntermediateDirectories: true)
            
            for move in actionableMoves {
                let source = move.originalURL
                
                // Validate safety
                guard PathValidator.isPathAllowed(source, allowedRoots: allowedRoots) else {
                    continue
                }
                
                // Final collision-safe target resolution right before physical move
                let finalTarget = resolveCollisionSafeTarget(for: source.lastPathComponent, in: group.destinationFolder)
                
                do {
                    try fileManager.moveItem(at: source, to: finalTarget)
                    
                    let entry = JournalEntry(
                        runId: batchId,
                        originalURL: source,
                        trashedURL: finalTarget,
                        fileSize: move.fileSize,
                        action: .moved
                    )
                    await journal.record(entry: entry)
                    processedCount += 1
                    totalBytesReclaimed += move.fileSize
                } catch {
                    // Skip and continue
                }
            }
        }
        
        return PlanExecutionSummary(
            batchId: batchId,
            itemsProcessed: processedCount,
            bytesReclaimed: totalBytesReclaimed
        )
    }
    
    /// Resolves file collision safely by generating a numbered suffix (`file (1).ext`) if destination exists.
    public func resolveCollisionSafeTarget(for filename: String, in destination: URL) -> URL {
        var target = destination.appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: target.path) else {
            return target
        }
        
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
    
    public static func defaultCategoryName(forExtension ext: String, filename: String) -> String {
        switch ext {
        case "pdf":
            return "Documents/PDFs"
        case "doc", "docx", "pages", "rtf", "txt", "md":
            return "Documents/Text & Notes"
        case "xls", "xlsx", "numbers", "csv":
            return "Documents/Spreadsheets"
        case "ppt", "pptx", "key":
            return "Documents/Presentations"
        case "jpg", "jpeg", "png", "heic", "gif", "tiff", "webp", "svg":
            if filename.lowercased().contains("screen shot") || filename.lowercased().contains("screenshot") {
                return "Media/Screenshots"
            }
            return "Media/Images"
        case "mp4", "mov", "mkv", "avi", "webm", "m4v":
            return "Media/Videos"
        case "mp3", "m4a", "wav", "flac", "aac", "aiff":
            return "Media/Audio"
        case "zip", "tar", "gz", "tgz", "bz2", "7z", "rar":
            return "Archives"
        case "dmg", "pkg", "iso":
            return "Installers"
        case "swift", "py", "js", "ts", "html", "css", "json", "yml", "yaml", "sh", "c", "cpp", "h":
            return "Development/Source Code"
        default:
            return "Other"
        }
    }
}
