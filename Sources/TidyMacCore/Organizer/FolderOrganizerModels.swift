import Foundation

/// Strategy used to classify files during folder organization.
public enum OrganizationStrategy: String, Sendable, Codable, CaseIterable, Identifiable {
    case byCategory = "Smart Categories"
    case byDate = "By Date (Year & Month)"
    case byType = "By File Type"
    
    public var id: String { rawValue }
}

/// Proposed file relocation item.
public struct ProposedMove: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    public let originalURL: URL
    public var targetURL: URL
    public var categoryName: String
    public let fileSize: Int64
    public var isSelected: Bool
    public var isDirectory: Bool
    public var sourceRelativePath: String
    
    public init(
        id: UUID = UUID(),
        originalURL: URL,
        targetURL: URL,
        categoryName: String,
        fileSize: Int64,
        isSelected: Bool = true,
        isDirectory: Bool = false,
        sourceRelativePath: String = ""
    ) {
        self.id = id
        self.originalURL = originalURL
        self.targetURL = targetURL
        self.categoryName = categoryName
        self.fileSize = fileSize
        self.isSelected = isSelected
        self.isDirectory = isDirectory
        self.sourceRelativePath = sourceRelativePath
    }
    
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

/// A cluster of proposed moves grouped under an editable category.
public struct OrganizationCategoryGroup: Identifiable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    public var destinationFolder: URL
    public var moves: [ProposedMove]
    
    public init(
        id: UUID = UUID(),
        name: String,
        destinationFolder: URL,
        moves: [ProposedMove]
    ) {
        self.id = id
        self.name = name
        self.destinationFolder = destinationFolder
        self.moves = moves
    }
    
    public var totalSize: Int64 {
        moves.filter(\.isSelected).reduce(0) { $0 + $1.fileSize }
    }
    
    public var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
}

/// Learned user categorization preferences persisting custom mappings.
public actor CategoryPreferencesStore {
    public static let shared = CategoryPreferencesStore()
    
    private let storageKey = "TidyMacLearnedCategoryPreferences"
    private var preferences: [String: String] = [:]
    
    public init() {
        if let stored = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String] {
            self.preferences = stored
        }
    }
    
    /// Learns that a specific file extension or pattern should map to a preferred category name.
    public func rememberPreference(extensionKey: String, category: String) {
        preferences[extensionKey.lowercased()] = category
        UserDefaults.standard.set(preferences, forKey: storageKey)
    }
    
    /// Retrieves user preferred category for an extension, if previously configured.
    public func preferredCategory(for extensionKey: String) -> String? {
        preferences[extensionKey.lowercased()]
    }
    
    /// Clears learned preferences.
    public func reset() {
        preferences.removeAll()
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
