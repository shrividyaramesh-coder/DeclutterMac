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

    /// Every folder name `determineCategory` can produce in any context, so a later run leaves them in place.
    public static let generatedFolderNames: Set<String> = reservedTopLevelCategories.union([
        "Folders", "No Extension", "Projects", "Source Code",
        "Images", "Videos", "Audio", "Screenshots", "AI Generated", "Banners & Graphics",
        "Photos & Pictures", "Vectors & Icons", "GIFs & Animations",
        "PDFs", "Text & Notes", "Spreadsheets", "Presentations",
        // Auto-organize folders
        "Recents", "Keep As Is", "Sorted"
    ])

    /// Whether a folder was created by this engine (any strategy) or names a learned category. These are the
    /// results of earlier runs; moving them again would nest "PDF Files" into "Folders", one month into the next, etc.
    public func isGeneratedFolder(named name: String) async -> Bool {
        if Self.generatedFolderNames.contains(name) { return true }
        if name.range(of: #"^[A-Z0-9]+ Files$"#, options: .regularExpression) != nil { return true } // By File Type
        if name.range(of: #"^\d{4}-\d{2} \(.+\)$"#, options: .regularExpression) != nil { return true } // By Date
        return await preferencesStore.learnedCategoryRoots().contains(name)
    }

    /// Discovers visible subdirectories inside `folder` up to `maxDepth` for drill-down navigation.
    public func discoverSubfolders(in folder: URL, maxDepth: Int = 2) -> [URL] {
        var subfolders: [URL] = []
        guard maxDepth > 0 else { return [] }
        
        guard let contents = try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        
        for item in contents {
            let name = item.lastPathComponent
            if name.hasPrefix(".") { continue }
            
            let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey])
            if values?.isSymbolicLink == true || values?.isPackage == true { continue }
            
            if values?.isDirectory == true {
                subfolders.append(item)
                if maxDepth > 1 {
                    let nested = discoverSubfolders(in: item, maxDepth: maxDepth - 1)
                    subfolders.append(contentsOf: nested)
                }
            }
        }
        
        return subfolders.sorted(by: { $0.path < $1.path })
    }
    
    /// Analyzes files and loose folders in a folder and generates proposed category groups with collision-safe targets.
    public func analyzeFolder(
        targetFolder: URL,
        baseDestination: URL? = nil,
        includeSubfolders: Bool = false,
        strategy: OrganizationStrategy = .byCategory
    ) async -> [OrganizationCategoryGroup] {
        let destRoot = baseDestination ?? targetFolder
        var movesByCategory: [String: [ProposedMove]] = [:]
        
        var itemsToAnalyze: [URL] = []
        
        if includeSubfolders {
            // Collect files from subdirectories recursively (up to 2500 items max for UI performance)
            if let enumerator = fileManager.enumerator(
                at: targetFolder,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey, .isPackageKey, .contentModificationDateKey, .creationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) {
                var count = 0
                while let fileURL = enumerator.nextObject() as? URL {
                    count += 1
                    if count > 2500 { break }
                    
                    let itemName = fileURL.lastPathComponent
                    if itemName.hasPrefix(".") { continue }
                    
                    let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey])
                    if values?.isSymbolicLink == true { continue }
                    
                    let isDirectory = values?.isDirectory ?? false
                    if isDirectory {
                        // Skip reserved top-level category containers
                        if Self.reservedTopLevelCategories.contains(itemName) { continue }
                        // Folders an earlier run moved as a unit stay intact; don't pull their files back out
                        if itemName == "Folders" || itemName == "Projects" {
                            enumerator.skipDescendants()
                            continue
                        }
                        // Allow project bundles as atomic units, and never split their contents into other categories
                        if !Self.isProjectOrBundleDirectory(fileURL) {
                            continue
                        }
                        enumerator.skipDescendants()
                    }
                    itemsToAnalyze.append(fileURL)
                }
            }
        } else {
            // Collect direct items in targetFolder
            guard let directItems = try? fileManager.contentsOfDirectory(
                at: targetFolder,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else {
                return []
            }
            
            itemsToAnalyze = directItems
            
            // Items to analyze: direct items + any items inside legacy targetFolder/Organized
            let legacyOrganized = targetFolder.appendingPathComponent("Organized")
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: legacyOrganized.path, isDirectory: &isDir), isDir.boolValue {
                if let legacyItems = try? fileManager.contentsOfDirectory(at: legacyOrganized, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: [.skipsHiddenFiles]) {
                    itemsToAnalyze.append(contentsOf: legacyItems)
                }
            }
        }
        
        for itemURL in itemsToAnalyze {
            let itemName = itemURL.lastPathComponent
            if itemName.hasPrefix(".") { continue }
            
            // Check if item is a directory or symlink
            let values = try? itemURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey, .contentModificationDateKey, .creationDateKey])
            if values?.isSymbolicLink == true { continue }
            let isDirectory = values?.isDirectory ?? false
            
            // Folders earlier runs created at the top level of targetFolder stay where they are
            let resolvedItemPath = itemURL.resolvingSymlinksInPath().standardizedFileURL.path
            let resolvedTargetPath = targetFolder.resolvingSymlinksInPath().standardizedFileURL.path
            let isTopLevel = (resolvedItemPath as NSString).deletingLastPathComponent == resolvedTargetPath
            if isDirectory && isTopLevel, await isGeneratedFolder(named: itemName) {
                continue
            }
            
            let categoryName: String
            let size: Int64
            
            if isDirectory {
                categoryName = await determineCategory(for: itemURL, isDirectory: true, targetFolder: targetFolder, strategy: strategy)
                size = fastFolderSize(at: itemURL)
            } else {
                categoryName = await determineCategory(for: itemURL, isDirectory: false, targetFolder: targetFolder, strategy: strategy)
                size = Int64(values?.fileSize ?? 0)
            }
            
            let categoryDestFolder = destRoot.appendingPathComponent(categoryName)
            
            // Compare resolved paths: the enumerator reports /private/var/... for a folder opened as /var/...
            let resolvedDestPath = categoryDestFolder.resolvingSymlinksInPath().standardizedFileURL.path
            
            // Never move an item into itself
            if resolvedItemPath == resolvedDestPath {
                continue
            }
            
            // Skip if item is already inside its destination category folder
            if resolvedItemPath.hasPrefix(resolvedDestPath + "/") {
                continue
            }
            
            let targetURL = resolveCollisionSafeTarget(for: itemName, in: categoryDestFolder)
            let relPath = resolvedItemPath.hasPrefix(resolvedTargetPath + "/")
                ? String(resolvedItemPath.dropFirst(resolvedTargetPath.count + 1))
                : itemName
            
            let move = ProposedMove(
                originalURL: itemURL,
                targetURL: targetURL,
                categoryName: categoryName,
                fileSize: size,
                isSelected: true,
                isDirectory: isDirectory,
                sourceRelativePath: relPath
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
            
            for move in actionableMoves {
                let source = move.originalURL
                
                // Validate safety
                guard PathValidator.isPathAllowed(source, allowedRoots: allowedRoots) else {
                    validationFailureCount += 1
                    continue
                }
                
                // Create the target directory only when something will actually move into it
                guard fileManager.fileExists(atPath: source.path) else { continue }
                do {
                    try fileManager.createDirectory(at: group.destinationFolder, withIntermediateDirectories: true)
                } catch {
                    lastError = error
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
    
    /// Determines whether a folder is a recognized software project or bundle (e.g. Node, Git, Rust, Xcode).
    public static func isProjectOrBundleDirectory(_ url: URL) -> Bool {
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: url.path) {
            let lower = contents.map { $0.lowercased() }
            return lower.contains("package.json") || lower.contains(".git") || lower.contains("cargo.toml") || lower.contains("cmakelists.txt") || lower.contains("podfile") || lower.contains("gemfile")
        }
        return false
    }
    
    /// Determines the best category name for a file or folder given targetFolder context and chosen strategy.
    public func determineCategory(
        for itemURL: URL,
        isDirectory: Bool,
        targetFolder: URL,
        strategy: OrganizationStrategy
    ) async -> String {
        let itemName = itemURL.lastPathComponent
        let ext = itemURL.pathExtension.lowercased()
        
        // 1. By Date Strategy
        if strategy == .byDate {
            let values = try? itemURL.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
            let date = values?.contentModificationDate ?? values?.creationDate ?? Date()
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM (MMMM)"
            return formatter.string(from: date)
        }
        
        // 2. By File Type Strategy
        if strategy == .byType {
            if isDirectory { return "Folders" }
            if ext.isEmpty { return "No Extension" }
            return "\(ext.uppercased()) Files"
        }
        
        // 3. Smart Categories Strategy
        let folderName = targetFolder.lastPathComponent.lowercased()
        let isImagesFolder = Self.nameHasWord(targetFolder.lastPathComponent, ["image", "photo", "pic", "picture"])
        
        // Context 3A: Organizing an Images folder directly (e.g. Downloads/Media/Images)
        if isImagesFolder {
            if isDirectory { return "Folders" }
            let lower = itemName.lowercased()
            if lower.contains("screenshot") || lower.contains("screen shot") || lower.contains("cleanshot") || lower.contains("capture") {
                return "Screenshots"
            }
            if lower.contains("chatgpt") || lower.contains("gemini") || lower.contains("dall-e") || lower.contains("dalle") || lower.contains("midjourney") || lower.contains("synthetic") {
                return "AI Generated"
            }
            if lower.contains("banner") || lower.contains("showcase") || lower.contains("logo") || lower.contains("mockup") || lower.contains("flyer") || lower.contains("poster") || lower.contains("header") || lower.contains("graphic") {
                return "Banners & Graphics"
            }
            if ext == "heic" || ext == "raw" || ext == "cr2" || ext == "nef" || ext == "dng" || lower.contains("img_") || lower.contains("dsc_") || lower.contains("photo") || lower.contains("whatsapp image") {
                return "Photos & Pictures"
            }
            if ext == "svg" || ext == "ai" || ext == "eps" {
                return "Vectors & Icons"
            }
            if ext == "gif" {
                return "GIFs & Animations"
            }
            return "Photos & Pictures"
        }
        
        // Context 3B: Organizing Media folder directly (e.g. Downloads/Media)
        if folderName == "media" {
            if isDirectory {
                let lower = itemName.lowercased()
                if lower.contains("image") || lower.contains("photo") { return "Images" }
                if lower.contains("video") || lower.contains("movie") { return "Videos" }
                if lower.contains("audio") || lower.contains("music") { return "Audio" }
                return "Folders"
            }
            switch ext {
            case "jpg", "jpeg", "png", "heic", "gif", "tiff", "webp", "svg":
                if itemName.lowercased().contains("screen shot") || itemName.lowercased().contains("screenshot") {
                    return "Screenshots"
                }
                return "Images"
            case "mp4", "mov", "mkv", "avi", "webm", "m4v":
                return "Videos"
            case "mp3", "m4a", "wav", "flac", "aac", "aiff":
                return "Audio"
            default:
                return "Other"
            }
        }
        
        // Context 3C: Organizing Documents folder directly (e.g. Downloads/Documents)
        if folderName == "documents" || folderName == "document" {
            if isDirectory {
                let cat = Self.defaultCategoryName(forFolder: itemName, folderURL: itemURL)
                return cat.replacingOccurrences(of: "Documents/", with: "")
            }
            let cat = Self.defaultCategoryName(forExtension: ext, filename: itemName)
            return cat.replacingOccurrences(of: "Documents/", with: "")
        }
        
        // Context 3D: Organizing Development folder directly (e.g. Downloads/Development)
        if folderName == "development" || folderName == "dev" || folderName == "code" {
            if isDirectory { return "Projects" }
            return "Source Code"
        }
        
        // Context 3E: General Folder (e.g. Downloads, Desktop, or arbitrary directory)
        if isDirectory {
            return Self.defaultCategoryName(forFolder: itemName, folderURL: itemURL)
        } else {
            if let learned = await preferencesStore.preferredCategory(for: ext) {
                return learned
            }
            return Self.defaultCategoryName(forExtension: ext, filename: itemName)
        }
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
        // 1. Code / Development projects
        if nameHasWord(folderName, ["project", "dev", "development", "developer", "code", "source", "src",
                                    "app", "repo", "git", "github", "sdk"]) {
            return "Development/Projects"
        }
        
        // 2. Media / Albums
        if nameHasWord(folderName, ["photo", "video", "image", "pic", "picture", "art", "artwork", "drawing",
                                    "album", "audio", "music", "media", "movie", "song", "wallpaper"]) {
            return "Media/Folders"
        }
        
        // 3. Installers
        if nameHasWord(folderName, ["installer", "setup"]) {
            return "Installers/Folders"
        }
        
        // 4. Archives
        if nameHasWord(folderName, ["archive", "backup", "zip", "extracted"]) {
            return "Archives/Folders"
        }
        
        // 5. Classes / Education / Work / Documents
        if nameHasWord(folderName, ["class", "course", "lecture", "material", "study", "school", "college",
                                    "paper", "doc", "document", "work", "report", "note", "homework", "assignment"]) {
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
    
    /// Whether a name contains one of `keywords` as a whole word (or its plural). Splits camelCase and
    /// separators, so "MyWebApp" and "class_notes" match "app" and "class" while "Happy" and "Party" don't.
    static func nameHasWord(_ name: String, _ keywords: [String]) -> Bool {
        var spaced = ""
        var previous: Character? = nil
        for character in name {
            if let previous, previous.isLowercase, character.isUppercase { spaced.append(" ") }
            spaced.append(character)
            previous = character
        }
        let words = Set(spaced.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        return keywords.contains { words.contains($0) || words.contains($0 + "s") || words.contains($0 + "es") }
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
