import Foundation
import TidyMacCore

@MainActor
func runDuplicateTests() async {
    print("\n--- Running DuplicateFinderEngine & Keep-One Invariant Tests ---")
    
    // 1. Hash Utility Tests
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("TidyMacDupTests_\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    let fileA = tempDir.appendingPathComponent("fileA.bin")
    let fileB = tempDir.appendingPathComponent("fileB.bin")
    let fileC = tempDir.appendingPathComponent("fileC.bin")
    
    let dataA = Data(repeating: 0x41, count: 40_000) // 40KB of 'A'
    let dataB = Data(repeating: 0x41, count: 40_000) // Identical 40KB of 'A'
    var dataC = Data(repeating: 0x41, count: 40_000) // 40KB with different middle byte
    dataC[20_000] = 0x5A // Change byte in middle
    
    FileManager.default.createFile(atPath: fileA.path, contents: dataA)
    FileManager.default.createFile(atPath: fileB.path, contents: dataB)
    FileManager.default.createFile(atPath: fileC.path, contents: dataC)
    
    let hashA = HashUtility.computeFullHash(for: fileA)
    let hashB = HashUtility.computeFullHash(for: fileB)
    let hashC = HashUtility.computeFullHash(for: fileC)
    
    expectEqual(hashA, hashB, "Identical files have identical SHA-256 digests")
    expectNotEqual(hashA, hashC, "Files differing in middle byte produce distinct SHA-256 digests")
    
    // 2. DuplicateGroup Invariant Enforcement
    let item1 = FileItem(url: fileA, fileSize: 40_000, category: .duplicates, riskLabel: .review, isSelected: true)
    let item2 = FileItem(url: fileB, fileSize: 40_000, category: .duplicates, riskLabel: .review, isSelected: true)
    
    // Both items initialized with isSelected = true
    var group = DuplicateGroup(fileSize: 40_000, hash: hashA ?? "", items: [item1, item2])
    let selectedCount = group.items.filter(\.isSelected).count
    expect(selectedCount < group.items.count, "DuplicateGroup must NEVER allow all copies to be selected")
    expectEqual(selectedCount, 1, "Exactly one duplicate copy selected, one preserved")
    
    // Attempt to manually select the preserved copy
    group.setSelection(for: group.items[0].id, isSelected: true)
    let countAfterAttempt = group.items.filter(\.isSelected).count
    expect(countAfterAttempt < group.items.count, "setSelection must reject selecting all copies")
    
    // 3. DuplicateFinderEngine 3-Tier Pipeline Fixture Test
    let dupFolder = tempDir.appendingPathComponent("SearchFolder")
    try? FileManager.default.createDirectory(at: dupFolder, withIntermediateDirectories: true)
    
    let originalCopy = dupFolder.appendingPathComponent("original.txt")
    let duplicateCopy1 = dupFolder.appendingPathComponent("copy1.txt")
    let duplicateCopy2 = dupFolder.appendingPathComponent("copy2.txt")
    let nonDuplicateSameSize = dupFolder.appendingPathComponent("same_size_diff.txt")
    let uniqueFile = dupFolder.appendingPathComponent("unique.txt")
    
    let duplicatePayload = "Identical duplicate cluster payload content".data(using: .utf8)!
    var diffPayload = duplicatePayload
    diffPayload[5] = 0x23 // Corrupt one byte to change hash
    
    FileManager.default.createFile(atPath: originalCopy.path, contents: duplicatePayload)
    FileManager.default.createFile(atPath: duplicateCopy1.path, contents: duplicatePayload)
    FileManager.default.createFile(atPath: duplicateCopy2.path, contents: duplicatePayload)
    FileManager.default.createFile(atPath: nonDuplicateSameSize.path, contents: diffPayload)
    FileManager.default.createFile(atPath: uniqueFile.path, contents: "Completely different content".data(using: .utf8))
    
    let engine = DuplicateFinderEngine.shared
    let groups = await engine.findDuplicates(folders: [dupFolder], strategy: .keepOldest)
    
    expectEqual(groups.count, 1, "Discovered exactly 1 duplicate cluster")
    if let foundGroup = groups.first {
        expectEqual(foundGroup.items.count, 3, "Duplicate cluster contains exactly 3 identical copies")
        let selectedInCluster = foundGroup.items.filter(\.isSelected).count
        expectEqual(selectedInCluster, 2, "2 copies marked for trashing, 1 original preserved")
        expect(selectedInCluster < foundGroup.items.count, "Keep-one invariant held during engine discovery")
    }

    // 4. Performance & Safety Benchmark on Real User Folders
    let home = FileManager.default.homeDirectoryForCurrentUser
    let realFolders = [
        home.appendingPathComponent("Downloads"),
        home.appendingPathComponent("Desktop")
    ].filter { FileManager.default.fileExists(atPath: $0.path) }
    
    let benchStart = Date()
    let realDupGroups = await engine.findDuplicates(folders: realFolders)
    let benchDuration = Date().timeIntervalSince(benchStart)
    print("  ⚡️ Real user duplicate scan completed in \(String(format: "%.2f", benchDuration))s (Discovered \(realDupGroups.count) duplicate groups)")
    expect(benchDuration < 5.0, "Duplicate scan on real user folders should complete under 5s")
}
