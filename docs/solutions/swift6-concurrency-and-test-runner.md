---
module: Core & Localization
tags: [swift6, concurrency, xctest, command-line-tools]
problem_type: architectural_edge_case
---

# Swift 6 Strict Concurrency with Localization & Standalone Test Runner

## Problem Encountered
1. In Swift 6 with `-strict-concurrency=complete`, marking an `ObservableObject` as `@MainActor` prevents synchronous calling of global helper functions like `localized(_ key: String) -> String` from non-isolated contexts (such as enums, background model transformations, or formatters).
2. On macOS systems running only Command Line Tools without `Xcode.app`, `XCTest.framework` is not bundled in the default SDK paths, causing `swift test` with `import XCTest` to fail during module emission.

## Root Cause
1. `@MainActor` isolation on `LocalizationManager.shared.currentLanguage` forces all read accesses to be asynchronous (`await`) unless the caller is also isolated to `@MainActor`.
2. `XCTest` is distributed within `Xcode.app/Contents/Developer/Platforms/MacOSX.platform/...`, not standalone Command Line Tools.

## Solution & Architecture
1. **Thread-Safe Decoupled Store**:
   Implemented `ThreadSafeLanguageStore` backed by `os_unfair_lock`. The string lookup is synchronous, non-isolated, and thread-safe. `LocalizationManager` updates this store and publishes changes on `@MainActor` to trigger SwiftUI updates.
2. **Deterministic Test Runner Target**:
   Created an executable target `TidyMacTestRunner` that executes all test suites directly using Swift's native standard library with structured assertions and non-zero exit codes on failure, ensuring 100% test automation on any macOS environment.

## Prevention Rule
Always back cross-cutting read-only utility lookups (like localization strings) with lock-protected Sendable stores so they can be consumed synchronously from any concurrency domain.
