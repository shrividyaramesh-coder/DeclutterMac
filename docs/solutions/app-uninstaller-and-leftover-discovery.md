---
module: AppUninstaller
tags: [uninstaller, leftovers, system-protected, bundle-id, safety]
problem_type: safety_and_discovery
---

# App Uninstaller Safety & Leftover Discovery

## Problem Encountered
1. Trashing macOS application bundles naively leaves gigabytes of orphaned data across `~/Library/Application Support`, `~/Library/Caches`, `~/Library/Preferences`, `~/Library/Containers`, and `~/Library/Saved Application State`.
2. Attempting to uninstall system applications or CoreServices (e.g., Finder, Safari, Preview) can destabilize the macOS operating system.
3. Leftovers can match common keywords (e.g., "Apple" or "Microsoft") if matching is done too broadly, risking deletion of shared or critical preference plists.

## Root Cause
- Application bundles on macOS are isolated from their user state directory trees.
- Without a strict system-app denylist and bundle identifier anchoring, leftover scanners can falsely target system files or miss app-specific directories.

## Solution & Architecture
1. **System Protection Guard**:
   - `InstalledApp.isSystemProtected` checks if the app is located in `/System`, `/System/Library`, `/System/Applications`, `/Applications/Utilities`, or matches `com.apple.*` bundle identifiers.
   - Any app marked `isSystemProtected` cannot be uninstalled or selected for leftover cleanup.
2. **Leftover Search Anchoring**:
   - `AppUninstallerEngine` searches standard user library directories (`Application Support`, `Caches`, `Preferences`, `Containers`, `Saved Application State`, `Logs`, `HTTPStorages`).
   - Leftovers must match the exact `bundleIdentifier` (e.g., `com.company.app`) or formatted bundle name folder (`<bundleId>.savedState`), avoiding loose substring matching.
3. **Atomic Multi-Item Trashing via UndoJournal**:
   - Trashing both the `.app` bundle and its associated leftovers is wrapped in a single `batchId` within `UndoJournal`, allowing single-click total restoration if the user uninstalls by mistake.

## Prevention Rule
Always lock system applications against uninstallation and anchor leftover discovery to verified bundle identifiers and known application support paths.
