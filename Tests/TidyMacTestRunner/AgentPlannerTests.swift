import Foundation
import TidyMacCore

@MainActor
func runAgentPlannerTests() async {
    print("\n--- Running Natural-Language Agent & Dry-Run Tests ---")
    
    let parser = OfflineHeuristicParser()
    
    // 1. Metadata-Only AI Boundary Test
    let metadataEntry = FileMetadataEntry(
        filename: "presentation.key",
        fileExtension: "key",
        sizeBytes: 15_000_000,
        relativeFolderPath: "Documents/Work"
    )
    expectEqual(metadataEntry.filename, "presentation.key", "Metadata entry stores filename")
    expectEqual(metadataEntry.sizeBytes, 15_000_000, "Metadata entry stores size")
    
    let request = MetadataOnlyRequest(
        userPrompt: "Clean old documents",
        files: [metadataEntry],
        targetFolders: ["~/Documents"]
    )
    expectEqual(request.files.count, 1, "Metadata request contains entries")
    
    // 2. Offline Heuristic Parser Tests
    // Test: Screenshots older than a month
    let screenshotPlan = parser.parse(prompt: "delete screenshots older than a month")
    expectEqual(screenshotPlan.steps.count, 1, "Screenshot query generates 1 plan step")
    let screenshotStep = screenshotPlan.steps.first
    expect(screenshotStep?.filter.categories?.contains(.screenshots) == true, "Filter targets .screenshots category")
    expectEqual(screenshotStep?.filter.minimumAgeDays, 30, "A month maps to 30 days minimum age")
    expectEqual(screenshotStep?.action, .trash, "Action is trash")
    
    // Test: Installers older than 7 days
    let installerPlan = parser.parse(prompt: "trash installers and disk images older than 7 days")
    expectEqual(installerPlan.steps.count, 1, "Installer query generates 1 plan step")
    let installerStep = installerPlan.steps.first
    expect(installerStep?.filter.categories?.contains(.oldDownloads) == true, "Filter targets .oldDownloads category")
    expectEqual(installerStep?.filter.minimumAgeDays, 7, "Installer age parsed as 7 days")
    expectEqual(installerStep?.action, .trash, "Action is trash")
    
    // Test: Large files over 1 GB
    let largeFilePlan = parser.parse(prompt: "find large files over 1 gb")
    expectEqual(largeFilePlan.steps.count, 1, "Large files query generates 1 step")
    let largeStep = largeFilePlan.steps.first
    expectEqual(largeStep?.filter.minimumSizeBytes, 1024 * 1024 * 1024, "Parses 1 GB minimum size")
    
    // Test: Caches and logs
    let cachePlan = parser.parse(prompt: "clear user caches and logs")
    expectEqual(cachePlan.steps.count, 1, "Cache/log query generates 1 step")
    let cacheStep = cachePlan.steps.first
    expect(cacheStep?.filter.categories?.contains(.caches) == true, "Targets caches")
    expect(cacheStep?.filter.categories?.contains(.logs) == true, "Targets logs")
    expectEqual(cacheStep?.action, .trash, "Action is trash")
    
    // Test: Organize downloads
    let organizePlan = parser.parse(prompt: "organize my Downloads")
    let organizeStep = organizePlan.steps.first
    expectEqual(organizeStep?.action, .move, "Organize intent maps to move action")
    expect(organizeStep?.destinationFolder != nil, "Move action specifies destination folder")
    
    // 3. Schema Validation Tests
    // Valid plan
    do {
        try CleaningPlanSchema.validate(screenshotPlan)
        expect(true, "Screenshot plan passes schema validation")
    } catch {
        expect(false, "Screenshot plan should pass validation: \(error)")
    }
    
    // Invalid plan: empty goal
    let emptyGoalPlan = CleaningPlan(userGoal: "", steps: screenshotPlan.steps, summary: "Empty")
    do {
        try CleaningPlanSchema.validate(emptyGoalPlan)
        expect(false, "Schema must reject empty user goal")
    } catch {
        expect(true, "Schema correctly rejected empty user goal")
    }
    
    // Invalid plan: protected root target
    let systemRootPlan = CleaningPlan(
        userGoal: "Purge system",
        steps: [
            CleaningPlanStep(
                targetFolder: "/System",
                filter: CleaningFilter(categories: [.caches]),
                action: .trash,
                explanation: "Unsafe"
            )
        ],
        summary: "Unsafe"
    )
    do {
        try CleaningPlanSchema.validate(systemRootPlan)
        expect(false, "Schema must reject targeting /System")
    } catch {
        expect(true, "Schema correctly rejected targeting /System")
    }
    
    // 4. Dry-Run & Safe Execution Tests
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("TidyMacAgentTests_\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    
    defer {
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    let oldScreenshotFile = tempDir.appendingPathComponent("Screen Shot 2024-01-01.png")
    FileManager.default.createFile(atPath: oldScreenshotFile.path, contents: Data(repeating: 0x55, count: 40_000))
    
    let recentScreenshotFile = tempDir.appendingPathComponent("Screen Shot 2026-10-10.png")
    FileManager.default.createFile(atPath: recentScreenshotFile.path, contents: Data(repeating: 0x66, count: 40_000))
    
    let sensitiveFile = tempDir.appendingPathComponent("sensitiveScreenshot.png")
    FileManager.default.createFile(atPath: sensitiveFile.path, contents: Data(repeating: 0x77, count: 10_000))
    
    let oldDate = Calendar.current.date(byAdding: .day, value: -60, to: Date()) ?? Date()
    let recentDate = Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date()
    
    let oldCandidate = FileItem(
        url: oldScreenshotFile,
        fileSize: 40_000,
        lastModifiedDate: oldDate,
        category: .screenshots,
        riskLabel: .safe
    )
    
    let recentCandidate = FileItem(
        url: recentScreenshotFile,
        fileSize: 40_000,
        lastModifiedDate: recentDate,
        category: .screenshots,
        riskLabel: .review
    )
    
    let manualCandidate = FileItem(
        url: sensitiveFile,
        fileSize: 10_000,
        lastModifiedDate: oldDate,
        category: .screenshots,
        riskLabel: .manual
    )
    
    // Dry run evaluation
    let matches = await PlanExecutor.shared.dryRun(
        plan: screenshotPlan,
        candidates: [oldCandidate, recentCandidate, manualCandidate]
    )
    
    // Only items older than 30 days should match
    expectEqual(matches.count, 2, "2 items matched age filter (>30 days)")
    
    let oldMatch = matches.first { $0.item.url == oldScreenshotFile }
    expect(oldMatch?.canExecute == true, "Safe old screenshot can be executed")
    expect(oldMatch?.isSelected == true, "Safe old screenshot is pre-selected")
    
    let manualMatch = matches.first { $0.item.url == sensitiveFile }
    expect(manualMatch?.canExecute == false, "Manual risk item can NEVER be executed")
    expect(manualMatch?.isSelected == false, "Manual risk item is never selected")
    
    // Execution test
    let summary = try? await PlanExecutor.shared.execute(
        matches: matches,
        journal: UndoJournal.shared,
        allowedRoots: [tempDir]
    )
    
    expectEqual(summary?.itemsProcessed, 1, "Only actionable safe item was processed")
    expect(!FileManager.default.fileExists(atPath: oldScreenshotFile.path), "Safe item was trashed")
    expect(FileManager.default.fileExists(atPath: sensitiveFile.path), "Manual item was preserved intact on disk")
}
