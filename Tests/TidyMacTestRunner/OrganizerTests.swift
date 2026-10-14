import Foundation
import TidyMacCore

@MainActor
func runOrganizerTests() async {
    print("\n--- Running Folder Organizer & Collision-Free Move Tests ---")
    
    let engine = FolderOrganizerEngine.shared
    let preferences = CategoryPreferencesStore.shared
    await preferences.reset()
    
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("TidyMacOrganizerTests_\(UUID().uuidString)")
    let sourceFolder = tempDir.appendingPathComponent("Downloads")
    let destFolder = sourceFolder.appendingPathComponent("Organized")
    
    try? FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
    
    defer {
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    // Seed test files
    let pdfFile = sourceFolder.appendingPathComponent("annual_report.pdf")
    FileManager.default.createFile(atPath: pdfFile.path, contents: Data("PDF report".utf8))
    
    let imageFile = sourceFolder.appendingPathComponent("holiday.png")
    FileManager.default.createFile(atPath: imageFile.path, contents: Data("PNG image".utf8))
    
    let zipFile = sourceFolder.appendingPathComponent("backup.zip")
    FileManager.default.createFile(atPath: zipFile.path, contents: Data("ZIP archive".utf8))
    
    let codeFile = sourceFolder.appendingPathComponent("script.swift")
    FileManager.default.createFile(atPath: codeFile.path, contents: Data("Swift code".utf8))
    
    // 1. Taxonomy Analysis Test (with baseDestination)
    var groups = await engine.analyzeFolder(targetFolder: sourceFolder, baseDestination: destFolder)
    expectEqual(groups.count, 4, "Generated 4 distinct category groups")
    
    // 1b. In-Place Taxonomy Analysis Test (baseDestination == nil)
    let inPlaceGroups = await engine.analyzeFolder(targetFolder: sourceFolder)
    expectEqual(inPlaceGroups.count, 4, "In-place generated 4 distinct category groups")
    let inPlaceFilesCount = inPlaceGroups.reduce(0) { $0 + $1.moves.count }
    expectEqual(inPlaceFilesCount, 4, "In-place found all 4 loose files")
    
    // In-place moves validation against PathValidator
    let userDownloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    let realDownloadsGroups = await engine.analyzeFolder(targetFolder: userDownloads)
    if let firstGroup = realDownloadsGroups.first, let firstMove = firstGroup.moves.first {
        let isAllowed = PathValidator.isPathAllowed(firstMove.originalURL, allowedRoots: [userDownloads])
        expect(isAllowed, "PathValidator must allow legitimate in-place organizer moves inside Downloads")
    }

    let categoryNames = groups.map(\.name)
    expect(categoryNames.contains("Documents/PDFs"), "Classified PDF into Documents/PDFs")
    expect(categoryNames.contains("Media/Images"), "Classified PNG into Media/Images")
    expect(categoryNames.contains("Archives"), "Classified ZIP into Archives")
    expect(categoryNames.contains("Development/Source Code"), "Classified Swift file into Development/Source Code")
    
    // 2. Collision-Safe Target Resolution Test
    let collisionDir = tempDir.appendingPathComponent("CollisionTest")
    try? FileManager.default.createDirectory(at: collisionDir, withIntermediateDirectories: true)
    
    let baseFile = collisionDir.appendingPathComponent("contract.pdf")
    FileManager.default.createFile(atPath: baseFile.path, contents: Data("Original contract".utf8))
    
    let firstCollision = await engine.resolveCollisionSafeTarget(for: "contract.pdf", in: collisionDir)
    expectEqual(firstCollision.lastPathComponent, "contract (1).pdf", "Appended (1) suffix on first collision")
    
    FileManager.default.createFile(atPath: firstCollision.path, contents: Data("Contract copy 1".utf8))
    let secondCollision = await engine.resolveCollisionSafeTarget(for: "contract.pdf", in: collisionDir)
    expectEqual(secondCollision.lastPathComponent, "contract (2).pdf", "Appended (2) suffix on second collision")
    
    // 3. User-Learned Preferences Test ("Learn from edits")
    if let pdfGroupIndex = groups.firstIndex(where: { $0.name == "Documents/PDFs" }) {
        groups = await engine.updateCategory(
            groupIndex: pdfGroupIndex,
            newName: "Finance/Tax_2025",
            groups: groups,
            destRoot: destFolder
        )
    }
    
    let learnedPref = await preferences.preferredCategory(for: "pdf")
    expectEqual(learnedPref, "Finance/Tax_2025", "Preferences store learned user custom category")
    
    // Re-analyzing a new PDF file should now automatically use the learned category
    let invoiceFile = sourceFolder.appendingPathComponent("invoice.pdf")
    FileManager.default.createFile(atPath: invoiceFile.path, contents: Data("Invoice".utf8))
    
    let updatedGroups = await engine.analyzeFolder(targetFolder: sourceFolder, baseDestination: destFolder)
    let updatedNames = updatedGroups.map(\.name)
    expect(updatedNames.contains("Finance/Tax_2025"), "New analysis applied learned category preference")
    
    // 4. Atomic Move & Undo Restoration Test
    let journal = UndoJournal(storageDirectory: tempDir)
    let executionSummary = try? await engine.applyMoves(
        groups: updatedGroups,
        journal: journal,
        allowedRoots: [tempDir]
    )
    
    expect(executionSummary != nil, "Move execution completed successfully")
    expectEqual(executionSummary?.itemsProcessed, 5, "Relocated 5 total files")
    
    // Verify source files moved
    expect(!FileManager.default.fileExists(atPath: pdfFile.path), "Original PDF removed from source")
    expect(!FileManager.default.fileExists(atPath: imageFile.path), "Original Image removed from source")
    
    // Verify files exist in organized subfolders
    let movedPDF = destFolder.appendingPathComponent("Finance/Tax_2025/annual_report.pdf")
    expect(FileManager.default.fileExists(atPath: movedPDF.path), "Moved PDF exists in organized destination folder")
    
    // Verify Undo Restoration restores moved files back to source
    if let batchId = executionSummary?.batchId {
        let restorationResult = try? await journal.restoreRun(runId: batchId)
        expectEqual(restorationResult?.restoredCount, 5, "UndoJournal restored all 5 moved files")
        expect(FileManager.default.fileExists(atPath: pdfFile.path), "Original PDF restored to initial source path")
        expect(FileManager.default.fileExists(atPath: imageFile.path), "Original Image restored to initial source path")
    }
    
    // 5. Loose Directory Organization & Undo Test
    let folderDir = tempDir.appendingPathComponent("DownloadsFolderTest")
    try? FileManager.default.createDirectory(at: folderDir, withIntermediateDirectories: true)
    
    let looseCodeProject = folderDir.appendingPathComponent("MyWebApp")
    try? FileManager.default.createDirectory(at: looseCodeProject, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: looseCodeProject.appendingPathComponent("package.json").path, contents: Data("{}".utf8))
    
    let looseNotesFolder = folderDir.appendingPathComponent("ClassNotes")
    try? FileManager.default.createDirectory(at: looseNotesFolder, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: looseNotesFolder.appendingPathComponent("lecture1.docx").path, contents: Data("Notes".utf8))
    
    let looseFile = folderDir.appendingPathComponent("cheatsheet.pdf")
    FileManager.default.createFile(atPath: looseFile.path, contents: Data("Cheatsheet".utf8))
    
    let mixedGroups = await engine.analyzeFolder(targetFolder: folderDir)
    let mixedMoves = mixedGroups.flatMap(\.moves)
    expectEqual(mixedMoves.count, 3, "Detected 2 loose folders and 1 loose file")
    
    let webAppMove = mixedMoves.first(where: { $0.originalURL.lastPathComponent == "MyWebApp" })
    expect(webAppMove != nil, "Found MyWebApp move")
    expectEqual(webAppMove?.isDirectory, true, "MyWebApp identified as directory")
    expectEqual(webAppMove?.categoryName, "Development/Projects", "MyWebApp categorized into Development/Projects")
    
    let notesMove = mixedMoves.first(where: { $0.originalURL.lastPathComponent == "ClassNotes" })
    expect(notesMove != nil, "Found ClassNotes move")
    expectEqual(notesMove?.isDirectory, true, "ClassNotes identified as directory")
    expectEqual(notesMove?.categoryName, "Documents/Folders", "ClassNotes categorized into Documents/Folders")
    
    let pdfMove = mixedMoves.first(where: { $0.originalURL.lastPathComponent == "cheatsheet.pdf" })
    expectEqual(pdfMove?.isDirectory, false, "PDF identified as file")
    
    // Test applying moves for folders
    let folderJournal = UndoJournal(storageDirectory: tempDir)
    let folderExecSummary = try? await engine.applyMoves(
        groups: mixedGroups,
        journal: folderJournal,
        allowedRoots: [tempDir]
    )
    expectEqual(folderExecSummary?.itemsProcessed, 3, "Moved 3 items (2 folders, 1 file)")
    expect(!FileManager.default.fileExists(atPath: looseCodeProject.path), "Original loose folder removed from source root")
    let targetProject = folderDir.appendingPathComponent("Development/Projects/MyWebApp")
    expect(FileManager.default.fileExists(atPath: targetProject.path), "Loose folder moved to Development/Projects/MyWebApp")
    expect(FileManager.default.fileExists(atPath: targetProject.appendingPathComponent("package.json").path), "Internal folder contents preserved intact")
    
    // Test undo restoration of directory
    if let batchId = folderExecSummary?.batchId {
        let undoResult = try? await folderJournal.restoreRun(runId: batchId)
        expectEqual(undoResult?.restoredCount, 3, "UndoJournal restored all items including folders")
        expect(FileManager.default.fileExists(atPath: looseCodeProject.path), "Loose directory restored back to source root")
        expect(FileManager.default.fileExists(atPath: looseCodeProject.appendingPathComponent("package.json").path), "Restored folder contents fully intact")
    }
}
