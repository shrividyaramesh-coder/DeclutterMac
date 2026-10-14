---
module: FileAccess & Cloud
tags: [cloud, icloud, dropbox, placeholders, eviction]
problem_type: performance_and_data_trap
---

# Preventing Unintended Cloud Downloads on Evicted Files

## Problem Encountered
When scanning user folders (such as Documents or Desktop) that are synced with iCloud Drive, Dropbox, or OneDrive, reading file contents (e.g. for hashing or metadata extraction) triggers macOS file coordination to automatically download the full file payload. On large libraries, this can trigger massive background network transfers, unexpected battery drain, and storage exhaustion.

## Root Cause
macOS APFS dataless faults (evicted files) report standard file sizes in directory listings, but opening the file descriptor causes the cloud daemon (bird or file provider) to fetch the content over the network.

## Solution & Architecture
1. **Filename Fault Detection**:
   Inspect hidden iCloud placeholder prefix/suffix patterns (`.<filename>.icloud`).
2. **Resource Value Status Checking**:
   Query `.ubiquitousItemDownloadingStatusKey`. If status is `.notDownloaded`, set `isCloudPlaceholder = true`.
3. **Engine-Wide Bypass**:
   Hashing engines, deep scanners, and duplicate finders skip reading byte streams for any file marked `isCloudPlaceholder == true`.

## Prevention Rule
Always check `ubiquitousItemDownloadingStatusKey` and placeholder naming before opening file handles in user-managed folders.
