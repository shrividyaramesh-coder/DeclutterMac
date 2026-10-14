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
- Defaulting the destination directory to an extraneous nested `Organized/` subfolder isolates files away from the user's primary working directory (e.g. `Downloads/Organized/...` instead of directly organizing `Downloads/...`).

## Solution & Architecture
1. **In-Place Organization & Direct Category Rooting**:
   - Destination root defaults directly to the target folder itself (`targetFolder`), organizing loose items in-place into clean subdirectories (`Downloads/Documents`, `Downloads/Media`, `Downloads/Installers`, `Downloads/Archives`).
   - Extraneous wrapper folders (like `Organized/`) are eliminated across the Organizer UI and the AI Agent natural language planner (`PlanExecutor`).
2. **Recursion Loop Protection with In-Place Organizing**:
   - When organizing in-place, naive path prefix checks can accidentally match all files in the target directory. The engine skips files whose parent directory is already the category destination (`parentDir == categoryDestFolder`) and items already filed under recognized top-level categories, while safely migrating loose items and legacy `Organized/` remnants.
3. **Collision-Safe Target Resolution**:
   - `FolderOrganizerEngine.resolveCollisionSafeTarget(for:in:)` detects existing files and appends numbered suffixes non-destructively: `contract (1).pdf`, `contract (2).pdf`.
   - Never overwrites existing destination files under any circumstance.
4. **Learned Category Preferences**:
   - `CategoryPreferencesStore` persists user renames in `UserDefaults` mapped by file extension.
   - When a user renames a proposed category in the UI, future runs automatically apply the user's custom taxonomy to new matching files.
5. **Atomic Multi-File Relocation & Reversibility**:
   - Moves are performed under an atomic `batchId` recorded in `UndoJournal` with action `.moved`.
   - A single click on "Undo" in `HistoryView` reverses all relocations back to their original source locations.

## Prevention Rule
Always organize folders in-place directly into category subfolders without extraneous wrapper directories, prevent recursion loops by checking relative category paths, resolve destination collisions with non-destructive counter suffixes prior to file movement, persist user taxonomy edits for future runs, and log every relocation in the Undo Journal.

