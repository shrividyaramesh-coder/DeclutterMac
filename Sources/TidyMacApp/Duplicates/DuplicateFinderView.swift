import SwiftUI
import AppKit
import TidyMacCore

public struct DuplicateFinderView: View {
    @State private var duplicateGroups: [DuplicateGroup] = []
    @State private var isScanning: Bool = false
    @State private var selectedStrategy: DuplicateKeepStrategy = .keepOldest
    @State private var isCleaning: Bool = false
    @State private var cleanAlertMessage: String? = nil

    public init() {}

    private var totalWastedBytes: Int64 {
        duplicateGroups.reduce(0) { $0 + $1.selectedWastedBytes }
    }

    private var totalSelectedDuplicatesCount: Int {
        duplicateGroups.reduce(0) { $0 + $1.items.filter(\.isSelected).count }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Action & Strategy Bar
            HStack(spacing: 16) {
                Button(action: scanDuplicates) {
                    Label(isScanning ? localized("action.scanning") : "Scan Duplicates", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isScanning || isCleaning)

                Picker("Rule:", selection: $selectedStrategy) {
                    ForEach(DuplicateKeepStrategy.allCases) { strategy in
                        Text(strategy.rawValue).tag(strategy)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 200)
                .onChange(of: selectedStrategy) { _, newStrategy in
                    reapplyStrategy(newStrategy)
                }

                Spacer()

                Button(action: cleanDuplicates) {
                    Label(isCleaning ? localized("action.cleaning") : "Clean Duplicates (\(ByteCountFormatter.string(fromByteCount: totalWastedBytes, countStyle: .file)))", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(totalSelectedDuplicatesCount == 0 || isScanning || isCleaning)
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if isScanning {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Scanning files for duplicates (Size grouping -> Partial hash -> Full SHA-256)...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else if duplicateGroups.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "doc.on.doc.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No Duplicates Discovered")
                        .font(.title2)
                        .bold()
                    Text("Click 'Scan Duplicates' to discover identical files across your managed folders.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    ForEach(duplicateGroups.indices, id: \.self) { groupIndex in
                        groupCard(groupIndex: groupIndex)
                    }
                }
                .listStyle(.inset)
            }
        }
        .alert(isPresented: Binding(get: { cleanAlertMessage != nil }, set: { if !$0 { cleanAlertMessage = nil } })) {
            Alert(
                title: Text("Duplicate Cleanup"),
                message: Text(cleanAlertMessage ?? ""),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func groupCard(groupIndex: Int) -> some View {
        let group = duplicateGroups[groupIndex]
        return Section(header:
            HStack {
                Text("\(group.items.count) Identical Files • \(ByteCountFormatter.string(fromByteCount: group.fileSize, countStyle: .file)) each")
                    .font(.headline)
                Spacer()
                Text("Reclaimable: \(ByteCountFormatter.string(fromByteCount: group.selectedWastedBytes, countStyle: .file))")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        ) {
            ForEach(group.items.indices, id: \.self) { itemIndex in
                let item = group.items[itemIndex]
                HStack(spacing: 12) {
                    // Checkbox with keep-one invariant
                    Toggle("", isOn: Binding(
                        get: { item.isSelected },
                        set: { newValue in
                            duplicateGroups[groupIndex].setSelection(for: item.id, isSelected: newValue)
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .labelsHidden()

                    // Kept vs Trashed Indicator
                    if !item.isSelected {
                        Text("ORIGINAL")
                            .font(.caption2)
                            .bold()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                    } else {
                        Text("DUPLICATE")
                            .font(.caption2)
                            .bold()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.15))
                            .foregroundStyle(.red)
                            .clipShape(Capsule())
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.url.lastPathComponent)
                            .font(.body)
                            .lineLimit(1)
                        Text(item.url.path)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Reveal in Finder
                    Button(action: {
                        NSWorkspace.shared.activateFileViewerSelecting([item.url])
                    }) {
                        Image(systemName: "magnifyingglass")
                    }
                    .buttonStyle(.plain)
                    .help("Reveal in Finder")
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func scanDuplicates() {
        guard !isScanning else { return }
        isScanning = true
        duplicateGroups = []

        Task {
            let folders = await FileAccessService.shared.getManagedFolderURLs().filter {
                !$0.path.contains("Library/Caches") && !$0.path.contains("Library/Developer")
            }
            let results = await DuplicateFinderEngine.shared.findDuplicates(folders: folders, strategy: selectedStrategy)
            await MainActor.run {
                self.duplicateGroups = results
                self.isScanning = false
            }
        }
    }

    private func reapplyStrategy(_ strategy: DuplicateKeepStrategy) {
        for groupIndex in duplicateGroups.indices {
            var items = duplicateGroups[groupIndex].items
            guard items.count > 1 else { continue }

            let keepIndex: Int
            switch strategy {
            case .keepOldest:
                keepIndex = items.indices.min(by: { items[$0].createdDate < items[$1].createdDate }) ?? 0
            case .keepShortestPath:
                keepIndex = items.indices.min(by: { items[$0].url.path.count < items[$1].url.path.count }) ?? 0
            }

            for i in items.indices {
                items[i].setSelected(i != keepIndex)
            }
            duplicateGroups[groupIndex].items = items
            duplicateGroups[groupIndex].enforceKeepOneInvariant()
        }
    }

    private func cleanDuplicates() {
        guard totalSelectedDuplicatesCount > 0 else { return }
        isCleaning = true

        Task {
            let runId = UUID()
            var trashedCount = 0
            var trashedBytes: Int64 = 0

            for group in duplicateGroups {
                // Safety assert: verify at least one copy is unselected
                guard group.items.filter(\.isSelected).count < group.items.count else {
                    continue
                }

                for item in group.items where item.isSelected {
                    do {
                        let trashedURL = try await TrashMover.shared.moveToTrash(at: item.url)
                        trashedBytes += item.fileSize
                        trashedCount += 1

                        let entry = JournalEntry(
                            runId: runId,
                            originalURL: item.url,
                            trashedURL: trashedURL,
                            fileSize: item.fileSize,
                            action: .trashed
                        )
                        await UndoJournal.shared.record(entry: entry)
                    } catch {
                        print("Failed to trash duplicate \(item.url.path): \(error)")
                    }
                }
            }

            await MainActor.run {
                self.isCleaning = false
                self.cleanAlertMessage = "Cleaned \(trashedCount) duplicate files, freeing \(ByteCountFormatter.string(fromByteCount: trashedBytes, countStyle: .file))."
                // Re-scan duplicates to refresh view
                self.scanDuplicates()
            }
        }
    }
}
