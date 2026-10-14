import Foundation
import AppKit

/// Standard folders offered during onboarding for Tidy Mac management.
public enum ManagedFolderType: String, Sendable, Codable, CaseIterable, Identifiable {
    case downloads
    case documents
    case desktop
    case pictures
    case caches

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .downloads: return "Downloads"
        case .documents: return "Documents"
        case .desktop: return "Desktop"
        case .pictures: return "Pictures & Screenshots"
        case .caches: return "User Caches & Logs"
        }
    }

    public var systemImage: String {
        switch self {
        case .downloads: return "arrow.down.circle.fill"
        case .documents: return "folder.fill"
        case .desktop: return "menubar.dock.rectangle"
        case .pictures: return "photo.stack.fill"
        case .caches: return "archivebox.fill"
        }
    }

    /// Resolves the default system URL for this folder type.
    public var defaultURL: URL {
        let fileManager = FileManager.default
        switch self {
        case .downloads:
            return fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        case .documents:
            return fileManager.urls(for: .documentDirectory, in: .userDomainMask).first ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        case .desktop:
            return fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        case .pictures:
            return fileManager.urls(for: .picturesDirectory, in: .userDomainMask).first ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
        case .caches:
            return fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches")
        }
    }
}

/// Manages system permissions, Full Disk Access (FDA) detection, and system settings navigation.
public final class PermissionsManager: Sendable {
    public static let shared = PermissionsManager()

    /// Deep-link URL to open macOS System Settings directly to Full Disk Access.
    public static let fullDiskAccessSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    private init() {}

    /// Checks if the application currently possesses Full Disk Access.
    /// Tested by probing read accessibility of a protected user directory (e.g., ~/Library/Safari or ~/Library/Mail).
    public func checkFullDiskAccess() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let protectedTestFolder = home.appendingPathComponent("Library/Safari")
        
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: protectedTestFolder.path, isDirectory: &isDir) {
            // Attempt to read directory contents
            do {
                _ = try FileManager.default.contentsOfDirectory(at: protectedTestFolder, includingPropertiesForKeys: nil)
                return true
            } catch {
                return false
            }
        }
        
        // Alternative probe: User Preferences or Mail
        let mailTestFolder = home.appendingPathComponent("Library/Mail")
        if FileManager.default.fileExists(atPath: mailTestFolder.path, isDirectory: &isDir) {
            do {
                _ = try FileManager.default.contentsOfDirectory(at: mailTestFolder, includingPropertiesForKeys: nil)
                return true
            } catch {
                return false
            }
        }
        
        // If neither exists, check if ~/Library/Preferences can be read
        let prefsFolder = home.appendingPathComponent("Library/Preferences")
        do {
            _ = try FileManager.default.contentsOfDirectory(at: prefsFolder, includingPropertiesForKeys: nil)
            return true
        } catch {
            return false
        }
    }

    /// Opens System Settings to the Full Disk Access pane.
    @MainActor
    public func openSystemSettings() {
        NSWorkspace.shared.open(Self.fullDiskAccessSettingsURL)
    }
}
