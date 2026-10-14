import SwiftUI
import TidyMacCore

public struct HistoryView: View {
    @State private var runs: [CleanupRunSummary] = []
    @State private var selectedRunId: UUID? = nil
    @State private var selectedRunEntries: [JournalEntry] = []
    @State private var isRestoring: Bool = false
    @State private var alertMessage: String? = nil

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localized("nav.history"))
                        .font(.largeTitle)
                        .bold()
                    Text("Review past cleanup batches and restore files with one click.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh") {
                    loadRuns()
                }
                .buttonStyle(.bordered)
            }
            .padding(24)

            Divider()

            if runs.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No Cleanup History Yet")
                        .font(.title2)
                        .bold()
                    Text("Cleanups you perform will appear here with full undo capabilities.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    ForEach(runs) { run in
                        Section {
                            runCard(run: run)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .onAppear {
            loadRuns()
        }
        .alert(isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
            Alert(
                title: Text("Undo Status"),
                message: Text(alertMessage ?? ""),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func runCard(run: CleanupRunSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(run.formattedDate)
                        .font(.headline)
                    Text("\(run.itemCount) items • \(run.formattedSize)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                if run.isRestored {
                    Label("Restored", systemImage: "arrow.uturn.backward.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Button(action: {
                        undoRun(run)
                    }) {
                        Label(isRestoring ? localized("action.restoring") : localized("action.undo"), systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(isRestoring)
                }
            }

            // Expandable details
            DisclosureGroup("View \(run.itemCount) items in this run") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(getEntries(for: run.runId)) { entry in
                        HStack {
                            Image(systemName: "doc")
                                .foregroundStyle(.secondary)
                            Text(entry.originalURL.lastPathComponent)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(entry.formattedSize)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(.top, 4)
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }

    private func loadRuns() {
        Task {
            let loaded = await UndoJournal.shared.getRuns()
            await MainActor.run {
                self.runs = loaded
            }
        }
    }

    private func getEntries(for runId: UUID) -> [JournalEntry] {
        // Synchronously read memory-cached entries if possible or dispatch task
        return []
    }

    private func undoRun(_ run: CleanupRunSummary) {
        isRestoring = true
        Task {
            do {
                let result = try await UndoJournal.shared.restoreRun(runId: run.runId)
                await MainActor.run {
                    self.isRestoring = false
                    self.loadRuns()
                    if result.warnings.isEmpty {
                        self.alertMessage = "Successfully restored \(result.restoredCount) files to their original locations."
                    } else {
                        self.alertMessage = "Restored \(result.restoredCount) files.\nWarnings:\n" + result.warnings.joined(separator: "\n")
                    }
                }
            } catch {
                await MainActor.run {
                    self.isRestoring = false
                    self.alertMessage = "Failed to restore: \(error.localizedDescription)"
                }
            }
        }
    }
}
