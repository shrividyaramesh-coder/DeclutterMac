# AGENTS.md — Tidy Mac Engineering Guide & Operational Context

This document outlines the architecture, coding standards, commands, and core safety invariants for **Tidy Mac**. All engineering agents and contributors must adhere to these directives.

---

## 1. Project Overview & Role

**Tidy Mac** is a native macOS application built with Swift 6 and SwiftUI (targeting macOS 14+). It provides safe storage cleanup, duplicate file removal, app uninstallation, natural language cleanup planning, and AI folder organization.

Development strictly follows **Compound Engineering**:
- **80% Planning & Review, 20% Execution**.
- Every bug, unexpected edge case, or critical architectural decision is recorded in `docs/solutions/` and summarized in the **Lessons Learned** section below.
- Knowledge compounds: each completed task informs and accelerates subsequent tasks.

---

## 2. Core Safety Invariants (Non-Negotiable)

1. **Trash-Only Deletion**:
   - Files are moved to the user's Trash via `FileManager.default.trashItem(at:resultingItemURL:)` or security-scoped equivalents.
   - Permanent deletion (`removeItem`, `unlink`, `rm -rf`) is **strictly forbidden** in production cleanup code.
2. **Hard-Coded Protected Paths Denylist**:
   - Under no circumstances can files be modified or trashed within system directories (`/System`, `/Library`, `/usr`, `/bin`, `/sbin`, `/private`, `/etc`, `/var`), the root user home directory (`~`), `.git` repositories, Apple Mail (`~/Library/Mail`), Photos libraries (`*.photoslibrary`), or system keychains.
3. **Canonical Path & Symlink Traversal Protection**:
   - Every file path must be canonicalized (`URL.resolvingSymlinksInPath()`) prior to evaluation.
   - Symlinks resolving outside permitted user-managed folders must be rejected.
   - Path-traversal sequences (`..`, hidden relative links) are caught and rejected by `PathValidator`.
4. **Duplicate Protection**:
   - The duplicate finder must **never** select all copies of a file within a duplicate cluster. At least one original copy must always remain unselected.
5. **Risk Label Enforcements**:
   - Items labeled **Manual** are strictly non-actionable in the UI and engine. They can never be checked, grouped for batch clean, or processed by cleanup routines.
6. **Metadata-Only AI Boundary**:
   - The AI agent (`LLMClient`) must strictly accept only `MetadataOnly` structs (file name, extension, byte size, created/modified dates, relative folder path).
   - Under no circumstances may file contents or file data be read, buffered, or transmitted to any AI provider.
7. **Dry-Run Confirmation**:
   - Natural-language plans and folder organization proposals must execute in dry-run preview first. No file movements or deletions may occur without explicit user confirmation.
8. **Undo Journaling**:
   - Every file modification or trash operation must be recorded in the `UndoJournal` with original location, target location, timestamp, and batch ID, enabling single-click full restoration.

---

## 3. Build & Test Commands

### Swift Package Manager (Primary & CI / CLI)
```bash
# Build all targets in debug mode
swift build

# Build for release
swift build -c release

# Run the complete automated test suite
swift test

# Run tests with parallel execution and verbose output
swift test --parallel -v

# Run a specific test suite (e.g. SafetyTests)
swift test --filter SafetyTests
```

### Xcode / xcodebuild (When Xcode.app is active)
```bash
# Build TidyMac macOS App Target
xcodebuild -scheme TidyMac -configuration Debug build

# Run Xcode Tests
xcodebuild test -scheme TidyMac -destination 'platform=macOS'
```

---

## 4. Coding Conventions & Standards

- **Language & Runtime**: Swift 6, macOS 14.0+ SDK (`@available(macOS 14.0, *)`).
- **Concurrency**: Strict Swift 6 Concurrency (`-strict-concurrency=complete`). Use `actor` for shared mutable state (e.g., `UndoJournal`, `StorageScanner`, `FileAccessService`), and `@MainActor` for ViewModels and UI state.
- **Safety First**: Zero force unwraps (`!`) in production code. Handle all `nil` and errors via typed `Result` or `throws`.
- **Localization**: No hard-coded user-facing strings. All strings use `LocalizedStringResource` or String Catalogs with support for 8 languages: English (`en`), French (`fr`), German (`de`), Japanese (`ja`), Korean (`ko`), Simplified Chinese (`zh-Hans`), Traditional Chinese (`zh-Hant`), Spanish (`es`).
- **Testing**: Every engine module must have accompanying tests in `Tests/TidyMacTests/`. Temp-directory fixtures must be used for file operations; never touch actual user directories during test execution.

---

## 5. Knowledge Store & Compounding

Documented solutions and architectural insights are preserved under `docs/solutions/`:
- `docs/solutions/`: Documented solutions to past problems (bugs, edge cases, best practices, workflow patterns), organized by category with YAML frontmatter (`module`, `tags`, `problem_type`).

### Standing Compounding Directive
At the conclusion of each work unit or whenever a non-obvious bug or edge case is resolved, capture the learning into a note under `docs/solutions/<topic>.md` and add a one-line summary rule to the **Lessons Learned** section below.

---

## 6. Lessons Learned

- **Concurrency & Global Utilities**: Cross-cutting utilities (such as `localized()`) must use a thread-safe Sendable store (e.g. `os_unfair_lock`) rather than pure `@MainActor` so non-isolated model properties can access them synchronously without async hops.
- **CLI Test Reliability**: Standalone `CommandLineTools` lacks `XCTest.framework`; executable test targets like `TidyMacTestRunner` provide deterministic, zero-dependency CI test validation on any macOS machine.
- **Denylist Scoping vs macOS Temp Paths**: `/var/folders` (`/private/var/folders`) hosts macOS per-user temporary directories; rather than a blanket `/var` ban, gate per-user temp access strictly to directories explicitly authorized in `allowedRoots`.
- **Cloud Eviction Defense**: Evicted cloud files (`.icloud` faults) trigger network downloads if opened; always check `ubiquitousItemDownloadingStatusKey` and bypass byte-reading for un-downloaded placeholders.
- **DirectoryEnumerator in Async Contexts**: `FileManager.DirectoryEnumerator.makeIterator()` is unavailable in async contexts in Swift 6; iterate via `while let fileURL = enumerator.nextObject() as? URL` to avoid concurrency safety errors.
- **Selection Safety Guard**: Enforce non-selectability directly within `FileItem.setSelected(_:)`; never allow UI bindings or "Select All" actions to select items marked with `RiskLabel.manual`.
- **Actor State Init & Safe Restoration**: Load persisted actor state using static functions in `init`; when restoring files from Trash, recreate missing parent directories and resolve collisions with a non-destructive counter suffix (`name (restored 1).ext`).
- **Duplicate Keep-One Guard**: Implement 3-tier duplicate detection (size -> partial hash -> full SHA-256) and hard-assert at both model and engine levels that at least one original copy in every duplicate cluster remains unselected.
- **System App & Leftover Isolation**: Refuse to uninstall system apps (`isSystemProtected`), and anchor leftover discovery strictly to exact bundle identifiers across Application Support, Caches, Preferences, and Saved Application State.
- **Metadata-Only AI Boundary & Dry Run**: Restrict LLM input solely to `MetadataOnlyRequest` (zero file contents), validate plan schemas against protected paths, provide offline heuristic fallback, and require interactive dry-run review before trashing.
- **Folder Organization & In-Place Direct Routing**: Organize folders directly into categorized subdirectories in-place without creating redundant wrapper folders (`Organized/`), guard against recursion loops by evaluating parent directories and relative top-level category paths, prevent collisions via incremental suffixes (`file (1).ext`), persist user-edited category preferences, and journal moves under `.moved` for single-click full restoration.
- **Continuous Cleanup & Approved Rule Invariants**: Restrict scheduled runs exclusively to user-approved rules, reject manual-risk items at the trigger evaluation level, and post summary notifications for headless awareness.
- **Licensing Protocol & Canonical Fixture Validation**: Decouple billing behind a local-first `LicenseProvider` protocol (2 GB free tier + 15-day trial), and resolve symlinks canonically (`resolvingSymlinksInPath()`) during end-to-end integration tests on macOS temp directories.
- **LaunchAgent Headless Execution & Ad-Hoc Packaging**: Intercept background daemon calls in `App.init` via `--scheduled-run` to execute headless async cleanup routines without allocating GUI windows, and package native `.app` bundles with ad-hoc signing and CoreGraphics-synthesized `AppIcon.icns` for seamless local deployment.
- **Home Directory Denylist Scoping & Move Eligibility**: Never include empty strings in relative identity denylists that form prefix checks (which inadvertently blocked all user home files), validate safety with real user paths in `allowedRoots`, and distinguish non-destructive organization moves from permanent/trash cleanup constraints.
- **Loose Folder Organization & Lazy UI Performance**: Scan top-level direct items to classify loose folders as intact atomic entities (e.g. project trees and photo bundles) into designated categories, protect reserved category roots from self-nesting loops, and render item lists using `LazyVStack` with collapsible category disclosure cards to preserve instantaneous 60fps UI responsiveness across hundreds of items.
