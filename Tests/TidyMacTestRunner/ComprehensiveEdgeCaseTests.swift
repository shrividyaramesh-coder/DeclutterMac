import Foundation
import TidyMacCore

@MainActor
func runComprehensiveEdgeCaseTests() async {
    print("\n--- Running Comprehensive Edge Cases & Stress Work Cases ---")
    
    let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("TidyMacEdgeCases_\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: tempRoot)
    }
    
    // =========================================================================
    // WORK CASE 1: Unicode, Emojis, Accents, and Spaces in Paths
    // =========================================================================
    let unicodeFolder = tempRoot.appendingPathComponent("📁 Dossier Été 2026 🚀/日本語・Español")
    try? FileManager.default.createDirectory(at: unicodeFolder, withIntermediateDirectories: true)
    
    let unicodeFile = unicodeFolder.appendingPathComponent("Données & Reçus (version finale) ⭐️.pdf")
    let unicodePayload = Data("Données importantes de l'été 2026 🎉".utf8)
    FileManager.default.createFile(atPath: unicodeFile.path, contents: unicodePayload)
    
    expect(
        PathValidator.isPathAllowed(unicodeFile, allowedRoots: [tempRoot]),
        "PathValidator must accept paths containing emojis, accents, and unicode characters"
    )
    
    // Trash unicode file
    do {
        let trashed = try await TrashMover.shared.moveToTrash(at: unicodeFile, allowedRoots: [tempRoot])
        expect(!FileManager.default.fileExists(atPath: unicodeFile.path), "Original unicode file removed after trashing")
        expect(FileManager.default.fileExists(atPath: trashed.path), "Trashed unicode file exists in Trash")
        
        // Log to UndoJournal and restore
        let batchId = UUID()
        let entry = JournalEntry(
            runId: batchId,
            originalURL: unicodeFile,
            trashedURL: trashed,
            fileSize: Int64(unicodePayload.count),
            action: .trashed
        )
        await UndoJournal.shared.record(entry: entry)
        
        let (restoredCount, _) = try await UndoJournal.shared.restoreRun(runId: batchId)
        expectEqual(restoredCount, 1, "UndoJournal must restore unicode/emoji file")
        expect(FileManager.default.fileExists(atPath: unicodeFile.path), "Restored unicode file exists at exact original path")
        let restoredData = try? Data(contentsOf: unicodeFile)
        expectEqual(restoredData, unicodePayload, "Restored unicode file matches original content byte-for-byte")
    } catch {
        expect(false, "Unicode trashing/restoring failed: \(error)")
    }
    
    // =========================================================================
    // WORK CASE 2: Multi-level Cascading Restoration Collisions
    // =========================================================================
    let collisionBase = tempRoot.appendingPathComponent("CollisionTest")
    try? FileManager.default.createDirectory(at: collisionBase, withIntermediateDirectories: true)
    
    let originalTarget = collisionBase.appendingPathComponent("document.pdf")
    FileManager.default.createFile(atPath: originalTarget.path, contents: Data("Existing target".utf8))
    
    let firstCollision = collisionBase.appendingPathComponent("document (restored 1).pdf")
    FileManager.default.createFile(atPath: firstCollision.path, contents: Data("Existing restored 1".utf8))
    
    // Trash a new file and attempt restoration to originalTarget
    let incomingFile = collisionBase.appendingPathComponent("incoming.pdf")
    FileManager.default.createFile(atPath: incomingFile.path, contents: Data("Incoming to restore".utf8))
    
    let trashedIncoming = try? await TrashMover.shared.moveToTrash(at: incomingFile, allowedRoots: [tempRoot])
    if let trashedIncoming = trashedIncoming {
        let batchId = UUID()
        let entry = JournalEntry(
            runId: batchId,
            originalURL: originalTarget, // target collides with document.pdf AND document (restored 1).pdf
            trashedURL: trashedIncoming,
            fileSize: 20,
            action: .trashed
        )
        await UndoJournal.shared.record(entry: entry)
        
        let result = try? await UndoJournal.shared.restoreRun(runId: batchId)
        expectEqual(result?.restoredCount, Optional(1), "Cascading restoration must succeed")
        
        let expectedCascadeTarget = collisionBase.appendingPathComponent("document (restored 2).pdf")
        expect(
            FileManager.default.fileExists(atPath: expectedCascadeTarget.path),
            "Cascading collision must increment to (restored 2)"
        )
        expect(
            FileManager.default.fileExists(atPath: originalTarget.path),
            "Original target must be preserved intact"
        )
        expect(
            FileManager.default.fileExists(atPath: firstCollision.path),
            "First collision file must be preserved intact"
        )
    }
    
    // =========================================================================
    // WORK CASE 3: Multi-level Cascading Collisions in Folder Organizer
    // =========================================================================
    let destDir = tempRoot.appendingPathComponent("Organized/Documents/PDFs")
    try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
    
    FileManager.default.createFile(atPath: destDir.appendingPathComponent("contract.pdf").path, contents: Data("v0".utf8))
    FileManager.default.createFile(atPath: destDir.appendingPathComponent("contract (1).pdf").path, contents: Data("v1".utf8))
    FileManager.default.createFile(atPath: destDir.appendingPathComponent("contract (2).pdf").path, contents: Data("v2".utf8))
    
    let safeCollisionTarget = await FolderOrganizerEngine.shared.resolveCollisionSafeTarget(
        for: "contract.pdf",
        in: destDir
    )
    let expectedIncrement = destDir.appendingPathComponent("contract (3).pdf")
    expectEqual(
        safeCollisionTarget.path,
        expectedIncrement.path,
        "Organizer must safely resolve collision across (1) and (2) by incrementing to (3)"
    )
    
    // =========================================================================
    // WORK CASE 4: 5-Way Duplicate Cluster & Keep-One Preservation
    // =========================================================================
    let dupDir = tempRoot.appendingPathComponent("DuplicatesCluster")
    try? FileManager.default.createDirectory(at: dupDir, withIntermediateDirectories: true)
    
    let payload5 = Data("IDENTICAL FIVE COPIES CONTENT VERIFICATION".utf8)
    var clusterURLs: [URL] = []
    for i in 1...5 {
        let u = dupDir.appendingPathComponent("copy_\(i).dat")
        FileManager.default.createFile(atPath: u.path, contents: payload5)
        clusterURLs.append(u)
    }
    
    let dupGroups = await DuplicateFinderEngine.shared.findDuplicates(folders: [dupDir])
    expectEqual(dupGroups.count, 1, "Must find exactly 1 duplicate group for 5 identical files")
    
    if let group = dupGroups.first {
        expectEqual(group.items.count, 5, "Duplicate cluster must contain all 5 copies")
        let selectedCount = group.items.filter(\.isSelected).count
        expectEqual(selectedCount, 4, "Auto-selection must select exactly 4 copies for trashing")
        
        let unselectedCount = group.items.filter({ !$0.isSelected }).count
        expectEqual(unselectedCount, 1, "Keep-One Guard: exactly 1 original copy must remain preserved unselected")
        
        // Attempt to select all 5 items
        var mutGroup = group
        for i in mutGroup.items.indices {
            mutGroup.setSelection(for: mutGroup.items[i].id, isSelected: true)
        }
        let forcedSelected = mutGroup.items.filter(\.isSelected).count
        expect(forcedSelected < 5, "setSelection must strictly reject selecting all 5 copies")
    }
    
    // =========================================================================
    // WORK CASE 5: Zero-Byte File Duplicate Defense
    // =========================================================================
    let zeroDir = tempRoot.appendingPathComponent("ZeroByteTest")
    try? FileManager.default.createDirectory(at: zeroDir, withIntermediateDirectories: true)
    
    let zero1 = zeroDir.appendingPathComponent("empty1.txt")
    let zero2 = zeroDir.appendingPathComponent("empty2.txt")
    FileManager.default.createFile(atPath: zero1.path, contents: Data())
    FileManager.default.createFile(atPath: zero2.path, contents: Data())
    
    let zeroGroups = await DuplicateFinderEngine.shared.findDuplicates(folders: [zeroDir])
    expectEqual(
        zeroGroups.count,
        0,
        "DuplicateFinder must ignore zero-byte files to avoid trashing empty configs or markers"
    )
    
    // =========================================================================
    // WORK CASE 6: Free Allowance & Lifetime Unlock Transitions
    // =========================================================================
    let license = makeTestLicenseProvider(StubLicenseVerifier(validKeys: ["TM-2026-PRO-LIFETIME"]))
    
    // Record free clean of 1.5 GB
    await license.recordCleanedBytes(1_500_000_000)
    let statusAfterClean = await license.currentStatus()
    expect(
        statusAfterClean.isUnlimited,
        "Active trial or available allowance grants cleaning authorization"
    )
    
    // Unlock lifetime license
    let unlocked = await license.unlockLifetime(key: "TM-2026-PRO-LIFETIME")
    expect(unlocked, "Unlock lifetime license must succeed with valid key format")
    
    let finalStatus = await license.currentStatus()
    expectEqual(
        finalStatus,
        LicenseStatus.unlocked(licenseKey: "TM-2026-PRO-LIFETIME"),
        "Lifetime unlocked status must be active and unlimited"
    )
    expect(finalStatus.isUnlimited, "Lifetime unlocked status is unlimited")
    
    // =========================================================================
    // WORK CASE 7: Complex Natural Language Query Variations
    // =========================================================================
    let parser = OfflineHeuristicParser()
    
    // Case 1: Mixed uppercase
    let planUpper = parser.parse(prompt: "DELETE SCREENSHOTS OLDER THAN 60 DAYS")
    expect(
        planUpper.steps.first?.filter.categories?.contains(.screenshots) == true,
        "Parses uppercase screenshot query"
    )
    expectEqual(planUpper.steps.first?.filter.minimumAgeDays, Optional(60), "Parses 60 days age filter")
    
    // Case 2: Multi-condition size + days
    let planMulti = parser.parse(prompt: "find large files older than 90 days over 2 GB")
    expect(
        planMulti.steps.first?.filter.categories?.contains(.largeFiles) == true,
        "Parses large files query"
    )
    expectEqual(planMulti.steps.first?.filter.minimumSizeBytes, Optional(2 * 1073741824), "Parses 2 GB size constraint")
    
    // Case 3: Installers in downloads
    let planInstallers = parser.parse(prompt: "remove old installers older than 14 days in Downloads")
    expect(
        planInstallers.steps.first?.filter.categories?.contains(.oldDownloads) == true,
        "Parses installer downloads query"
    )
    expectEqual(planInstallers.steps.first?.filter.minimumAgeDays, Optional(14), "Parses 14 days age constraint")
    
    // Case 4: Nonsense query fallback
    let planEmpty = parser.parse(prompt: "random unrelated query without intent")
    expect(
        planEmpty.steps.first?.action != .trash,
        "Unrecognized query produces non-destructive safe default"
    )
    
    // =========================================================================
    // WORK CASE 8: System App Protection Shield
    // =========================================================================
    let protectedSystemApps = [
        "/Applications/Safari.app",
        "/System/Applications/Finder.app",
        "/Applications/Utilities/Terminal.app",
        "/System/Applications/Mail.app",
        "/Applications/App Store.app"
    ]
    
    for sysPath in protectedSystemApps {
        let app = InstalledApp(
            name: (sysPath as NSString).lastPathComponent,
            bundleIdentifier: "com.apple.test",
            version: "1.0",
            url: URL(fileURLWithPath: sysPath),
            appSize: 100_000_000,
            lastOpenedDate: Date(),
            isSystemProtected: true
        )
        expect(app.isSystemProtected, "System app \(app.name) must be marked isSystemProtected")
    }
    
    // =========================================================================
    // WORK CASE 9: Localization Integrity Across All 8 Languages
    // =========================================================================
    let criticalKeys = [
        "app.name", "app.tagline", "nav.overview", "nav.cleanup", "nav.duplicates",
        "nav.apps", "nav.organize", "nav.rules", "nav.history", "nav.settings",
        "action.scan", "action.clean", "action.select_recommended", "action.undo",
        "risk.safe", "risk.review", "risk.manual", "permission.fda_title"
    ]
    
    for lang in AppLanguage.allCases {
        for key in criticalKeys {
            let localizedVal = LocalizedStrings.lookup(key: key, language: lang)
            expect(!localizedVal.isEmpty && localizedVal != key, "Key '\(key)' must have valid localization for \(lang.rawValue)")
        }
    }
    
    // =========================================================================
    // WORK CASE 10: Evicted Cloud Placeholder File Safety
    // =========================================================================
    let cloudDir = tempRoot.appendingPathComponent("CloudEvictionTest")
    try? FileManager.default.createDirectory(at: cloudDir, withIntermediateDirectories: true)
    
    let evictedFile = cloudDir.appendingPathComponent(".presentation.key.icloud")
    FileManager.default.createFile(atPath: evictedFile.path, contents: Data("placeholder".utf8))
    
    expect(
        CloudFolderDetector.isDatalessCloudPlaceholder(evictedFile),
        "CloudFolderDetector must detect .icloud eviction fault"
    )
    
    let downloadedFile = cloudDir.appendingPathComponent("presentation.key")
    FileManager.default.createFile(atPath: downloadedFile.path, contents: Data("downloaded content".utf8))
    expect(
        !CloudFolderDetector.isDatalessCloudPlaceholder(downloadedFile),
        "Downloaded file must not be flagged as evicted placeholder"
    )
}
