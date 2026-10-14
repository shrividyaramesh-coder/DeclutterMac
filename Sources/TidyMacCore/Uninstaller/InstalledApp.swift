import Foundation

/// Represents an installed application bundle on the user's Mac.
public struct InstalledApp: Identifiable, Sendable, Codable, Hashable {
    public let id: UUID
    public let name: String
    public let bundleIdentifier: String?
    public let version: String?
    public let url: URL
    public let appSize: Int64
    public let lastOpenedDate: Date?
    public let isSystemProtected: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        bundleIdentifier: String? = nil,
        version: String? = nil,
        url: URL,
        appSize: Int64,
        lastOpenedDate: Date? = nil,
        isSystemProtected: Bool = false
    ) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.url = url
        self.appSize = appSize
        self.lastOpenedDate = lastOpenedDate
        self.isSystemProtected = isSystemProtected
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: appSize, countStyle: .file)
    }

    public var formattedLastUsed: String {
        guard let date = lastOpenedDate else { return "Never opened" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

/// An aggregated bundle containing the main app and all discovered related leftovers.
public struct AppUninstallBundle: Identifiable, Sendable, Codable {
    public let id: UUID
    public let app: InstalledApp
    public var leftovers: [FileItem]

    public init(id: UUID = UUID(), app: InstalledApp, leftovers: [FileItem] = []) {
        self.id = id
        self.app = app
        self.leftovers = leftovers
    }

    public var totalSize: Int64 {
        app.appSize + leftovers.reduce(0) { $0 + $1.fileSize }
    }

    public var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
}
