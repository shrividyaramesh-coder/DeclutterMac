import Foundation
import TidyMacCore

/// Regressions found by organizing the same folder more than once and by everyday prompt wording.
@MainActor
func runOrganizerRegressionTests() async {
    print("\n--- Running Organizer Re-Run & Prompt Wording Regression Tests ---")

    let fileManager = FileManager.default
    let tempDir = fileManager.temporaryDirectory.appendingPathComponent("TidyMacRegressionTests_\(UUID().uuidString)")
    try? fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: tempDir) }

    let defaultsSuite = "TidyMacRegressionTests_\(UUID().uuidString)"
    let preferences = CategoryPreferencesStore(defaults: UserDefaults(suiteName: defaultsSuite)!)
    let engine = FolderOrganizerEngine(preferencesStore: preferences)
    let journal = UndoJournal(storageDirectory: tempDir)

    func makeFolder(_ name: String) -> URL {
        let url = tempDir.appendingPathComponent(name)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func makeFile(_ url: URL) {
        try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        fileManager.createFile(atPath: url.path, contents: Data("x".utf8))
    }
    func listing(_ root: URL) -> [String] {
        let base = root.resolvingSymlinksInPath().path + "/"
        var paths: [String] = []
        if let enumerator = fileManager.enumerator(at: root.resolvingSymlinksInPath(), includingPropertiesForKeys: nil) {
            while let url = enumerator.nextObject() as? URL {
                paths.append(url.resolvingSymlinksInPath().path.replacingOccurrences(of: base, with: ""))
            }
        }
        return paths.sorted()
    }
    func organize(_ folder: URL, strategy: OrganizationStrategy, deep: Bool = false) async {
        let groups = await engine.analyzeFolder(targetFolder: folder, includeSubfolders: deep, strategy: strategy)
        _ = try? await engine.applyMoves(groups: groups, journal: journal, allowedRoots: [tempDir])
    }
    func candidates(in folder: URL) -> [FileItem] {
        var items: [FileItem] = []
        guard let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        while let url = enumerator.nextObject() as? URL {
            let category = CategoryClassifier.classify(url: url, fileSize: 1, createdDate: Date())
            items.append(FileItem(url: url, fileSize: 1, category: category))
        }
        return items
    }

    // 1. Organizing the same folder twice changes nothing on the second run, in every strategy
    for strategy in OrganizationStrategy.allCases {
        let folder = makeFolder("Rerun-\(strategy)".replacingOccurrences(of: " ", with: ""))
        makeFile(folder.appendingPathComponent("report.pdf"))
        makeFile(folder.appendingPathComponent("notes.txt"))
        makeFile(folder.appendingPathComponent("photo.png"))
        makeFile(folder.appendingPathComponent("Taxes 2025/w2.pdf"))
        await organize(folder, strategy: strategy)
        let afterFirstRun = listing(folder)
        await organize(folder, strategy: strategy)
        expectEqual(listing(folder), afterFirstRun, "Second \(strategy.rawValue) run leaves the folder unchanged")
    }

    // 2. A learned category's folder is not swept into Documents/Folders on the next run
    let learnedFolder = makeFolder("Learned")
    makeFile(learnedFolder.appendingPathComponent("invoice.pdf"))
    await preferences.rememberPreference(extensionKey: "pdf", category: "Finance/Invoices")
    await organize(learnedFolder, strategy: .byCategory)
    await organize(learnedFolder, strategy: .byCategory)
    expect(
        fileManager.fileExists(atPath: learnedFolder.appendingPathComponent("Finance/Invoices/invoice.pdf").path),
        "Learned category folder stays at the top level across runs"
    )
    await preferences.reset()

    // 3. Deep scan moves a project as one unit and never pulls files out of it
    let deepFolder = makeFolder("Deep")
    makeFile(deepFolder.appendingPathComponent("myrepo/.git/HEAD"))
    makeFile(deepFolder.appendingPathComponent("myrepo/build.zip"))
    makeFile(deepFolder.appendingPathComponent("myrepo/main.swift"))
    let deepGroups = await engine.analyzeFolder(targetFolder: deepFolder, includeSubfolders: true)
    let deepMoves = deepGroups.flatMap(\.moves)
    expectEqual(deepMoves.map(\.sourceRelativePath), ["myrepo"], "Deep scan proposes only the project folder itself")
    _ = try? await engine.applyMoves(groups: deepGroups, journal: journal, allowedRoots: [tempDir])
    let movedRepo = deepFolder.appendingPathComponent("Development/Projects/myrepo")
    expect(fileManager.fileExists(atPath: movedRepo.appendingPathComponent("build.zip").path), "Project keeps its archive")
    expect(fileManager.fileExists(atPath: movedRepo.appendingPathComponent("main.swift").path), "Project keeps its source")
    expect(!fileManager.fileExists(atPath: deepFolder.appendingPathComponent("Archives").path), "No files pulled out into Archives")

    // 4. Folder names match whole words only, with no personal keywords
    expectEqual(FolderOrganizerEngine.defaultCategoryName(forFolder: "Happy Birthday"), "Documents/Folders", "'Happy' does not read as 'app'")
    expectEqual(FolderOrganizerEngine.defaultCategoryName(forFolder: "Device Manuals"), "Documents/Folders", "'Device' does not read as 'dev'")
    expectEqual(FolderOrganizerEngine.defaultCategoryName(forFolder: "Charts"), "Documents/Folders", "'Charts' does not read as 'art'")
    expectEqual(FolderOrganizerEngine.defaultCategoryName(forFolder: "Party Photos"), "Media/Folders", "'Photos' still reads as media")
    expectEqual(FolderOrganizerEngine.defaultCategoryName(forFolder: "MyWebApp"), "Development/Projects", "camelCase 'App' still reads as a project")

    // 5. Prompt wording: the action wins over the file type, and words are matched whole
    let parser = OfflineHeuristicParser()
    let folderPath = tempDir.path
    func step(_ prompt: String) -> CleaningPlanStep? {
        parser.parse(prompt: prompt, defaultManagedFolder: tempDir).steps.first
    }
    expectEqual(step("organize my screenshots")?.action, .move, "'organize my screenshots' moves instead of trashing")
    expect(step("organize my screenshots")?.filter.categories?.contains(.screenshots) == true, "Organizing screenshots targets screenshots")
    expectEqual(step("sort my installers")?.action, .move, "'sort my installers' moves instead of trashing")
    expectEqual(step("organize my logo files")?.action, .move, "'logo' does not read as 'log'")
    expectEqual(step("organize my folder")?.filter.minimumAgeDays, nil, "'folder' does not read as 'old'")
    expectEqual(step("sort today's files")?.filter.minimumAgeDays, nil, "'today' does not read as 'day'")
    expectEqual(step("organize files by number")?.filter.minimumSizeBytes, nil, "'number' does not read as 'mb'")
    expectEqual(step("clean up my folder")?.action, .review, "A removal word with no criteria only reviews")
    expectEqual(step("delete files older than two weeks")?.filter.minimumAgeDays, 14, "Number words are parsed")
    expectEqual(step("trash downloads older than 3 months")?.filter.minimumAgeDays, 90, "Months are parsed")
    expectEqual(step("remove files over 500mb")?.filter.minimumSizeBytes, 500 * 1024 * 1024, "Unspaced sizes are parsed")
    expectEqual(step("organize my folder")?.targetFolder, folderPath, "Unnamed folder falls back to the managed folder")

    // 6. Agent "organize" twice: only loose files move, existing folders stay put
    let agentFolder = makeFolder("Agent")
    makeFile(agentFolder.appendingPathComponent("report.pdf"))
    makeFile(agentFolder.appendingPathComponent("photo.jpg"))
    makeFile(agentFolder.appendingPathComponent("myrepo/package.json"))
    makeFile(agentFolder.appendingPathComponent("Taxes 2025/w2.pdf"))
    var agentListings: [[String]] = []
    for _ in 1...2 {
        let plan = parser.parse(prompt: "organize this", defaultManagedFolder: agentFolder)
        let matches = await PlanExecutor.shared.dryRun(plan: plan, candidates: candidates(in: agentFolder))
        expect(matches.allSatisfy { !$0.item.url.hasDirectoryPath && $0.item.url.lastPathComponent != "w2.pdf" },
               "Organize dry run lists only loose files")
        _ = try? await PlanExecutor.shared.execute(matches: matches, journal: journal, allowedRoots: [tempDir])
        agentListings.append(listing(agentFolder))
    }
    expect(agentListings[0].contains("Documents/PDFs/report.pdf"), "Agent organize files the PDF")
    expect(agentListings[0].contains("myrepo/package.json"), "Agent organize leaves project folders in place")
    expect(agentListings[0].contains("Taxes 2025/w2.pdf"), "Agent organize leaves user folders in place")
    expectEqual(agentListings[1], agentListings[0], "Second agent organize leaves the folder unchanged")

    UserDefaults.standard.removePersistentDomain(forName: defaultsSuite)
}
