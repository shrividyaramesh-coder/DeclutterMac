import Foundation

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

    private var isScanning = false

    public init() {}

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
                        options: [.skipsPackageDescendants],
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

                        // Periodic progress ping
                        totalScanned += 1
                        if totalScanned % 25 == 0 {
                            continuation.yield(.progress(
                                itemsScanned: totalScanned,
                                bytesFound: Int(totalBytes),
                                currentPath: fileURL.lastPathComponent
                            ))
                        }

                        // Validate against safety invariants and denylist
                        guard PathValidator.isPathAllowed(fileURL, allowedRoots: folders) else {
                            continue
                        }

                        // Fetch resource attributes
                        guard let values = try? fileURL.resourceValues(forKeys: resourceKeys) else {
                            continue
                        }

                        // Skip directory containers themselves (we inspect files within)
                        if values.isDirectory == true && values.isPackage != true {
                            continue
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

                        let item = FileItem(
                            url: fileURL,
                            relativePath: fileURL.path.replacingOccurrences(of: folder.path, with: ""),
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
