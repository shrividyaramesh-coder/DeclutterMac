import Foundation

/// Strategy for auto-selecting which file in a duplicate cluster to preserve.
public enum DuplicateKeepStrategy: String, Sendable, Codable, CaseIterable, Identifiable {
    case keepOldest = "Keep Oldest File"
    case keepShortestPath = "Keep Shortest Path"

    public var id: String { rawValue }
}

/// A verified cluster of identical files sharing identical size, partial hash, and full SHA-256.
public struct DuplicateGroup: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    public let fileSize: Int64
    public let hash: String
    public var items: [FileItem]

    public init(id: UUID = UUID(), fileSize: Int64, hash: String, items: [FileItem]) {
        self.id = id
        self.fileSize = fileSize
        self.hash = hash
        self.items = items
        self.enforceKeepOneInvariant()
    }

    /// Wasted storage that can be reclaimed by deleting all selected duplicate copies.
    public var selectedWastedBytes: Int64 {
        let selectedCount = items.filter(\.isSelected).count
        return Int64(selectedCount) * fileSize
    }

    /// Total potential space reclaimable if only one copy is kept.
    public var maxReclaimableBytes: Int64 {
        guard items.count > 1 else { return 0 }
        return Int64(items.count - 1) * fileSize
    }

    /// Core Safety Invariant: NEVER allow all copies in a duplicate cluster to be selected.
    public mutating func enforceKeepOneInvariant() {
        let selectedCount = items.filter(\.isSelected).count
        if selectedCount == items.count && !items.isEmpty {
            // Uncheck the first item to guarantee at least one copy is preserved
            items[0].setSelected(false)
        }
    }

    /// Mutates selection of a specific item while upholding the keep-one invariant.
    public mutating func setSelection(for itemId: UUID, isSelected: Bool) {
        guard let index = items.firstIndex(where: { $0.id == itemId }) else { return }

        if isSelected {
            // Check if selecting this item would select all items
            let currentlySelected = items.filter(\.isSelected).count
            if currentlySelected + 1 >= items.count {
                // Cannot select all copies
                return
            }
        }

        items[index].setSelected(isSelected)
        enforceKeepOneInvariant()
    }
}

/// 3-Tier duplicate finding pipeline: Size Grouping -> Partial Hash -> Full SHA-256 Digest.
public actor DuplicateFinderEngine {
    public static let shared = DuplicateFinderEngine()

    public init() {}

    private static let blackHoleDirectoryNames: Set<String> = [
        "node_modules", ".git", "Pods", ".build", "DerivedData",
        ".gradle", ".cargo", "venv", ".venv", "vendor"
    ]

    /// Executes the 3-tier duplicate detection pipeline across specified folders.
    public func findDuplicates(
        folders: [URL],
        strategy: DuplicateKeepStrategy = .keepOldest
    ) async -> [DuplicateGroup] {
        // Step 1: Collect all regular files and group by exact file size
        var filesBySize: [Int64: [URL]] = [:]
        let fileManager = FileManager.default
        let canonicalRoots = PathValidator.canonicalizeRoots(folders)
        let resourceKeys: Set<URLResourceKey> = [
            .fileSizeKey,
            .isDirectoryKey,
            .isPackageKey,
            .isSymbolicLinkKey,
            .creationDateKey,
            .contentModificationDateKey
        ]

        for folder in folders {
            // Never scan system caches or developer build trees for duplicates
            if folder.path.contains("Library/Caches") || folder.path.contains("Library/Developer") {
                continue
            }
            guard fileManager.fileExists(atPath: folder.path) else { continue }
            guard let enumerator = fileManager.enumerator(
                at: folder,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsPackageDescendants, .skipsHiddenFiles],
                errorHandler: { _, _ in true }
            ) else { continue }

            while let fileURL = enumerator.nextObject() as? URL {
                if Task.isCancelled { return [] }

                guard PathValidator.isPathAllowedFast(fileURL, precomputedCanonicalRoots: canonicalRoots) else { continue }
                guard let values = try? fileURL.resourceValues(forKeys: resourceKeys) else { continue }

                // Prune black-hole dependency directories and package bundles
                if values.isDirectory == true {
                    let name = fileURL.lastPathComponent
                    if Self.blackHoleDirectoryNames.contains(name) || name.hasSuffix(".photoslibrary") {
                        enumerator.skipDescendants()
                    }
                    continue
                }

                // Skip packages, symlinks, and dataless cloud placeholders
                if values.isPackage == true || values.isSymbolicLink == true { continue }
                if CloudFolderDetector.isDatalessCloudPlaceholder(fileURL) { continue }

                let size = Int64(values.fileSize ?? 0)
                guard size > 0 else { continue } // Skip 0-byte empty files

                filesBySize[size, default: []].append(fileURL)
            }
        }

        // Tier 1 Filter: Discard groups with only 1 file
        let candidateSizeGroups = filesBySize.filter { $0.value.count > 1 }

        // Tier 2: Group by 32 KB Partial Hash
        var partialHashGroups: [String: (size: Int64, urls: [URL])] = [:]
        for (size, urls) in candidateSizeGroups {
            for url in urls {
                if Task.isCancelled { return [] }
                guard let partialHash = HashUtility.computePartialHash(for: url, fileSize: size) else { continue }
                let key = "\(size)_\(partialHash)"
                var group = partialHashGroups[key, default: (size: size, urls: [])]
                group.urls.append(url)
                partialHashGroups[key] = group
            }
        }

        // Tier 2 Filter: Discard groups with only 1 file
        let candidatePartialGroups = partialHashGroups.filter { $0.value.urls.count > 1 }

        // Tier 3: Group by Full SHA-256 Digest
        var fullHashGroups: [String: (size: Int64, urls: [URL])] = [:]
        for (_, group) in candidatePartialGroups {
            for url in group.urls {
                if Task.isCancelled { return [] }
                guard let fullHash = HashUtility.computeFullHash(for: url) else { continue }
                var finalGroup = fullHashGroups[fullHash, default: (size: group.size, urls: [])]
                finalGroup.urls.append(url)
                fullHashGroups[fullHash] = finalGroup
            }
        }

        // Construct validated DuplicateGroups
        var resultGroups: [DuplicateGroup] = []

        for (hash, group) in fullHashGroups where group.urls.count > 1 {
            var items: [FileItem] = []
            for url in group.urls {
                let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                let item = FileItem(
                    url: url,
                    fileSize: group.size,
                    createdDate: values?.creationDate ?? Date(),
                    lastModifiedDate: values?.contentModificationDate ?? Date(),
                    category: .duplicates,
                    riskLabel: .review,
                    isSelected: false
                )
                items.append(item)
            }

            // Apply Keep Strategy
            applyStrategy(strategy, to: &items)

            var duplicateGroup = DuplicateGroup(
                fileSize: group.size,
                hash: hash,
                items: items
            )
            // Hard invariant check
            duplicateGroup.enforceKeepOneInvariant()
            resultGroups.append(duplicateGroup)
        }

        return resultGroups.sorted(by: { $0.selectedWastedBytes > $1.selectedWastedBytes })
    }

    /// Marks all duplicates as selected EXCEPT the one designated to be kept.
    private func applyStrategy(_ strategy: DuplicateKeepStrategy, to items: inout [FileItem]) {
        guard items.count > 1 else { return }

        let keepIndex: Int
        switch strategy {
        case .keepOldest:
            keepIndex = items.indices.min(by: { items[$0].createdDate < items[$1].createdDate }) ?? 0
        case .keepShortestPath:
            keepIndex = items.indices.min(by: { items[$0].url.path.count < items[$1].url.path.count }) ?? 0
        }

        for i in items.indices {
            if i == keepIndex {
                items[i].setSelected(false) // Keep this original copy
            } else {
                items[i].setSelected(true)  // Mark duplicate copy for trashing
            }
        }
    }
}
