import SwiftUI
import TidyMacCore

public struct AgentChatView: View {
    @ObservedObject private var localization = LocalizationManager.shared
    
    @State private var inputText: String = ""
    @State private var selectedProvider: AIProvider = .heuristic
    @State private var isAnalyzing: Bool = false
    @State private var generatedPlan: CleaningPlan? = nil
    @State private var matchResults: [PlanMatchResult] = []
    @State private var executionSummary: PlanExecutionSummary? = nil
    @State private var errorMessage: String? = nil
    
    private let promptSuggestions = [
        "Delete screenshots older than a month",
        "Trash installers and disk images older than 7 days",
        "Find large files over 500 MB",
        "Clear safe user caches and logs",
        "Organize my Downloads folder"
    ]
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header with Privacy Notice
            headerView
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Chat / Goal Input Section
                    inputSection
                    
                    // Quick Prompts Suggestions
                    suggestionsSection
                    
                    // Status / Loading Indicator
                    if isAnalyzing {
                        analyzingIndicator
                    }
                    
                    // Error Message
                    if let error = errorMessage {
                        errorBanner(error)
                    }
                    
                    // Plan Preview & Dry-Run Section
                    if let plan = generatedPlan {
                        planDetailsSection(plan)
                        dryRunResultsSection
                    }
                    
                    // Post-Execution Summary
                    if let summary = executionSummary {
                        executionSummarySection(summary)
                    }
                }
                .padding(24)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                    Text("AI Agent Planner")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                Text("AI-assisted storage optimization with strict dry-run confirmation.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Privacy Badge
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(.green)
                Text("Metadata-Only AI Boundary")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.green.opacity(0.12))
            .cornerRadius(8)
            
            // Provider Picker
            Picker("", selection: $selectedProvider) {
                ForEach(AIProvider.allCases, id: \.self) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 200)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
    
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tell Tidy Mac what you want to clean or organize:")
                .font(.headline)
            
            HStack(spacing: 12) {
                TextField("e.g. 'delete screenshots older than a month', 'clean downloads'", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                    .onSubmit {
                        submitPrompt()
                    }
                
                Button(action: submitPrompt) {
                    HStack(spacing: 6) {
                        Image(systemName: "wand.and.stars")
                        Text("Create Plan")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isAnalyzing)
            }
        }
    }
    
    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick suggestions:")
                .font(.caption)
                .foregroundColor(.secondary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(promptSuggestions, id: \.self) { prompt in
                        Button(action: {
                            inputText = prompt
                            submitPrompt()
                        }) {
                            Text(prompt)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    private var analyzingIndicator: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("Analyzing files and generating structured plan...")
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
    
    private func planDetailsSection(_ plan: CleaningPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checklist")
                    .foregroundColor(.accentColor)
                Text("Proposed Cleanup Plan (Dry Run)")
                    .font(.headline)
                Spacer()
                Text("Dry-Run Only — No files modified")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.15))
                    .foregroundColor(.orange)
                    .cornerRadius(6)
            }
            
            Text(plan.summary)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            ForEach(plan.steps) { step in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundColor(.accentColor)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.explanation)
                            .font(.body)
                            .fontWeight(.medium)
                        Text("Target: \(step.targetFolder) • Action: \(step.action.rawValue.capitalized)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(6)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var dryRunResultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Candidate Matches (\(matchResults.count))")
                    .font(.headline)
                Spacer()
                let totalSelectedSize = matchResults.filter(\.isSelected).reduce(0) { $0 + $1.item.fileSize }
                Text("Selected: \(ByteCountFormatter.string(fromByteCount: totalSelectedSize, countStyle: .file))")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.accentColor)
            }
            
            if matchResults.isEmpty {
                Text("No candidate files matched this plan in the scanned folders.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 8) {
                    ForEach($matchResults) { $result in
                        matchRow(result: $result)
                    }
                }
                
                // Action Buttons
                HStack(spacing: 12) {
                    Button(action: {
                        generatedPlan = nil
                        matchResults = []
                    }) {
                        Text("Cancel Plan")
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button(action: executePlan) {
                        HStack(spacing: 6) {
                            Image(systemName: isMovePlan ? "folder.badge.gearshape" : "trash.fill")
                            Text(isMovePlan ? "Confirm & Organize Files" : "Confirm & Move to Trash")
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(matchResults.filter(\.isSelected).isEmpty)
                }
                .padding(.top, 12)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private func matchRow(result: Binding<PlanMatchResult>) -> some View {
        HStack(spacing: 12) {
            Toggle("", isOn: result.isSelected)
                .labelsHidden()
                .disabled(!result.wrappedValue.canExecute)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(result.wrappedValue.item.url.lastPathComponent)
                    .font(.body)
                    .fontWeight(.medium)
                Text(result.wrappedValue.item.url.path)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer()
            
            Text(ByteCountFormatter.string(fromByteCount: result.wrappedValue.item.fileSize, countStyle: .file))
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Risk / Action Badge
            if isMovePlan {
                Text("Organize")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundColor(.accentColor)
                    .cornerRadius(4)
            } else {
                Text(result.wrappedValue.item.riskLabel.title)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(riskBadgeColor(result.wrappedValue.item.riskLabel).opacity(0.15))
                    .foregroundColor(riskBadgeColor(result.wrappedValue.item.riskLabel))
                    .cornerRadius(4)
            }
        }
        .padding(8)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(6)
    }
    
    private var isMovePlan: Bool {
        generatedPlan?.steps.contains { $0.action == .move } ?? false
    }
    
    private func executionSummarySection(_ summary: PlanExecutionSummary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(isMovePlan ? "Files Organized Successfully!" : "Plan Executed Successfully!")
                    .font(.headline)
                Text("\(summary.itemsProcessed) items \(isMovePlan ? "organized into categorized folders" : "moved to Trash") • \(ByteCountFormatter.string(fromByteCount: summary.bytesReclaimed, countStyle: .file)) processed")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
    }
    
    private func riskBadgeColor(_ risk: RiskLabel) -> Color {
        switch risk {
        case .safe: return .green
        case .review: return .orange
        case .manual: return .red
        }
    }
    
    // MARK: - Actions
    
    private func submitPrompt() {
        guard !inputText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isAnalyzing = true
        errorMessage = nil
        executionSummary = nil
        
        Task {
            let prompt = inputText
            let plan = await AgentCoordinator.shared.requestPlan(
                prompt: prompt,
                provider: selectedProvider,
                sampleFiles: []
            )
            
            // Sample test candidates from managed folders or targeted plan folders
            let defaultFolders = await FileAccessService.shared.getManagedFolderURLs()
            let planTargetURLs = plan.steps.map { URL(fileURLWithPath: $0.targetFolder) }
            let foldersToScan = planTargetURLs.isEmpty ? defaultFolders : planTargetURLs
            
            var candidateItems: [FileItem] = []
            for folder in foldersToScan {
                if let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                    var count = 0
                    while let fileURL = enumerator.nextObject() as? URL {
                        count += 1
                        if count > 500 { break }
                        let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                        let size = Int64(values?.fileSize ?? 0)
                        let modDate = values?.contentModificationDate ?? Date()
                        let category = CategoryClassifier.classify(url: fileURL, fileSize: size, createdDate: modDate)
                        let risk = RiskEvaluator.evaluateRisk(category: category, url: fileURL, fileSize: size, createdDate: modDate)
                        
                        candidateItems.append(FileItem(
                            url: fileURL,
                            fileSize: size,
                            lastModifiedDate: modDate,
                            category: category,
                            riskLabel: risk
                        ))
                    }
                }
            }
            
            let matches = await PlanExecutor.shared.dryRun(plan: plan, candidates: candidateItems)
            
            await MainActor.run {
                self.generatedPlan = plan
                self.matchResults = matches
                self.isAnalyzing = false
            }
        }
    }
    
    private func executePlan() {
        guard !matchResults.isEmpty else { return }
        
        Task {
            do {
                let allowedRoots = await FileAccessService.shared.getManagedFolderURLs()
                let summary = try await PlanExecutor.shared.execute(
                    matches: matchResults,
                    journal: UndoJournal.shared,
                    allowedRoots: allowedRoots
                )
                
                await MainActor.run {
                    self.executionSummary = summary
                    self.generatedPlan = nil
                    self.matchResults = []
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
