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
    
    // Reserved top-level category names that must NEVER be moved or re-organized into themselves
    public static let reservedTopLevelCategories: Set<String> = [
        "Documents", "Media", "Archives", "Installers", "Development", "Other", "Organized"
    ]
    
    /// Analyzes files and loose folders in a folder and generates proposed category groups with collision-safe targets.
    public func analyzeFolder(
        targetFolder: URL,
        baseDestination: URL? = nil
    ) async -> [OrganizationCategoryGroup] {
        let destRoot = baseDestination ?? targetFolder
        var movesByCategory: [String: [ProposedMove]] = [:]
        
        // 1. Collect direct items in targetFolder
        guard let directItems = try? fileManager.contentsOfDirectory(
            at: targetFolder,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        
        // Items to analyze: direct items + any items inside legacy targetFolder/Organized
        var itemsToAnalyze: [URL] = directItems
        let legacyOrganized = targetFolder.appendingPathComponent("Organized")
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: legacyOrganized.path, isDirectory: &isDir), isDir.boolValue {
            if let legacyItems = try? fileManager.contentsOfDirectory(at: legacyOrganized, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: [.skipsHiddenFiles]) {
                itemsToAnalyze.append(contentsOf: legacyItems)
            }
        }
        
        for itemURL in itemsToAnalyze {
            let itemName = itemURL.lastPathComponent
            if itemName.hasPrefix(".") { continue }
            
            // Check if item is a directory
            let values = try? itemURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            let isDirectory = values?.isDirectory ?? false
            
            // If it's a reserved category folder at the top level of targetFolder, skip it
            if isDirectory && Self.reservedTopLevelCategories.contains(itemName) && itemURL.deletingLastPathComponent().standardizedFileURL == targetFolder.standardizedFileURL {
                continue
            }
            
            let categoryName: String
            let size: Int64
            
            if isDirectory {
                // Determine category for loose folder
                categoryName = Self.defaultCategoryName(forFolder: itemName, folderURL: itemURL)
                size = fastFolderSize(at: itemURL)
            } else {
                let ext = itemURL.pathExtension.lowercased()
                if let learned = await preferencesStore.preferredCategory(for: ext) {
                    categoryName = learned
                } else {
                    categoryName = Self.defaultCategoryName(forExtension: ext, filename: itemName)
                }
                size = Int64(values?.fileSize ?? 0)
            }
            
            let categoryDestFolder = destRoot.appendingPathComponent(categoryName)
            
            // Skip if item is already inside its destination category folder
            let parentDir = itemURL.deletingLastPathComponent().standardizedFileURL
            if parentDir == categoryDestFolder.standardizedFileURL || itemURL.path.hasPrefix(categoryDestFolder.path + "/") {
                continue
            }
            
            let targetURL = resolveCollisionSafeTarget(for: itemName, in: categoryDestFolder)
            
            let move = ProposedMove(
                originalURL: itemURL,
                targetURL: targetURL,
                categoryName: categoryName,
                fileSize: size,
                isSelected: true,
                isDirectory: isDirectory
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
        var lastError: Error? = nil
        var validationFailureCount = 0
        
        let allActionable = groups.flatMap(\.moves).filter(\.isSelected)
        
        for group in groups {
            let actionableMoves = group.moves.filter(\.isSelected)
            guard !actionableMoves.isEmpty else { continue }
            
            // Create target directory if needed
            do {
                try fileManager.createDirectory(at: group.destinationFolder, withIntermediateDirectories: true)
            } catch {
                lastError = error
                continue
            }
            
            for move in actionableMoves {
                let source = move.originalURL
                
                // Validate safety
                guard PathValidator.isPathAllowed(source, allowedRoots: allowedRoots) else {
                    validationFailureCount += 1
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
                    lastError = error
                }
            }
        }
        
        if processedCount == 0 && !allActionable.isEmpty {
            if let err = lastError {
                throw err
            } else if validationFailureCount > 0 {
                throw SecurityError.protectedPath("Selected files were rejected by safety invariants.")
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
    
    /// Classifies a loose folder based on its title and internal file signatures.
    public static func defaultCategoryName(forFolder folderName: String, folderURL: URL? = nil) -> String {
        let name = folderName.lowercased()
        
        // 1. Code / Development projects
        if name.contains("project") || name.contains("dev") || name.contains("code") ||
           name.contains("app") || name.contains("repo") || name.contains("git") ||
           name.contains("stitch") || name.contains("starter") || name.contains("utility") {
            return "Development/Projects"
        }
        
        // 2. Media / Albums
        if name.contains("photo") || name.contains("video") || name.contains("image") ||
           name.contains("pic") || name.contains("art") || name.contains("draw") ||
           name.contains("nail") || name.contains("album") || name.contains("audio") ||
           name.contains("music") || name.contains("media") {
            return "Media/Folders"
        }
        
        // 3. Installers
        if name.contains("installer") || name.contains("setup") || name.contains("cleanable") {
            return "Installers/Folders"
        }
        
        // 4. Archives
        if name.contains("archive") || name.contains("backup") || name.contains("zip") || name.contains("extracted") {
            return "Archives/Folders"
        }
        
        // 5. Classes / Education / Work / Documents
        if name.contains("class") || name.contains("course") || name.contains("lecture") ||
           name.contains("material") || name.contains("study") || name.contains("school") ||
           name.contains("college") || name.contains("paper") || name.contains("doc") ||
           name.contains("work") || name.contains("report") || name.contains("consumer") ||
           name.contains("shriv") || name.contains("personal") || name.contains("general") {
            return "Documents/Folders"
        }
        
        // 6. Inspect contents if URL provided
        if let folderURL = folderURL, let contents = try? FileManager.default.contentsOfDirectory(atPath: folderURL.path) {
            let lowerContents = contents.map { $0.lowercased() }
            if lowerContents.contains(where: { $0 == "package.json" || $0.hasSuffix(".swift") || $0.hasSuffix(".py") || $0.hasSuffix(".js") || $0 == ".git" }) {
                return "Development/Projects"
            }
            if lowerContents.contains(where: { $0.hasSuffix(".png") || $0.hasSuffix(".jpg") || $0.hasSuffix(".jpeg") || $0.hasSuffix(".mp4") }) {
                return "Media/Folders"
            }
        }
        
        return "Documents/Folders"
    }
    
    /// Calculates folder size quickly with an iteration limit to maintain UI responsiveness.
    public func fastFolderSize(at url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return 0
        }
        var total: Int64 = 0
        var count = 0
        while let fileURL = enumerator.nextObject() as? URL {
            count += 1
            if count > 500 { break }
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            if values?.isDirectory != true {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }
}
