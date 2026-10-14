---
module: UndoJournal & Storage
tags: [undo, journal, actor-init, swift6, collision-handling, restore]
problem_type: architectural_design
---

# Swift 6 Actor Initializers and Collision-Safe File Restoration

## Problem Encountered
1. In Swift 6, calling an actor-isolated instance method from `init()` triggers:
   `error: call to actor-isolated instance method in a synchronous nonisolated context`.
2. When a user clicks "Undo" to restore previously trashed files, two failure modes can emerge:
   - The original parent directory was deleted or renamed while the file was in Trash.
   - Another file with the exact same name was created at the original location, risking accidental overwrite upon restoration.

## Root Cause
1. During `init`, the actor instance is not yet fully initialized, so calling isolated methods is disallowed to guarantee data race safety.
2. File system state changes between the time an item is trashed and when Undo is executed.

## Solution & Architecture
1. **Static Storage Reader for Actor Init**:
   Implemented `private static func readStorage(from:)` which reads and decodes the persisted JSON synchronously, assigning the loaded properties to `self.runs` and `self.entriesByRun` in `init` without actor isolation violations.
2. **Defensive Re-creation and Collision Handling**:
   - `fileManager.createDirectory(at: destinationDir, withIntermediateDirectories: true)` ensures the target hierarchy exists.
   - `resolveCollisionIfNeeded(for:)` probes `fileExists`. If a collision is detected, it loops to find the first available non-destructive suffix: `file (restored 1).ext`.
   - If an item was emptied from Trash externally by Finder, it is recorded as a warning string in the result tuple without aborting the remaining restorations.

## Prevention Rule
Always use static functions for file loading during actor `init`, and always apply non-destructive collision renaming during file restoration operations.
