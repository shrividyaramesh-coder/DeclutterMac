import Foundation

/// Errors that may occur during Trash operations.
public enum TrashError: Error, LocalizedError, Equatable {
    case fileNotFound(String)
    case pathValidationFailed(String)
    case trashedURLMissing(String)
    case underlyingError(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "File not found at path: \(path)"
        case .pathValidationFailed(let reason):
            return "Safety validation failed: \(reason)"
        case .trashedURLMissing(let path):
            return "Item was moved to Trash but macOS did not return a valid resulting URL for '\(path)'."
        case .underlyingError(let message):
            return "Trash operation failed: \(message)"
        }
    }
}

/// Actor responsible for safely moving items to the macOS Trash.
/// Enforces Trash-only invariant: NEVER performs permanent deletion (`removeItem` or `unlink`).
public actor TrashMover {
    public static let shared = TrashMover()

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Moves a file or directory to the user's Trash after strict path validation.
    /// - Parameters:
    ///   - url: URL of the file or directory to be trashed.
    ///   - allowedRoots: Optional list of authorized root directories.
    /// - Returns: The resulting URL of the item in the Trash folder.
    @discardableResult
    public func moveToTrash(at url: URL, allowedRoots: [URL]? = nil) throws -> URL {
        // 1. Enforce path validation & denylist invariants
        do {
            try PathValidator.validatePath(url, allowedRoots: allowedRoots)
        } catch {
            throw TrashError.pathValidationFailed(error.localizedDescription)
        }

        // 2. Verify file exists
        let path = url.path(percentEncoded: false)
        guard fileManager.fileExists(atPath: path) else {
            throw TrashError.fileNotFound(path)
        }

        // 3. Clear immutable lock flag if present so macOS can move to Trash
        clearImmutableFlagIfNeeded(at: url)

        // 4. Move to Trash via macOS FileManager API
        var resultingURL: NSURL?
        do {
            try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
        } catch {
            throw TrashError.underlyingError(error.localizedDescription)
        }

        guard let trashedURL = resultingURL as URL? else {
            throw TrashError.trashedURLMissing(path)
        }

        return trashedURL
    }

    /// Clears user immutable flag if file is locked.
    private func clearImmutableFlagIfNeeded(at url: URL) {
        var resourceValues = URLResourceValues()
        if let values = try? url.resourceValues(forKeys: [.isUserImmutableKey]), values.isUserImmutable == true {
            resourceValues.isUserImmutable = false
            var mutableURL = url
            try? mutableURL.setResourceValues(resourceValues)
        }
    }
}
