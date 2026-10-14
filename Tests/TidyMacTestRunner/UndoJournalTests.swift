import Foundation
import TidyMacCore

@MainActor
func runUndoJournalTests() async {
    print("\n--- Running UndoJournal & Safe Restoration Tests ---")
    
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("TidyMacUndoTests_\(UUID().uuidString)")
    let journalStorage = tempDir.appendingPathComponent("JournalStore")
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    
    defer {
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    let journal = UndoJournal(storageDirectory: journalStorage)
    let runId = UUID()
    
    // 1. Trashing and Restoration Round-trip Test
    let testFolder = tempDir.appendingPathComponent("Documents/Projects")
    try? FileManager.default.createDirectory(at: testFolder, withIntermediateDirectories: true)
    let originalFile = testFolder.appendingPathComponent("important_plan.txt")
    let payload = "Critical architectural plan content that must be restored"
    FileManager.default.createFile(atPath: originalFile.path, contents: payload.data(using: .utf8))
    
    do {
        // Move to trash
        let trashedURL = try await TrashMover.shared.moveToTrash(at: originalFile, allowedRoots: [tempDir])
        expect(!FileManager.default.fileExists(atPath: originalFile.path), "Original file removed after trashing")
        expect(FileManager.default.fileExists(atPath: trashedURL.path), "File exists in Trash")
        
        let entry = JournalEntry(
            runId: runId,
            timestamp: Date(),
            originalURL: originalFile,
            trashedURL: trashedURL,
            fileSize: Int64(payload.utf8.count),
            action: .trashed
        )
        await journal.record(entry: entry)
        
        // Verify run summary
        let runs = await journal.getRuns()
        expectEqual(runs.first?.runId, runId, "Run summary matches recorded runId")
        expectEqual(runs.first?.itemCount, 1, "Run summary reflects 1 item")
        
        // Restore run
        let restoreResult = try await journal.restoreRun(runId: runId)
        expectEqual(restoreResult.restoredCount, 1, "Successfully restored 1 file")
        expect(FileManager.default.fileExists(atPath: originalFile.path), "File restored back to original path")
        
        let restoredData = try Data(contentsOf: originalFile)
        let restoredString = String(data: restoredData, encoding: .utf8)
        expectEqual(restoredString, payload, "Restored file content matches original payload byte-for-byte")
    } catch {
        expect(false, "Trashing and restoration failed unexpectedly: \(error)")
    }
    
    // 2. Directory Recreation Test (Parent deleted)
    let recreateRunId = UUID()
    let nestedFolder = tempDir.appendingPathComponent("Subfolder/SubSub")
    try? FileManager.default.createDirectory(at: nestedFolder, withIntermediateDirectories: true)
    let nestedFile = nestedFolder.appendingPathComponent("nested_data.txt")
    FileManager.default.createFile(atPath: nestedFile.path, contents: "Nested".data(using: .utf8))
    
    do {
        let trashedURL = try await TrashMover.shared.moveToTrash(at: nestedFile, allowedRoots: [tempDir])
        // Now delete the parent folder
        try? FileManager.default.removeItem(at: nestedFolder)
        expect(!FileManager.default.fileExists(atPath: nestedFolder.path), "Parent directory was removed")
        
        let entry = JournalEntry(
            runId: recreateRunId,
            originalURL: nestedFile,
            trashedURL: trashedURL,
            fileSize: 6,
            action: .trashed
        )
        await journal.record(entry: entry)
        
        let result = try await journal.restoreRun(runId: recreateRunId)
        expectEqual(result.restoredCount, 1, "Restored file after parent directory was deleted")
        expect(FileManager.default.fileExists(atPath: nestedFile.path), "Parent directory recreated and file restored")
    } catch {
        expect(false, "Directory recreation test failed: \(error)")
    }
    
    // 3. Collision Resolution Test
    let collisionRunId = UUID()
    let collisionFile = tempDir.appendingPathComponent("collision_target.txt")
    FileManager.default.createFile(atPath: collisionFile.path, contents: "Old Version".data(using: .utf8))
    
    do {
        let trashedURL = try await TrashMover.shared.moveToTrash(at: collisionFile, allowedRoots: [tempDir])
        // Create a new conflicting file at the same original path
        FileManager.default.createFile(atPath: collisionFile.path, contents: "New Conflicting Version".data(using: .utf8))
        
        let entry = JournalEntry(
            runId: collisionRunId,
            originalURL: collisionFile,
            trashedURL: trashedURL,
            fileSize: 11,
            action: .trashed
        )
        await journal.record(entry: entry)
        
        let result = try await journal.restoreRun(runId: collisionRunId)
        expectEqual(result.restoredCount, 1, "Restored colliding file with non-destructive suffix")
        
        let conflictingExists = FileManager.default.fileExists(atPath: collisionFile.path)
        let restoredCandidate = tempDir.appendingPathComponent("collision_target (restored 1).txt")
        let restoredExists = FileManager.default.fileExists(atPath: restoredCandidate.path)
        
        expect(conflictingExists, "Existing conflicting file preserved intact")
        expect(restoredExists, "Restored file written to collision-safe filename without overwriting")
    } catch {
        expect(false, "Collision resolution test failed: \(error)")
    }
}
