import Foundation
import TidyMacCore

/// Stands in for the on-device model with fixed answers.
struct StubTopicCategorizer: TopicCategorizing {
    var topics: [String: String]
    func topics(for itemNames: [String], existingTopics: [String]) async -> [String: String] {
        topics.filter { itemNames.contains($0.key) }
    }
}

@MainActor
func runAutoOrganizerTests() async {
    print("\n--- Running Auto-Organize (Recents, Keep As Is, AI Topics) Tests ---")

    let fileManager = FileManager.default
    let tempDir = fileManager.temporaryDirectory.appendingPathComponent("TidyMacAutoOrganizeTests_\(UUID().uuidString)")
    try? fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: tempDir) }

    let preferences = CategoryPreferencesStore(defaults: UserDefaults(suiteName: "TidyMacAutoOrganizeTests_\(UUID().uuidString)")!)
    let engine = FolderOrganizerEngine(preferencesStore: preferences)
    let journal = UndoJournal(storageDirectory: tempDir)
    let now = Date()
    let day: TimeInterval = 86_400

    func makeFile(_ url: URL, age: TimeInterval) {
        try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        fileManager.createFile(atPath: url.path, contents: Data("x".utf8))
        let date = now.addingTimeInterval(-age)
        try? fileManager.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: url.path)
    }
    func exists(_ url: URL, _ path: String) -> Bool {
        fileManager.fileExists(atPath: url.appendingPathComponent(path).path)
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

    // 1. File-type sorting (AI off)
    let desktop = tempDir.appendingPathComponent("Desktop")
    makeFile(desktop.appendingPathComponent("new_notes.txt"), age: 3600)               // new: goes to Recents
    makeFile(desktop.appendingPathComponent("old_report.pdf"), age: 10 * day)         // old: sorted
    makeFile(desktop.appendingPathComponent("just_saved.txt"), age: 10)               // still being saved: left alone
    makeFile(desktop.appendingPathComponent("movie.mp4.crdownload"), age: 10 * day)   // still downloading: left alone
    makeFile(desktop.appendingPathComponent("Keep As Is/contract.pdf"), age: 10 * day) // never touched
    makeFile(desktop.appendingPathComponent("Recents/aged_photo.png"), age: 5 * day)  // waited long enough: sorted
    makeFile(desktop.appendingPathComponent("Recents/fresh_photo.png"), age: 1 * day) // still waiting

    let organizer = AutoOrganizer(engine: engine, categorizer: nil, journal: journal)
    let result = await organizer.run(folders: [desktop], recentsDays: 3, useAITopics: false, now: now)

    expect(exists(desktop, "Recents/new_notes.txt"), "New file moves into Recents")
    expect(exists(desktop, "Documents/PDFs/old_report.pdf"), "Old file is sorted into its file-type folder")
    expect(exists(desktop, "just_saved.txt"), "A file saved moments ago is left alone")
    expect(exists(desktop, "movie.mp4.crdownload"), "A file still downloading is left alone")
    expect(exists(desktop, "Keep As Is/contract.pdf"), "Keep As Is is never touched")
    expect(exists(desktop, "Media/Images/aged_photo.png"), "A file that waited in Recents long enough is sorted")
    expect(exists(desktop, "Recents/fresh_photo.png"), "A file still within the wait period stays in Recents")
    expectEqual(result.movedToRecents, 1, "One item moved into Recents")
    expectEqual(result.sorted, 2, "Two items sorted")
    expectEqual(result.batchIDs.count, 1, "The pass is one undoable batch")

    // 2. Running again changes nothing
    let afterFirstRun = listing(desktop)
    let secondResult = await organizer.run(folders: [desktop], recentsDays: 3, useAITopics: false, now: now)
    expectEqual(listing(desktop), afterFirstRun, "A second pass leaves the folder unchanged")
    expectEqual(secondResult.totalMoved, 0, "A second pass moves nothing")

    // 3. The whole pass can be undone from History
    if let batchID = result.batchIDs.first {
        let restored = try? await journal.restoreRun(runId: batchID)
        expectEqual(restored?.restoredCount, 3, "Undo restores every item from the pass")
        expect(exists(desktop, "new_notes.txt") && exists(desktop, "old_report.pdf") && exists(desktop, "Recents/aged_photo.png"),
               "Undo puts items back where they were")
    }

    // 4. AI topic folders, with file-type folders for anything the model didn't place
    let downloads = tempDir.appendingPathComponent("Downloads")
    makeFile(downloads.appendingPathComponent("2025_W2_form.pdf"), age: 10 * day)
    makeFile(downloads.appendingPathComponent("flight_tokyo.pdf"), age: 10 * day)
    makeFile(downloads.appendingPathComponent("unplaced.zip"), age: 10 * day)
    let stub = StubTopicCategorizer(topics: ["2025_W2_form.pdf": "Tax Documents", "flight_tokyo.pdf": "Travel"])
    let aiOrganizer = AutoOrganizer(engine: engine, categorizer: stub, journal: journal)
    _ = await aiOrganizer.run(folders: [downloads], recentsDays: 3, useAITopics: true, now: now)
    expect(exists(downloads, "Sorted/Tax Documents/2025_W2_form.pdf"), "AI topic folder used for tax form")
    expect(exists(downloads, "Sorted/Travel/flight_tokyo.pdf"), "AI topic folder used for flight booking")
    expect(exists(downloads, "Archives/unplaced.zip"), "Items the model didn't place fall back to file-type folders")
    let aiSecondRun = await aiOrganizer.run(folders: [downloads], recentsDays: 3, useAITopics: true, now: now)
    expectEqual(aiSecondRun.totalMoved, 0, "Sorted/ topic folders are left alone on the next pass")

    // 5. Model output is cleaned before it becomes a folder name
    expectEqual(TopicNames.sanitize("  Tax / Documents  "), "Tax Documents", "Slashes and extra spaces are removed")
    expectEqual(TopicNames.sanitize("../../etc"), "etc", "Path tricks are neutralized")
    expectEqual(TopicNames.sanitize("   "), nil, "Blank names are rejected")
    expectEqual(TopicNames.sanitize(String(repeating: "A", count: 80)), nil, "Overlong names are rejected")
    let parsed = TopicResponseParser.parse(
        "```json\n{\"a.pdf\": \"Travel\", \"not-asked.pdf\": \"Other\", \"b.pdf\": \"\"}\n```",
        allowedNames: ["a.pdf", "b.pdf"]
    )
    expectEqual(parsed, ["a.pdf": "Travel"], "Parser keeps only asked-for items with usable folder names")
    expectEqual(TopicResponseParser.parse("Sorry, I can't help.", allowedNames: ["a.pdf"]), [:], "Non-JSON replies are ignored")

    // 6. Settings persist, clamp the wait period, and follow the license
    let suite = "TidyMacAutoOrganizeSettings_\(UUID().uuidString)"
    let store = AutoOrganizeSettingsStore(defaults: UserDefaults(suiteName: suite)!)
    expect(!(await store.get().isEnabled), "Auto-organize starts off")
    expectEqual(await store.get().recentsDays, 3, "Default wait period is 3 days")
    var updated = await store.get()
    updated.isEnabled = true
    updated.recentsDays = 999
    await store.update(updated)
    let reloaded = AutoOrganizeSettingsStore(defaults: UserDefaults(suiteName: suite)!)
    expect(await reloaded.get().isEnabled, "Enabled setting persists")
    expectEqual(await reloaded.get().recentsDays, AutoOrganizeSettings.recentsDayRange.upperBound, "Wait period is clamped")
    UserDefaults.standard.removePersistentDomain(forName: suite)
    expect(AutoOrganizeSettingsStore.isAllowed(by: .trial(daysRemaining: 5)), "Allowed during the trial")
    expect(AutoOrganizeSettingsStore.isAllowed(by: .unlocked(licenseKey: "k")), "Allowed with a lifetime license")
    expect(!AutoOrganizeSettingsStore.isAllowed(by: .freeTier(bytesCleaned: 0, allowanceBytes: 1)), "Paused on the free tier")

    // 7. The real on-device model, when this Mac has it
    if let model = TopicCategorizerFactory.onDevice() {
        let names = ["2025_W2_form.pdf", "Flight_Booking_Tokyo.pdf", "Invoice_March_Acme.pdf", "IMG_2034.HEIC"]
        let topics = await model.topics(for: names, existingTopics: [])
        print("  ℹ️ On-device model topics: \(topics)")
        expect(!topics.isEmpty, "On-device model places at least some files into topic folders")
        expect(topics.values.allSatisfy { TopicNames.sanitize($0) == $0 }, "On-device model folder names are clean")
    } else {
        print("  ℹ️ On-device model not available on this Mac; skipped live AI check")
    }
}
