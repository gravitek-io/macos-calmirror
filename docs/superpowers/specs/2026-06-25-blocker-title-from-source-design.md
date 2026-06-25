# Blocker title derived from the source event

Date: 2026-06-25
Status: Approved

## Problem

Today every mirrored ("blocker") event uses a single, generic, per-rule label
(`blockerLabel`, default `"Busy"`). The label never reflects the source event,
so a destination calendar shows a wall of identical "Busy" blocks. The user
wants the blocker to carry the source event name by default, while still being
able to opt back into a fixed, customizable placeholder.

## Goal

Each `MirrorRule` chooses between two ways of titling its blockers:

| Mode | `usePlaceholder` | Blocker title |
|------|------------------|---------------|
| **Source name** (default) | `false` | `[<RuleTitle>] <source event name>` |
| **Source name, empty source title** | `false` | `[<RuleTitle>] (No title)` |
| **Placeholder** | `true` | `blockerLabel` (free text, suggested default `[<RuleTitle>] Busy`) |

- In source-name mode the `[<RuleTitle>]` prefix is **computed at sync time**, so
  it always reflects the rule's current title.
- In placeholder mode `blockerLabel` is free text. When the user ticks the
  "use placeholder" box, the field is pre-filled with `[<RuleTitle>] Busy` as a
  suggestion but is fully editable. Renaming the rule afterwards does **not**
  rewrite a placeholder's `[...]` prefix (it is plain stored text).

## Privacy impact (deliberate)

The current design copies **no** source data — only times. This change
introduces copying the source event **title** (and only the title) by default.
Location, notes, attendees, URL, alarms and recurrence remain stripped. The
privacy comment in `CalendarService.createBlockerEvent` and the README must be
updated to reflect that the title is now mirrored in source-name mode.

## Migration of existing rules

Persisted rules have no `usePlaceholder` field. To avoid silently turning an
existing user's "Busy" blockers into titles that reveal their events:

- **New rule** (constructed via the initializer) → `usePlaceholder = false`
  (source name = the new desired default).
- **Existing persisted rule** (decoded without the field) → `usePlaceholder = true`,
  preserving its current "Busy"-only behavior.

So only rules created after this change adopt the new default; existing
configurations keep behaving as before.

## Propagation of source renames

The user wants a source rename to update the existing blocker.

- `ContentHasher.computeContentHash` will include the **computed blocker title**
  in addition to start/end/all-day. A source rename changes the computed title →
  the hash changes → the blocker is updated. In placeholder mode the computed
  title is constant, so renames cause no needless updates.
- The update path (`updateBlockerEvent`) will now also write the title (today it
  only updates the dates).
- One-time effect: on the first sync after upgrade, every existing blocker is
  rewritten once because the title now participates in the hash. No visible
  consequence.

## Validation

`emptyLabel` is an error **only** when `usePlaceholder == true`. In source-name
mode an empty `blockerLabel` is harmless and accepted.

## Affected files

- `Sources/CalmMirrorCore/Models/MirrorRule.swift`
  - new `usePlaceholder: Bool`
  - helper `blockerTitle(forSourceTitle:)` (pure, testable, no EventKit)
  - `CodingKeys` + custom decoder (fallback `usePlaceholder = true`)
  - conditional label validation
- `Sources/CalmMirrorCore/Engine/ContentHasher.swift`
  - include the computed blocker title in the hash
- `Sources/CalmMirrorCore/Engine/SyncEngine.swift`
  - `computeDiff` receives the rule and computes each blocker title
  - create path: title from `rule.blockerTitle(forSourceTitle: event.title)`
  - update path: pass the computed title
- `Sources/CalmMirrorCore/Calendar/CalendarService.swift`
  - `updateBlockerEvent` accepts/writes the title; update privacy comment
- `Sources/CalmMirrorApp/Views/RuleEditorView.swift`
  - `Toggle` "Use a fixed placeholder" + conditional placeholder `TextField`
    (pre-filled `[<title>] Busy`), conditional validation, explanatory note in
    source-name mode
- `Sources/calmirror/CLI.swift`
  - `--use-placeholder` flag (parity), keep `--label`
- `README.md` — document the two modes and the privacy nuance
- Tests: `MirrorRuleTests`, `ContentHasherTests`, `RuleStoreTests`

## Out of scope

- No mirroring of any source field other than the title.
- No retroactive UI to bulk-rewrite historical blockers (the hash change does it
  naturally on the next sync).

## Local testing & release

- Dedicated PR from branch `feat/blocker-title-from-source`.
- Local test instructions provided to the user before merge.
- After the user validates locally, a new git tag is cut.
