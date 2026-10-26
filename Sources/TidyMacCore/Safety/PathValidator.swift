import Foundation

/// Security errors raised when file paths violate invariants or safety boundaries.
public enum SecurityError: Error, LocalizedError, Equatable {
    case protectedPath(String)
    case pathTraversalAttempt(String)
    case symlinkEscapesAllowedBoundary(String, target: String)
    case emptyPath
    case permanentDeletionForbidden

    public var errorDescription: String? {
        switch self {
        case .protectedPath(let path):
            return "Operation denied: '\(path)' is a protected system or personal identity path."
        case .pathTraversalAttempt(let path):
            return "Operation denied: Path traversal sequence detected in '\(path)'."
        case .symlinkEscapesAllowedBoundary(let path, let target):
            return "Operation denied: Symlink '\(path)' resolves to '\(target)' outside allowed folders."
        case .emptyPath:
            return "Operation denied: File path is empty."
        case .permanentDeletionForbidden:
            return "Operation denied: Permanent file deletion is strictly forbidden; all deletions must use Trash."
        }
    }
}

/// Validates file paths, enforcing canonicalization, symlink bounds, and denylist invariants.
public struct PathValidator: Sendable {
    /// Fixed system root prefixes that are strictly forbidden from modification under all circumstances.
    private static let protectedSystemPrefixes: [String] = [
        "/System",
        "/Library",
        "/usr",
        "/bin",
        "/sbin",
        "/private/etc",
        "/private/var/root",
        "/private/var/db",
        "/private/var/log",
        "/private/var/vm",
        "/private/var/run",
        "/etc",
        "/opt",
        "/dev",
        "/Volumes",
        "/System/Applications",
        "/System/Library",
        "/Applications/Utilities",
        "/Applications/Safari.app"
    ]

    /// Protected folder/file names relative to the user's home directory.
    private static let protectedHomeRelativePaths: [String] = [
        ".ssh",
        ".gnupg",
        ".aws",
        ".zshrc",
        ".bashrc",
        ".bash_profile",
        ".profile",
        ".gitconfig",
        ".config",
        "Library/Keychains",
        "Library/IdentityServices",
        "Library/Mail",
        "Pictures/Photos Library.photoslibrary"
    ]

    /// Validates whether a given URL is permitted for cleanup or file operations.
    /// - Parameters:
    ///   - url: The target file or directory URL.
    ///   - allowedRoots: Optional list of approved root directory URLs (e.g. granted user folders).
    /// - Returns: `true` if the path satisfies all safety criteria, `false` otherwise.
    public static func isPathAllowed(_ url: URL, allowedRoots: [URL]? = nil) -> Bool {
        do {
            try validatePath(url, allowedRoots: allowedRoots)
            return true
        } catch {
            return false
        }
    }

    /// Precomputes canonical allowed roots for efficient repetitive path checks.
    public static func canonicalizeRoots(_ roots: [URL]) -> [String] {
        return roots.map {
            (($0.resolvingSymlinksInPath().path(percentEncoded: false)) as NSString).standardizingPath
        }
    }

    /// Fast-path validation using precomputed canonical roots.
    public static func isPathAllowedFast(_ url: URL, precomputedCanonicalRoots: [String]?) -> Bool {
        do {
            try validatePath(url, precomputedCanonicalRoots: precomputedCanonicalRoots)
            return true
        } catch {
            return false
        }
    }

    /// Validates a path and throws a descriptive `SecurityError` if it violates any invariant.
    public static func validatePath(_ url: URL, allowedRoots: [URL]? = nil) throws {
        let canonicalRoots = allowedRoots.map { canonicalizeRoots($0) }
        try validatePath(url, precomputedCanonicalRoots: canonicalRoots)
    }

    /// Validates a path against precomputed canonical roots.
    public static func validatePath(_ url: URL, precomputedCanonicalRoots: [String]?) throws {
        let rawPath = url.path(percentEncoded: false)
        guard !rawPath.isEmpty else {
            throw SecurityError.emptyPath
        }

        // 1. Detect path-traversal sequences
        let rel = url.relativePath
        if rel.contains("..") || rawPath.hasPrefix("../") || rawPath.contains("/../") || rawPath.hasSuffix("/..") || rawPath == ".." || rawPath.contains("/./") || rawPath.hasPrefix("./") {
            throw SecurityError.pathTraversalAttempt(rawPath)
        }

        // 2. Canonicalize path and resolve all symlinks
        let canonicalURL = url.resolvingSymlinksInPath()
        let canonicalPath = (canonicalURL.path(percentEncoded: false) as NSString).standardizingPath

        // 3. Denylist: Check hard-coded system directory prefixes
        for sysPrefix in protectedSystemPrefixes {
            if canonicalPath == sysPrefix || canonicalPath.hasPrefix(sysPrefix + "/") {
                throw SecurityError.protectedPath(canonicalPath)
            }
        }

        // Check general /private and /var restrictions:
        // /var and /private are strictly blocked UNLESS the path is inside macOS per-user temporary folders
        // (/private/var/folders or /var/folders) AND is explicitly contained within an authorized allowedRoot.
        let isPerUserTemp = canonicalPath.hasPrefix("/private/var/folders/") || canonicalPath.hasPrefix("/var/folders/")
        if (canonicalPath == "/private" || canonicalPath.hasPrefix("/private/")) ||
           (canonicalPath == "/var" || canonicalPath.hasPrefix("/var/")) {
            if !isPerUserTemp {
                throw SecurityError.protectedPath(canonicalPath)
            }
            // If it is in per-user temp, it is ONLY permitted if explicitly granted via allowedRoots
            guard let precomputedCanonicalRoots = precomputedCanonicalRoots, !precomputedCanonicalRoots.isEmpty else {
                throw SecurityError.protectedPath(canonicalPath)
            }
            let isCoveredByAllowedTemp = precomputedCanonicalRoots.contains { canonicalRoot in
                canonicalPath == canonicalRoot || canonicalPath.hasPrefix(canonicalRoot + "/")
            }
            if !isCoveredByAllowedTemp {
                throw SecurityError.protectedPath(canonicalPath)
            }
        }

        // 4. Denylist: Check user home directory and critical identity paths
        let homePath = (FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false) as NSString).standardizingPath
        if canonicalPath == homePath {
            // Modifying the home root directory itself is forbidden
            throw SecurityError.protectedPath(canonicalPath)
        }

        for relPath in protectedHomeRelativePaths {
            guard !relPath.isEmpty else { continue }
            let fullProtected = "\(homePath)/\(relPath)"
            if canonicalPath == fullProtected || canonicalPath.hasPrefix(fullProtected + "/") {
                throw SecurityError.protectedPath(canonicalPath)
            }
        }

        // 5. Denylist: Check developer internals (.git, .svn, .hg) anywhere in path
        let pathComponents = canonicalURL.pathComponents
        if pathComponents.contains(".git") || pathComponents.contains(".svn") || pathComponents.contains(".hg") {
            throw SecurityError.protectedPath(canonicalPath)
        }

        // 6. Check symlink escape: If original was a symlink, verify its resolved destination
        let isSymlink: Bool = {
            if let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]), values.isSymbolicLink == true {
                return true
            }
            return false
        }()

        // 7. Allowed Roots containment check (if precomputedCanonicalRoots is specified)
        if let precomputedCanonicalRoots = precomputedCanonicalRoots, !precomputedCanonicalRoots.isEmpty {
            let isWithinAnyRoot = precomputedCanonicalRoots.contains { root in
                canonicalPath == root || canonicalPath.hasPrefix(root + "/")
            }

            guard isWithinAnyRoot else {
                if isSymlink {
                    throw SecurityError.symlinkEscapesAllowedBoundary(rawPath, target: canonicalPath)
                } else {
                    throw SecurityError.protectedPath(canonicalPath)
                }
            }
        }
    }
}
