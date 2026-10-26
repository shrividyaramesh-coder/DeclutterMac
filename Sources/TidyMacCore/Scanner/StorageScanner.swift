import Foundation
import Darwin

/// Scan lifecycle and progress reporting events streamed to the UI.
public enum ScanEvent: Sendable {
    case progress(itemsScanned: Int, bytesFound: Int, currentPath: String)
    case itemDiscovered(FileItem)
    case completed(totalItems: Int, totalBytes: Int)
    case cancelled
}

/// Actor responsible for multi-directory storage indexing and clutter detection.
public actor StorageScanner {
    public static let shared = StorageScanner()

    private static let blackHoleDirectoryNames: Set<String> = [
        "node_modules", ".git", "Pods", ".build", "DerivedData",
        ".gradle", ".cargo", "venv", ".venv", "vendor"
    ]

    public init() {}

    /// Rapidly computes the total byte size of a directory by summing regular file sizes via POSIX dirent.
    public static func fastFolderSize(at url: URL) -> Int64 {
        let path = url.path(percentEncoded: false)
        return fastFolderSize(atPath: path)
    }

    public static func fastFolderSize(atPath path: String) -> Int64 {
        var total: Int64 = 0
        var stack = [path]
        var statBuf = stat()

        while let currentPath = stack.popLast() {
            guard let dir = opendir(currentPath) else { continue }
            while let entry = readdir(dir) {
                var name = entry.pointee.d_name
                let firstChar = withUnsafeBytes(of: &name) { $0[0] }
                // Skip hidden files (.DS_Store, .git) and current/parent directory links (. and ..)
                if firstChar == 0 || firstChar == 46 /* '.' */ {
                    continue
                }

                let dType = entry.pointee.d_type
                let childName = withUnsafePointer(to: &name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) {
                        String(cString: $0)
                    }
                }
                let childPath = currentPath + "/" + childName

                if dType == DT_REG {
                    if lstat(childPath, &statBuf) == 0 {
                        total += Int64(statBuf.st_size)
                    }
                } else if dType == DT_DIR {
                    if childName != "node_modules" && childName != "Pods" && !childName.hasSuffix(".photoslibrary") {
                        stack.append(childPath)
                    }
                }
            }
            closedir(dir)
        }
        return total
    }

    /// Streams discovered clutter items and scan progress asynchronously.
    /// - Parameters:
    ///   - folders: Directories to scan.
    ///   - includeDeveloperCaches: Whether to include Xcode DerivedData and developer caches.
    /// - Returns: An `AsyncStream` delivering `ScanEvent` updates.
    public func scan(
        folders: [URL],
        includeDeveloperCaches: Bool = false
    ) -> AsyncStream<ScanEvent> {
        AsyncStream { continuation in
            let scanTask = Task {
                var totalScanned = 0
                var totalBytes: Int64 = 0

                let fileManager = FileManager.default
                let canonicalRoots = PathValidator.canonicalizeRoots(folders)
                let resourceKeys: Set<URLResourceKey> = [
                    .fileSizeKey,
                    .creationDateKey,
                    .contentModificationDateKey,
                    .contentAccessDateKey,
                    .isRegularFileKey,
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                    .isPackageKey
                ]

                for folder in folders {
                    if Task.isCancelled {
                        continuation.yield(.cancelled)
                        continuation.finish()
                        return
                    }

                    guard fileManager.fileExists(atPath: folder.path) else { continue }

                    // Skip developer caches if opt-in is disabled
                    if !includeDeveloperCaches && folder.path.contains("Library/Developer") {
                        continue
                    }

                    // Directory enumerator skipping package bundles and hidden internals
                    guard let enumerator = fileManager.enumerator(
                        at: folder,
                        includingPropertiesForKeys: Array(resourceKeys),
                        options: [.skipsPackageDescendants, .skipsHiddenFiles],
                        errorHandler: { _, _ in true }
                    ) else {
                        continue
                    }

                    while let fileURL = enumerator.nextObject() as? URL {
                        if Task.isCancelled {
                            continuation.yield(.cancelled)
                            continuation.finish()
                            return
                        }

                        // Validate against safety invariants and denylist
                        guard PathValidator.isPathAllowedFast(fileURL, precomputedCanonicalRoots: canonicalRoots) else {
                            continue
                        }

                        // Fetch resource attributes
                        guard let values = try? fileURL.resourceValues(forKeys: resourceKeys) else {
                            continue
                        }

                        let isDir = values.isDirectory == true && values.isPackage != true
                        let dirName = fileURL.lastPathComponent

                        // Handle directories
                        if isDir {
                            // 1. Black hole pruning: skip developer dependencies (.git, node_modules, etc.)
                            if Self.blackHoleDirectoryNames.contains(dirName) {
                                enumerator.skipDescendants()
                                continue
                            }

                            // 2. App Caches Aggregation:
                            // If this directory is directly inside ~/Library/Caches, treat as an atomic bundle
                            let parentURL = fileURL.deletingLastPathComponent()
                            if parentURL.lastPathComponent == "Caches" && fileURL.path.contains("Library/Caches") {
                                enumerator.skipDescendants()
                                let folderSize = Self.fastFolderSize(at: fileURL)
                                if folderSize == 0 {
                                    continue
                                }
                                totalScanned += 1
                                let createdDate = values.creationDate ?? Date()
                                let modifiedDate = values.contentModificationDate ?? Date()
                                let openedDate = values.contentAccessDate

                                let category = CategoryClassifier.classify(
                                    url: fileURL,
                                    fileSize: folderSize,
                                    createdDate: createdDate,
                                    lastOpenedDate: openedDate
                                )
                                let risk = RiskEvaluator.evaluateRisk(
                                    category: category,
                                    url: fileURL,
                                    fileSize: folderSize,
                                    createdDate: createdDate,
                                    lastOpenedDate: openedDate
                                )

                                let relPath = fileURL.path.replacingOccurrences(of: folder.path, with: "")
                                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                                let item = FileItem(
                                    url: fileURL,
                                    relativePath: relPath.isEmpty ? fileURL.lastPathComponent : relPath,
                                    fileSize: folderSize,
                                    createdDate: createdDate,
                                    lastModifiedDate: modifiedDate,
                                    lastOpenedDate: openedDate,
                                    category: category,
                                    riskLabel: risk
                                )

                                totalBytes += folderSize
                                continuation.yield(.progress(
                                    itemsScanned: totalScanned,
                                    bytesFound: Int(totalBytes),
                                    currentPath: fileURL.lastPathComponent
                                ))
                                continuation.yield(.itemDiscovered(item))
                                continue
                            }

                            // 3. Developer Caches Aggregation:
                            // If this directory is inside Xcode DerivedData or CoreSimulator/Caches
                            if fileURL.path.contains("Library/Developer/Xcode/DerivedData") ||
                               fileURL.path.contains("Library/Developer/CoreSimulator/Caches") {
                                enumerator.skipDescendants()
                                if !includeDeveloperCaches {
                                    continue
                                }
                                let folderSize = Self.fastFolderSize(at: fileURL)
                                if folderSize == 0 {
                                    continue
                                }
                                totalScanned += 1
                                let createdDate = values.creationDate ?? Date()
                                let modifiedDate = values.contentModificationDate ?? Date()
                                let openedDate = values.contentAccessDate

                                let relPath = fileURL.path.replacingOccurrences(of: folder.path, with: "")
                                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                                let item = FileItem(
                                    url: fileURL,
                                    relativePath: relPath.isEmpty ? fileURL.lastPathComponent : relPath,
                                    fileSize: folderSize,
                                    createdDate: createdDate,
                                    lastModifiedDate: modifiedDate,
                                    lastOpenedDate: openedDate,
                                    category: .developerCaches,
                                    riskLabel: .review
                                )

                                totalBytes += folderSize
                                continuation.yield(.progress(
                                    itemsScanned: totalScanned,
                                    bytesFound: Int(totalBytes),
                                    currentPath: fileURL.lastPathComponent
                                ))
                                continuation.yield(.itemDiscovered(item))
                                continue
                            }

                            // Regular directory container: descend into it to inspect files within
                            continue
                        }

                        // Periodic progress ping for regular files
                        totalScanned += 1
                        if totalScanned % 25 == 0 {
                            continuation.yield(.progress(
                                itemsScanned: totalScanned,
                                bytesFound: Int(totalBytes),
                                currentPath: fileURL.lastPathComponent
                            ))
                        }

                        // Skip cloud placeholders to avoid triggering force-downloads
                        if CloudFolderDetector.isDatalessCloudPlaceholder(fileURL) {
                            continue
                        }

                        let fileSize = Int64(values.fileSize ?? 0)
                        let createdDate = values.creationDate ?? Date()
                        let modifiedDate = values.contentModificationDate ?? Date()
                        let openedDate = values.contentAccessDate

                        let category = CategoryClassifier.classify(
                            url: fileURL,
                            fileSize: fileSize,
                            createdDate: createdDate,
                            lastOpenedDate: openedDate
                        )

                        // If not including developer caches, drop if classified as such
                        if !includeDeveloperCaches && category == .developerCaches {
                            continue
                        }

                        let risk = RiskEvaluator.evaluateRisk(
                            category: category,
                            url: fileURL,
                            fileSize: fileSize,
                            createdDate: createdDate,
                            lastOpenedDate: openedDate
                        )

                        let relPath = fileURL.path.replacingOccurrences(of: folder.path, with: "")
                            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                        let item = FileItem(
                            url: fileURL,
                            relativePath: relPath.isEmpty ? fileURL.lastPathComponent : relPath,
                            fileSize: fileSize,
                            createdDate: createdDate,
                            lastModifiedDate: modifiedDate,
                            lastOpenedDate: openedDate,
                            category: category,
                            riskLabel: risk
                        )

                        totalBytes += fileSize
                        continuation.yield(.itemDiscovered(item))
                    }
                }

                continuation.yield(.completed(totalItems: totalScanned, totalBytes: Int(totalBytes)))
                continuation.finish()
            }

            continuation.onTermination = { _ in
                scanTask.cancel()
            }
        }
    }
}
