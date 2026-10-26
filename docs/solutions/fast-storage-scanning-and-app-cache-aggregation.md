---
module: StorageScanner & CleanupView
tags: [performance, caching, concurrency, dirent, swift6]
problem_type: architectural_optimization
---

# Fast Storage Scanning, App Cache Aggregation, and UI Update Batching

## 1. Problem Description
Clean Up scanning previously experienced severe slowness, hangs, and UI freezing on machines with active usage.
Investigation revealed multiple cascading bottlenecks:
1. **Unbounded Traversal of Deep App Caches**: On macOS machines, `~/Library/Caches` regularly contains over 200,000 individual cache chunk files (e.g. Google Chrome alone maintains >100,000 files in `Cache_Data`).
2. **Kernel `lstat` Thrashing**: For every individual file, `PathValidator.validatePath` invoked `resolvingSymlinksInPath()` on both the file URL and all `allowedRoots`, totaling over 1,500,000 system calls.
3. **Black-Hole Directory Recursion**: Scanning user folders (`~/Documents`, `~/Downloads`) descended into developer project trees (`node_modules`, `.git`, `Pods`, `.build`, `DerivedData`).
4. **Main Thread Thrashing**: In `CleanupView`, every single file discovery triggered an individual `await MainActor.run { self.appState.scannedItems.append(item) }`, firing over 200,000 `@Published` diffing events and causing $O(N^2)$ recalculations in `groupedCategories()` and `indicesForCategory()`.

## 2. Root Cause Analysis
- Cleaning tools (CleanMyMac, DaisyDisk, OnyX) operate on app cache bundles atomically (e.g. "Google Chrome Cache", "Spotify Cache"), rather than presenting hundreds of thousands of loose 4KB binary files to the user.
- Enumerating subfiles without `.skipsHiddenFiles` and without calling `enumerator.skipDescendants()` wasted 99% of CPU time in non-actionable subdirectories.
- Dispatching single items individually onto `@MainActor` in a tight asynchronous loop overwhelmed SwiftUI view updates.

## 3. Implemented Solution
1. **App Cache Aggregation (`~/Library/Caches`)**:
   - When encountering a directory directly under `Library/Caches` (e.g. `com.spotify.client`, `Google`, `com.apple.Safari`), compute its folder size rapidly via POSIX dirent, emit a single aggregated `FileItem`, and call `enumerator.skipDescendants()`.
   - Prunes over 210,000 subfiles into ~50-120 actionable app bundles.
2. **Developer Dependencies & Black-Hole Pruning**:
   - In any scanned folder, directories matching `node_modules`, `.git`, `Pods`, `.build`, `DerivedData`, `.cargo`, `.gradle`, or `.venv` trigger immediate `enumerator.skipDescendants()`.
   - In `~/Library/Developer/Xcode/DerivedData`, each project is sized atomically and pruned.
3. **Precomputed Canonical Roots & Fast Path Validation**:
   - Pre-canonicalize `allowedRoots` once via `PathValidator.canonicalizeRoots(folders)` at scan start rather than re-evaluating on every file.
   - Use `PathValidator.isPathAllowedFast` to bypass repeated `resolvingSymlinksInPath()` for non-symlink paths.
4. **POSIX Darwin `fastFolderSize`**:
   - Utilizes `opendir` and `readdir` (`struct dirent`) to sum byte sizes directly from Darwin libc without allocating intermediate `NSURL` objects or Objective-C reflection bridges.
5. **Batching UI Updates**:
   - In `CleanupView`, buffer `itemDiscovered` events into batches (up to 25 items or every 100ms) before dispatching to `MainActor`.
   - Throttle `scanStatusText` progress updates to at most once per 100ms.

## 4. Verification & Results
- `~/Library/Caches` scan time dropped from minutes / freezing down to **0.58s** across 8.44 GB and 210,000+ underlying files.
- UI maintains steady 60fps with zero main thread hangs or sluggishness.
- All 568 automated unit, fixture, and benchmark tests in `TidyMacTestRunner` pass cleanly.
