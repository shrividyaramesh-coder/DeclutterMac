import SwiftUI
import AppKit
import TidyMacCore

public struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    
    @State private var currentStep: Int = 0
    @State private var hasFullDiskAccess: Bool = false
    @State private var selectedFolders: Set<ManagedFolderType> = Set(ManagedFolderType.allCases)
    @State private var customFolderURLs: [URL] = []
    @State private var isSaving: Bool = false
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 28))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized("app.name"))
                        .font(.title2)
                        .bold()
                    Text(localized("app.tagline"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Step \(currentStep + 1) of 3")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Content Body
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if currentStep == 0 {
                        permissionsStepView
                    } else if currentStep == 1 {
                        foldersStepView
                    } else {
                        safetyGuaranteeStepView
                    }
                }
                .padding(24)
            }
            
            Divider()
            
            // Footer Navigation
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        currentStep -= 1
                    }
                    .buttonStyle(.bordered)
                }
                
                Spacer()
                
                if currentStep < 2 {
                    Button("Continue") {
                        currentStep += 1
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(action: {
                        finishOnboarding()
                    }) {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Get Started")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)
                }
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 620, height: 500)
        .onAppear {
            checkPermissions()
        }
    }
    
    // MARK: - Step 1: Full Disk Access Guidance
    
    private var permissionsStepView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Full Disk Access & Permissions")
                .font(.title3)
                .bold()
            
            Text("macOS isolates application sandboxes to protect user security. To scan system caches, application leftovers, and duplicate files, Declutter Mac works best with Full Disk Access.")
                .font(.body)
                .foregroundStyle(.secondary)
            
            // Status Card
            HStack(spacing: 14) {
                Image(systemName: hasFullDiskAccess ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(hasFullDiskAccess ? .green : .orange)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(hasFullDiskAccess ? "Full Disk Access Granted" : "Limited Access (Sandboxed Mode)")
                        .font(.headline)
                        .foregroundStyle(hasFullDiskAccess ? .green : .primary)
                    Text(hasFullDiskAccess ? "Declutter Mac is fully authorized to inspect system caches, developer tools, and app leftovers." : "Declutter Mac can still manage specific user folders, but cannot scan deep caches or leftovers without Full Disk Access.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            
            HStack(spacing: 12) {
                Button(action: {
                    PermissionsManager.shared.openSystemSettings()
                }) {
                    Label(localized("permission.open_settings"), systemImage: "gearshape")
                }
                .buttonStyle(.borderedProminent)
                
                Button("Refresh Status") {
                    checkPermissions()
                }
                .buttonStyle(.bordered)
            }
            
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.green)
                Text("Privacy Guarantee: All scanning is 100% local. Files are never uploaded or retained.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        }
    }
    
    // MARK: - Step 2: Managed Folders Selection
    
    private var foldersStepView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose Folders to Manage")
                .font(.title3)
                .bold()
            
            Text("Select the default folders you would like Declutter Mac to monitor for junk, duplicates, and organization. Declutter Mac creates security-scoped bookmarks to remember your choices.")
                .font(.body)
                .foregroundStyle(.secondary)
            
            VStack(spacing: 8) {
                ForEach(ManagedFolderType.allCases) { folder in
                    Toggle(isOn: Binding(
                        get: { selectedFolders.contains(folder) },
                        set: { isSelected in
                            if isSelected {
                                selectedFolders.insert(folder)
                            } else {
                                selectedFolders.remove(folder)
                            }
                        }
                    )) {
                        HStack {
                            Image(systemName: folder.systemImage)
                                .foregroundStyle(.tint)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(folder.title)
                                    .font(.subheadline)
                                    .bold()
                                Text(folder.defaultURL.path)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                
                ForEach(customFolderURLs, id: \.self) { url in
                    HStack {
                        Image(systemName: "folder.badge.plus")
                            .foregroundStyle(.purple)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(url.lastPathComponent)
                                .font(.subheadline)
                                .bold()
                            Text(url.path)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button(action: {
                            customFolderURLs.removeAll(where: { $0 == url })
                        }) {
                            Image(systemName: "xmark.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            
            Button(action: {
                pickCustomFolder()
            }) {
                Label("Add Another Folder...", systemImage: "plus")
            }
            .buttonStyle(.bordered)
        }
    }
    
    // MARK: - Step 3: Safety Guardrails
    
    private var safetyGuaranteeStepView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Safety & Core Invariants")
                .font(.title3)
                .bold()
            
            Text("Declutter Mac is engineered with non-negotiable safety guardrails to ensure zero accidental data loss.")
                .font(.body)
                .foregroundStyle(.secondary)
            
            VStack(spacing: 12) {
                safetyFeatureRow(
                    icon: "trash.fill",
                    color: .blue,
                    title: "Trash-Only Deletion",
                    desc: "Files are never permanently deleted by cleanup routines; they are moved to your macOS Trash."
                )
                
                safetyFeatureRow(
                    icon: "lock.fill",
                    color: .red,
                    title: "Hard-Coded Protected Denylist",
                    desc: "System directories, keychains, Photos libraries, Apple Mail, and Git repositories cannot be touched."
                )
                
                safetyFeatureRow(
                    icon: "doc.on.doc.fill",
                    color: .orange,
                    title: "Duplicate Keep-One Guard",
                    desc: "Duplicate finder strictly preserves at least one original copy in every cluster."
                )
                
                safetyFeatureRow(
                    icon: "arrow.uturn.backward.circle.fill",
                    color: .green,
                    title: "Full Undo Journal",
                    desc: "Every clean or organization move is recorded with timestamps for single-click restoration."
                )
            }
        }
    }
    
    private func safetyFeatureRow(icon: String, color: Color, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .bold()
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Helpers & Actions
    
    private func checkPermissions() {
        let fda = PermissionsManager.shared.checkFullDiskAccess()
        self.hasFullDiskAccess = fda
        appState.hasFullDiskAccess = fda
    }
    
    private func pickCustomFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Folder"
        
        if panel.runModal() == .OK, let url = panel.url {
            if !customFolderURLs.contains(url) {
                customFolderURLs.append(url)
            }
        }
    }
    
    private func finishOnboarding() {
        isSaving = true
        Task {
            // Save security-scoped bookmarks for selected folders
            for folderType in selectedFolders {
                let url = folderType.defaultURL
                _ = try? await FileAccessService.shared.saveBookmark(for: url)
            }
            for customURL in customFolderURLs {
                _ = try? await FileAccessService.shared.saveBookmark(for: customURL)
            }
            
            await MainActor.run {
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                isSaving = false
                dismiss()
            }
        }
    }
}
