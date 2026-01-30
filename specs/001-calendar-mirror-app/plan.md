# Implementation Plan: CalMirror - Calendar Event Mirroring

**Branch**: `001-calendar-mirror-app` | **Date**: 2026-01-30 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/001-calendar-mirror-app/spec.md`

## Summary

CalMirror is a native macOS application that mirrors calendar events from a source calendar to a target calendar as privacy-safe blocker entries. It works exclusively through Apple Calendar (EventKit) to avoid third-party SaaS data exposure. The system consists of a SwiftUI menu bar app for configuration and log viewing, a CLI tool for sync execution, and a launchd agent for automated 15-minute sync cycles.

## Technical Context

**Language/Version**: Swift 5.10+, macOS 14+ (Sonoma)
**Primary Dependencies**: EventKit (calendar access), CryptoKit (content hashing), Swift Argument Parser (CLI)
**Storage**: UserDefaults (shared suite for rules), JSON files (sync state and logs)
**Testing**: XCTest (unit tests on CalmMirrorCore)
**Target Platform**: macOS 14+ (Sonoma)
**Project Type**: Single Swift Package with 3 targets (library, app, CLI)
**Performance Goals**: Sync cycle completes in <30 seconds for 200 events; zero resources between runs
**Constraints**: <50 MB memory during sync; no long-running process; no third-party SaaS dependencies
**Scale/Scope**: Single user, 1-10 mirror rules, up to ~500 events per rule window

## Constitution Check

_GATE: Must pass before Phase 0 research. Re-check after Phase 1 design._

The constitution defines 3 core principles: Clean Architecture, Pragmatic Simplicity, User Experience First.

| Principle              | Status | Evidence                                                                                                       |
| ---------------------- | ------ | -------------------------------------------------------------------------------------------------------------- |
| Clean Architecture     | PASS   | Shared core library with clear boundaries (Models, Engine, Storage, Calendar). UI and CLI are thin consumers.   |
| Pragmatic Simplicity   | PASS   | No third-party dependencies beyond Apple's SPM packages. UserDefaults + JSON files. No database, no ORM.        |
| User Experience First  | PASS   | Menu bar app for zero-friction access. Automated sync with zero user intervention. Privacy-first blocker design. |

**Post-Phase 1 re-check:**

| Principle              | Status | Post-Design Evidence                                                                                                                       |
| ---------------------- | ------ | ------------------------------------------------------------------------------------------------------------------------------------------ |
| Clean Architecture     | PASS   | Data model separates concerns: MirrorRule (config), SyncRecord (state), SyncLog (observability). No entity knows about storage mechanism. |
| Pragmatic Simplicity   | PASS   | 3 Codable structs, 2 storage mechanisms (UserDefaults + JSON). Dedicated calendar simplifies blocker identification. No ORM needed.         |
| User Experience First  | PASS   | CLI provides dry-run, human-readable output, and short UUID display. GUI is a lightweight menu bar app with Settings integration.            |

## Project Structure

### Documentation (this feature)

```text
specs/001-calendar-mirror-app/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0: tech stack research and decisions
├── data-model.md        # Phase 1: entity definitions and storage layout
├── quickstart.md        # Phase 1: developer quickstart guide
├── contracts/
│   └── cli.md           # Phase 1: CLI interface contract
├── checklists/
│   └── requirements.md  # Spec quality checklist
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

```text
Sources/
├── CalmMirrorCore/                  # Shared library
│   ├── Models/
│   │   ├── MirrorRule.swift         # Rule configuration (Codable)
│   │   ├── SyncRecord.swift         # Source-to-blocker mapping (Codable)
│   │   └── SyncLog.swift            # Execution log with changes and errors (Codable)
│   ├── Engine/
│   │   ├── SyncEngine.swift         # Core sync algorithm (diff, create, update, delete)
│   │   └── ContentHasher.swift      # SHA-256 content hash for change detection
│   ├── Storage/
│   │   ├── RuleStore.swift          # UserDefaults wrapper for MirrorRule[]
│   │   ├── SyncRecordStore.swift    # JSON file I/O per rule
│   │   └── SyncLogStore.swift       # Rolling JSON log (30-day retention)
│   └── Calendar/
│       ├── CalendarService.swift    # EKEventStore wrapper (singleton, permissions, CRUD)
│       └── LaunchdManager.swift     # Install/uninstall/status for launchd plist
├── CalmMirrorApp/                   # SwiftUI menu bar application
│   ├── CalmMirrorApp.swift          # @main with MenuBarExtra + Settings scenes
│   ├── Views/
│   │   ├── MenuBarView.swift        # Quick status and sync trigger
│   │   ├── RulesListView.swift      # List of configured rules with enable/disable/delete
│   │   ├── RuleEditorView.swift     # Create/edit rule form (calendar pickers, window, label)
│   │   └── LogsView.swift           # Chronological sync log viewer
│   └── Info.plist                   # NSCalendarsFullAccessUsageDescription
└── calmirror/                       # CLI executable
    └── CLI.swift                    # Swift Argument Parser command tree

Tests/
└── CalmMirrorCoreTests/
    ├── SyncEngineTests.swift        # Diff algorithm, blocker lifecycle
    ├── ContentHasherTests.swift     # Hash determinism and change detection
    ├── RuleStoreTests.swift         # CRUD, validation, persistence
    ├── SyncRecordStoreTests.swift   # JSON read/write, atomicity
    └── SyncLogStoreTests.swift      # Append, retention pruning

Resources/
└── com.gravitek.calmirror.sync.plist  # launchd agent template
```

**Structure Decision**: Single Swift Package with 3 targets (CalmMirrorCore library, CalmMirrorApp executable, calmirror CLI executable). This keeps all code in one repository with shared types and logic. The CalmMirrorApp target may need an Xcode project wrapper for Info.plist and entitlements management — this will be evaluated during implementation.

## Key Design Decisions

| Decision                    | Choice                           | See                    |
| --------------------------- | -------------------------------- | ---------------------- |
| Daemon architecture         | launchd scheduled agent          | research.md            |
| Sync interval               | Fixed 15 min (not configurable)  | spec.md Clarifications |
| Blocker identification      | Dedicated calendar + JSON map    | data-model.md          |
| Event change detection      | SHA-256 content hash             | data-model.md          |
| CLI parsing framework       | Swift Argument Parser            | contracts/cli.md       |
| App presentation            | MenuBarExtra (menu bar app)      | research.md            |
| Config storage              | UserDefaults shared suite        | data-model.md          |
| Sync state storage          | JSON file per rule               | data-model.md          |
| macOS minimum target        | macOS 14 (Sonoma)                | research.md            |
| EventKit singleton          | Single EKEventStore instance     | research.md            |
| Batch commit strategy       | Groups of 50-100, then commit()  | research.md            |
| Recurring events            | Predicate auto-expansion         | research.md            |
| Notes tag                   | "Managed by CalMirror" (no data) | research.md            |

## Generated Artifacts

| Artifact                           | Path                                              | Status   |
| ---------------------------------- | ------------------------------------------------- | -------- |
| Feature specification              | `specs/001-calendar-mirror-app/spec.md`            | Complete |
| Research summary                   | `specs/001-calendar-mirror-app/research.md`        | Complete |
| Data model                         | `specs/001-calendar-mirror-app/data-model.md`      | Complete |
| CLI contract                       | `specs/001-calendar-mirror-app/contracts/cli.md`   | Complete |
| Quickstart guide                   | `specs/001-calendar-mirror-app/quickstart.md`      | Complete |
| Requirements checklist             | `specs/001-calendar-mirror-app/checklists/requirements.md` | Complete |
| Task breakdown                     | `specs/001-calendar-mirror-app/tasks.md`           | Pending (`/speckit.tasks`) |

## Complexity Tracking

No constitution violations detected. All design decisions align with the 3 core principles (Clean Architecture, Pragmatic Simplicity, User Experience First).
