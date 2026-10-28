import Foundation

/// Outcome of one auto-organize pass.
public struct AutoOrganizeResult: Sendable, Equatable {
    public var movedToRecents: Int = 0
    public var sorted: Int = 0
    /// Undo journal batches, one per folder that changed.
    public var batchIDs: [UUID] = []

    public init() {}

    public var totalMoved: Int { movedToRecents + sorted }
}

/// Keeps folders tidy without being asked:
/// - new items move into `Recents/` so the folder stays clear,
/// - after `recentsDays` they are sorted into topic folders (`Sorted/<Topic>/`, on-device AI) or file-type folders,
/// - `Keep As Is/` and folders created by earlier runs are never touched,
/// - items still downloading or being saved are left alone until they settle.
/// Every move goes through the undo journal.
public actor AutoOrganizer {
    public static let shared = AutoOrganizer()

    public static let recentsFolderName = "Recents"
    public static let keepAsIsFolderName = "Keep As Is"
    public static let topicsFolderName = "Sorted"

    /// Items changed more recently than this are probably still downloading or being saved.
    public static let settleSeconds: TimeInterval = 120
    static let inProgressExtensions: Set<String> = ["crdownload", "download", "part", "partial", "opdownload", "tmp"]

    private let engine: FolderOrganizerEngine
    private let categorizer: TopicCategorizing?
    private let journal: UndoJournal
    private let fileManager: FileManager

    public init(
        engine: FolderOrganizerEngine = .shared,
        categorizer: TopicCategorizing? = TopicCategorizerFactory.onDevice(),
        journal: UndoJournal = .shared,
        fileManager: FileManager = .default
    ) {
        self.engine = engine
        self.categorizer = categorizer
        self.journal = journal
        self.fileManager = fileManager
    }

    public func run(folders: [URL], recentsDays: Int, useAITopics: Bool, now: Date = Date()) async -> AutoOrganizeResult {
        var result = AutoOrganizeResult()
        for folder in folders {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            let folderResult = await organize(folder: folder, recentsDays: recentsDays, useAITopics: useAITopics, now: now)
            result.movedToRecents += folderResult.movedToRecents
            result.sorted += folderResult.sorted
            result.batchIDs += folderResult.batchIDs
        }
        return result
    }

    private func organize(folder: URL, recentsDays: Int, useAITopics: Bool, now: Date) async -> AutoOrganizeResult {
        let recents = folder.appendingPathComponent(Self.recentsFolderName, isDirectory: true)
        let topicsRoot = folder.appendingPathComponent(Self.topicsFolderName, isDirectory: true)
        try? fileManager.createDirectory(at: recents, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: folder.appendingPathComponent(Self.keepAsIsFolderName, isDirectory: true), withIntermediateDirectories: true)
        let waitPeriod = TimeInterval(recentsDays) * 86_400

        // The engine already skips generated folders (Recents, Keep As Is, Sorted, category folders) and
        // proposes a file-type destination for everything else.
        let looseItems = await engine.analyzeFolder(targetFolder: folder).flatMap(\.moves)
        let waitingItems = await engine.analyzeFolder(targetFolder: recents, baseDestination: folder).flatMap(\.moves)

        var toRecents: [ProposedMove] = []
        var toSort: [ProposedMove] = []
        for move in looseItems where isSettled(move.originalURL, now: now) {
            if age(of: move.originalURL, now: now) < waitPeriod {
                toRecents.append(move)
            } else {
                toSort.append(move)
            }
        }
        for move in waitingItems where isSettled(move.originalURL, now: now) && age(of: move.originalURL, now: now) >= waitPeriod {
            toSort.append(move)
        }

        var topicByName: [String: String] = [:]
        if useAITopics, let categorizer, !toSort.isEmpty {
            let existingTopics = ((try? fileManager.contentsOfDirectory(atPath: topicsRoot.path)) ?? [])
                .filter { !$0.hasPrefix(".") }
                .sorted()
            topicByName = await categorizer.topics(for: toSort.map(\.originalURL.lastPathComponent), existingTopics: existingTopics)
        }

        var groupsByDestination: [String: OrganizationCategoryGroup] = [:]
        func add(_ move: ProposedMove, to destination: URL, name: String) {
            groupsByDestination[destination.path, default: OrganizationCategoryGroup(name: name, destinationFolder: destination, moves: [])]
                .moves.append(move)
        }
        for move in toRecents {
            add(move, to: recents, name: Self.recentsFolderName)
        }
        for move in toSort {
            if let topic = topicByName[move.originalURL.lastPathComponent] {
                add(move, to: topicsRoot.appendingPathComponent(topic, isDirectory: true), name: "\(Self.topicsFolderName)/\(topic)")
            } else {
                add(move, to: move.targetURL.deletingLastPathComponent(), name: move.categoryName)
            }
        }

        var result = AutoOrganizeResult()
        guard !groupsByDestination.isEmpty else { return result }
        let groups = groupsByDestination.values.sorted { $0.name < $1.name }
        guard let summary = try? await engine.applyMoves(groups: groups, journal: journal, allowedRoots: [folder]) else {
            return result
        }
        // applyMoves only reports a total; attribute it from what actually left its original place.
        result.movedToRecents = toRecents.filter { !fileManager.fileExists(atPath: $0.originalURL.path) }.count
        result.sorted = summary.itemsProcessed - result.movedToRecents
        if summary.itemsProcessed > 0 {
            result.batchIDs = [summary.batchId]
        }
        return result
    }

    /// How long ago the item was created or last changed, whichever is later.
    private func age(of url: URL, now: Date) -> TimeInterval {
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        let dates = [values?.creationDate, values?.contentModificationDate].compactMap { $0 }
        guard let latest = dates.max() else { return 0 }
        return now.timeIntervalSince(latest)
    }

    /// False while an item is still downloading or was saved moments ago.
    private func isSettled(_ url: URL, now: Date) -> Bool {
        if Self.inProgressExtensions.contains(url.pathExtension.lowercased()) { return false }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? now
        return now.timeIntervalSince(modified) >= Self.settleSeconds
    }
}
