---
module: branding-and-distribution
tags: [rebrand, packaging, vercel, domain, iconography]
problem_type: rebrand_architecture
---

# Rebranding to Declutter Mac and Unified Distribution Architecture

## Context
The application was rebranded from "Tidy Mac" to "Declutter Mac" after acquiring the premium domain `decluttermac.com`. The transition required end-to-end updates across the native macOS codebase, UI, LaunchAgent daemons, localization string catalogues, distribution bundles, web collateral, and custom iconography.

## Architecture & Implementation Strategy

1. **Localization & UI Identity**:
   - Updated `LocalizedStrings.swift` across all 8 supported languages (`en`, `fr`, `de`, `ja`, `ko`, `zh-Hans`, `zh-Hant`, `es`) so `app.name` resolves to `Declutter Mac`.
   - Updated Menubar extra, settings view, onboarding copy, and agent chat views.
   - Updated LaunchAgent identifier to `com.decluttermac.cleanup` and log paths to `Library/Logs/DeclutterMac`.

2. **Modern Mac Iconography**:
   - Designed a new high-resolution icon in `scripts/generate_icon.swift` using CoreGraphics.
   - Features an Apple Silicon display silhouette on an obsidian squircle with radiant cyan-to-emerald declutter sweep and aligned floating file cards.
   - Automatically compiles into `build/AppIcon.icns` for the application bundle and `web/app-icon.png` (1024x1024) for the website.

3. **Packaging & Backward-Compatible Distribution**:
   - `scripts/package_app.sh` compiles and signs `build/DeclutterMac.app` with `com.decluttermac.app` bundle ID.
   - Packages `DeclutterMac.dmg` and `DeclutterMac.zip`.
   - Generates backward-compatible aliases for `TidyMac.dmg` and `TidyMac.zip` so existing links and downloaders never break.
   - Configured `vercel.json` and `web/vercel.json` for seamless deployment under `decluttermac.com`.
