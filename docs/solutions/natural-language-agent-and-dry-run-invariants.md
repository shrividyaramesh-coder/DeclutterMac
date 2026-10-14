---
module: AgentPlanner & Safety
tags: [natural-language, dry-run, llm, metadata-only, schema-validation, heuristic-parser]
problem_type: safety_and_architecture
---

# Natural-Language Cleanup Agent & Dry-Run Invariants

## Problem Encountered
1. Natural language cleanup requests ("clean old screenshots", "delete downloads") can lead to catastrophic data loss if an LLM is given direct execution authority or file system access.
2. Transmitting document contents or user files to external AI models violates macOS user privacy expectations.
3. Users without an active OpenAI or Anthropic API key or in offline environments would encounter broken features without a heuristic fallback.

## Root Cause
- Directly invoking shell commands or file APIs from unconstrained LLM outputs bypasses safety boundaries.
- Monolithic scanner pipelines lack an intermediate dry-run review stage before file deletion.

## Solution & Architecture
1. **Metadata-Only AI Boundary**:
   - `LLMClient` protocol accepts only `MetadataOnlyRequest` containing `FileMetadataEntry` (filename, extension, size, dates, folder path).
   - Zero file contents, document text, or binary streams can enter the LLM interface.
2. **Offline Heuristic Fallback**:
   - `OfflineHeuristicParser` extracts categories, age thresholds, and size filters locally using regex and semantic rules.
   - `AgentCoordinator` uses the heuristic parser by default and as a resilient fallback if API keys are absent or network requests fail.
3. **Strict Schema Validation**:
   - `CleaningPlanSchema.validate(_:)` validates all generated plans, rejecting empty steps, invalid target folders, and protected system paths (`/`, `/System`, `/Library`, `/usr`).
4. **Mandatory Dry-Run Preview**:
   - `PlanExecutor.dryRun` evaluates candidates against plan filters without touching disk.
   - Items with `RiskLabel.manual` are strictly marked `canExecute = false` and `isSelected = false`.
   - Deletion requires explicit user confirmation, executing solely through `TrashMover` and journaling every action in `UndoJournal`.

## Prevention Rule
Never allow AI models to directly execute filesystem modifications. Enforce a metadata-only input boundary, strict schema validation, offline heuristic fallback, and an interactive dry-run preview prior to confirmed trashing.
