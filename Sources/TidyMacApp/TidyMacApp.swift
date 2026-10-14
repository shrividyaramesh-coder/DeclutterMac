import SwiftUI
import TidyMacCore

@main
struct TidyMacApp: App {
    @StateObject private var appState = AppState.shared
    @StateObject private var localization = LocalizationManager.shared

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

        MenuBarExtra("Tidy Mac", systemImage: "sparkles") {
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
    }

    @ViewBuilder
    private func detailView(for item: AppNavigationItem) -> some View {
        switch item {
        case .overview:
            DashboardView()
        case .cleanup:
            CleanupView()
        default:
            VStack(spacing: 20) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                Text(item.localizedTitle)
                    .font(.title)
                    .bold()
                Text(localized("app.tagline"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
