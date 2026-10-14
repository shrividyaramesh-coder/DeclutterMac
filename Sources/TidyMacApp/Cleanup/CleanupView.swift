import SwiftUI
import TidyMacCore

public struct CleanupView: View {
    @EnvironmentObject var appState: AppState
    @State private var scanStatusText: String = ""
    @State private var isCleaning: Bool = false
    @State private var cleanResultSummary: String? = nil

    public init() {}

    private var selectedItems: [FileItem] {
        appState.scannedItems.filter(\.isSelected)
    }

    private var selectedBytes: Int64 {
        selectedItems.reduce(0) { $0 + $1.fileSize }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Action Bar
            HStack(spacing: 12) {
                Button(action: startScan) {
                    Label(appState.isScanning ? localized("action.scanning") : localized("action.scan"), systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.isScanning || isCleaning)

                Button(action: selectRecommended) {
                    Label(localized("action.select_recommended"), systemImage: "checkmark.shield")
                }
                .buttonStyle(.bordered)
                .disabled(appState.scannedItems.isEmpty || appState.isScanning)

                Button(action: deselectAll) {
                    Label(localized("action.deselect_all"), systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .disabled(appState.scannedItems.isEmpty || appState.isScanning)

                Spacer()

                Button(action: cleanSelected) {
                    Label(isCleaning ? localized("action.cleaning") : "\(localized("action.clean")) (\(ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file)))", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(selectedItems.isEmpty || appState.isScanning || isCleaning)
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Space Preview Banner
            SpacePreviewView(
                currentFreeBytes: appState.storageSummary.freeDiskBytes,
                selectedCleanupBytes: selectedBytes
            )
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // Scanning Status / Progress
            if appState.isScanning {
                HStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                    Text(scanStatusText.isEmpty ? localized("action.scanning") : scanStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            // Results List or Empty State
            if appState.scannedItems.isEmpty && !appState.isScanning {
                VStack(spacing: 16) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 48))
                        .foregroundStyle(.tint)
                    Text("No Scanned Items Yet")
                        .font(.title2)
                        .bold()
                    Text("Click 'Scan Now' to search for temporary caches, old installers, and unused files.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button(localized("action.scan"), action: startScan)
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    ForEach(groupedCategories(), id: \.self) { category in
                        Section(header: categoryHeader(category: category)) {
                            ForEach(indicesForCategory(category), id: \.self) { index in
                                CleanupItemRow(item: $appState.scannedItems[index])
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .alert(isPresented: Binding(get: { cleanResultSummary != nil }, set: { if !$0 { cleanResultSummary = nil } })) {
            Alert(
                title: Text("Cleanup Complete"),
                message: Text(cleanResultSummary ?? ""),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func categoryHeader(category: ScanCategory) -> some View {
        let items = appState.scannedItems.filter { $0.category == category }
        let totalCategoryBytes = items.reduce(0) { $0 + $1.fileSize }
        return HStack {
            Label(category.displayName, systemImage: category.systemImage)
                .font(.headline)
            Spacer()
            Text("\(items.count) items • \(ByteCountFormatter.string(fromByteCount: totalCategoryBytes, countStyle: .file))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func groupedCategories() -> [ScanCategory] {
        let activeCategories = Set(appState.scannedItems.map(\.category))
        return ScanCategory.allCases.filter { activeCategories.contains($0) }
    }

    private func indicesForCategory(_ category: ScanCategory) -> [Int] {
        appState.scannedItems.indices.filter { appState.scannedItems[$0].category == category }
    }

    private func startScan() {
        guard !appState.isScanning else { return }
        appState.isScanning = true
        appState.scannedItems = []
        scanStatusText = "Initializing storage scan..."

        Task {
            let managedFolders = await FileAccessService.shared.getManagedFolderURLs()
            let stream = await StorageScanner.shared.scan(folders: managedFolders, includeDeveloperCaches: true)

            for await event in stream {
                switch event {
                case .progress(let scanned, _, let currentPath):
                    await MainActor.run {
                        self.scanStatusText = "Scanning (\(scanned) items): \(currentPath)"
                    }
                case .itemDiscovered(let item):
                    await MainActor.run {
                        self.appState.scannedItems.append(item)
                    }
                case .completed(_, let totalBytes):
                    await MainActor.run {
                        self.appState.isScanning = false
                        self.scanStatusText = ""
                        self.recalculateStorageSummary(reclaimableBytes: Int64(totalBytes))
                    }
                case .cancelled:
                    await MainActor.run {
                        self.appState.isScanning = false
                        self.scanStatusText = "Scan cancelled."
                    }
                }
            }
        }
    }

    private func selectRecommended() {
        for index in appState.scannedItems.indices {
            if appState.scannedItems[index].riskLabel == .safe {
                appState.scannedItems[index].setSelected(true)
            } else {
                appState.scannedItems[index].setSelected(false)
            }
        }
    }

    private func deselectAll() {
        for index in appState.scannedItems.indices {
            appState.scannedItems[index].setSelected(false)
        }
    }

    private func cleanSelected() {
        guard !selectedItems.isEmpty else { return }
        isCleaning = true

        Task {
            let toClean = selectedItems
            var trashedBytes: Int64 = 0
            var trashedCount = 0

            for item in toClean {
                do {
                    _ = try await TrashMover.shared.moveToTrash(at: item.url)
                    trashedBytes += item.fileSize
                    trashedCount += 1
                } catch {
                    print("Failed to trash \(item.url.path): \(error)")
                }
            }

            await MainActor.run {
                // Remove successfully cleaned items from scanned list
                let cleanedIDs = Set(toClean.map(\.id))
                self.appState.scannedItems.removeAll { cleanedIDs.contains($0.id) }
                self.appState.storageSummary = StorageSummary(
                    totalDiskBytes: self.appState.storageSummary.totalDiskBytes,
                    freeDiskBytes: self.appState.storageSummary.freeDiskBytes + trashedBytes,
                    usedDiskBytes: max(0, self.appState.storageSummary.usedDiskBytes - trashedBytes),
                    reclaimableBytes: max(0, self.appState.storageSummary.reclaimableBytes - trashedBytes),
                    lifetimeReclaimedBytes: self.appState.storageSummary.lifetimeReclaimedBytes + trashedBytes
                )
                self.isCleaning = false
                self.cleanResultSummary = "Successfully moved \(trashedCount) items to the Trash, reclaiming \(ByteCountFormatter.string(fromByteCount: trashedBytes, countStyle: .file))."
            }
        }
    }

    private func recalculateStorageSummary(reclaimableBytes: Int64) {
        var breakdown: [ScanCategory: Int64] = [:]
        for item in appState.scannedItems {
            breakdown[item.category, default: 0] += item.fileSize
        }

        // Query system disk values
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let values = try? home.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        let total = Int64(values?.volumeTotalCapacity ?? 1_000_000_000_000)
        let free = Int64(values?.volumeAvailableCapacityForImportantUsage ?? 200_000_000_000)
        let used = max(0, total - free)

        appState.storageSummary = StorageSummary(
            totalDiskBytes: total,
            freeDiskBytes: free,
            usedDiskBytes: used,
            reclaimableBytes: reclaimableBytes,
            lifetimeReclaimedBytes: appState.storageSummary.lifetimeReclaimedBytes,
            categoryBreakdown: breakdown
        )
    }
}
