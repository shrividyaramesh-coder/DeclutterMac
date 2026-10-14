import SwiftUI
import AppKit
import TidyMacCore

public struct AppUninstallerView: View {
    @State private var apps: [InstalledApp] = []
    @State private var searchText: String = ""
    @State private var isLoading: Bool = false
    @State private var activeUninstallBundle: AppUninstallBundle? = nil
    @State private var isUninstalling: Bool = false
    @State private var alertMessage: String? = nil

    public init() {}

    private var filteredApps: [InstalledApp] {
        if searchText.isEmpty {
            return apps
        }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.bundleIdentifier?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header & Search
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized("nav.apps"))
                        .font(.largeTitle)
                        .bold()
                    Text("Completely remove apps and their hidden support leftovers.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TextField("Search installed apps...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)

                Button("Refresh") {
                    loadApps()
                }
                .buttonStyle(.bordered)
            }
            .padding(20)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Scanning /Applications and computing app sizes...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else if filteredApps.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "app.badge.checkmark")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No Applications Found")
                        .font(.title2)
                        .bold()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List(filteredApps) { app in
                    appRow(app: app)
                }
                .listStyle(.inset)
            }
        }
        .onAppear {
            loadApps()
        }
        .sheet(item: $activeUninstallBundle) { bundle in
            uninstallReviewSheet(bundle: bundle)
        }
        .alert(isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
            Alert(
                title: Text("App Uninstallation"),
                message: Text(alertMessage ?? ""),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func appRow(app: InstalledApp) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "app.fill")
                .font(.system(size: 32))
                .foregroundStyle(.tint)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(app.name)
                        .font(.headline)
                    if let version = app.version {
                        Text("v\(version)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if app.isSystemProtected {
                        Text("SYSTEM PROTECTED")
                            .font(.caption2)
                            .bold()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())
                    }
                }
                Text("Last modified: \(app.formattedLastUsed)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(app.formattedSize)
                .font(.subheadline)
                .bold()
                .frame(width: 80, alignment: .trailing)

            if app.isSystemProtected {
                Button("Protected") {}
                    .buttonStyle(.bordered)
                    .disabled(true)
            } else {
                Button("Uninstall") {
                    prepareUninstall(for: app)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(.vertical, 4)
    }

    private func uninstallReviewSheet(bundle: AppUninstallBundle) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Uninstall \(bundle.app.name)")
                .font(.title2)
                .bold()
            Text("Review the application bundle and all associated leftover files found across your Library. Everything will be moved to the Trash.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("App Bundle", systemImage: "app.dashed")
                        .font(.headline)
                    Spacer()
                    Text(bundle.app.formattedSize)
                        .bold()
                }
                Text(bundle.app.url.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text("Related Leftovers (\(bundle.leftovers.count) found):")
                .font(.headline)

            if bundle.leftovers.isEmpty {
                Text("No additional support files or caches were found.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                List(bundle.leftovers) { item in
                    HStack {
                        Image(systemName: item.category.systemImage)
                        VStack(alignment: .leading) {
                            Text(item.url.lastPathComponent)
                                .font(.body)
                            Text(item.url.path)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(item.formattedSize)
                            .font(.caption)
                    }
                }
                .frame(height: 180)
            }

            Divider()

            HStack {
                Text("Total to reclaim: \(bundle.formattedTotalSize)")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    activeUninstallBundle = nil
                }
                .buttonStyle(.bordered)

                Button("Move to Trash") {
                    executeUninstall(bundle: bundle)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(isUninstalling)
            }
        }
        .padding(24)
        .frame(minWidth: 540, minHeight: 460)
    }

    private func loadApps() {
        isLoading = true
        Task {
            let loaded = await AppUninstallerEngine.shared.listInstalledApps()
            await MainActor.run {
                self.apps = loaded
                self.isLoading = false
            }
        }
    }

    private func prepareUninstall(for app: InstalledApp) {
        Task {
            let bundle = await AppUninstallerEngine.shared.findLeftovers(for: app)
            await MainActor.run {
                self.activeUninstallBundle = bundle
            }
        }
    }

    private func executeUninstall(bundle: AppUninstallBundle) {
        isUninstalling = true
        Task {
            let runId = UUID()
            var trashedBytes: Int64 = 0
            var trashedCount = 0

            // 1. Move main app bundle to Trash
            do {
                let trashedURL = try await TrashMover.shared.moveToTrash(at: bundle.app.url)
                trashedBytes += bundle.app.appSize
                trashedCount += 1
                await UndoJournal.shared.record(entry: JournalEntry(
                    runId: runId,
                    originalURL: bundle.app.url,
                    trashedURL: trashedURL,
                    fileSize: bundle.app.appSize,
                    action: .trashed
                ))
            } catch {
                print("Failed to trash app bundle: \(error)")
            }

            // 2. Move leftovers to Trash
            for item in bundle.leftovers {
                do {
                    let trashedURL = try await TrashMover.shared.moveToTrash(at: item.url)
                    trashedBytes += item.fileSize
                    trashedCount += 1
                    await UndoJournal.shared.record(entry: JournalEntry(
                        runId: runId,
                        originalURL: item.url,
                        trashedURL: trashedURL,
                        fileSize: item.fileSize,
                        action: .trashed
                    ))
                } catch {
                    print("Failed to trash leftover: \(error)")
                }
            }

            await MainActor.run {
                self.isUninstalling = false
                self.activeUninstallBundle = nil
                self.alertMessage = "Successfully uninstalled \(bundle.app.name) and its leftovers, reclaiming \(ByteCountFormatter.string(fromByteCount: trashedBytes, countStyle: .file))."
                self.loadApps()
            }
        }
    }
}
