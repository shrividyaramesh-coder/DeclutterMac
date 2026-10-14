import Foundation

/// Represents a discrete file or bundle identified during scanning.
public struct FileItem: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let url: URL
    public let relativePath: String
    public let fileSize: Int64
    public let createdDate: Date
    public let lastModifiedDate: Date
    public let lastOpenedDate: Date?
    public let category: ScanCategory
    public let riskLabel: RiskLabel
    public var isSelected: Bool
    public let isCloudPlaceholder: Bool

    public init(
        id: UUID = UUID(),
        url: URL,
        relativePath: String? = nil,
        fileSize: Int64,
        createdDate: Date = Date(),
        lastModifiedDate: Date = Date(),
        lastOpenedDate: Date? = nil,
        category: ScanCategory,
        riskLabel: RiskLabel? = nil,
        isSelected: Bool? = nil,
        isCloudPlaceholder: Bool = false
    ) {
        self.id = id
        self.url = url
        self.relativePath = relativePath ?? url.lastPathComponent
        self.fileSize = fileSize
        self.createdDate = createdDate
        self.lastModifiedDate = lastModifiedDate
        self.lastOpenedDate = lastOpenedDate
        self.category = category
        let resolvedRisk = riskLabel ?? category.defaultRisk
        self.riskLabel = resolvedRisk
        // Invariant: manual risk items can never be selected.
        if resolvedRisk == .manual {
            self.isSelected = false
        } else {
            self.isSelected = isSelected ?? (resolvedRisk == .safe)
        }
        self.isCloudPlaceholder = isCloudPlaceholder
    }

    /// Human-readable file size string (e.g. "14.2 MB").
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    /// Mutates selection while upholding the non-selectable Manual invariant.
    public mutating func setSelected(_ selected: Bool) {
        guard riskLabel.isSelectable else {
            self.isSelected = false
            return
        }
        self.isSelected = selected
    }
}
