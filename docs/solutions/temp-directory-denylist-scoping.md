---
module: Safety & PathValidator
tags: [safety, denylist, temp-directory, symlinks, macos]
problem_type: architectural_edge_case
---

# macOS Temp Directory Canonicalization and Denylist Scoping

## Problem Encountered
When testing file operations and trash moves using macOS temp directories (`FileManager.default.temporaryDirectory` or `NSTemporaryDirectory()`), paths resolve to `/var/folders/...` which canonicalize to `/private/var/folders/...`. If the protected denylist unconditionally rejects all prefixes starting with `/var` and `/private`, test fixtures and legitimate per-user temp caches are rejected as system violations.

## Root Cause
macOS stores user-specific caches and temporary files under `/private/var/folders/<hash>/...`. While `/private` and `/var` contain sensitive system directories (`/private/etc`, `/private/var/root`, `/private/var/db`), `/private/var/folders` is specifically user-scoped scratch space.

## Solution & Architecture
1. **Targeted System Root Denylist**:
   Explicitly deny system-critical subpaths: `/private/etc`, `/private/var/root`, `/private/var/db`, `/private/var/log`, `/private/var/vm`, `/private/var/run`, `/etc`, `/System`, `/Library`, `/usr`, `/bin`, `/sbin`.
2. **Explicit Allowed Root Scoping for Per-User Temp**:
   Paths residing within `/private/var/folders/` or `/var/folders/` are blocked by default, BUT permitted if and only if they are explicitly contained within an authorized `allowedRoots` directory passed into `PathValidator.validatePath(url, allowedRoots: ...)`.

## Prevention Rule
Never apply broad prefix blocks on `/var` or `/private` without scoping per-user temp directories (`/private/var/folders`) to explicit caller authorization via `allowedRoots`.
