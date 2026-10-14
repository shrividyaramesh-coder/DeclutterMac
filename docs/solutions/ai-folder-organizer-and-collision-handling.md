---
module: FolderOrganizer & Storage
tags: [organizer, taxonomy, collision-avoidance, learned-preferences, undo-restoration]
problem_type: safety_and_architecture
---

# AI Folder Organizer, Collision Handling, & Preference Learning

## Problem Encountered
1. When organizing folders automatically (e.g. `Downloads` or `Documents`), moving files into target directories can overwrite existing files sharing the same name.
2. Static classification schemes fail to adapt when users prefer specific categorization structures (e.g. classifying `.pdf` under `Finance/Tax_2025` rather than generic `Documents/PDFs`).
3. If an organization operation reorganizes hundreds of files, reversing the entire operation by hand is virtually impossible.

## Root Cause
- Standard `FileManager.moveItem(at:to:)` throws if the destination path already exists and cannot generate non-destructive suffixes automatically.
- Without a persistent preference store, customized user taxonomy is lost on subsequent runs.
- Without recording the original paths in an undo journal, reverse relocation cannot be automated.

## Solution & Architecture
1. **Collision-Safe Target Resolution**:
   - `FolderOrganizerEngine.resolveCollisionSafeTarget(for:in:)` detects existing files and appends numbered suffixes non-destructively: `contract (1).pdf`, `contract (2).pdf`.
   - Never overwrites existing destination files under any circumstance.
2. **Learned Category Preferences**:
   - `CategoryPreferencesStore` persists user renames in `UserDefaults` mapped by file extension.
   - When a user renames a proposed category in the UI, future runs automatically apply the user's custom taxonomy to new matching files.
3. **Atomic Multi-File Relocation & Reversibility**:
   - Moves are performed under an atomic `batchId` recorded in `UndoJournal` with action `.moved`.
   - A single click on "Undo" in `HistoryView` reverses all relocations back to their original source locations.

## Prevention Rule
Always resolve destination collisions with non-destructive counter suffixes prior to file movement, persist user taxonomy edits for future runs, and log every relocation in the Undo Journal.
