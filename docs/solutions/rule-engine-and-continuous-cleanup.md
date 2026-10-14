---
module: RuleEngine & Scheduling
tags: [rules, templates, continuous-cleanup, scheduling, notifications, safety-invariants]
problem_type: safety_and_architecture
---

# Rule Engine, Continuous Cleanup, & Notification Integration

## Problem Encountered
1. Unattended background cleanup schedules could execute unexpected operations if allowed to run unapproved or destructive actions.
2. Background rules could inadvertently match protected or user-critical files if items labeled with `RiskLabel.manual` were not filtered at the rule evaluation level.
3. Users need clear, non-intrusive notification feedback after scheduled cleanups run while the app window is closed.

## Root Cause
- Decoupling schedule execution from rule approval allows arbitrary or unvalidated cleanup triggers.
- Evaluating rule triggers purely on extension or age without checking `RiskLabel` allows manual-risk items to be deleted.

## Solution & Architecture
1. **Rule Model & Templates Library**:
   - `BuiltInRuleTemplates.defaultRules()` ships 12 built-in rule templates (covering screenshots, installers, archives, caches, logs, derived data).
   - Rules can be enabled, disabled, edited, and manually triggered on demand.
2. **Strict Approval & Risk Guards**:
   - `ScheduleCoordinator` strictly filters `rules.filter(\.isEnabled)` so scheduled runs only execute user-approved rules.
   - `RuleEngine.matches` strictly guards against `RiskLabel.manual`, ensuring protected items are never matched or modified regardless of trigger parameters.
3. **Continuous Scheduling & Notification**:
   - `ScheduleCoordinator` supports `.daily`, `.weekly`, `.monthly`, and `.onLowDiskSpace(thresholdGB:)`.
   - `UserNotificationService` dispatches a summary notification via `UNUserNotificationCenter` reporting total files cleaned and bytes reclaimed with undo availability.

## Prevention Rule
Always restrict scheduled headless cleanups strictly to user-approved rules, reject manual-risk items at the trigger evaluation boundary, and dispatch summary notifications for full user awareness.
