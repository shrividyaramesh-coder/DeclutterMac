import Foundation
import ServiceManagement
import TidyMacCore

/// Runs auto-organize in the background while the app is open (it lives in the menu bar),
/// and owns the Launch at Login setting so it keeps running after a restart.
@MainActor
final class AutoOrganizeController: ObservableObject {
    static let shared = AutoOrganizeController()

    /// How often chosen folders are checked. Each check is a quick folder listing; AI only runs for items being sorted.
    static let checkInterval: TimeInterval = 120

    @Published private(set) var settings = AutoOrganizeSettings()
    @Published private(set) var isRunning = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var isAllowedByLicense = true
    @Published private(set) var launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    let isAIAvailable = TopicCategorizerFactory.isOnDeviceModelAvailable

    private var timer: Timer?

    private init() {}

    func start() {
        Task {
            settings = await AutoOrganizeSettingsStore.shared.get()
            rescheduleTimer()
            if settings.isEnabled { await runNow() }
        }
    }

    func update(_ change: (inout AutoOrganizeSettings) -> Void) {
        var newSettings = settings
        change(&newSettings)
        let wasEnabled = settings.isEnabled
        settings = newSettings
        Task {
            await AutoOrganizeSettingsStore.shared.update(newSettings)
            settings = await AutoOrganizeSettingsStore.shared.get()
            rescheduleTimer()
            if settings.isEnabled && !wasEnabled {
                // Turning it on should keep it on after a restart, like a menu bar utility is expected to
                if !launchAtLoginEnabled { setLaunchAtLogin(true) }
                await runNow()
            }
        }
    }

    func runNow() async {
        guard !isRunning else { return }
        let status = await LocalLicenseProvider.shared.currentStatus()
        isAllowedByLicense = AutoOrganizeSettingsStore.isAllowed(by: status)
        guard isAllowedByLicense else {
            statusMessage = "Auto-organize is paused. Unlock the lifetime license to keep your folders tidy automatically."
            return
        }
        isRunning = true
        let current = settings
        let result = await AutoOrganizer.shared.run(
            folders: current.folderURLs,
            recentsDays: current.recentsDays,
            useAITopics: current.useAITopics
        )
        isRunning = false

        var updated = await AutoOrganizeSettingsStore.shared.get()
        updated.lastRunDate = Date()
        if result.totalMoved > 0 { updated.lastRunMovedCount = result.totalMoved }
        await AutoOrganizeSettingsStore.shared.update(updated)
        settings = updated
        statusMessage = result.totalMoved == 0
            ? "Everything is tidy."
            : "Moved \(result.movedToRecents) new item\(result.movedToRecents == 1 ? "" : "s") to Recents and sorted \(result.sorted). Undo anytime in History."
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            statusMessage = "Couldn't change Launch at Login: \(error.localizedDescription). You can add Declutter Mac in System Settings → General → Login Items."
        }
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }

    private func rescheduleTimer() {
        timer?.invalidate()
        timer = nil
        guard settings.isEnabled else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { _ in
            Task { @MainActor in await AutoOrganizeController.shared.runNow() }
        }
    }
}
