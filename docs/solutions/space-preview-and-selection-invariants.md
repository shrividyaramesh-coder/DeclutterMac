---
module: Dashboard & Cleanup UI
tags: [ui, space-preview, selection-invariants, swiftui]
problem_type: architectural_design
---

# Space Preview Synchronization and Selection Safety Invariants

## Problem Encountered
When presenting storage cleanup previews to users, inconsistencies between selected bytes, projected disk free space, and post-clean results erode user trust. Additionally, accidental batch selection of sensitive or system files (classified as Manual) could lead to unintended trashing if checkbox bindings don't strictly enforce non-selectability.

## Root Cause
If selection logic relies purely on boolean state variables in the view layer without model-level invariants, select-all or batch actions can inadvertently tick protected items.

## Solution & Architecture
1. **Model-Enforced Non-Selectability**:
   `FileItem.setSelected(_:)` verifies `riskLabel.isSelectable` prior to mutating `isSelected`. If `riskLabel == .manual`, `isSelected` is permanently forced to `false`.
2. **Deterministic Projected Free Space**:
   Calculated as `currentFreeBytes + selectedCleanupBytes`. The three-card banner displays Current Free Space, Selected for Cleanup, and Projected Free Space side by side with real-time updates.
3. **Select Recommended Preset**:
   The "Select Recommended" action strictly ticks only `.safe` items, unchecking `.review` items and keeping `.manual` items disabled.

## Prevention Rule
Never bind SwiftUI toggle checkboxes directly to mutable state without an underlying risk invariant guard prohibiting selection of Manual-risk items.
