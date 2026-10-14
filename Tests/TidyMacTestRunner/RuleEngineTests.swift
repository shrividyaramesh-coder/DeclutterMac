import Foundation
import TidyMacCore

@MainActor
func runRuleEngineTests() async {
    print("\n--- Running RuleEngine & ScheduleCoordinator Tests ---")
    
    // 1. Built-in Templates Library Test
    let defaultTemplates = BuiltInRuleTemplates.defaultRules()
    expect(defaultTemplates.count >= 10, "Provides at least 10 built-in rule templates (found: \(defaultTemplates.count))")
    
    let engine = RuleEngine.shared
    await engine.resetToDefaults()
    let rules = await engine.getRules()
    expectEqual(rules.count, defaultTemplates.count, "RuleEngine successfully loaded default template rules")
    
    // 2. Trigger Evaluation Tests
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("TidyMacRuleTests_\(UUID().uuidString)")
    let downloadsDir = tempDir.appendingPathComponent("Downloads")
    try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
    
    defer {
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    let oldInstallerFile = downloadsDir.appendingPathComponent("installer.dmg")
    FileManager.default.createFile(atPath: oldInstallerFile.path, contents: Data(repeating: 0x99, count: 50_000))
    
    let recentInstallerFile = downloadsDir.appendingPathComponent("recent.dmg")
    FileManager.default.createFile(atPath: recentInstallerFile.path, contents: Data(repeating: 0x88, count: 50_000))
    
    let manualItemFile = downloadsDir.appendingPathComponent("system.dmg")
    FileManager.default.createFile(atPath: manualItemFile.path, contents: Data(repeating: 0x77, count: 50_000))
    
    let now = Date()
    let oldDate = Calendar.current.date(byAdding: .day, value: -15, to: now) ?? now
    let recentDate = Calendar.current.date(byAdding: .day, value: -2, to: now) ?? now
    
    let oldInstallerItem = FileItem(
        url: oldInstallerFile,
        fileSize: 50_000,
        lastModifiedDate: oldDate,
        category: .oldDownloads,
        riskLabel: .safe
    )
    
    let recentInstallerItem = FileItem(
        url: recentInstallerFile,
        fileSize: 50_000,
        lastModifiedDate: recentDate,
        category: .oldDownloads,
        riskLabel: .review
    )
    
    let manualItem = FileItem(
        url: manualItemFile,
        fileSize: 50_000,
        lastModifiedDate: oldDate,
        category: .oldDownloads,
        riskLabel: .manual
    )
    
    let installerRule = CleanupRule(
        name: "Test Installer Rule",
        description: "Test rule",
        trigger: RuleTrigger(fileExtensions: ["dmg"], minimumAgeDays: 7),
        action: .moveToTrash
    )
    
    let matchesOld = await engine.matches(file: oldInstallerItem, trigger: installerRule.trigger, relativeTo: now)
    expect(matchesOld, "Old installer matches trigger (> 7 days, .dmg)")
    
    let matchesRecent = await engine.matches(file: recentInstallerItem, trigger: installerRule.trigger, relativeTo: now)
    expect(!matchesRecent, "Recent installer does NOT match trigger (< 7 days)")
    
    // Safety Invariant: Manual items can NEVER be matched by any cleanup rule
    let matchesManual = await engine.matches(file: manualItem, trigger: installerRule.trigger, relativeTo: now)
    expect(!matchesManual, "Manual risk item is strictly protected and never matches any cleanup rule")
    
    // 3. Execution & Undo Restoration Test
    let customJournal = UndoJournal(storageDirectory: tempDir)
    let executionEngine = RuleEngine(
        trashMover: .shared,
        journal: customJournal
    )
    
    let summary = try? await executionEngine.executeRules(
        rulesToRun: [installerRule],
        candidates: [oldInstallerItem, recentInstallerItem, manualItem],
        allowedRoots: [tempDir]
    )
    
    expectEqual(summary?.itemsProcessed, 1, "Only matching safe file was processed")
    expect(!FileManager.default.fileExists(atPath: oldInstallerFile.path), "Matching file was trashed")
    expect(FileManager.default.fileExists(atPath: recentInstallerFile.path), "Non-matching file preserved intact")
    expect(FileManager.default.fileExists(atPath: manualItemFile.path), "Manual file preserved intact")
    
    // Verify Undo Restoration
    if let batchId = summary?.batchId {
        let restoredResult = try? await customJournal.restoreRun(runId: batchId)
        expectEqual(restoredResult?.restoredCount, 1, "UndoJournal successfully restored file trashed by rule")
        expect(FileManager.default.fileExists(atPath: oldInstallerFile.path), "Original file restored to path")
    }
    
    // 4. ScheduleCoordinator Tests
    let coordinator = ScheduleCoordinator.shared
    var settings = await coordinator.getSettings()
    settings.isEnabled = true
    settings.frequency = .daily
    settings.lastRunDate = Calendar.current.date(byAdding: .day, value: -2, to: Date())
    await coordinator.updateSettings(settings)
    
    let isDue = await coordinator.isRunDue()
    expect(isDue, "Daily schedule is due when last run was 2 days ago")
    
    // Check low disk threshold
    settings.frequency = .onLowDiskSpace(thresholdGB: 20)
    await coordinator.updateSettings(settings)
    let isDiskLowDue = await coordinator.isRunDue(currentFreeBytes: 10 * 1024 * 1024 * 1024) // 10 GB free < 20 GB threshold
    expect(isDiskLowDue, "Low disk trigger is due when free space is below configured threshold")
    
    let isDiskNormalDue = await coordinator.isRunDue(currentFreeBytes: 50 * 1024 * 1024 * 1024) // 50 GB free > 20 GB threshold
    expect(!isDiskNormalDue, "Low disk trigger is NOT due when free space is above configured threshold")
}
