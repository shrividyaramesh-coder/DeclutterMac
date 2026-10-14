---
module: DuplicateEngine & Safety
tags: [duplicates, pipeline, hashing, keep-one, sha256]
problem_type: performance_and_safety_invariant
---

# 3-Tier Duplicate Detection Pipeline and Keep-One Invariant

## Problem Encountered
1. Full cryptographic hashing across large directories with gigabytes of data is extremely I/O intensive and slow.
2. In duplicate cleaning, if an algorithmic bug or user accidental click selects all copies of a file within a cluster, deleting the selection results in complete data loss.

## Root Cause
- Naive duplicate detection hashes every file unconditionally.
- State-level checkbox lists in UI layers without group-level safety checks allow selecting all items in a group.

## Solution & Architecture
1. **Three-Tier Progressive Pipeline**:
   - **Tier 1 (Size Grouping)**: Groups files by exact `fileSize` using metadata only. Discards unique sizes with zero file read.
   - **Tier 2 (Partial Hash)**: Reads first 16 KB and last 16 KB, computing SHA-256. Discards candidate pairs with non-matching boundaries.
   - **Tier 3 (Full SHA-256 Streaming)**: Computes full digest using 64 KB streaming buffers for remaining candidates.
2. **Keep-One Invariant**:
   - `DuplicateGroup.enforceKeepOneInvariant()` guarantees that at least one original copy remains unselected.
   - `DuplicateGroup.setSelection` strictly prevents the user or auto-select routine from selecting the final remaining copy.
   - `DuplicateFinderEngine` asserts `items.filter(\.isSelected).count < items.count` before executing any trash operation.

## Prevention Rule
Always enforce that duplicate clusters retain at least one unselected copy at both the model mutation level and the execution engine boundary.
