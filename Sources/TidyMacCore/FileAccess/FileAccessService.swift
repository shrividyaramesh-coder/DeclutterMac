import Foundation

/// Unified file access layer supporting both sandboxed Security-Scoped Bookmarks and direct Full Disk Access.
public actor FileAccessService {
    public static let shared = FileAccessService()

    private let bookmarkStorageKey = "TidyMacSecurityScopedBookmarks"
    private var activeBookmarks: [String: Data] = [:]
    private var resolvedURLs: [String: URL] = [:]

    public init() {
        if let stored = UserDefaults.standard.dictionary(forKey: bookmarkStorageKey) as? [String: Data] {
            self.activeBookmarks = stored
        }
    }

    /// Stores a security-scoped bookmark for an approved folder URL.
    public func saveBookmark(for url: URL) throws -> Data {
        let canonical = url.resolvingSymlinksInPath()
        let bookmarkData = try canonical.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        activeBookmarks[canonical.path] = bookmarkData
        UserDefaults.standard.set(activeBookmarks, forKey: bookmarkStorageKey)
        resolvedURLs[canonical.path] = canonical
        return bookmarkData
    }

    /// Resolves and returns all currently managed and accessible folder URLs.
    public func getManagedFolderURLs() -> [URL] {
        var urls: [URL] = []

        for (path, data) in activeBookmarks {
            var isStale = false
            if let resolved = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                if isStale {
                    // Refresh stale bookmark data
                    if let freshData = try? resolved.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                        activeBookmarks[path] = freshData
                        UserDefaults.standard.set(activeBookmarks, forKey: bookmarkStorageKey)
                    }
                }
                urls.append(resolved)
                resolvedURLs[path] = resolved
            } else {
                // Direct path fallback if bookmark resolution is unsupported in current environment
                let fallback = URL(fileURLWithPath: path)
                urls.append(fallback)
            }
        }

        // If no bookmarks saved yet, supply default onboarding paths
        if urls.isEmpty {
            for folderType in ManagedFolderType.allCases {
                let defaultURL = folderType.defaultURL
                if FileManager.default.fileExists(atPath: defaultURL.path) {
                    urls.append(defaultURL)
                }
            }
        }

        return urls
    }

    /// Executes an operation inside a security-scoped access block with guaranteed cleanup.
    public func withSecurityScope<T: Sendable>(for url: URL, operation: @Sendable (URL) throws -> T) throws -> T {
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try operation(url)
    }

    /// Removes a managed folder from persistent bookmarks.
    public func removeManagedFolder(at url: URL) {
        let path = url.resolvingSymlinksInPath().path
        activeBookmarks.removeValue(forKey: path)
        resolvedURLs.removeValue(forKey: path)
        UserDefaults.standard.set(activeBookmarks, forKey: bookmarkStorageKey)
    }
}
