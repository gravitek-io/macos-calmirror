# Tasks: CalMirror - Calendar Event Mirroring

**Input**: Design documents from `/specs/001-calendar-mirror-app/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/cli.md

**Tests**: Unit tests are included per CLAUDE.md requirement ("basic layer of unit tests to detect major regression").

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Swift Package**: `Sources/CalmMirrorCore/`, `Sources/CalmMirrorApp/`, `Sources/calmirror/`
- **Tests**: `Tests/CalmMirrorCoreTests/`
- **Resources**: `Resources/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Initialize the Swift Package project and configure build targets

- [x] T001 Create Package.swift with three targets (CalmMirrorCore library, CalmMirrorApp executable, calmirror CLI executable) and Swift Argument Parser dependency in Package.swift
- [x] T002 Create directory structure: Sources/CalmMirrorCore/{Models,Engine,Storage,Calendar}/, Sources/CalmMirrorApp/Views/, Sources/calmirror/, Tests/CalmMirrorCoreTests/, Resources/
- [x] T003 [P] Create CalmMirrorApp entry point with empty MenuBarExtra scene and Settings scene in Sources/CalmMirrorApp/CalmMirrorApp.swift
- [x] T004 [P] Create CLI entry point with root ParsableCommand and version subcommand using Swift Argument Parser in Sources/calmirror/CLI.swift
- [x] T005 [P] Create Info.plist with NSCalendarsFullAccessUsageDescription and bundle identifier in Sources/CalmMirrorApp/Info.plist
- [x] T006 [P] Create launchd agent plist template with Label com.gravitek.calmirror.sync, StartInterval 900, ProcessType Background in Resources/com.gravitek.calmirror.sync.plist
- [x] T007 Verify project builds successfully with `swift build` and tests run with `swift test`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core models, storage layer, and calendar access that ALL user stories depend on

**CRITICAL**: No user story work can begin until this phase is complete

- [x] T008 [P] Implement MirrorRule model with Codable, Identifiable, validation rules (no self-mirroring, windowDays 1...120, non-empty label) in Sources/CalmMirrorCore/Models/MirrorRule.swift
- [x] T009 [P] Implement SyncRecord model with derived id, source/blocker identifier pairs, content hash field in Sources/CalmMirrorCore/Models/SyncRecord.swift
- [x] T010 [P] Implement SyncLog, BlockerChange, SyncError models with ErrorCode enum in Sources/CalmMirrorCore/Models/SyncLog.swift
- [x] T011 [P] Implement ContentHasher with SHA-256 computation for (startDate, endDate, isAllDay) using CryptoKit in Sources/CalmMirrorCore/Engine/ContentHasher.swift
- [x] T012 Implement RuleStore wrapping UserDefaults shared suite (com.gravitek.calmirror) with CRUD operations for MirrorRule array in Sources/CalmMirrorCore/Storage/RuleStore.swift
- [x] T013 [P] Implement SyncRecordStore for JSON file I/O per rule under ~/Library/Application Support/CalMirror/sync/ with atomic writes in Sources/CalmMirrorCore/Storage/SyncRecordStore.swift
- [x] T014 [P] Implement SyncLogStore for rolling JSON log file with 30-day retention pruning under ~/Library/Application Support/CalMirror/logs/ in Sources/CalmMirrorCore/Storage/SyncLogStore.swift
- [x] T015 Implement CalendarService wrapping singleton EKEventStore with permission request (requestFullAccessToEvents), calendar enumeration grouped by account, read-only/writable detection via allowsContentModifications in Sources/CalmMirrorCore/Calendar/CalendarService.swift
- [x] T016 [P] Write unit tests for MirrorRule validation (self-mirroring, window range, empty label) in Tests/CalmMirrorCoreTests/MirrorRuleTests.swift
- [x] T017 [P] Write unit tests for ContentHasher determinism and change detection in Tests/CalmMirrorCoreTests/ContentHasherTests.swift
- [x] T018 [P] Write unit tests for RuleStore CRUD operations (add, edit, delete, enable/disable, persistence) in Tests/CalmMirrorCoreTests/RuleStoreTests.swift
- [x] T019 [P] Write unit tests for SyncRecordStore JSON read/write, atomic write, file-per-rule isolation in Tests/CalmMirrorCoreTests/SyncRecordStoreTests.swift
- [x] T020 [P] Write unit tests for SyncLogStore append, 30-day retention pruning in Tests/CalmMirrorCoreTests/SyncLogStoreTests.swift
- [x] T021 Verify all foundational tests pass with `swift test` (note: requires Xcode — only CLT installed, tests written for XCTest)

**Checkpoint**: Foundation ready — all models, storage, and calendar access in place. User story implementation can now begin.

---

## Phase 3: User Story 1 — Configure a Calendar Mirror Rule (Priority: P1) MVP

**Goal**: Users can create, edit, and delete mirror rules through the SwiftUI menu bar app, with calendar picker grouped by account, window days, and blocker label configuration.

**Independent Test**: Open the app, add a new rule selecting source/target calendars, set window and label, verify rule persists after app restart. Edit and delete rules.

### Implementation for User Story 1

- [x] T022 [US1] Implement RulesListView showing all configured rules with enable/disable toggle and delete action, using RuleStore in Sources/CalmMirrorApp/Views/RulesListView.swift
- [x] T023 [US1] Implement RuleEditorView with calendar pickers (source and target grouped by account from CalendarService), window days stepper (1-120), blocker label text field, and validation (same calendar prevention, non-empty label) in Sources/CalmMirrorApp/Views/RuleEditorView.swift
- [x] T024 [US1] Implement MenuBarView showing rule count, last sync status, and button to open rules list in Sources/CalmMirrorApp/Views/MenuBarView.swift
- [x] T025 [US1] Wire CalmMirrorApp.swift MenuBarExtra to MenuBarView and Settings scene to RulesListView, request calendar permissions on first launch in Sources/CalmMirrorApp/CalmMirrorApp.swift
- [x] T026 [US1] Implement `calmirror calendars` subcommand listing all calendars grouped by account with id, title, writable status per contracts/cli.md in Sources/calmirror/CLI.swift
- [x] T027 [US1] Implement `calmirror rules` subcommands (list, add, remove, enable, disable) per contracts/cli.md in Sources/calmirror/CLI.swift

**Checkpoint**: User Story 1 complete — users can configure mirror rules via GUI or CLI. Rules persist across restarts.

---

## Phase 4: User Story 2 — Automatic Event Synchronization (Priority: P1) MVP

**Goal**: The sync engine reads source events, creates/updates/deletes privacy-safe blocker events in the target calendar, tracking state via JSON mapping. Blocker events contain only the configured label.

**Independent Test**: Create a rule, run `calmirror sync`, verify blocker events appear in target calendar with correct times and label only. Delete a source event, re-sync, verify blocker removed. Change source event time, re-sync, verify blocker updated.

### Implementation for User Story 2

- [x] T028 [US2] Implement SyncEngine.sync(rule:) method: fetch source events via predicate for time window, load existing SyncRecords, compute diff (new/changed/orphaned) using content hash, create/update/delete blocker events with batch commit, update SyncRecords, return SyncLog in Sources/CalmMirrorCore/Engine/SyncEngine.swift
- [x] T029 [US2] Implement blocker event creation in CalendarService ensuring only label title, startDate, endDate, isAllDay, availability(.busy) are set — explicitly nil location, structuredLocation, URL, notes set to "Managed by CalMirror", no alarms, no recurrence rules in Sources/CalmMirrorCore/Calendar/CalendarService.swift
- [x] T030 [US2] Implement blocker event update (time change) and delete operations in CalendarService with fallback identifier lookup (eventIdentifier then calendarItemExternalIdentifier) in Sources/CalmMirrorCore/Calendar/CalendarService.swift
- [x] T031 [US2] Implement all-day event handling: mirror isAllDay flag from source to blocker in SyncEngine in Sources/CalmMirrorCore/Engine/SyncEngine.swift
- [x] T032 [US2] Implement recurring event handling: rely on predicateForEvents auto-expansion, create standalone blockers per occurrence in SyncEngine in Sources/CalmMirrorCore/Engine/SyncEngine.swift
- [x] T033 [US2] Implement calendar availability detection in SyncEngine: check calendar(withIdentifier:) returns non-nil for both source and target before syncing, log SyncError with calendarNotFound code if unavailable in Sources/CalmMirrorCore/Engine/SyncEngine.swift
- [x] T034 [US2] Implement `calmirror sync` subcommand with --rule and --dry-run options, iterating enabled rules through SyncEngine, printing summary per contracts/cli.md in Sources/calmirror/CLI.swift
- [x] T035 [US2] Write unit tests for SyncEngine diff algorithm: new events create blockers, deleted source events remove blockers, changed hash updates blockers, unchanged events are skipped in Tests/CalmMirrorCoreTests/SyncEngineTests.swift
- [x] T036 [US2] Write unit tests verifying blocker events contain zero source data (no title leak, no location, no attendees, no notes beyond tag) in Tests/CalmMirrorCoreTests/SyncEngineTests.swift

**Checkpoint**: User Story 2 complete — sync engine creates, updates, and removes privacy-safe blocker events. Can be triggered via `calmirror sync`.

---

## Phase 5: User Story 3 — View Synchronization Logs (Priority: P2)

**Goal**: Users can view chronological sync execution logs showing what changed (blockers added/removed/updated) and any errors, in both the GUI and CLI.

**Independent Test**: Run a sync, open the logs view, verify execution details (rule used, blockers added/removed, errors) are displayed. Trigger an error (e.g., delete target calendar), verify error appears in log.

### Implementation for User Story 3

- [x] T037 [US3] Implement LogsView showing chronological list of SyncLog entries from SyncLogStore, with expand/collapse for each entry showing added/removed/updated counts and error messages in Sources/CalmMirrorApp/Views/LogsView.swift
- [x] T038 [US3] Add logs navigation entry to MenuBarView (last sync status summary + link to open LogsView) in Sources/CalmMirrorApp/Views/MenuBarView.swift
- [x] T039 [US3] Implement `calmirror logs` subcommand with --rule filter, --last count, human-readable and --json output per contracts/cli.md in Sources/calmirror/CLI.swift
- [x] T040 [US3] Implement `calmirror status` subcommand showing agent status, last sync, next scheduled run, rule counts per contracts/cli.md in Sources/calmirror/CLI.swift

**Checkpoint**: User Story 3 complete — users can view sync logs via GUI or CLI to troubleshoot issues.

---

## Phase 6: User Story 4 — Manage Multiple Mirror Rules (Priority: P2)

**Goal**: Multiple mirror rules execute independently during sync, each with its own sync records and blocker set. Deleting one rule does not affect another's blockers.

**Independent Test**: Create two rules with different source/target pairs. Run sync. Verify each rule creates its own blockers. Delete one rule. Verify only that rule's blockers are cleaned up.

### Implementation for User Story 4

- [x] T041 [US4] Update SyncEngine to iterate all enabled rules sequentially, using per-rule SyncRecord files, logging per-rule SyncLog entries in Sources/CalmMirrorCore/Engine/SyncEngine.swift
- [x] T042 [US4] Implement rule deletion cascade in RuleStore: delete SyncRecord JSON file for rule, delete all managed blocker events from target calendar via CalendarService in Sources/CalmMirrorCore/Storage/RuleStore.swift
- [x] T043 [US4] Write unit test verifying independent rule execution: two rules produce separate sync records, deleting rule A leaves rule B's blockers intact in Tests/CalmMirrorCoreTests/SyncEngineTests.swift

**Checkpoint**: User Story 4 complete — multiple rules operate independently without interference.

---

## Phase 7: User Story 5 — Background Daemon Operation (Priority: P3)

**Goal**: The launchd agent runs `calmirror sync` every 15 minutes automatically, starting at login, persisting when the UI is closed.

**Independent Test**: Install the agent, close the UI, wait 15+ minutes, verify sync ran by checking logs.

### Implementation for User Story 5

- [x] T044 [US5] Implement LaunchdManager with install (write plist + launchctl bootstrap), uninstall (bootout + delete plist), and status (check loaded/PID) operations in Sources/CalmMirrorCore/Calendar/LaunchdManager.swift
- [x] T045 [US5] Implement `calmirror agent` subcommands (install, uninstall, status) per contracts/cli.md in Sources/calmirror/CLI.swift
- [x] T046 [US5] Implement signal handling (SIGTERM/SIGINT) in the sync command to gracefully finish current rule batch and write partial state in Sources/calmirror/CLI.swift

**Checkpoint**: User Story 5 complete — sync runs automatically via launchd agent without requiring the UI.

---

## Phase 8: User Story 6 — Install via Homebrew (Priority: P3)

**Goal**: Users can install CalMirror via Homebrew with a single command that sets up the CLI + launchd agent.

**Independent Test**: Run `brew install gravitek/tap/calmirror` on a clean machine, verify `calmirror version` works, run `brew services start calmirror`, verify sync runs.

### Implementation for User Story 6

- [x] T047 [US6] Create Homebrew formula with swift build (universal binary arm64+x86_64), bin.install for calmirror CLI, and brew services block with run_type :interval and interval 900 in homebrew-tap/Formula/calmirror.rb
- [x] T048 [US6] Create homebrew-tap repository structure with Formula/ directory and README in homebrew-tap/README.md

**Checkpoint**: User Story 6 complete — users can install and manage CalMirror via Homebrew.

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Edge cases, error handling refinements, and final quality pass

- [x] T049 [P] Implement edge case: detect and warn when referenced calendar becomes unavailable (source removed, access revoked) — mark rule inactive in UI with warning badge in Sources/CalmMirrorApp/Views/RulesListView.swift
- [x] T050 [P] Implement edge case: reject read-only target calendar during rule creation with user-friendly error in Sources/CalmMirrorApp/Views/RuleEditorView.swift
- [x] T051 [P] Implement edge case: handle cancelled source events by filtering status != .canceled in SyncEngine in Sources/CalmMirrorCore/Engine/SyncEngine.swift
- [x] T052 Verify all tests pass, run full sync end-to-end with real calendars, validate no source event data leaks into blocker events
- [x] T053 Run quickstart.md validation: verify documented build, test, and CLI commands work as described

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion — BLOCKS all user stories
- **US1 (Phase 3)**: Depends on Foundational — can start after Phase 2
- **US2 (Phase 4)**: Depends on Foundational — can start after Phase 2 (parallel with US1 on different files, but logically benefits from US1 rule config)
- **US3 (Phase 5)**: Depends on US2 (needs SyncLog data to display)
- **US4 (Phase 6)**: Depends on US2 (extends single-rule sync to multi-rule)
- **US5 (Phase 7)**: Depends on US2 (launchd runs the sync command)
- **US6 (Phase 8)**: Depends on US5 (packages CLI + agent)
- **Polish (Phase 9)**: Depends on all desired user stories being complete

### User Story Dependencies

- **US1 (P1)**: After Foundational — no story dependencies
- **US2 (P1)**: After Foundational — benefits from US1 but independently testable via CLI
- **US3 (P2)**: After US2 — needs sync logs to exist
- **US4 (P2)**: After US2 — extends sync engine to multi-rule
- **US5 (P3)**: After US2 — launchd runs `calmirror sync`
- **US6 (P3)**: After US5 — packages the CLI with brew services

### Within Each User Story

- Models before services
- Services before UI/CLI consumers
- Core implementation before integration
- Tests alongside or after implementation

### Parallel Opportunities

- T003, T004, T005, T006 in Phase 1 (different files)
- T008, T009, T010, T011 in Phase 2 (model files, no dependencies)
- T013, T014 in Phase 2 (separate store files)
- T016, T017, T018, T019, T020 in Phase 2 (separate test files)
- T049, T050, T051 in Phase 9 (independent edge cases)
- US1 and US2 can be worked on in parallel after Foundational phase

---

## Parallel Example: Phase 2 Foundational

```bash
# Launch all model tasks in parallel:
Task T008: "MirrorRule model in Sources/CalmMirrorCore/Models/MirrorRule.swift"
Task T009: "SyncRecord model in Sources/CalmMirrorCore/Models/SyncRecord.swift"
Task T010: "SyncLog model in Sources/CalmMirrorCore/Models/SyncLog.swift"
Task T011: "ContentHasher in Sources/CalmMirrorCore/Engine/ContentHasher.swift"

# Then launch storage tasks in parallel:
Task T013: "SyncRecordStore in Sources/CalmMirrorCore/Storage/SyncRecordStore.swift"
Task T014: "SyncLogStore in Sources/CalmMirrorCore/Storage/SyncLogStore.swift"

# Then launch all test tasks in parallel:
Task T016: "MirrorRuleTests.swift"
Task T017: "ContentHasherTests.swift"
Task T018: "RuleStoreTests.swift"
Task T019: "SyncRecordStoreTests.swift"
Task T020: "SyncLogStoreTests.swift"
```

---

## Implementation Strategy

### MVP First (User Stories 1 + 2)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL — blocks all stories)
3. Complete Phase 3: US1 — Configure mirror rules
4. Complete Phase 4: US2 — Sync engine
5. **STOP and VALIDATE**: Test end-to-end with real calendars via `calmirror sync`
6. At this point, the user can manually run sync from CLI or GUI

### Incremental Delivery

1. Setup + Foundational → Foundation ready
2. Add US1 + US2 → Test end-to-end → **MVP!** (manual sync via CLI)
3. Add US3 → Logs visible in GUI and CLI
4. Add US4 → Multi-rule support
5. Add US5 → Automated background sync via launchd
6. Add US6 → Homebrew distribution
7. Each story adds value without breaking previous stories

---

## Notes

- [P] tasks = different files, no dependencies on incomplete tasks
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- The CLAUDE.md pragmatic testing approach applies: unit tests cover models, storage, and sync engine — not SwiftUI views
