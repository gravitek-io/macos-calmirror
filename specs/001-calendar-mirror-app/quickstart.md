# CalMirror — Quickstart Guide

**Branch**: `001-calendar-mirror-app` | **Date**: 2026-01-30

## Prerequisites

- macOS 14+ (Sonoma)
- Xcode 15+ (with Swift 5.10+ toolchain)
- Apple Calendar configured with at least two calendar accounts

## Project Setup

```bash
# Clone and enter the project
cd /Users/thomas/Dev/gravitek/github.com/calmirror

# Build the project (once Package.swift is created)
swift build

# Run tests
swift test
```

## Project Structure

```text
CalmMirror/
├── Package.swift                       # SPM manifest
├── Sources/
│   ├── CalmMirrorCore/                 # Shared library (models, sync engine, storage)
│   │   ├── Models/
│   │   │   ├── MirrorRule.swift
│   │   │   ├── SyncRecord.swift
│   │   │   └── SyncLog.swift
│   │   ├── Engine/
│   │   │   ├── SyncEngine.swift
│   │   │   └── EventMatcher.swift
│   │   ├── Storage/
│   │   │   ├── RuleStore.swift         # UserDefaults wrapper
│   │   │   ├── SyncRecordStore.swift   # JSON file per rule
│   │   │   └── SyncLogStore.swift      # Rolling JSON log
│   │   └── Calendar/
│   │       ├── CalendarService.swift   # EKEventStore wrapper
│   │       └── LaunchdManager.swift    # launchd plist management
│   ├── CalmMirrorApp/                  # SwiftUI GUI (menu bar app)
│   │   ├── CalmMirrorApp.swift
│   │   ├── Views/
│   │   │   ├── MenuBarView.swift
│   │   │   ├── RulesListView.swift
│   │   │   ├── RuleEditorView.swift
│   │   │   └── LogsView.swift
│   │   └── Info.plist
│   └── calmirror/                      # CLI executable
│       └── CLI.swift                   # Swift Argument Parser entry point
├── Tests/
│   └── CalmMirrorCoreTests/
│       ├── SyncEngineTests.swift
│       ├── EventMatcherTests.swift
│       ├── RuleStoreTests.swift
│       └── SyncRecordStoreTests.swift
└── Resources/
    └── com.gravitek.calmirror.sync.plist  # launchd agent template
```

## Key Components

| Component        | Purpose                                       | Entry Point                    |
| ---------------- | --------------------------------------------- | ------------------------------ |
| CalmMirrorCore   | Models, sync engine, storage, calendar access  | Library — no entry point       |
| CalmMirrorApp    | SwiftUI menu bar GUI for configuration/logs    | `CalmMirrorApp.swift`          |
| calmirror (CLI)  | Command-line sync tool invoked by launchd      | `CLI.swift`                    |

## Development Workflow

```bash
# Build CLI only
swift build --product calmirror

# Run CLI
swift run calmirror calendars
swift run calmirror sync --dry-run

# Build and run the SwiftUI app (requires Xcode)
open Package.swift  # Opens in Xcode

# Run tests
swift test
```

## Configuration & Data Paths

| Data             | Location                                                       |
| ---------------- | -------------------------------------------------------------- |
| Rules config     | UserDefaults suite `com.gravitek.calmirror`                    |
| Sync records     | `~/Library/Application Support/CalMirror/sync/{ruleId}.json`   |
| Sync logs        | `~/Library/Application Support/CalMirror/logs/sync-logs.json`  |
| launchd agent    | `~/Library/LaunchAgents/com.gravitek.calmirror.sync.plist`     |

## Key Dependencies

| Dependency              | Purpose                    | Source         |
| ----------------------- | -------------------------- | -------------- |
| EventKit                | Calendar read/write access | Apple SDK      |
| CryptoKit               | Content hash computation   | Apple SDK      |
| Swift Argument Parser   | CLI command parsing        | SPM (Apple)    |

No third-party dependencies beyond Apple's own Swift Argument Parser.
