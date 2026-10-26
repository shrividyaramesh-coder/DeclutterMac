import Foundation
import TidyMacCore

@MainActor
func runEndToEndFixtureTests() async {
    print("\n--- Running Master End-to-End Fixture Integration Tests ---")
    
    let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("TidyMacE2E_\(UUID().uuidString)")
    let fakeHome = tempRoot.appendingPathComponent("UserHome")
    
    let fakeDownloads = fakeHome.appendingPathComponent("Downloads")
    let fakeDocuments = fakeHome.appendingPathComponent("Documents")
    let fakeDesktop = fakeHome.appendingPathComponent("Desktop")
    let fakePictures = fakeHome.appendingPathComponent("Pictures")
    let fakeCaches = fakeHome.appendingPathComponent("Library/Caches/com.sample.test")
    let fakeLogs = fakeHome.appendingPathComponent("Library/Logs")
    let fakeSSH = fakeHome.appendingPathComponent(".ssh")
    let fakeKeychains = fakeHome.appendingPathComponent("Library/Keychains")
    let fakePhotos = fakeHome.appendingPathComponent("Pictures/Photos Library.photoslibrary")
    let fakeCloud = fakeHome.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
    
    // Create directory tree
    try? FileManager.default.createDirectory(at: fakeDownloads, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: fakeDocuments, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: fakeDesktop, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: fakePictures, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: fakeCaches, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: fakeLogs, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: fakeSSH, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: fakeKeychains, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: fakePhotos, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: fakeCloud, withIntermediateDirectories: true)
    
    defer {
        try? FileManager.default.removeItem(at: tempRoot)
    }
    
    let now = Date()
    let sixtyDaysAgo = Calendar.current.date(byAdding: .day, value: -60, to: now) ?? now
    let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: now) ?? now
    
    // 1. Seed Fixture Files
    // Cache file (Safe)
    let cacheFile = fakeCaches.appendingPathComponent("cache.data")
    FileManager.default.createFile(atPath: cacheFile.path, contents: Data(repeating: 0x11, count: 50_000))
    try? FileManager.default.setAttributes([.modificationDate: sixtyDaysAgo], ofItemAtPath: cacheFile.path)
    
    // Log file (Safe)
    let logFile = fakeLogs.appendingPathComponent("system.log")
    FileManager.default.createFile(atPath: logFile.path, contents: Data(repeating: 0x22, count: 20_000))
    try? FileManager.default.setAttributes([.modificationDate: sixtyDaysAgo], ofItemAtPath: logFile.path)
    
    // Old Installer (Safe)
    let oldInstaller = fakeDownloads.appendingPathComponent("old_setup.dmg")
    FileManager.default.createFile(atPath: oldInstaller.path, contents: Data(repeating: 0x33, count: 80_000))
    try? FileManager.default.setAttributes([.modificationDate: sixtyDaysAgo], ofItemAtPath: oldInstaller.path)
    
    // Recent Installer (Review)
    let recentInstaller = fakeDownloads.appendingPathComponent("new_setup.dmg")
    FileManager.default.createFile(atPath: recentInstaller.path, contents: Data(repeating: 0x44, count: 80_000))
    try? FileManager.default.setAttributes([.modificationDate: twoDaysAgo], ofItemAtPath: recentInstaller.path)
    
    // Old Screenshot (Review)
    let oldScreenshot = fakeDesktop.appendingPathComponent("Screen Shot 2024-01-01.png")
    FileManager.default.createFile(atPath: oldScreenshot.path, contents: Data(repeating: 0x55, count: 40_000))
    try? FileManager.default.setAttributes([.modificationDate: sixtyDaysAgo], ofItemAtPath: oldScreenshot.path)
    
    // Duplicate files (3 copies across Documents, Downloads, Desktop)
    let duplicatePayload = Data("EXACT DUPLICATE CONTENT PAYLOAD SHA256 VERIFIED".utf8)
    let dupOriginal = fakeDocuments.appendingPathComponent("contract_master.pdf")
    let dupCopy1 = fakeDownloads.appendingPathComponent("contract_copy.pdf")
    let dupCopy2 = fakeDesktop.appendingPathComponent("contract_backup.pdf")
    FileManager.default.createFile(atPath: dupOriginal.path, contents: duplicatePayload)
    FileManager.default.createFile(atPath: dupCopy1.path, contents: duplicatePayload)
    FileManager.default.createFile(atPath: dupCopy2.path, contents: duplicatePayload)
    
    // Cloud placeholder file
    let cloudPlaceholder = fakeCloud.appendingPathComponent(".project_archive.zip.icloud")
    FileManager.default.createFile(atPath: cloudPlaceholder.path, contents: Data("placeholder".utf8))
    
    // Protected files (MUST NEVER BE TRASHED OR MODIFIED)
    let sshKey = fakeSSH.appendingPathComponent("id_rsa")
    FileManager.default.createFile(atPath: sshKey.path, contents: Data("PRIVATE KEY CONTENT".utf8))
    
    let keychainDb = fakeKeychains.appendingPathComponent("login.keychain-db")
    FileManager.default.createFile(atPath: keychainDb.path, contents: Data("KEYCHAIN DB CONTENT".utf8))
    
    let allowedRoots = [tempRoot]
    
    // 2. Full Storage Scan Verification
    let scanner = StorageScanner.shared
    let stream = await scanner.scan(folders: [fakeDownloads, fakeDocuments, fakeDesktop, fakeCaches, fakeLogs])
    var discoveredItems: [FileItem] = []
    
    for await event in stream {
        if case .itemDiscovered(let item) = event {
            discoveredItems.append(item)
        }
    }
    
    expect(discoveredItems.count >= 6, "Scanner successfully discovered fixture files (found: \(discoveredItems.count))")
    
    let cacheItem = discoveredItems.first(where: { $0.url.resolvingSymlinksInPath() == cacheFile.resolvingSymlinksInPath() })
    expectEqual(cacheItem?.category, .caches, "Cache file categorized as .caches")
    expectEqual(cacheItem?.riskLabel, .safe, "Cache file evaluated as Safe")
    
    let logItem = discoveredItems.first(where: { $0.url.resolvingSymlinksInPath() == logFile.resolvingSymlinksInPath() })
    expectEqual(logItem?.category, .logs, "Log file categorized as .logs")
    expectEqual(logItem?.riskLabel, .safe, "Log file evaluated as Safe")
    
    let oldInstallerItem = discoveredItems.first(where: { $0.url.resolvingSymlinksInPath() == oldInstaller.resolvingSymlinksInPath() })
    expectEqual(oldInstallerItem?.category, .oldDownloads, "Installer categorized as .oldDownloads")
    expectEqual(oldInstallerItem?.riskLabel, .safe, "Old installer evaluated as Safe")
    
    // 3. Duplicate Detection & Keep-One Guard Verification
    let duplicateEngine = DuplicateFinderEngine.shared
    let dupGroups = await duplicateEngine.findDuplicates(folders: [fakeDocuments, fakeDownloads, fakeDesktop])
    expectEqual(dupGroups.count, 1, "Duplicate pipeline detected exactly 1 duplicate group")
    
    if let group = dupGroups.first {
        expectEqual(group.items.count, 3, "Duplicate group contains all 3 copies")
        let selectedCount = group.items.filter(\.isSelected).count
        expectEqual(selectedCount, 2, "Auto-selection selected exactly 2 copies for trashing")
        expectEqual(group.items.count - selectedCount, 1, "Keep-One invariant: at least 1 original preserved unselected")
    }
    
    // 4. Safe Trashing & Reversible Undo Execution
    let journal = UndoJournal(storageDirectory: tempRoot)
    let batchId = UUID()
    let safeItemsToClean = discoveredItems.filter { $0.riskLabel == .safe }
    expect(!safeItemsToClean.isEmpty, "Safe items ready for recommended cleanup")
    
    for item in safeItemsToClean {
        if let trashedURL = try? await TrashMover.shared.moveToTrash(at: item.url, allowedRoots: allowedRoots) {
            let entry = JournalEntry(
                runId: batchId,
                originalURL: item.url,
                trashedURL: trashedURL,
                fileSize: item.fileSize,
                action: .trashed
            )
            await journal.record(entry: entry)
        }
    }
    
    // Verify files removed from source location
    expect(!FileManager.default.fileExists(atPath: cacheFile.path), "Cache file moved to Trash")
    expect(!FileManager.default.fileExists(atPath: logFile.path), "Log file moved to Trash")
    expect(!FileManager.default.fileExists(atPath: oldInstaller.path), "Old installer moved to Trash")
    
    // Invariant Verification: Protected system/user identity files MUST NEVER BE TOUCHED
    expect(FileManager.default.fileExists(atPath: sshKey.path), "Safety Invariant: ~/.ssh/id_rsa is untouched and preserved")
    expect(FileManager.default.fileExists(atPath: keychainDb.path), "Safety Invariant: Keychains DB is untouched and preserved")
    
    // 5. Byte-for-Byte Undo Restoration
    let restoration = try? await journal.restoreRun(runId: batchId)
    expectEqual(restoration?.restoredCount, safeItemsToClean.count, "Undo restoration restored all cleaned items")
    
    expect(FileManager.default.fileExists(atPath: cacheFile.path), "Restored cache file exists at original location")
    expect(FileManager.default.fileExists(atPath: logFile.path), "Restored log file exists at original location")
    expect(FileManager.default.fileExists(atPath: oldInstaller.path), "Restored installer exists at original location")
    
    let restoredCacheData = try? Data(contentsOf: cacheFile)
    expectEqual(restoredCacheData?.count, 50_000, "Restored cache file matches original byte count exactly")
    
    // 6. Licensing & Allowance Verification
    let licenseProvider = LocalLicenseProvider.shared
    await licenseProvider.reset()
    let initialStatus = await licenseProvider.currentStatus()
    expect(initialStatus.isUnlimited, "Initial 15-day trial grants full access")
    
    // Record cleaned bytes
    await licenseProvider.recordCleanedBytes(150_000)
    
    // Test lifetime unlock
    let unlocked = await licenseProvider.unlockLifetime(key: "TM-2026-LIFETIME-PRO")
    expect(unlocked, "Successfully unlocked lifetime license")
    let unlockedStatus = await licenseProvider.currentStatus()
    expectEqual(unlockedStatus, .unlocked(licenseKey: "TM-2026-LIFETIME-PRO"), "License status reflects unlocked lifetime state")
    
    // 7. Folder Sorting Allowance Verification (2 Free, Then Paywall, Then $3.99 Lifetime Unlock)
    await licenseProvider.reset()
    let initialCanSort = await licenseProvider.canSortFolder()
    expect(initialCanSort, "New user starts with folder sorting authorization")
    expectEqual(await licenseProvider.folderSortsCount(), 0, "Initial folder sorts count is 0")
    
    // Perform sort 1
    await licenseProvider.recordFolderSort()
    expectEqual(await licenseProvider.folderSortsCount(), 1, "First folder sort recorded")
    expect(await licenseProvider.canSortFolder(), "User can sort second folder")
    
    // Perform sort 2
    await licenseProvider.recordFolderSort()
    expectEqual(await licenseProvider.folderSortsCount(), 2, "Second folder sort recorded")
    let canSortAfterTwo = await licenseProvider.canSortFolder()
    expect(!canSortAfterTwo, "User blocked after sorting 2 free folders")
    
    // Unlock lifetime pass ($3.99)
    let unlockedSort = await licenseProvider.unlockLifetime(key: "DM-LIFETIME-399-E2E")
    expect(unlockedSort, "$3.99 Lifetime key accepted")
    expect(await licenseProvider.canSortFolder(), "User can sort unlimited folders after lifetime unlock")
    
    // Perform sort 3
    await licenseProvider.recordFolderSort()
    expectEqual(await licenseProvider.folderSortsCount(), 3, "Third folder sort recorded")
    expect(await licenseProvider.canSortFolder(), "Unlimited sorting continues after unlock")
    
    await licenseProvider.reset()
}
