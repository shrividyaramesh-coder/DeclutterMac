# Tidy Mac 🧹✨

> **"Declutter your Mac with zero effort."**

**Tidy Mac** is a native macOS application built with **Swift 6** and **SwiftUI** (targeting macOS 14+). It provides safe storage cleanup, 3-tier duplicate file removal, app uninstallation with leftover discovery, natural language cleanup planning, and AI folder organization.

---

## 🛡️ Core Safety Invariants (Non-Negotiable)

Tidy Mac is engineered with safety-by-design principles:

1. **Trash-Only Deletion**:
   - Files are moved to the user's Trash via `FileManager.default.trashItem(at:resultingItemURL:)`.
   - Permanent deletion (`removeItem`, `unlink`, `rm -rf`) is **strictly forbidden** in production cleanup code.
2. **Hard-Coded Protected Paths Denylist**:
   - System directories (`/System`, `/Library`, `/usr`, `/bin`, `/sbin`, `/private`, `/etc`, `/var`), the root user home directory (`~`), `.git` repositories, Apple Mail (`~/Library/Mail`), Photos libraries (`*.photoslibrary`), and system keychains (`~/Library/Keychains`) are permanently protected.
3. **Canonical Path & Symlink Traversal Protection**:
   - All file paths are canonicalized (`resolvingSymlinksInPath()`) prior to evaluation.
   - Symlinks resolving outside permitted user-managed folders and relative path traversals (`..`) are rejected by `PathValidator`.
4. **Duplicate Keep-One Guard**:
   - The duplicate finder never allows all copies within a duplicate cluster to be selected. At least one original copy is always preserved.
5. **Risk Labels (Safe / Review / Manual)**:
   - **Safe**: Pre-selected for recommended cleanup (caches, logs, old installers).
   - **Review**: User must inspect before cleaning (screenshots, large files, downloads).
   - **Manual**: Visibility only. Strictly non-actionable; cannot be selected or deleted.
6. **Metadata-Only AI Boundary**:
   - The AI cleanup agent accepts only `MetadataOnlyRequest` structs (filename, extension, byte size, dates, relative folder path).
   - File contents, document text, and photos are **never** opened, read, or transmitted to any AI provider.
7. **Dry-Run Confirmation**:
   - Natural language plans and folder organization proposals execute in a dry-run preview first. No file movement or trashing occurs without explicit user confirmation.
8. **Reversible Undo Journaling**:
   - Every file modification or trash operation is recorded in `UndoJournal` with original location, target location, timestamp, and batch ID, enabling single-click full restoration.

---

## 🚀 Features

### 1. Onboarding & Permissions
- Explains Full Disk Access in plain language, deep-links directly to macOS System Settings, and degrades gracefully per folder if access is not granted.
- Manages user-authorized folders (Desktop, Documents, Downloads, Pictures) with security-scoped bookmarks.

### 2. Storage Overview Dashboard
- Interactive disk usage bar showing used, free, and reclaimable space.
- Category breakdown with live counters and lifetime space reclaimed tracker.

### 3. Cleanup Scanner & One-Click Clean
- Finds user caches, diagnostic logs, old installers (.dmg, .pkg, .iso), screenshots, and large files.
- Color-coded risk badges with "Select Recommended" quick action.
- Dynamic space preview: Current Free, Selected Cleanup, Projected Free.
- Background scanning with live progress reporting.

### 4. Duplicate Finder
- 3-tier progressive pipeline: Size grouping $\rightarrow$ partial 32 KB hash $\rightarrow$ full SHA-256 streaming digest.
- Auto-selection keeping oldest or shortest path, enforcing the keep-one invariant.
- Skips cloud placeholders and package bundles.

### 5. App Uninstaller & Leftovers Scanner
- Lists installed applications with bundle size and last-used date.
- Discovers orphaned leftovers across `~/Library/Application Support`, `~/Library/Caches`, `~/Library/Preferences`, `~/Library/Containers`, and `~/Library/Saved Application State`.
- Refuses to uninstall system applications or CoreServices.

### 6. Natural-Language Cleanup Agent
- Chat-style input (e.g. *"delete screenshots older than a month"*, *"trash installers older than 7 days"*).
- Converts requests into typed `CleaningPlan` JSON schemas with full validation.
- **Offline Heuristic Fallback**: Fully functional local parser without requiring an API key.
- Supports Anthropic (Claude) and OpenAI (GPT-4o) with secure Keychain credential storage.

### 7. AI Folder Organizer
- Proposes structured directory taxonomy based on file extensions and metadata.
- Allows inline editing of category names and remembers user preferences for future runs ("Learn from edits").
- Collision-safe renaming: appends non-destructive counter suffixes (`file (1).ext`) without overwriting.

### 8. Custom Rules & 12 Built-in Templates
- 12 built-in rules for screenshots, installers, archives, caches, logs, Xcode DerivedData, and more.
- Create, toggle, edit, and run individual rules manually.

### 9. Continuous Cleanup (Set & Forget)
- Background scheduling options: Daily, Weekly, Monthly, or When Free Space is low.
- Executes only user-approved rules and dispatches summary notifications via `UNUserNotificationCenter`.

### 10. Privacy & Security Screen
- Transparent statement of privacy guarantees matching code-enforced invariants.

### 11. 8-Language Localization
- Full in-app language switcher supporting:
  - English (`en`), French (`fr`), German (`de`), Japanese (`ja`), Korean (`ko`), Simplified Chinese (`zh-Hans`), Traditional Chinese (`zh-Hant`), Spanish (`es`).

### 12. Licensing & Free Allowance
- Unlimited free scanning with a 2 GB free cleaning allowance, followed by a 15-day full-access trial.
- Decoupled `LicenseProvider` protocol with lifetime purchase unlock.

---

## 🛠️ Build & Test Commands

### Prerequisites
- macOS 14.0+ (Sonoma or Sequoia)
- Swift 6.0+

### Building the Project
```bash
# Debug build
swift build

# Release build
swift build -c release
```

### Packaging Native macOS App Bundle (`TidyMac.app`)
```bash
# Package into build/TidyMac.app with custom AppIcon.icns, Info.plist, and ad-hoc codesign
bash scripts/package_app.sh

# Install into ~/Applications
bash scripts/install.sh

# Launch the app
open build/TidyMac.app
```

### Running Automated Tests
```bash
# Run the complete test suite (357 automated tests, 100% pass rate)
swift run TidyMacTestRunner
```

### Headless Background Scheduling
```bash
# Trigger scheduled cleanup headless (as invoked by launchd LaunchAgent)
swift run TidyMacApp --scheduled-run
```

---

## 🏛️ Architecture & Codebase Map

```
Tidymac/
├── Package.swift
├── scripts/
│   ├── package_app.sh       # Packages build/TidyMac.app with codesigning
│   ├── generate_icon.swift  # Synthesizes AppIcon.icns across all macOS resolutions
│   └── install.sh           # Installs TidyMac.app to ~/Applications
├── Sources/
│   ├── TidyMacCore/
│   │   ├── Safety/          # PathValidator, TrashMover
│   │   ├── FileAccess/      # FileAccessService, PermissionsManager, CloudFolderDetector
│   │   ├── Scanner/         # StorageScanner, CategoryClassifier, RiskEvaluator
│   │   ├── Duplicate/       # DuplicateFinderEngine, HashUtility
│   │   ├── Uninstaller/     # AppUninstallerEngine, InstalledApp
│   │   ├── Agent/           # OfflineHeuristicParser, LLMClient, CleaningPlan, PlanExecutor
│   │   ├── Organizer/       # FolderOrganizerEngine, CategoryPreferencesStore
│   │   ├── Rules/           # RuleEngine, RuleModel, BuiltInRuleTemplates
│   │   ├── Scheduling/      # ScheduleCoordinator, LaunchAgentManager, UserNotificationService
│   │   ├── Storage/         # UndoJournal
│   │   ├── Licensing/       # LicenseProvider, LocalLicenseProvider
│   │   ├── Localization/    # LocalizationManager, LocalizedStrings
│   │   └── Models/          # FileItem, RiskLabel, ScanCategory, StorageSummary, JournalEntry
│   └── TidyMacApp/
│       ├── Onboarding/      # OnboardingView (FDA setup & folder picker)
│       ├── Dashboard/       # DashboardView (with FDA status banner), DiskUsageBar
│       ├── Cleanup/         # CleanupView, SpacePreviewView, CleanupItemRow
│       ├── Duplicates/      # DuplicateFinderView
│       ├── Uninstaller/     # AppUninstallerView
│       ├── Agent/           # AgentChatView
│       ├── Organizer/       # FolderOrganizerView
│       ├── Rules/           # RulesManagementView (with LaunchAgent daemon sync)
│       ├── History/         # HistoryView
│       ├── Settings/        # SettingsView
│       ├── Privacy/         # PrivacySecurityView
│       └── TidyMacApp.swift # Main window, MenuBarExtra, headless CLI interceptor
├── Tests/
│   └── TidyMacTestRunner/   # 357 automated tests covering all modules & E2E fixtures
└── docs/
    ├── plans/               # Master engineering plans
    └── solutions/           # Documented compounding lessons learned
```

---

## 📄 License

Proprietary — All rights reserved. Original branding and implementation of Tidy Mac.
