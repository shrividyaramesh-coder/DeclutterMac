import Foundation

/// Trigger conditions for a cleanup rule.
public struct RuleTrigger: Codable, Sendable, Equatable {
    public var folderPath: String? // e.g. "~/Downloads", "~/Desktop", nil for all managed folders
    public var fileExtensions: [String]? // e.g. ["dmg", "pkg"]
    public var categories: [ScanCategory]? // e.g. [.screenshots, .caches]
    public var minimumAgeDays: Int? // e.g. 30
    public var minimumSizeBytes: Int64? // e.g. 100 MB
    public var namePattern: String? // e.g. "Screen Shot", "temp"
    
    public init(
        folderPath: String? = nil,
        fileExtensions: [String]? = nil,
        categories: [ScanCategory]? = nil,
        minimumAgeDays: Int? = nil,
        minimumSizeBytes: Int64? = nil,
        namePattern: String? = nil
    ) {
        self.folderPath = folderPath
        self.fileExtensions = fileExtensions
        self.categories = categories
        self.minimumAgeDays = minimumAgeDays
        self.minimumSizeBytes = minimumSizeBytes
        self.namePattern = namePattern
    }
}

/// Action to execute when rule trigger matches.
public enum RuleAction: Codable, Sendable, Equatable {
    case moveToTrash
    case moveToFolder(path: String)
    case reviewOnly
    
    private enum CodingKeys: String, CodingKey {
        case type, path
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .moveToTrash:
            try container.encode("moveToTrash", forKey: .type)
        case .moveToFolder(let path):
            try container.encode("moveToFolder", forKey: .type)
            try container.encode(path, forKey: .path)
        case .reviewOnly:
            try container.encode("reviewOnly", forKey: .type)
        }
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "moveToTrash":
            self = .moveToTrash
        case "moveToFolder":
            let path = try container.decode(String.self, forKey: .path)
            self = .moveToFolder(path: path)
        default:
            self = .reviewOnly
        }
    }
}

/// A standalone or scheduled cleanup rule.
public struct CleanupRule: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    public var description: String
    public var trigger: RuleTrigger
    public var action: RuleAction
    public var isEnabled: Bool
    public let isBuiltIn: Bool
    public let createdAt: Date
    
    public init(
        id: UUID = UUID(),
        name: String,
        description: String,
        trigger: RuleTrigger,
        action: RuleAction,
        isEnabled: Bool = true,
        isBuiltIn: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.trigger = trigger
        self.action = action
        self.isEnabled = isEnabled
        self.isBuiltIn = isBuiltIn
        self.createdAt = createdAt
    }
}

/// Library of built-in templates (exceeding the required 10 templates).
public enum BuiltInRuleTemplates {
    public static func defaultRules() -> [CleanupRule] {
        [
            CleanupRule(
                name: "Old Screenshots to Trash",
                description: "Moves screenshots older than 30 days from Desktop and Pictures to Trash.",
                trigger: RuleTrigger(categories: [.screenshots], minimumAgeDays: 30),
                action: .moveToTrash,
                isEnabled: true,
                isBuiltIn: true
            ),
            CleanupRule(
                name: "Stale Installers in Downloads",
                description: "Moves disk images (.dmg, .pkg, .iso) older than 7 days in Downloads to Trash.",
                trigger: RuleTrigger(folderPath: "~/Downloads", fileExtensions: ["dmg", "pkg", "iso"], minimumAgeDays: 7),
                action: .moveToTrash,
                isEnabled: true,
                isBuiltIn: true
            ),
            CleanupRule(
                name: "Old Download Archives",
                description: "Trashes zip, tar, and gz archives older than 14 days in Downloads.",
                trigger: RuleTrigger(folderPath: "~/Downloads", fileExtensions: ["zip", "tar", "gz", "tgz", "7z"], minimumAgeDays: 14),
                action: .moveToTrash,
                isEnabled: true,
                isBuiltIn: true
            ),
            CleanupRule(
                name: "Large Inactive Files",
                description: "Reviews large files exceeding 1 GB not modified in 90 days.",
                trigger: RuleTrigger(minimumAgeDays: 90, minimumSizeBytes: 1024 * 1024 * 1024),
                action: .reviewOnly,
                isEnabled: true,
                isBuiltIn: true
            ),
            CleanupRule(
                name: "User Cache Cleanup",
                description: "Purges temporary application cache directories older than 14 days in ~/Library/Caches.",
                trigger: RuleTrigger(folderPath: "~/Library/Caches", categories: [.caches], minimumAgeDays: 14),
                action: .moveToTrash,
                isEnabled: true,
                isBuiltIn: true
            ),
            CleanupRule(
                name: "Old Log Files Purge",
                description: "Trashes diagnostic log files (.log) older than 7 days in ~/Library/Logs.",
                trigger: RuleTrigger(folderPath: "~/Library/Logs", categories: [.logs], minimumAgeDays: 7),
                action: .moveToTrash,
                isEnabled: true,
                isBuiltIn: true
            ),
            CleanupRule(
                name: "Sort PDFs from Downloads",
                description: "Moves PDF documents in Downloads to Documents/PDFs.",
                trigger: RuleTrigger(folderPath: "~/Downloads", fileExtensions: ["pdf"]),
                action: .moveToFolder(path: "~/Documents/PDFs"),
                isEnabled: false,
                isBuiltIn: true
            ),
            CleanupRule(
                name: "Organize Office Documents",
                description: "Moves docx, xlsx, and pptx files from Downloads to Documents/Work.",
                trigger: RuleTrigger(folderPath: "~/Downloads", fileExtensions: ["docx", "doc", "xlsx", "pptx", "key", "pages"]),
                action: .moveToFolder(path: "~/Documents/Work"),
                isEnabled: false,
                isBuiltIn: true
            ),
            CleanupRule(
                name: "Screen Recordings Cleanup",
                description: "Trashes video recordings (.mov, .mp4) matching 'Screen Recording' older than 14 days.",
                trigger: RuleTrigger(fileExtensions: ["mov", "mp4"], minimumAgeDays: 14, namePattern: "Screen Recording"),
                action: .moveToTrash,
                isEnabled: true,
                isBuiltIn: true
            ),
            CleanupRule(
                name: "Temporary Artifacts & 0-Byte Files",
                description: "Cleans empty 0-byte files and temporary .tmp artifacts older than 3 days.",
                trigger: RuleTrigger(fileExtensions: ["tmp", "bak", "part"], minimumAgeDays: 3),
                action: .moveToTrash,
                isEnabled: true,
                isBuiltIn: true
            ),
            CleanupRule(
                name: "Xcode Derived Data Purge",
                description: "Cleans old Xcode build caches older than 30 days in ~/Library/Developer/Xcode/DerivedData.",
                trigger: RuleTrigger(folderPath: "~/Library/Developer/Xcode/DerivedData", minimumAgeDays: 30),
                action: .moveToTrash,
                isEnabled: false,
                isBuiltIn: true
            ),
            CleanupRule(
                name: "Creative App Scratch Caches",
                description: "Purges old Adobe and Figma autosaves and media caches older than 30 days.",
                trigger: RuleTrigger(folderPath: "~/Library/Application Support/Adobe", minimumAgeDays: 30),
                action: .moveToTrash,
                isEnabled: false,
                isBuiltIn: true
            )
        ]
    }
}
