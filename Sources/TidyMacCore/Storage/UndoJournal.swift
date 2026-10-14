import Foundation

/// Errors that can occur during Undo restoration operations.
public enum UndoError: Error, LocalizedError, Equatable {
    case runNotFound(UUID)
    case fileNoLongerInTrash(String)
    case restorationFailed(String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .runNotFound(let runId):
            return "No recorded cleanup run found for ID: \(runId.uuidString)"
        case .fileNoLongerInTrash(let path):
            return "File is no longer in the Trash: '\(path)'. It may have been permanently emptied by Finder."
        case .restorationFailed(let path, let reason):
            return "Could not restore '\(path)': \(reason)"
        }
    }
}

/// Metadata summary of an entire cleanup execution batch.
public struct CleanupRunSummary: Identifiable, Sendable, Codable, Equatable {
    public let runId: UUID
    public let timestamp: Date
    public let itemCount: Int
    public let totalBytes: Int64
    public var isRestored: Bool

    public var id: UUID { runId }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}

/// Actor managing the atomic journaling and reversible restoration of all cleanup operations.
public actor UndoJournal {
    public static let shared = UndoJournal()

    private let fileManager: FileManager
    private var entriesByRun: [UUID: [JournalEntry]] = [:]
    private var runs: [CleanupRunSummary] = []
    private let storageURL: URL

    public init(fileManager: FileManager = .default, storageDirectory: URL? = nil) {
        self.fileManager = fileManager
        let dir = storageDirectory ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/TidyMac")
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        self.storageURL = dir.appendingPathComponent("undo_journal.json")
        let loaded = Self.readStorage(from: self.storageURL)
        self.runs = loaded.runs
        self.entriesByRun = loaded.entries
    }

    /// Records an atomic journal entry.
    public func record(entry: JournalEntry) {
        var runEntries = entriesByRun[entry.runId, default: []]
        runEntries.append(entry)
        entriesByRun[entry.runId] = runEntries

        // Update or create run summary
        if let index = runs.firstIndex(where: { $0.runId == entry.runId }) {
            let existing = runs[index]
            runs[index] = CleanupRunSummary(
                runId: entry.runId,
                timestamp: existing.timestamp,
                itemCount: runEntries.count,
                totalBytes: runEntries.reduce(0) { $0 + $1.fileSize },
                isRestored: false
            )
        } else {
            runs.insert(CleanupRunSummary(
                runId: entry.runId,
                timestamp: entry.timestamp,
                itemCount: 1,
                totalBytes: entry.fileSize,
                isRestored: false
            ), at: 0)
        }

        saveJournal()
    }

    /// Returns all recorded cleanup runs in reverse chronological order.
    public func getRuns() -> [CleanupRunSummary] {
        runs
    }

    /// Returns entries for a specific run.
    public func getEntries(for runId: UUID) -> [JournalEntry] {
        entriesByRun[runId] ?? []
    }

    /// Restores all items in a cleanup run back to their original locations.
    /// - Parameter runId: UUID of the run to reverse.
    /// - Returns: Tuple containing count of restored files and array of non-fatal warnings (e.g., emptied from Trash).
    @discardableResult
    public func restoreRun(runId: UUID) throws -> (restoredCount: Int, warnings: [String]) {
        guard let entries = entriesByRun[runId], !entries.isEmpty else {
            throw UndoError.runNotFound(runId)
        }

        var restoredCount = 0
        var warnings: [String] = []
        var updatedEntries: [JournalEntry] = []

        for entry in entries {
            if entry.action == .restored {
                updatedEntries.append(entry)
                continue
            }

            let trashedPath = entry.trashedURL.path(percentEncoded: false)
            guard fileManager.fileExists(atPath: trashedPath) else {
                warnings.append("Item was emptied from Trash or moved: \(entry.originalURL.lastPathComponent)")
                updatedEntries.append(entry)
                continue
            }

            // Ensure destination directory exists
            let destinationDir = entry.originalURL.deletingLastPathComponent()
            try? fileManager.createDirectory(at: destinationDir, withIntermediateDirectories: true)

            // Resolve collision if destination file already exists
            let targetURL = resolveCollisionIfNeeded(for: entry.originalURL)

            do {
                try fileManager.moveItem(at: entry.trashedURL, to: targetURL)
                restoredCount += 1
                var restoredEntry = entry
                // Mark action as restored
                restoredEntry = JournalEntry(
                    id: entry.id,
                    runId: entry.runId,
                    timestamp: Date(),
                    originalURL: targetURL,
                    trashedURL: entry.trashedURL,
                    fileSize: entry.fileSize,
                    checksum: entry.checksum,
                    action: .restored
                )
                updatedEntries.append(restoredEntry)
            } catch {
                warnings.append("Failed to restore \(entry.originalURL.lastPathComponent): \(error.localizedDescription)")
                updatedEntries.append(entry)
            }
        }

        entriesByRun[runId] = updatedEntries
        if let index = runs.firstIndex(where: { $0.runId == runId }) {
            runs[index].isRestored = (restoredCount > 0)
        }
        saveJournal()

        return (restoredCount, warnings)
    }

    /// Avoids overwriting an existing file at restore destination by generating a counter suffix.
    private func resolveCollisionIfNeeded(for url: URL) -> URL {
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
            return url
        }

        let dir = url.deletingLastPathComponent()
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension

        var counter = 1
        while true {
            let newFilename = ext.isEmpty ? "\(name) (restored \(counter))" : "\(name) (restored \(counter)).\(ext)"
            let candidate = dir.appendingPathComponent(newFilename)
            if !fileManager.fileExists(atPath: candidate.path(percentEncoded: false)) {
                return candidate
            }
            counter += 1
        }
    }

    private func saveJournal() {
        struct JournalStorageModel: Codable {
            let runs: [CleanupRunSummary]
            let entries: [String: [JournalEntry]]
        }

        var mappedEntries: [String: [JournalEntry]] = [:]
        for (k, v) in entriesByRun {
            mappedEntries[k.uuidString] = v
        }

        let storageModel = JournalStorageModel(runs: runs, entries: mappedEntries)
        if let data = try? JSONEncoder().encode(storageModel) {
            try? data.write(to: storageURL, options: .atomic)
        }
    }

    private static func readStorage(from storageURL: URL) -> (runs: [CleanupRunSummary], entries: [UUID: [JournalEntry]]) {
        struct JournalStorageModel: Codable {
            let runs: [CleanupRunSummary]
            let entries: [String: [JournalEntry]]
        }

        guard let data = try? Data(contentsOf: storageURL),
              let model = try? JSONDecoder().decode(JournalStorageModel.self, from: data) else {
            return ([], [:])
        }

        var mapped: [UUID: [JournalEntry]] = [:]
        for (k, v) in model.entries {
            if let uuid = UUID(uuidString: k) {
                mapped[uuid] = v
            }
        }
        return (model.runs, mapped)
    }
}
