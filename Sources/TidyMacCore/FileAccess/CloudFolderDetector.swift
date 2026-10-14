import Foundation

/// Identifies whether a directory or file belongs to a known cloud synchronization provider.
public enum CloudProvider: String, Sendable, Codable, CaseIterable {
    case iCloud = "iCloud Drive"
    case dropBox = "Dropbox"
    case googleDrive = "Google Drive"
    case oneDrive = "OneDrive"

    public var systemImage: String {
        switch self {
        case .iCloud: return "icloud.fill"
        case .dropBox: return "shippingbox.fill"
        case .googleDrive: return "externaldrive.fill"
        case .oneDrive: return "cloud.fill"
        }
    }
}

public struct CloudFolderDetector: Sendable {
    /// Detects if a URL is located inside any recognized cloud-synced directory.
    public static func detectProvider(for url: URL) -> CloudProvider? {
        let path = url.path(percentEncoded: false)
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)

        if path.contains("Library/Mobile Documents/com~apple~CloudDocs") || path.contains("Mobile Documents") {
            return .iCloud
        }
        if path.hasPrefix("\(homePath)/Dropbox") || path.contains("/Dropbox/") {
            return .dropBox
        }
        if path.hasPrefix("\(homePath)/Google Drive") || path.contains("/Google Drive/") || path.contains("GoogleDrive") {
            return .googleDrive
        }
        if path.hasPrefix("\(homePath)/OneDrive") || path.contains("/OneDrive/") {
            return .oneDrive
        }

        return nil
    }

    /// Checks whether a file is an evicted/dataless cloud placeholder.
    /// Invariant: Dataless cloud files must NEVER be read or hashed to prevent forced downloads.
    public static func isDatalessCloudPlaceholder(_ url: URL) -> Bool {
        // 1. Check filename prefix/extension common to iCloud placeholders (.filename.icloud)
        if url.lastPathComponent.hasPrefix(".") && url.pathExtension == "icloud" {
            return true
        }

        // 2. Query URLResourceValues for ubiquity download status
        if let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
           values.isUbiquitousItem == true {
            if values.ubiquitousItemDownloadingStatus == .notDownloaded {
                return true
            }
        }

        return false
    }

    /// Returns a plain language warning string if the target URL is in a cloud directory.
    public static func syncWarning(for url: URL) -> String? {
        guard let provider = detectProvider(for: url) else { return nil }
        return "Warning: '\(url.lastPathComponent)' is synced via \(provider.rawValue). Deleting it will also remove it from your other connected devices."
    }
}
