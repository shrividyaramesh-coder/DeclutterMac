import SwiftUI
import AppKit
import TidyMacCore

public struct SettingsView: View {
    @ObservedObject private var localization = LocalizationManager.shared
    
    @State private var selectedLanguage: AppLanguage = LocalizationManager.shared.currentLanguage
    @State private var selectedAIProvider: AIProvider = .heuristic
    @State private var anthropicKey: String = ""
    @State private var openAIKey: String = ""
    @State private var licenseStatus: LicenseStatus = .trial(daysRemaining: 15)
    @State private var unlockKeyInput: String = ""
    @State private var licenseMessage: String? = nil
    @State private var managedFolders: [URL] = []
    @State private var launchAtLogin: Bool = true
    @State private var showMenuBarIcon: Bool = true
    @State private var showOnboardingSheet: Bool = false
    @State private var scheduleSettings: ScheduleSettings = ScheduleSettings()
    @State private var folderSortsUsed: Int = 0
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                headerView
                
                Divider()
                
                // Section 1: General & Localization
                generalSection
                
                // Section 2: Continuous Cleanup Schedule (Set & Forget)
                scheduleSection
                
                // Section 3: AI Provider & API Keys
                aiProviderSection
                
                // Section 4: Trial & Licensing
                licensingSection
                
                // Section 5: Managed Folders & Permissions
                managedFoldersSection
            }
            .padding(28)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showOnboardingSheet) {
            OnboardingView()
                .environmentObject(AppState.shared)
        }
        .task {
            await loadData()
        }
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(localized("nav.settings"))
                    .font(.title)
                    .fontWeight(.bold)
                Text("Customize Declutter Mac preferences, AI integrations, and licensing.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }
    
    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("General")
                .font(.headline)
            
            VStack(spacing: 12) {
                // Language Picker
                HStack {
                    Text("Language")
                        .font(.body)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { localization.currentLanguage },
                        set: { newLang in
                            localization.setLanguage(newLang)
                        }
                    )) {
                        ForEach(AppLanguage.allCases, id: \.self) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 200)
                }
                
                Divider()
                
                // Menu Bar Toggle
                Toggle("Show Declutter Mac in Menu Bar", isOn: $showMenuBarIcon)
                
                // Launch at Login Toggle
                Toggle("Launch Declutter Mac at Login", isOn: $launchAtLogin)
                
                Divider()
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Onboarding & Permissions Wizard")
                            .font(.body)
                        Text("Re-run initial setup, manage approved folders, or review Full Disk Access.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Review Permissions") {
                        showOnboardingSheet = true
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
        }
    }
    
    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Continuous Cleanup Schedule (Set & Forget)")
                    .font(.headline)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { scheduleSettings.isEnabled },
                    set: { enabled in
                        scheduleSettings.isEnabled = enabled
                        Task {
                            await ScheduleCoordinator.shared.updateSettings(scheduleSettings)
                            let exeURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
                            if enabled {
                                _ = try? LaunchAgentManager.shared.install(executableURL: exeURL, frequency: scheduleSettings.frequency)
                            } else {
                                LaunchAgentManager.shared.uninstall()
                            }
                        }
                    }
                ))
                .labelsHidden()
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Automate recurring cleanups in the background even when Declutter Mac is closed. Only rules you have approved will be executed.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if scheduleSettings.isEnabled {
                    Divider()
                    
                    HStack(spacing: 16) {
                        Text("Frequency")
                            .font(.body)
                        
                        Spacer()
                        
                        Picker("", selection: Binding(
                            get: { scheduleSettings.frequency },
                            set: { freq in
                                scheduleSettings.frequency = freq
                                Task {
                                    await ScheduleCoordinator.shared.updateSettings(scheduleSettings)
                                    let exeURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
                                    _ = try? LaunchAgentManager.shared.install(executableURL: exeURL, frequency: freq)
                                }
                            }
                        )) {
                            Text("Daily").tag(ScheduleFrequency.daily)
                            Text("Weekly").tag(ScheduleFrequency.weekly)
                            Text("Monthly").tag(ScheduleFrequency.monthly)
                            Text("When Free Space < 15 GB").tag(ScheduleFrequency.onLowDiskSpace(thresholdGB: 15))
                        }
                        .pickerStyle(.menu)
                        .frame(width: 220)
                    }
                    
                    HStack {
                        if let lastRun = scheduleSettings.lastRunDate {
                            Text("Last run: \(DateFormatter.localizedString(from: lastRun, dateStyle: .short, timeStyle: .short))")
                        } else {
                            Text("Last run: Never")
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            AppState.shared.selectedNavigation = .rules
                        }) {
                            HStack(spacing: 4) {
                                Text("Configure Approved Rules")
                                Image(systemName: "arrow.right")
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
        }
    }
    
    private var aiProviderSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("AI Provider & Credentials")
                    .font(.headline)
                Spacer()
                Text("Metadata Only")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.15))
                    .foregroundColor(.green)
                    .cornerRadius(4)
            }
            
            VStack(spacing: 14) {
                HStack {
                    Text("Active Provider")
                        .font(.body)
                    Spacer()
                    Picker("", selection: $selectedAIProvider) {
                        ForEach(AIProvider.allCases, id: \.self) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 220)
                }
                
                if selectedAIProvider == .anthropic {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Anthropic API Key (Claude)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack {
                            SecureField("sk-ant-...", text: $anthropicKey)
                                .textFieldStyle(.roundedBorder)
                            Button("Save") {
                                _ = KeychainService.shared.saveKey(anthropicKey, forAccount: "anthropic_api_key")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                
                if selectedAIProvider == .openAI {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("OpenAI API Key (GPT-4o)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack {
                            SecureField("sk-proj-...", text: $openAIKey)
                                .textFieldStyle(.roundedBorder)
                            Button("Save") {
                                _ = KeychainService.shared.saveKey(openAIKey, forAccount: "openai_api_key")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                
                if selectedAIProvider == .heuristic {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Offline Heuristic Engine is fully active. No API keys or internet connection required.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
        }
    }
    
    private var licensingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("License & Edition")
                .font(.headline)
            
            VStack(spacing: 14) {
                switch licenseStatus {
                case .unlocked(let key):
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Declutter Mac — Lifetime License Active")
                                .font(.body)
                                .fontWeight(.semibold)
                            Text("License Key: \(key.prefix(12))... • Unlimited folder sorting & disk cleaning on all your Macs")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("Lifetime Unlocked")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.12))
                            .cornerRadius(6)
                    }
                    
                default:
                    HStack(spacing: 12) {
                        Image(systemName: "folder.badge.gearshape")
                            .foregroundColor(.accentColor)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Declutter Mac — Free Tier")
                                .font(.body)
                                .fontWeight(.semibold)
                            Text("First 2 folders free • $3.99 one-time purchase for lifetime unlimited access")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("\(min(2, folderSortsUsed)) of 2 Folders Used")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(folderSortsUsed >= 2 ? .orange : .accentColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background((folderSortsUsed >= 2 ? Color.orange : Color.accentColor).opacity(0.12))
                            .cornerRadius(6)
                    }
                    
                    Divider()
                    
                    HStack(spacing: 12) {
                        TextField("Enter $3.99 Lifetime License Key", text: $unlockKeyInput)
                            .textFieldStyle(.roundedBorder)
                        
                        Button("Unlock") {
                            unlockLicense()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(unlockKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    
                    if let msg = licenseMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundColor(msg.contains("success") ? .green : .red)
                    }
                    
                    HStack(spacing: 12) {
                        Button("Restore Purchases") {
                            restoreLicense()
                        }
                        .buttonStyle(.bordered)
                        
                        Button(action: {
                            if let url = URL(string: "https://www.decluttermac.com#pricing") {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "cart.fill")
                                Text("Buy $3.99 Lifetime Pass Online")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
        }
    }
    
    private var managedFoldersSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Authorized Managed Folders")
                .font(.headline)
            
            VStack(spacing: 8) {
                ForEach(managedFolders, id: \.self) { folder in
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.accentColor)
                        Text(folder.lastPathComponent)
                            .font(.body)
                        Spacer()
                        Text(folder.path)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(8)
                    .background(Color(NSColor.windowBackgroundColor))
                    .cornerRadius(6)
                }
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Actions
    
    private func loadData() async {
        let status = await LocalLicenseProvider.shared.currentStatus()
        let folders = await FileAccessService.shared.getManagedFolderURLs()
        let anthropic = KeychainService.shared.getKey(forAccount: "anthropic_api_key") ?? ""
        let openai = KeychainService.shared.getKey(forAccount: "openai_api_key") ?? ""
        let schedule = await ScheduleCoordinator.shared.getSettings()
        let sorts = await LocalLicenseProvider.shared.folderSortsCount()
        
        await MainActor.run {
            self.licenseStatus = status
            self.managedFolders = folders
            self.anthropicKey = anthropic
            self.openAIKey = openai
            self.scheduleSettings = schedule
            self.folderSortsUsed = sorts
        }
    }
    
    private func unlockLicense() {
        Task {
            let success = await LocalLicenseProvider.shared.unlockLifetime(key: unlockKeyInput)
            if success {
                let status = await LocalLicenseProvider.shared.currentStatus()
                await MainActor.run {
                    self.licenseStatus = status
                    self.licenseMessage = "Lifetime license activated successfully!"
                    self.unlockKeyInput = ""
                }
            }
        }
    }
    
    private func restoreLicense() {
        Task {
            let restored = await LocalLicenseProvider.shared.restorePurchases()
            if restored {
                let status = await LocalLicenseProvider.shared.currentStatus()
                await MainActor.run {
                    self.licenseStatus = status
                    self.licenseMessage = "Purchases restored successfully."
                }
            } else {
                await MainActor.run {
                    self.licenseMessage = "No previous purchases found."
                }
            }
        }
    }
}
