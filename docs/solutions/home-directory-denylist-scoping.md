---
module: Safety & Organizer
tags: [path-validator, denylist-scoping, user-home-directory, dry-run-move, organize]
problem_type: safety_bug_and_behavioral_defect
---

# Home Directory Denylist Scoping & Organization Move Eligibility

## Problem Encountered
1. When organizing folders (e.g. `Downloads`), the engine appeared to complete or run without moving any files on the user's real file system.
2. In the AI Agent planner, general user files (such as `.pdf`, `.docx`, `.xlsx`, `.png`) matching an organization prompt were labeled as "Manual" risk with their checkboxes disabled, and the confirmation button displayed "Confirm & Move to Trash" instead of organizing files.
3. Diagnostic testing revealed `PathValidator.validatePath` threw `SecurityError.protectedPath` on every legitimate file within `~/Downloads`!

## Root Cause
1. **Empty String in `protectedHomeRelativePaths`**:
   - `PathValidator` contained `""` inside `protectedHomeRelativePaths` intended to represent the home root `~` itself.
   - However, the validation loop checked:
     `let fullProtected = relPath.isEmpty ? homePath : "\(homePath)/\(relPath)"`
     `if canonicalPath == fullProtected || canonicalPath.hasPrefix(fullProtected + "/")`
   - When `relPath` was `""`, `fullProtected + "/"` resolved to `/Users/<username>/`.
   - Because EVERY user file inside `Downloads`, `Documents`, `Desktop`, and `Pictures` begins with `/Users/<username>/`, `PathValidator` erroneously blocked every file in the user's home directory.
   - Previous tests passed because test fixtures ran inside temporary directories (`/private/var/folders/...`), which did not begin with `/Users/<username>/`.
2. **Move Plans Constrained by Cleanup Risk Constraints**:
   - `PlanMatchResult.init` set `canExecute = (item.riskLabel != .manual)`.
   - General user files are categorized as `manualReview` to prevent unintended *cleanup/deletion*.
   - When a plan requested `.move` (folder organization), this non-destructive relocation was incorrectly blocked by the deletion safety guard.

## Solution & Architecture
1. **Accurate User Home Root Scoping**:
   - Removed `""` from `protectedHomeRelativePaths`.
   - Retained the strict exact-match check `if canonicalPath == homePath { throw SecurityError.protectedPath(...) }`, preventing any trashing or modification of the root home directory `~` itself while allowing subfolders authorized by `allowedRoots`.
   - Added unit test coverage verifying that valid user files in `~/Downloads` inside `allowedRoots` are explicitly permitted.
2. **Action-Aware Plan Execution**:
   - In `PlanMatchResult.init`, non-destructive `.move` actions allow user document selection and execution, while `.trash` operations continue to enforce the strict `item.riskLabel != .manual` invariant.
   - In `AgentChatView`, dynamically display "Confirm & Organize Files" and "Organize" badges for move plans.
3. **Auto-Analysis & Frictionless Organizer UX**:
   - `FolderOrganizerView` now automatically analyzes the selected folder on load and on folder change, and surfaces an empty state guide when idle.

## Prevention Rule
Never include empty strings in relative-path denylists that form prefix checks; test safety invariants using paths rooted both inside and outside the user home directory; and distinguish non-destructive organization moves from permanent/trash deletion routines.
