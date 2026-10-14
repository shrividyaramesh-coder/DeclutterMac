---
module: scheduling-and-packaging
tags: [launchd, LaunchAgent, app-bundle, codesign, onboarding, fda, creative-apps]
problem_type: architectural_enhancement
---

# Solution: Background Scheduling (LaunchAgent), Interactive Onboarding, and macOS App Packaging

## 1. Problem Statement
To function as a truly autonomous and native macOS utility, Tidy Mac needed:
1. **Headless continuous execution**: Scheduled cleanups must execute even when the main SwiftUI application window is closed, dispatching notifications upon completion.
2. **First-run onboarding & permissions**: Plain-language explanation of Full Disk Access (FDA), deep-linking to System Settings, and user-authorized folder selection via security-scoped bookmarks.
3. **Application bundle packaging**: A standalone `.app` bundle (`TidyMac.app`) with custom `AppIcon.icns`, complete `Info.plist`, resource bundles, and code signing.
4. **Expanded app clutter discovery**: Explicit detection of creative suites (Adobe Media Cache, Final Cut Pro, Figma, Blender), modern browsers (Brave, Edge), and messaging apps (Discord, Teams).

---

## 2. Architecture & Implementation

### 2.1 Headless Background Runner (`--scheduled-run`) & `LaunchAgentManager`
- `LaunchAgentManager` formats and installs `~/Library/LaunchAgents/com.tidymac.cleanup.plist`.
- Configures `ProgramArguments` pointing to the application executable with `--scheduled-run`.
- Sets `LowPriorityIO = true` and `ProcessType = Background` to ensure zero perceptible impact on foreground user tasks.
- Sets `StartInterval` dynamically based on user frequency preference:
  - Daily: `86,400` seconds
  - Weekly: `604,800` seconds
  - Monthly: `2,592,000` seconds
  - Low disk space trigger: `900` seconds (15-minute polling interval)
- `TidyMacApp.init()` intercepts `--scheduled-run`:
  ```swift
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
  ```
  It runs `executeScheduledRun()` without allocating any GUI scenes, posts a system notification summary via `UserNotificationService`, and cleanly terminates.

### 2.2 Interactive Onboarding & FDA Guidance (`OnboardingView`)
- Multi-step onboarding view automatically displayed on first launch (persisted via `hasCompletedOnboarding` in `UserDefaults`).
- Detects Full Disk Access status via `PermissionsManager.shared.checkFullDiskAccess()`.
- Deep-links directly to macOS System Settings:
  `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`
- Provides default managed folder toggles (Downloads, Documents, Desktop, Pictures/Screenshots, Caches) and custom folder additions via `NSOpenPanel`, generating security-scoped bookmarks in `FileAccessService`.
- Displays an alert banner at the top of `DashboardView` whenever FDA is not detected, offering one-click access to grant permissions or review settings.

### 2.3 Automated App Packaging & Icon Generation
- `scripts/generate_icon.swift`: Synthesizes an Apple-compliant icon set across 10 resolutions (16px to 1024px @2x) using CoreGraphics gradients and SF Symbols, converting it to `AppIcon.icns` via `iconutil`.
- `scripts/package_app.sh`: Compiles release binaries via `swift build -c release`, assembles `build/TidyMac.app/Contents/{MacOS,Resources}`, writes an `Info.plist` with all required Apple privacy usage keys (`NSDesktopFolderUsageDescription`, etc.), and applies ad-hoc code signing.
- `scripts/install.sh`: Deploys the packaged `TidyMac.app` into `~/Applications`.

### 2.4 Creative & Work Application Clutter Detection
- `CategoryClassifier` was updated to classify scratch and media caches from Adobe (`Library/Application Support/Adobe/Common/Media Cache Files`), Final Cut Pro (`Library/Caches/com.apple.FinalCut`), Figma (`Library/Caches/com.figma.Desktop`), Blender, and Canva as `.caches`.
- Added Brave (`Library/Caches/com.brave.Browser`) and Microsoft Edge to `.browserCaches`.
- Added Discord (`Library/Caches/com.hnc.Discord`) and Microsoft Teams (`Library/Caches/com.microsoft.teams2`) to `.messagingMedia`.

---

## 3. Verification & Results

- **Automated Tests**: Added `LaunchAgentAndAppPolishTests.swift` covering plist XML generation, intervals, creative classifiers, and permissions.
- Total test count expanded from 333 to **357 tests**, all passing with a **100% success rate**.
- Tested headless scheduled execution via `swift run TidyMacApp --scheduled-run` (exit code 0).
- Successfully built, signed, and validated `build/TidyMac.app`.
