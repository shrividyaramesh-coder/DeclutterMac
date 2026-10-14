---
module: FolderOrganizer & UI Navigation
tags: [organizer, subfolders, deep-scan, media, images, context-aware-categorization, openpanel]
problem_type: architectural_limitation_and_ux_gap
---

# Subfolder Navigation, Deep Scan, and Context-Aware Smart Organization

## Problem Encountered
When attempting to organize folders, users observed:
1. Files were not showing up in the Organizer when analyzing parent folders (like `Downloads`): because previous runs had grouped files into `Media`, `Documents`, etc., and the engine only inspected direct items at depth 1 while skipping reserved category containers, `Downloads` appeared empty (`"No loose files found in 'Downloads' to organize."`).
2. There was no way to organize specific subfolders (like `Downloads/Media` or `Downloads/Media/Images`) because the UI only provided a static picker with 5 preset root directories and lacked subfolder navigation or a custom folder picker.
3. If an `Images` or `Media` subfolder was analyzed directly, the engine prepended redundant root taxonomy names (`Media/Images/Media/Images`), causing nested subfolder duplication, rather than organizing images by their internal types (AI Generated, Screenshots, Banners, Photos) or dates.

## Root Cause
1. **Single-Depth Inspection & Reserved Root Skipping**:
   - `FolderOrganizerEngine` previously only read immediate items of `targetFolder`. Once files had been categorized into `Downloads/Media/Images`, a subsequent scan of `Downloads` skipped `Media` (as a reserved top-level category container), hiding all 800+ files.
2. **Fixed Root Directory UI**:
   - `FolderOrganizerView` did not expose subfolder drill-downs or an `NSOpenPanel` custom folder chooser, making it impossible for users to target `Downloads/Media` or `Downloads/Media/Images`.
3. **Static Global Taxonomy without Context Awareness**:
   - `defaultCategoryName(forExtension:)` always emitted global prefixes (`Media/Images`, `Documents/PDFs`). When the target folder was already `Media/Images`, moving a file into `destRoot + "Media/Images"` produced duplicated nested paths (`Media/Images/Media/Images`).

## Solution & Architecture
1. **Subfolder Discovery & Navigation**:
   - Implemented `FolderOrganizerEngine.discoverSubfolders(in:maxDepth:)` to dynamically enumerate visible subdirectories (e.g. `Media`, `Media/Images`, `Documents`, `Development`).
   - Added a secondary **Scope / Subfolder Picker** in `FolderOrganizerView`:
     - `All Subfolders (Deep Scan)`: Recursively scans all nested files across subdirectories.
     - `Root Only (Direct Files)`: Inspects only loose items at the root level.
     - `📂 Subfolder drill-down`: Direct 1-click targeting of any discovered subfolder (such as `Media/Images`).
   - Added a **"Browse..." (`NSOpenPanel`)** button allowing users to pick any custom folder or subfolder on their Mac, automatically creating security-scoped bookmarks in `FileAccessService`.
2. **Context-Aware Smart Categorization**:
   - Added `FolderOrganizerEngine.determineCategory(for:isDirectory:targetFolder:strategy:)`:
     - **Images Folder Context** (e.g. `Images`, `Photos`, `Media/Images`): Intelligently categorizes images into `AI Generated` (ChatGPT, Gemini, Midjourney), `Screenshots`, `Banners & Graphics`, and `Photos & Pictures`.
     - **Media Folder Context** (e.g. `Downloads/Media`): Categorizes into `Images`, `Videos`, `Audio`, `Folders` without redundant `Media/` prefixes.
     - **Documents Folder Context**: Categorizes into `PDFs`, `Spreadsheets`, `Text & Notes`, `Presentations` without redundant `Documents/` prefixes.
   - Introduced `OrganizationStrategy` supporting:
     - `Smart Categories`
     - `By Date (Year & Month)` (e.g. `2026-10 (October)`, `2026-08 (August)`)
     - `By File Type` (e.g. `PNG Files`, `JPEG Files`, `PDF Files`)
3. **Category Filtering & Single-Category Execution**:
   - Added horizontal **Category Filter Pills** in the proposal view (`All (N)`, `Media/Images (X)`, `Documents (Y)`).
   - Added a **"Select Only This Category"** button enabling instant one-click selection of just media/images or any chosen category, unchecking all other items.
4. **Collision & Identity Protection**:
   - Checked that items are never moved into themselves or their own destination folder (`itemURL.standardizedFileURL == categoryDestFolder.standardizedFileURL`).

## Prevention Rule
Always provide subfolder drill-down navigation and recursive deep-scan options so users can view and organize nested or previously grouped files, strip redundant parent category prefixes when organizing subfolders directly, and offer category filter pills with "Select Only" actions for targeted single-category organization.
