import Foundation

/// Strict metadata-only representation of a file.
/// Under NO CIRCUMSTANCES may file contents, binary streams, or document text
/// be included in this structure or transmitted to any AI provider.
public struct FileMetadataEntry: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let filename: String
    public let fileExtension: String
    public let sizeBytes: Int64
    public let createdDate: Date?
    public let modifiedDate: Date?
    public let lastAccessDate: Date?
    public let relativeFolderPath: String
    
    public init(
        id: UUID = UUID(),
        filename: String,
        fileExtension: String,
        sizeBytes: Int64,
        createdDate: Date? = nil,
        modifiedDate: Date? = nil,
        lastAccessDate: Date? = nil,
        relativeFolderPath: String
    ) {
        self.id = id
        self.filename = filename
        self.fileExtension = fileExtension
        self.sizeBytes = sizeBytes
        self.createdDate = createdDate
        self.modifiedDate = modifiedDate
        self.lastAccessDate = lastAccessDate
        self.relativeFolderPath = relativeFolderPath
    }
}

/// Request payload sent to LLM providers or heuristic planners.
public struct MetadataOnlyRequest: Codable, Sendable, Equatable {
    public let userPrompt: String
    public let files: [FileMetadataEntry]
    public let targetFolders: [String]
    
    public init(userPrompt: String, files: [FileMetadataEntry] = [], targetFolders: [String] = []) {
        self.userPrompt = userPrompt
        self.files = files
        self.targetFolders = targetFolders
    }
}
