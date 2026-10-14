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
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                headerView
                
                Divider()
                
                // Section 1: General & Localization
                generalSection
                
                // Section 2: AI Provider & API Keys
                aiProviderSection
                
                // Section 3: Trial & Licensing
                licensingSection
                
                // Section 4: Managed Folders & Permissions
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
                Text("Customize Tidy Mac preferences, AI integrations, and licensing.")
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
                Toggle("Show Tidy Mac in Menu Bar", isOn: $showMenuBarIcon)
                
                // Launch at Login Toggle
                Toggle("Launch Tidy Mac at Login", isOn: $launchAtLogin)
                
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
            Text("Trial & Licensing")
                .font(.headline)
            
            VStack(spacing: 14) {
                switch licenseStatus {
                case .trial(let days):
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Full Access Trial Active")
                                .font(.body)
                                .fontWeight(.semibold)
                            Text("\(days) days remaining in full trial")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("\(days) Days")
                            .font(.headline)
                            .foregroundColor(.accentColor)
                    }
                    
                case .freeTier(let cleaned, let allowance):
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Free Cleaning Allowance")
                                .font(.body)
                                .fontWeight(.semibold)
                            Spacer()
                            Text("\(ByteCountFormatter.string(fromByteCount: cleaned, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: allowance, countStyle: .file))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        ProgressView(value: Double(min(cleaned, allowance)), total: Double(allowance))
                    }
                    
                case .unlocked(let key):
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tidy Mac Lifetime Unlocked")
                                .font(.body)
                                .fontWeight(.semibold)
                            Text("License: \(key.prefix(8))...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                }
                
                if case .unlocked = licenseStatus {
                    // Already unlocked
                } else {
                    Divider()
                    
                    HStack(spacing: 12) {
                        TextField("Enter Lifetime License Key", text: $unlockKeyInput)
                            .textFieldStyle(.roundedBorder)
                        
                        Button("Unlock") {
                            unlockLicense()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(unlockKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                        
                        Button("Restore") {
                            restoreLicense()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                if let message = licenseMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.accentColor)
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
        
        await MainActor.run {
            self.licenseStatus = status
            self.managedFolders = folders
            self.anthropicKey = anthropic
            self.openAIKey = openai
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
