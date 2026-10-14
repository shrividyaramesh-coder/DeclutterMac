import SwiftUI
import TidyMacCore

public struct RulesManagementView: View {
    @ObservedObject private var localization = LocalizationManager.shared
    
    @State private var rules: [CleanupRule] = []
    @State private var scheduleSettings = ScheduleSettings()
    @State private var isRunningRule: Bool = false
    @State private var executionSummary: PlanExecutionSummary? = nil
    @State private var errorMessage: String? = nil
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            headerView
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    scheduleSection
                    
                    if let summary = executionSummary {
                        executionBanner(summary)
                    }
                    
                    if let error = errorMessage {
                        errorBanner(error)
                    }
                    
                    rulesListSection
                }
                .padding(24)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .task {
            await loadData()
        }
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "checklist.checked")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                    Text(localization.localized(.navRules))
                        .font(.title2)
                        .fontWeight(.bold)
                }
                Text("Automate recurring cleanups with approved rule templates and continuous schedules.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: resetToDefaults) {
                Text("Reset Defaults")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
    
    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(.accentColor)
                    .font(.headline)
                Text("Continuous Cleanup Schedule (Set & Forget)")
                    .font(.headline)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { scheduleSettings.isEnabled },
                    set: { enabled in
                        scheduleSettings.isEnabled = enabled
                        Task { await ScheduleCoordinator.shared.updateSettings(scheduleSettings) }
                    }
                ))
                .labelsHidden()
            }
            
            Text("Runs quietly in the background when conditions are met, only executing rules you've approved.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if scheduleSettings.isEnabled {
                HStack(spacing: 16) {
                    Text("Frequency:")
                        .font(.body)
                        .fontWeight(.medium)
                    
                    Picker("", selection: Binding(
                        get: { scheduleSettings.frequency },
                        set: { freq in
                            scheduleSettings.frequency = freq
                            Task { await ScheduleCoordinator.shared.updateSettings(scheduleSettings) }
                        }
                    )) {
                        Text("Daily").tag(ScheduleFrequency.daily)
                        Text("Weekly").tag(ScheduleFrequency.weekly)
                        Text("Monthly").tag(ScheduleFrequency.monthly)
                        Text("When Free Space < 15 GB").tag(ScheduleFrequency.onLowDiskSpace(thresholdGB: 15))
                    }
                    .pickerStyle(.menu)
                    .frame(width: 220)
                    
                    Spacer()
                    
                    if let lastRun = scheduleSettings.lastRunDate {
                        Text("Last run: \(DateFormatter.localizedString(from: lastRun, dateStyle: .short, timeStyle: .short))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Never run")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var rulesListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Cleanup Rules (\(rules.filter(\.isEnabled).count) active of \(rules.count))")
                    .font(.headline)
                Spacer()
            }
            
            VStack(spacing: 10) {
                ForEach(rules) { rule in
                    ruleCard(rule: rule)
                }
            }
        }
    }
    
    private func ruleCard(rule: CleanupRule) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { enabled in
                    Task {
                        await RuleEngine.shared.toggleRule(id: rule.id, isEnabled: enabled)
                        await loadData()
                    }
                }
            ))
            .labelsHidden()
            .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(rule.name)
                        .font(.body)
                        .fontWeight(.semibold)
                    
                    if rule.isBuiltIn {
                        Text("Template")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(4)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        runSingleRule(rule)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                            Text("Run Now")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRunningRule)
                }
                
                Text(rule.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Badges
                HStack(spacing: 6) {
                    if let folder = rule.trigger.folderPath {
                        badge(text: folder, icon: "folder")
                    }
                    if let age = rule.trigger.minimumAgeDays {
                        badge(text: "> \(age) days", icon: "calendar")
                    }
                    if let exts = rule.trigger.fileExtensions {
                        badge(text: exts.joined(separator: ", "), icon: "doc")
                    }
                    if let size = rule.trigger.minimumSizeBytes {
                        badge(text: "> \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))", icon: "scalemass")
                    }
                    
                    Spacer()
                    
                    actionBadge(action: rule.action)
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
    
    private func badge(text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption2)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(6)
    }
    
    private func actionBadge(action: RuleAction) -> some View {
        HStack(spacing: 4) {
            switch action {
            case .moveToTrash:
                Image(systemName: "trash")
                Text("Trash")
            case .moveToFolder(let dest):
                Image(systemName: "arrow.right.circle")
                Text("Move to \(dest)")
            case .reviewOnly:
                Image(systemName: "eye")
                Text("Review")
            }
        }
        .font(.caption2)
        .fontWeight(.medium)
        .foregroundColor(.accentColor)
    }
    
    private func executionBanner(_ summary: PlanExecutionSummary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Rule Execution Complete!")
                    .font(.headline)
                Text("Processed \(summary.itemsProcessed) files • Reclaimed \(ByteCountFormatter.string(fromByteCount: summary.bytesReclaimed, countStyle: .file)) • Recorded in History for Undo")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
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
    
    // MARK: - Actions
    
    private func loadData() async {
        let loadedRules = await RuleEngine.shared.getRules()
        let settings = await ScheduleCoordinator.shared.getSettings()
        await MainActor.run {
            self.rules = loadedRules
            self.scheduleSettings = settings
        }
    }
    
    private func resetToDefaults() {
        Task {
            await RuleEngine.shared.resetToDefaults()
            await loadData()
        }
    }
    
    private func runSingleRule(_ rule: CleanupRule) {
        isRunningRule = true
        errorMessage = nil
        executionSummary = nil
        
        Task {
            do {
                let folders = await FileAccessService.shared.getManagedFolderURLs()
                var candidates: [FileItem] = []
                for folder in folders {
                    if let enumerator = FileManager.default.enumerator(
                        at: folder,
                        includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                        options: [.skipsHiddenFiles, .skipsPackageDescendants]
                    ) {
                        while let fileURL = enumerator.nextObject() as? URL {
                            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                            let size = Int64(values?.fileSize ?? 0)
                            let modDate = values?.contentModificationDate ?? Date()
                            let category = CategoryClassifier.classify(url: fileURL, fileSize: size, createdDate: modDate)
                            let risk = RiskEvaluator.evaluateRisk(category: category, url: fileURL, fileSize: size, createdDate: modDate)
                            
                            candidates.append(FileItem(
                                url: fileURL,
                                fileSize: size,
                                lastModifiedDate: modDate,
                                category: category,
                                riskLabel: risk
                            ))
                        }
                    }
                }
                
                let summary = try await RuleEngine.shared.executeRules(
                    rulesToRun: [rule],
                    candidates: candidates,
                    allowedRoots: folders
                )
                
                await MainActor.run {
                    self.executionSummary = summary
                    self.isRunningRule = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isRunningRule = false
                }
            }
        }
    }
}
