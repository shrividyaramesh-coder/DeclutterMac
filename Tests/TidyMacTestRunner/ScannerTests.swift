import Foundation
import TidyMacCore

@MainActor
func runScannerTests() async {
    print("\n--- Running StorageScanner & RiskEvaluator Tests ---")
    
    // 1. Category Classification Tests
    let cacheURL = URL(fileURLWithPath: "/Users/test/Library/Caches/com.apple.app/cache.db")
    expectEqual(CategoryClassifier.classify(url: cacheURL, fileSize: 1024, createdDate: Date()), .caches, "Classifies /Library/Caches as .caches")
    
    let logURL = URL(fileURLWithPath: "/Users/test/Library/Logs/crash.log")
    expectEqual(CategoryClassifier.classify(url: logURL, fileSize: 1024, createdDate: Date()), .logs, "Classifies .log file as .logs")
    
    let dmgURL = URL(fileURLWithPath: "/Users/test/Downloads/ApplicationInstaller.dmg")
    expectEqual(CategoryClassifier.classify(url: dmgURL, fileSize: 50 * 1024 * 1024, createdDate: Date()), .oldDownloads, "Classifies .dmg as .oldDownloads")
    
    let screenshotURL = URL(fileURLWithPath: "/Users/test/Desktop/Screen Shot 2026-10-14 at 10.00.00.png")
    expectEqual(CategoryClassifier.classify(url: screenshotURL, fileSize: 2 * 1024 * 1024, createdDate: Date()), .screenshots, "Classifies Screen Shot prefix as .screenshots")
    
    let largeFileURL = URL(fileURLWithPath: "/Users/test/Documents/huge_archive.dat")
    expectEqual(CategoryClassifier.classify(url: largeFileURL, fileSize: 150 * 1024 * 1024, createdDate: Date()), .largeFiles, "Classifies files > 100MB as .largeFiles")
    
    // 2. Risk Evaluator Tests
    let safeCacheRisk = RiskEvaluator.evaluateRisk(category: .caches, url: cacheURL, fileSize: 1024, createdDate: Date())
    expectEqual(safeCacheRisk, .safe, "Caches category evaluated as Safe")
    
    let oldDate = Date().addingTimeInterval(-10 * 24 * 60 * 60) // 10 days ago
    let oldDmgRisk = RiskEvaluator.evaluateRisk(category: .oldDownloads, url: dmgURL, fileSize: 50 * 1024 * 1024, createdDate: oldDate)
    expectEqual(oldDmgRisk, .safe, "Installers older than 7 days evaluated as Safe")
    
    let freshDate = Date().addingTimeInterval(-1 * 24 * 60 * 60) // 1 day ago
    let freshDmgRisk = RiskEvaluator.evaluateRisk(category: .oldDownloads, url: dmgURL, fileSize: 50 * 1024 * 1024, createdDate: freshDate)
    expectEqual(freshDmgRisk, .review, "Recent installers evaluated as Review")
    
    let screenshotRisk = RiskEvaluator.evaluateRisk(category: .screenshots, url: screenshotURL, fileSize: 2 * 1024 * 1024, createdDate: oldDate)
    expectEqual(screenshotRisk, .review, "Screenshots evaluated as Review")
    
    let manualURL = URL(fileURLWithPath: "/Users/test/Library/Preferences/com.apple.system.plist")
    let manualRisk = RiskEvaluator.evaluateRisk(category: .manualReview, url: manualURL, fileSize: 1024, createdDate: Date())
    expectEqual(manualRisk, .manual, "Sensitive plists evaluated as Manual")
    
    // 3. StorageScanner Fixture Integration Test
    let fixtureDir = FileManager.default.temporaryDirectory.appendingPathComponent("TidyMacScannerTest_\(UUID().uuidString)")
    let cachesDir = fixtureDir.appendingPathComponent("Library/Caches")
    let logsDir = fixtureDir.appendingPathComponent("Library/Logs")
    let downloadsDir = fixtureDir.appendingPathComponent("Downloads")
    let desktopDir = fixtureDir.appendingPathComponent("Desktop")
    
    try? FileManager.default.createDirectory(at: cachesDir, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: desktopDir, withIntermediateDirectories: true)
    
    defer {
        try? FileManager.default.removeItem(at: fixtureDir)
    }
    
    // Seed test files
    let testCache = cachesDir.appendingPathComponent("sample_cache.bin")
    FileManager.default.createFile(atPath: testCache.path, contents: Data(repeating: 0xAA, count: 50_000))
    
    let testLog = logsDir.appendingPathComponent("app.log")
    FileManager.default.createFile(atPath: testLog.path, contents: "Sample log output\n".data(using: .utf8))
    
    let testDmg = downloadsDir.appendingPathComponent("TestApp.dmg")
    FileManager.default.createFile(atPath: testDmg.path, contents: Data(repeating: 0xBB, count: 100_000))
    // Backdate creation date to 10 days ago
    try? FileManager.default.setAttributes([.creationDate: oldDate], ofItemAtPath: testDmg.path)
    
    let testScreenshot = desktopDir.appendingPathComponent("Screenshot 2026-10-14.png")
    FileManager.default.createFile(atPath: testScreenshot.path, contents: Data(repeating: 0xCC, count: 20_000))
    
    // Execute live scan
    let scanner = StorageScanner.shared
    let stream = await scanner.scan(folders: [fixtureDir])
    
    var discoveredItems: [FileItem] = []
    var isCompleted = false
    
    for await event in stream {
        switch event {
        case .itemDiscovered(let item):
            discoveredItems.append(item)
        case .completed:
            isCompleted = true
        case .progress, .cancelled:
            break
        }
    }
    
    expect(isCompleted, "Scanner completed successfully")
    expectEqual(discoveredItems.count, 4, "Discovered exactly 4 seeded test items")
    
    // Verify item categorizations
    let cacheItem = discoveredItems.first(where: { $0.url.lastPathComponent == "sample_cache.bin" })
    expect(cacheItem != nil && cacheItem?.category == .caches && cacheItem?.riskLabel == .safe, "Cache item classified as .caches and Safe")
    expect(cacheItem?.isSelected == true, "Safe cache item auto-selected")
    
    let logItem = discoveredItems.first(where: { $0.url.lastPathComponent == "app.log" })
    expect(logItem != nil && logItem?.category == .logs && logItem?.riskLabel == .safe, "Log item classified as .logs and Safe")
    
    let dmgItem = discoveredItems.first(where: { $0.url.lastPathComponent == "TestApp.dmg" })
    expect(dmgItem != nil && dmgItem?.category == .oldDownloads, "Old dmg classified as .oldDownloads")
    
    let shotItem = discoveredItems.first(where: { $0.url.lastPathComponent == "Screenshot 2026-10-14.png" })
    expect(shotItem != nil && shotItem?.category == .screenshots && shotItem?.riskLabel == .review, "Screenshot classified as .screenshots and Review")
    
    // 4. Cancellation Test
    let cancelTask = Task {
        let cancelStream = await scanner.scan(folders: [fixtureDir])
        for await _ in cancelStream {}
    }
    cancelTask.cancel()
    _ = await cancelTask.result
    expect(cancelTask.isCancelled, "Scanner handles Task cancellation gracefully")
}
