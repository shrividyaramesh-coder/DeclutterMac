import Foundation

/// Action type recorded in the Undo Journal.
public enum JournalAction: String, Sendable, Codable {
    case trashed
    case restored
    case moved
}

/// A single atomic operation recorded in the undo journal.
public struct JournalEntry: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let runId: UUID
    public let timestamp: Date
    public let originalURL: URL
    public let trashedURL: URL
    public let fileSize: Int64
    public let checksum: String?
    public let action: JournalAction

    public init(
        id: UUID = UUID(),
        runId: UUID,
        timestamp: Date = Date(),
        originalURL: URL,
        trashedURL: URL,
        fileSize: Int64,
        checksum: String? = nil,
        action: JournalAction = .trashed
    ) {
        self.id = id
        self.runId = runId
        self.timestamp = timestamp
        self.originalURL = originalURL
        self.trashedURL = trashedURL
        self.fileSize = fileSize
        self.checksum = checksum
        self.action = action
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}
