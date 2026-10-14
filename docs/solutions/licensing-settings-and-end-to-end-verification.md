---
module: Licensing, Settings, & Fixture Verification
tags: [licensing, trial, settings, privacy, fixture, end-to-end]
problem_type: architectural_integration
---

# Licensing, Settings, Privacy Architecture, & End-to-End Fixture Verification

## Problem Encountered
1. Monetization architectures often intertwine tightly with core engines, making local offline usage and headless automated testing brittle or dependent on network mocking.
2. Users require transparent visibility into licensing allowances (2 GB free tier, 15-day trial) and strict privacy guarantees (local scanning, metadata-only AI boundary, protected denylist).
3. Without a holistic end-to-end integration test against realistic filesystem fixtures, regressions in component interactions (scanner -> duplicates -> trash -> undo -> licensing) can go unnoticed.

## Root Cause
- Hard-coding StoreKit or remote billing services directly inside the cleanup workflow prevents clean local testing and app distribution flexibility.
- Complex path handling on macOS (symlinks between `/var/folders` and `/private/var/folders`) can cause pointer equality mismatches in test harnesses if canonical resolution isn't uniformly applied.

## Solution & Architecture
1. **Decoupled LicenseProvider Protocol**:
   - `LicenseProvider` protocol with `currentStatus()`, `recordCleanedBytes(_:)`, `unlockLifetime(key:)`, and `restorePurchases()`.
   - `LocalLicenseProvider` implements a default 2 GB free cleaning allowance and 15-day full-access trial, ready to be backed by StoreKit 2 in production.
2. **Dedicated Settings & Privacy Screens**:
   - `SettingsView` provides live 8-language localization switching, AI provider configuration with Keychain credential storage, and managed folder inspection.
   - `PrivacySecurityView` presents plain-language privacy guarantees matching code-enforced invariants (100% local scanning, metadata-only LLM boundary, Trash-only deletion, protected denylist).
3. **Master End-to-End Fixture Suite**:
   - `EndToEndFixtureTests` constructs a complete simulated macOS user directory with caches, logs, installers, screenshots, 3-tier duplicates, cloud placeholders, and sensitive identity files (`~/.ssh`, `Keychains`).
   - Verifies the full pipeline: scan -> duplicate keep-one detection -> safe trashing -> protected path preservation -> byte-for-byte undo restoration -> allowance tracking -> lifetime unlock.

## Prevention Rule
Always isolate billing behind a protocol with local allowance fallbacks, resolve symlinks canonically when comparing filesystem paths, and maintain an end-to-end fixture test verifying the complete user lifecycle.
