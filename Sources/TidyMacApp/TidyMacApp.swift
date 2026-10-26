import SwiftUI
import TidyMacCore

@main
struct TidyMacApp: App {
    @StateObject private var appState = AppState.shared
    @StateObject private var localization = LocalizationManager.shared

    init() {
        if CommandLine.arguments.contains("--scheduled-run") {
            let semaphore = DispatchSemaphore(value: 0)
            Task.detached {
                _ = try? await ScheduleCoordinator.shared.executeScheduledRun()
                semaphore.signal()
            }
            semaphore.wait()
            exit(0)
        }
    }

    var body: some Scene {
        WindowGroup {
            MainContentView()
                .environmentObject(appState)
                .environmentObject(localization)
                .frame(minWidth: 960, minHeight: 640)
        }
        .commands {
            CommandMenu("Language") {
                ForEach(AppLanguage.allCases) { lang in
                    Button(action: {
                        localization.setLanguage(lang)
                    }) {
                        HStack {
                            Text(lang.displayName)
                            if localization.currentLanguage == lang {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        }

        MenuBarExtra("Declutter Mac", systemImage: "folder.badge.gearshape") {
            VStack(alignment: .leading, spacing: 6) {
                Text(localized("app.name"))
                    .font(.headline)
                Text(localized("app.tagline"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider()
                Text("\(localized("dashboard.reclaimable_now")): \(appState.storageSummary.formattedReclaimable)")
                    .font(.subheadline)
                Divider()
                Button(localized("action.scan")) {
                    appState.selectedNavigation = .cleanup
                }
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .padding(8)
        }
    }
}

struct MainContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var localization: LocalizationManager
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @State private var showOnboarding: Bool = false

    var body: some View {
        NavigationSplitView {
            List(AppNavigationItem.allCases, selection: $appState.selectedNavigation) { item in
                NavigationLink(value: item) {
                    Label(item.localizedTitle, systemImage: item.systemImage)
                }
            }
            .navigationTitle(localized("app.name"))
            .frame(minWidth: 200)
        } detail: {
            detailView(for: appState.selectedNavigation)
        }
        .onAppear {
            if !hasCompletedOnboarding {
                showOnboarding = true
            }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView()
                .environmentObject(appState)
        }
    }

    @ViewBuilder
    private func detailView(for item: AppNavigationItem) -> some View {
        switch item {
        case .overview:
            DashboardView()
        case .cleanup:
            CleanupView()
        case .duplicates:
            DuplicateFinderView()
        case .apps:
            AppUninstallerView()
        case .agent:
            AgentChatView()
        case .organize:
            FolderOrganizerView()
        case .rules:
            RulesManagementView()
        case .history:
            HistoryView()
        case .privacy:
            PrivacySecurityView()
        case .settings:
            SettingsView()
        }
    }
}
