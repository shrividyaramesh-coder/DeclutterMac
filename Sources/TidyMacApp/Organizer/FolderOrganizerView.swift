import SwiftUI
import TidyMacCore

public struct FolderOrganizerView: View {
    @ObservedObject private var localization = LocalizationManager.shared
    
    @State private var selectedFolder: URL? = nil
    @State private var availableFolders: [URL] = []
    @State private var isAnalyzing: Bool = false
    @State private var categoryGroups: [OrganizationCategoryGroup] = []
    @State private var executionSummary: PlanExecutionSummary? = nil
    @State private var errorMessage: String? = nil
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            headerView
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    folderSelectionSection
                    
                    if isAnalyzing {
                        analyzingIndicator
                    }
                    
                    if let error = errorMessage {
                        errorBanner(error)
                    }
                    
                    if !categoryGroups.isEmpty {
                        proposalsSection
                    }
                    
                    if let summary = executionSummary {
                        successBanner(summary)
                    }
                }
                .padding(24)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .task {
            let folders = await FileAccessService.shared.getManagedFolderURLs()
            availableFolders = folders
            if selectedFolder == nil {
                selectedFolder = folders.first(where: { $0.lastPathComponent == "Downloads" }) ?? folders.first
            }
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
                Text("Smart folder structuring with collision-safe moves and full undo.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Select folder to organize:")
                .font(.headline)
            
            HStack(spacing: 12) {
                Picker("", selection: $selectedFolder) {
                    ForEach(availableFolders, id: \.self) { folder in
                        Text(folder.lastPathComponent).tag(Optional(folder))
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 200)
                
                Button(action: analyzeSelectedFolder) {
                    HStack(spacing: 6) {
                        Image(systemName: "wand.and.stars")
                        Text("Analyze & Propose Structure")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedFolder == nil || isAnalyzing)
            }
        }
    }
    
    private var analyzingIndicator: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("Analyzing files and generating taxonomy...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
    
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.red)
            Spacer()
        }
        .padding(12)
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }
    
    private var proposalsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Proposed Folder Structure (\(totalMovesCount) files)")
                    .font(.headline)
                Spacer()
                Text("Selected: \(ByteCountFormatter.string(fromByteCount: totalSelectedSize, countStyle: .file))")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.accentColor)
            }
            
            ForEach(categoryGroups.indices, id: \.self) { index in
                categoryGroupCard(index: index)
            }
            
            // Bottom Action Bar
            HStack(spacing: 12) {
                Button(action: {
                    categoryGroups = []
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
                        Text("Apply Organization Moves")
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(totalSelectedSize == 0)
            }
            .padding(.top, 12)
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private func categoryGroupCard(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .foregroundColor(.accentColor)
                
                // Editable Category Name
                TextField("Category Name", text: Binding(
                    get: { categoryGroups[index].name },
                    set: { newName in
                        guard let folder = selectedFolder else { return }
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
                
                Text("\(categoryGroups[index].moves.count) files • \(categoryGroups[index].formattedTotalSize)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            VStack(spacing: 6) {
                ForEach(categoryGroups[index].moves.indices, id: \.self) { moveIndex in
                    moveRow(groupIndex: index, moveIndex: moveIndex)
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
            
            VStack(alignment: .leading, spacing: 2) {
                Text(move.originalURL.lastPathComponent)
                    .font(.body)
                    .fontWeight(.medium)
                Text("→ \(move.targetURL.path)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
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
                Text("\(summary.itemsProcessed) files relocated into organized subfolders • Reversible via History")
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
    
    private var totalMovesCount: Int {
        categoryGroups.reduce(0) { $0 + $1.moves.count }
    }
    
    private var totalSelectedSize: Int64 {
        categoryGroups.reduce(0) { $0 + $1.totalSize }
    }
    
    // MARK: - Actions
    
    private func analyzeSelectedFolder() {
        guard let folder = selectedFolder else { return }
        isAnalyzing = true
        errorMessage = nil
        executionSummary = nil
        
        Task {
            let groups = await FolderOrganizerEngine.shared.analyzeFolder(targetFolder: folder)
            await MainActor.run {
                self.categoryGroups = groups
                self.isAnalyzing = false
                if groups.isEmpty {
                    self.errorMessage = "No loose files found in '\(folder.lastPathComponent)' to organize."
                }
            }
        }
    }
    
    private func applyOrganization() {
        guard !categoryGroups.isEmpty, let folder = selectedFolder else { return }
        
        Task {
            do {
                let summary = try await FolderOrganizerEngine.shared.applyMoves(
                    groups: categoryGroups,
                    journal: UndoJournal.shared,
                    allowedRoots: [folder]
                )
                
                await MainActor.run {
                    self.executionSummary = summary
                    self.categoryGroups = []
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
