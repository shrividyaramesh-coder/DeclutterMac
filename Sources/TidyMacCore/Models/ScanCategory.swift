import Foundation

/// Categories of storage junk and clutter discovered during scans.
public enum ScanCategory: String, Sendable, Codable, CaseIterable, Identifiable {
    case caches
    case logs
    case developerCaches
    case oldDownloads
    case screenshots
    case largeFiles
    case duplicates
    case appLeftovers
    case trash
    case messagingMedia
    case browserCaches
    case manualReview

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .caches:
            return "User Caches"
        case .logs:
            return "System & App Logs"
        case .developerCaches:
            return "Developer Caches"
        case .oldDownloads:
            return "Old Installers & Downloads"
        case .screenshots:
            return "Screenshots"
        case .largeFiles:
            return "Large Unused Files"
        case .duplicates:
            return "Duplicate Files"
        case .appLeftovers:
            return "App Leftovers"
        case .trash:
            return "Trash Can"
        case .messagingMedia:
            return "Messaging Media"
        case .browserCaches:
            return "Browser Caches"
        case .manualReview:
            return "Manual Review"
        }
    }

    public var systemImage: String {
        switch self {
        case .caches:
            return "archivebox.fill"
        case .logs:
            return "doc.plaintext.fill"
        case .developerCaches:
            return "hammer.fill"
        case .oldDownloads:
            return "arrow.down.circle.fill"
        case .screenshots:
            return "camera.viewfinder"
        case .largeFiles:
            return "internaldrive.fill"
        case .duplicates:
            return "doc.on.doc.fill"
        case .appLeftovers:
            return "trash.slash.fill"
        case .trash:
            return "trash.fill"
        case .messagingMedia:
            return "message.fill"
        case .browserCaches:
            return "globe"
        case .manualReview:
            return "magnifyingglass.circle.fill"
        }
    }

    public var defaultRisk: RiskLabel {
        switch self {
        case .caches, .logs, .oldDownloads, .trash, .browserCaches:
            return .safe
        case .developerCaches, .screenshots, .largeFiles, .duplicates, .appLeftovers, .messagingMedia:
            return .review
        case .manualReview:
            return .manual
        }
    }
}
