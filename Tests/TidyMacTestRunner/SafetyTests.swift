import Foundation
import TidyMacCore

@MainActor
func runSafetyTests() async {
    print("\n--- Running Safety & Security Invariant Tests ---")
    
    // 1. System Denylist Tests
    let systemPaths = [
        "/System",
        "/System/Library",
        "/System/Library/CoreServices",
        "/Library",
        "/Library/Preferences",
        "/usr",
        "/usr/bin/swift",
        "/private/etc/hosts",
        "/etc/passwd",
        "/Applications/Utilities",
        "/Applications/Safari.app"
    ]
    
    for path in systemPaths {
        let url = URL(fileURLWithPath: path)
        expect(!PathValidator.isPathAllowed(url), "Denylist must block system path: \(path)")
    }
    
    // 2. User Home & Identity Denylist Tests
    let homeURL = FileManager.default.homeDirectoryForCurrentUser
    expect(!PathValidator.isPathAllowed(homeURL), "Denylist must block user home root directory (~)")
    
    let identityRelativePaths = [
        ".ssh",
        ".ssh/id_rsa",
        ".gnupg",
        ".aws",
        ".aws/credentials",
        ".zshrc",
        ".bashrc",
        ".gitconfig",
        ".config",
        "Library/Keychains",
        "Library/Mail",
        "Pictures/Photos Library.photoslibrary"
    ]
    
    for rel in identityRelativePaths {
        let url = homeURL.appendingPathComponent(rel)
        expect(!PathValidator.isPathAllowed(url), "Denylist must block user identity path: \(rel)")
    }
    
    // 3. Git internals protection
    let gitURL = URL(fileURLWithPath: "/Users/test/Projects/myrepo/.git/config")
    expect(!PathValidator.isPathAllowed(gitURL), "Denylist must block .git repository internals")
    
    // 4. Path Traversal Defense Tests
    let traversalPaths = [
        "/Users/test/Downloads/../../System",
        "/Users/test/Documents/../.ssh/id_rsa",
        "/Users/test/Desktop/../..",
        "../../etc/hosts"
    ]
    
    for trav in traversalPaths {
        let url = URL(fileURLWithPath: trav)
        expect(!PathValidator.isPathAllowed(url), "PathValidator must block path traversal: \(trav)")
    }
    
    // 5. Allowed Roots & Symlink Bounds Enforcement
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("TidyMacSafetyTests_\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    let safeFile = tempDir.appendingPathComponent("safe_document.txt")
    FileManager.default.createFile(atPath: safeFile.path, contents: "Sample Data".data(using: .utf8))
    
    expect(PathValidator.isPathAllowed(safeFile, allowedRoots: [tempDir]), "Safe file inside allowed root must be allowed")
    
    // External symlink pointing outside allowed root
    let symlinkURL = tempDir.appendingPathComponent("escape_link")
    try? FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
    
    expect(!PathValidator.isPathAllowed(symlinkURL, allowedRoots: [tempDir]), "Symlink pointing outside allowed root must be blocked")
    
    // 6. TrashMover Tests
    let trashTestFile = tempDir.appendingPathComponent("test_to_trash.txt")
    FileManager.default.createFile(atPath: trashTestFile.path, contents: "Junk Data".data(using: .utf8))
    
    do {
        let trashedURL = try await TrashMover.shared.moveToTrash(at: trashTestFile, allowedRoots: [tempDir])
        expect(!FileManager.default.fileExists(atPath: trashTestFile.path), "Original file must be removed from original location after trashing")
        expect(FileManager.default.fileExists(atPath: trashedURL.path), "Trashed file must exist in Trash directory")
        expect(trashedURL.path.contains(".Trash") || trashedURL.path.contains("Trash"), "Resulting item URL must be in Trash folder")
    } catch {
        expect(false, "TrashMover failed with unexpected error: \(error)")
    }
    
    // 7. TrashMover Denylist Protection Test
    do {
        _ = try await TrashMover.shared.moveToTrash(at: URL(fileURLWithPath: "/System/Library"))
        expect(false, "TrashMover must refuse to trash protected system path")
    } catch {
        expect(true, "TrashMover correctly rejected trashing protected system path")
    }
}
