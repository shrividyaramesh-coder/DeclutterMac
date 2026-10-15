import SwiftUI
import TidyMacCore
import AppKit

public enum SubfolderOption: Hashable {
    case deepScan
    case topLevelOnly
    case specific(URL)
}

public struct FolderOrganizerView: View {
    @ObservedObject private var localization = LocalizationManager.shared
    
    @State private var selectedFolder: URL? = nil
    @State private var availableFolders: [URL] = []
    @State private var discoveredSubfolders: [URL] = []
    @State private var selectedSubfolderOption: SubfolderOption = .deepScan
    @State private var strategy: OrganizationStrategy = .byCategory
    
    @State private var isAnalyzing: Bool = false
    @State private var categoryGroups: [OrganizationCategoryGroup] = []
    @State private var selectedCategoryFilter: String? = nil
    @State private var executionSummary: PlanExecutionSummary? = nil
    @State private var errorMessage: String? = nil
    @State private var collapsedGroupIndices: Set<Int> = []
    
    @State private var folderSortsUsed: Int = 0
    @State private var isLifetimeUnlocked: Bool = false
    @State private var showPaywallSheet: Bool = false
    @State private var paywallKeyInput: String = ""
    @State private var paywallMessage: String? = nil
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            headerView
            
            Divider()
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    folderSelectionSection
                    
                    if isAnalyzing {
                        analyzingIndicator
                    }
                    
                    if let error = errorMessage {
                        errorBanner(error)
                    }
                    
                    if !categoryGroups.isEmpty {
                        proposalsSection
                    } else if !isAnalyzing && errorMessage == nil && executionSummary == nil {
                        emptyStateGuide
                    }
                    
                    if let summary = executionSummary {
                        successBanner(summary)
                    }
                }
                .padding(24)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showPaywallSheet) {
            paywallSheetView
        }
        .task {
            await refreshLicenseAndSorts()
            let folders = await FileAccessService.shared.getManagedFolderURLs()
            availableFolders = folders
            if selectedFolder == nil {
                selectedFolder = folders.first(where: { $0.lastPathComponent == "Downloads" }) ?? folders.first
            }
            if let root = selectedFolder {
                await loadSubfolders(for: root)
            }
            if categoryGroups.isEmpty && selectedFolder != nil {
                analyzeActiveFolder()
            }
        }
        .onChange(of: selectedFolder) { _, newFolder in
            if let folder = newFolder {
                Task {
                    await loadSubfolders(for: folder)
                    selectedSubfolderOption = .deepScan
                    analyzeActiveFolder()
                }
            }
        }
        .onChange(of: selectedSubfolderOption) { _, _ in
            analyzeActiveFolder()
        }
        .onChange(of: strategy) { _, _ in
            analyzeActiveFolder()
        }
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                    Text(localized("nav.organize"))
                        .font(.title2)
                        .fontWeight(.bold)
                }
                Text("Smart folder structuring with collision-safe moves, subfolder navigation, and full undo.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isLifetimeUnlocked {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                    Text("Lifetime Unlocked")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.12))
                .cornerRadius(8)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "folder.badge.plus")
                        .foregroundColor(.accentColor)
                    let remaining = max(0, 2 - folderSortsUsed)
                    Text("Free: \(remaining) of 2 sorts left")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.12))
                .cornerRadius(8)
            }
            
            HStack(spacing: 6) {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .foregroundColor(.accentColor)
                Text("100% Reversible via Undo")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.12))
            .cornerRadius(8)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
    
    private var folderSelectionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Row 1: Target Folder, Subfolder Drill-down, and Custom Browser
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Folder:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $selectedFolder) {
                        ForEach(availableFolders, id: \.self) { folder in
                            Text(folder.lastPathComponent).tag(Optional(folder))
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 160)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scope / Subfolder:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $selectedSubfolderOption) {
                        Text("All Subfolders (Deep Scan)").tag(SubfolderOption.deepScan)
                        Text("Root Only (Direct Files)").tag(SubfolderOption.topLevelOnly)
                        
                        if !discoveredSubfolders.isEmpty {
                            Divider()
                            ForEach(discoveredSubfolders, id: \.self) { sf in
                                let rel = relativeSubfolderPath(for: sf)
                                Text("📂 \(rel)").tag(SubfolderOption.specific(sf))
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 250)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(" ").font(.caption)
                    Button(action: pickCustomFolder) {
                        HStack(spacing: 4) {
                            Image(systemName: "folder.badge.plus")
                            Text("Browse...")
                        }
                    }
                    .buttonStyle(.bordered)
                    .help("Choose any custom folder or subfolder on your Mac")
                }
                
                if let activeURL = activeTargetFolder {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(" ").font(.caption)
                        Button(action: {
                            NSWorkspace.shared.activateFileViewerSelecting([activeURL])
                        }) {
                            Image(systemName: "arrow.up.forward.app")
                        }
                        .buttonStyle(.bordered)
                        .help("Reveal selected folder in Finder")
                    }
                }
                
                Spacer()
            }
            
            // Row 2: Organization Strategy & Analyze Action
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Organization Strategy:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $strategy) {
                        ForEach(OrganizationStrategy.allCases) { strat in
                            Text(strat.rawValue).tag(strat)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 380)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(" ").font(.caption)
                    Button(action: analyzeActiveFolder) {
                        HStack(spacing: 6) {
                            Image(systemName: "wand.and.stars")
                            Text("Analyze & Propose Structure")
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(activeTargetFolder == nil || isAnalyzing)
                }
                
                Spacer()
            }
            
            // Active Target Path Display Badge
            if let activeURL = activeTargetFolder {
                HStack(spacing: 6) {
                    Image(systemName: isDirectSubfolderSelected ? "folder.fill.badge.gearshape" : "folder.fill")
                        .foregroundColor(.accentColor)
                        .font(.caption)
                    Text("Target Path: \(activeURL.path)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    if isDeepScanMode {
                        Text("• Deep Scan (Includes all subfolders)")
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                .cornerRadius(6)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var analyzingIndicator: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("Analyzing files and generating smart category taxonomy...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
    
    private func errorBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.accentColor)
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                Spacer()
            }
            
            if !isDeepScanMode {
                Button(action: {
                    selectedSubfolderOption = .deepScan
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                        Text("Scan All Subfolders (Deep Scan)")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.08))
        .cornerRadius(8)
    }
    
    private var emptyStateGuide: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 40))
                .foregroundColor(.accentColor)
            Text("Ready to Organize")
                .font(.headline)
            Text("Click **Analyze & Propose Structure** above to inspect loose files and subfolders in your selected folder and preview smart category groupings.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
    }
    
    private var proposalsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Proposals Header
            HStack {
                Text("Proposed Folder Structure (\(totalMovesCount) items)")
                    .font(.headline)
                
                Spacer()
                
                Button(action: toggleAllCategories) {
                    Text(collapsedGroupIndices.isEmpty ? "Collapse All" : "Expand All")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .padding(.trailing, 8)
                
                Text("Selected: \(ByteCountFormatter.string(fromByteCount: totalSelectedSize, countStyle: .file))")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.accentColor)
            }
            
            // Category Filter Bar & Quick Select
            categoryFilterBar
            
            // Category Group Cards
            ForEach(filteredCategoryGroupIndices, id: \.self) { index in
                categoryGroupCard(index: index)
            }
            
            // Bottom Action Bar
            HStack(spacing: 12) {
                Button(action: {
                    categoryGroups = []
                    collapsedGroupIndices.removeAll()
                    selectedCategoryFilter = nil
                }) {
                    Text("Discard Proposal")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button(action: applyOrganization) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right.doc.on.clipboard")
                        Text("Apply Organization Moves (\(selectedItemsCount))")
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedItemsCount == 0)
            }
            .padding(.top, 12)
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var categoryFilterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterPill(title: "All", count: totalMovesCount, isSelected: selectedCategoryFilter == nil) {
                        selectedCategoryFilter = nil
                    }
                    
                    ForEach(categoryGroups) { group in
                        filterPill(title: group.name, count: group.moves.count, isSelected: selectedCategoryFilter == group.name) {
                            selectedCategoryFilter = group.name
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            
            HStack(spacing: 10) {
                if let filter = selectedCategoryFilter {
                    Button(action: {
                        selectOnlyCategory(named: filter)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Select Only \"\(filter)\"")
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                
                Button(action: selectAllItems) {
                    Text("Select All")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button(action: deselectAllItems) {
                    Text("Deselect All")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }
    
    private func filterPill(title: String, count: Int, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption)
                    .fontWeight(isSelected ? .bold : .medium)
                Text("\(count)")
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(isSelected ? Color.white.opacity(0.3) : Color.secondary.opacity(0.15))
                    .cornerRadius(6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentColor : Color(NSColor.windowBackgroundColor))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
    private func categoryGroupCard(index: Int) -> some View {
        let isCollapsed = collapsedGroupIndices.contains(index)
        let group = categoryGroups[index]
        let allSelectedInGroup = group.moves.allSatisfy(\.isSelected)
        
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button(action: {
                    if isCollapsed {
                        collapsedGroupIndices.remove(index)
                    } else {
                        collapsedGroupIndices.insert(index)
                    }
                }) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption.weight(.bold))
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
                
                // Group Select Toggle
                Toggle("", isOn: Binding(
                    get: { allSelectedInGroup },
                    set: { newVal in
                        for mIndex in categoryGroups[index].moves.indices {
                            categoryGroups[index].moves[mIndex].isSelected = newVal
                        }
                    }
                ))
                .labelsHidden()
                
                Image(systemName: "folder.fill")
                    .foregroundColor(.accentColor)
                
                // Editable Category Name
                TextField("Category Name", text: Binding(
                    get: { categoryGroups[index].name },
                    set: { newName in
                        guard let folder = activeTargetFolder else { return }
                        let destRoot = folder
                        Task {
                            let updated = await FolderOrganizerEngine.shared.updateCategory(
                                groupIndex: index,
                                newName: newName,
                                groups: categoryGroups,
                                destRoot: destRoot
                            )
                            await MainActor.run {
                                self.categoryGroups = updated
                            }
                        }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)
                
                Spacer()
                
                Text("\(group.moves.count) items • \(group.formattedTotalSize)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if !isCollapsed {
                Divider()
                
                LazyVStack(spacing: 6) {
                    ForEach(group.moves.indices, id: \.self) { moveIndex in
                        moveRow(groupIndex: index, moveIndex: moveIndex)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
    }
    
    private func moveRow(groupIndex: Int, moveIndex: Int) -> some View {
        let move = categoryGroups[groupIndex].moves[moveIndex]
        
        return HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { categoryGroups[groupIndex].moves[moveIndex].isSelected },
                set: { categoryGroups[groupIndex].moves[moveIndex].isSelected = $0 }
            ))
            .labelsHidden()
            
            Image(systemName: move.isDirectory ? "folder.fill" : "doc.fill")
                .foregroundColor(move.isDirectory ? .accentColor : .secondary)
                .font(.body)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(move.originalURL.lastPathComponent)
                        .font(.body)
                        .fontWeight(.medium)
                    
                    if move.isDirectory {
                        Text("Folder")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundColor(.accentColor)
                            .cornerRadius(4)
                    }
                }
                
                HStack(spacing: 4) {
                    if !move.sourceRelativePath.isEmpty && move.sourceRelativePath != move.originalURL.lastPathComponent {
                        Text("From: \(move.sourceRelativePath)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Text("→ \(move.targetURL.path)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            
            Spacer()
            
            Text(move.formattedSize)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    private func successBanner(_ summary: PlanExecutionSummary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Folder Organization Completed!")
                    .font(.headline)
                Text("\(summary.itemsProcessed) items relocated into organized subfolders • Reversible via History")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Computed Properties
    
    private var activeTargetFolder: URL? {
        guard let root = selectedFolder else { return nil }
        switch selectedSubfolderOption {
        case .deepScan, .topLevelOnly:
            return root
        case .specific(let url):
            return url
        }
    }
    
    private var isDeepScanMode: Bool {
        if case .deepScan = selectedSubfolderOption {
            return true
        }
        return false
    }
    
    private var isDirectSubfolderSelected: Bool {
        if case .specific = selectedSubfolderOption {
            return true
        }
        return false
    }
    
    private var filteredCategoryGroupIndices: [Int] {
        if let filter = selectedCategoryFilter {
            return categoryGroups.indices.filter { categoryGroups[$0].name == filter }
        }
        return Array(categoryGroups.indices)
    }
    
    private var totalMovesCount: Int {
        categoryGroups.reduce(0) { $0 + $1.moves.count }
    }
    
    private var selectedItemsCount: Int {
        categoryGroups.flatMap(\.moves).filter(\.isSelected).count
    }
    
    private var totalSelectedSize: Int64 {
        categoryGroups.reduce(0) { $0 + $1.totalSize }
    }
    
    private func relativeSubfolderPath(for url: URL) -> String {
        guard let root = selectedFolder else { return url.lastPathComponent }
        let rel = url.path.replacingOccurrences(of: root.path + "/", with: "")
        return rel.isEmpty ? url.lastPathComponent : rel
    }
    
    // MARK: - Actions
    
    private func loadSubfolders(for folder: URL) async {
        let subs = await FolderOrganizerEngine.shared.discoverSubfolders(in: folder, maxDepth: 2)
        await MainActor.run {
            self.discoveredSubfolders = subs
        }
    }
    
    private func pickCustomFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Folder to Organize"
        
        if panel.runModal() == .OK, let url = panel.url {
            let canonical = url.resolvingSymlinksInPath()
            Task {
                _ = try? await FileAccessService.shared.saveBookmark(for: canonical)
                await MainActor.run {
                    if !availableFolders.contains(canonical) {
                        availableFolders.append(canonical)
                    }
                    selectedFolder = canonical
                    selectedSubfolderOption = .deepScan
                }
                await loadSubfolders(for: canonical)
                analyzeActiveFolder()
            }
        }
    }
    
    private func analyzeActiveFolder() {
        guard let target = activeTargetFolder else { return }
        isAnalyzing = true
        errorMessage = nil
        executionSummary = nil
        selectedCategoryFilter = nil
        
        let includeSubs = isDeepScanMode
        let chosenStrategy = strategy
        
        Task {
            let groups = await FolderOrganizerEngine.shared.analyzeFolder(
                targetFolder: target,
                includeSubfolders: includeSubs,
                strategy: chosenStrategy
            )
            await MainActor.run {
                self.categoryGroups = groups
                self.isAnalyzing = false
                if groups.isEmpty {
                    if includeSubs {
                        self.errorMessage = "No files found in '\(target.lastPathComponent)' that need relocation."
                    } else {
                        self.errorMessage = "No loose files found in '\(target.lastPathComponent)' at the top level. Try switching to 'All Subfolders (Deep Scan)' or selecting a subfolder above."
                    }
                }
            }
        }
    }
    
    private func selectOnlyCategory(named categoryName: String) {
        for gIndex in categoryGroups.indices {
            let isTarget = categoryGroups[gIndex].name == categoryName
            for mIndex in categoryGroups[gIndex].moves.indices {
                categoryGroups[gIndex].moves[mIndex].isSelected = isTarget
            }
        }
    }
    
    private func selectAllItems() {
        for gIndex in categoryGroups.indices {
            for mIndex in categoryGroups[gIndex].moves.indices {
                categoryGroups[gIndex].moves[mIndex].isSelected = true
            }
        }
    }
    
    private func deselectAllItems() {
        for gIndex in categoryGroups.indices {
            for mIndex in categoryGroups[gIndex].moves.indices {
                categoryGroups[gIndex].moves[mIndex].isSelected = false
            }
        }
    }
    
    private func applyOrganization() {
        guard !categoryGroups.isEmpty, let target = activeTargetFolder, let root = selectedFolder else { return }
        
        Task {
            let canSort = await LocalLicenseProvider.shared.canSortFolder()
            if !canSort {
                await MainActor.run {
                    self.showPaywallSheet = true
                }
                return
            }
            
            do {
                let summary = try await FolderOrganizerEngine.shared.applyMoves(
                    groups: categoryGroups,
                    journal: UndoJournal.shared,
                    allowedRoots: [root, target]
                )
                
                await LocalLicenseProvider.shared.recordFolderSort()
                await refreshLicenseAndSorts()
                
                await MainActor.run {
                    self.executionSummary = summary
                    self.categoryGroups = []
                    self.selectedCategoryFilter = nil
                }
                
                // Refresh subfolders list
                await loadSubfolders(for: root)
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func refreshLicenseAndSorts() async {
        let sorts = await LocalLicenseProvider.shared.folderSortsCount()
        let status = await LocalLicenseProvider.shared.currentStatus()
        let unlocked: Bool
        if case .unlocked = status {
            unlocked = true
        } else {
            unlocked = false
        }
        await MainActor.run {
            self.folderSortsUsed = sorts
            self.isLifetimeUnlocked = unlocked
        }
    }
    
    private var paywallSheetView: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            
            VStack(spacing: 6) {
                Text("Free Folder Sorts Used")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("You have organized your 2 free folders! Unlock lifetime unlimited folder sorting and Mac cleaning for just $7.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
            
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tidy Mac Lifetime License")
                            .font(.body)
                            .fontWeight(.semibold)
                        Text("Unlimited folder sorting & cleaning on all your Macs")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("$7.00")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.accentColor)
                }
                .padding(14)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                
                HStack(spacing: 8) {
                    TextField("Enter $7 Lifetime License Key", text: $paywallKeyInput)
                        .textFieldStyle(.roundedBorder)
                    
                    Button("Unlock") {
                        Task {
                            let success = await LocalLicenseProvider.shared.unlockLifetime(key: paywallKeyInput)
                            if success {
                                await refreshLicenseAndSorts()
                                await MainActor.run {
                                    self.showPaywallSheet = false
                                }
                            } else {
                                await MainActor.run {
                                    self.paywallMessage = "Invalid license key format."
                                }
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(paywallKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                
                if let msg = paywallMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                
                Button(action: {
                    if let url = URL(string: "http://localhost:8000") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "cart.fill")
                        Text("Purchase $7 Lifetime License Online")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                }
                .buttonStyle(.bordered)
            }
            
            Button("Close") {
                showPaywallSheet = false
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .font(.caption)
        }
        .padding(32)
        .frame(width: 460)
    }
    
    private func toggleAllCategories() {
        if collapsedGroupIndices.isEmpty {
            collapsedGroupIndices = Set(categoryGroups.indices)
        } else {
            collapsedGroupIndices.removeAll()
        }
    }
}
