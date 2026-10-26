---
title: Freemium Folder Sort Gate and $3.99 Lifetime Unlock
category: licensing
date: 2026-10-26
author: Declutter Mac Engineering
tags: [licensing, freemium, pricing, organizer, vercel]
---

# Freemium Folder Sort Gate & $3.99 Lifetime Unlock

## Context & Requirement
The user requested a freemium pricing structure:
- **Free Allowance**: Users can sort up to 2 messy folders completely free.
- **Paywall / One-Time Cost**: After sorting 2 folders, subsequent organization requires a one-time purchase of **$3.99** for lifetime unlimited access.

## Implementation Details

### 1. Core Licensing Engine (`LocalLicenseProvider.swift`)
- Set `maxFreeFolderSorts = 2`.
- Gated `canSortFolder()`:
  - If `lifetimeKey` is present and valid, returns `true` (unlimited).
  - Otherwise, returns `folderSorts < 2`.
- `recordFolderSort()` increments persisted sort counter in `UserDefaults`.
- `unlockLifetime(key:)` stores valid non-empty license keys and immediately grants unlimited status.

### 2. Folder Organizer UI (`FolderOrganizerView.swift`)
- Gated `applyOrganization()`: checks `await LocalLicenseProvider.shared.canSortFolder()`. If exhausted, opens `showPaywallSheet = true` without executing moves.
- Header status badge dynamically displays:
  - When unlocked: `Lifetime Unlocked` (green).
  - When sorts < 2: `Free: X of 2 sorts left` (accentColor).
  - When sorts >= 2 (locked): Interactive button `2 of 2 Free Sorts Used • Unlock ($3.99)` (orange) which directly summons the paywall sheet.
- Paywall sheet provides $3.99 lifetime license overview, direct license key input field, instant activation button, and web checkout button linking directly to `https://www.decluttermac.com#pricing`.

### 3. Settings View (`SettingsView.swift`)
- Displays current edition state (Free Tier vs Lifetime Active).
- Shows real-time counter: `X of 2 Folders Used`.
- Allows entering a $3.99 lifetime key, restoring purchases, or launching online checkout.

### 4. Website & Instant Checkout (`web/index.html`)
- Updated pricing across the site to $3.99 one-time.
- Implemented interactive checkout modal generating `DM-LIFETIME-XXXX-XXXX` license keys, 1-click clipboard copy, and automatic DMG installer download.
- Deployed directly to production on Vercel at `https://decluttermac.com` and `https://www.decluttermac.com`.
