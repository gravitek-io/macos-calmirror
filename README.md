# CalMirror

macOS application that mirrors calendar events between accounts by creating blocker events. Keeps your personal and work calendars in sync automatically.

## How It Works

CalMirror reads events from a **source calendar** and creates "blocker" events in a **target calendar** within a configurable time window. A background agent runs every 15 minutes to keep everything in sync. Changes (new, updated, cancelled events) are detected via content hashing.

## Requirements

- macOS 26+
- Swift 6.2+ toolchain
- At least two calendar accounts configured in Apple Calendar

## Installation

### Quick Install

```bash
./scripts/install.sh
```

This builds and installs everything:

| Component | Location | Purpose |
|-----------|----------|---------|
| GUI app | `/Applications/CalMirror.app` | Configure rules, view sync logs |
| CLI | `/usr/local/bin/calmirror` | Run sync manually or via launchd |
| launchd agent | `~/Library/LaunchAgents/com.gravitek.calmirror.sync.plist` | Automatic sync every 15 min |

You can also install components separately:

```bash
./scripts/install.sh --app   # GUI app only
./scripts/install.sh --cli   # CLI + launchd agent only
```

### After Installation

1. **Open CalMirror** from `/Applications` or Spotlight
2. **Grant calendar access** when prompted
3. **Create a rule**: pick a source calendar, a target calendar, set the sync window (days) and blocker label
4. The launchd agent syncs automatically every 15 minutes

To trigger a manual sync:

```bash
calmirror sync
```

To verify the agent is running:

```bash
launchctl list | grep calmirror
```

## Architecture

```
CalMirror/
├── Sources/
│   ├── CalmMirrorCore/          # Shared library
│   │   ├── Models/              # MirrorRule, SyncRecord, SyncLog
│   │   ├── Engine/              # SyncEngine, ContentHasher
│   │   ├── Storage/             # RuleStore, SyncRecordStore, SyncLogStore
│   │   └── Calendar/            # CalendarService, LaunchdManager
│   ├── CalmMirrorApp/           # SwiftUI windowed app
│   │   ├── CalmMirrorApp.swift
│   │   └── Views/               # RulesListView, RuleEditorView, LogsView
│   └── calmirror/               # CLI (Swift Argument Parser)
├── Tests/CalmMirrorCoreTests/   # 57 unit tests
├── Resources/                   # launchd plist template
└── scripts/
    └── install.sh               # Build & install script
```

| Component | Purpose |
|-----------|---------|
| **CalmMirrorCore** | Models, sync engine, storage, calendar access |
| **CalmMirrorApp** | SwiftUI GUI for rule configuration and log viewing |
| **calmirror** | CLI invoked by launchd and for interactive use |

## Development

```bash
# Build
swift build

# Run tests
swift test

# Run CLI directly
swift run calmirror calendars
swift run calmirror sync

# Open in Xcode
open Package.swift
```

## Data Storage

| Data | Location |
|------|----------|
| Rules | UserDefaults suite `com.gravitek.calmirror` |
| Sync records | `~/Library/Application Support/CalMirror/sync/{ruleId}.json` |
| Sync logs | `~/Library/Application Support/CalMirror/logs/sync-logs.json` |
| launchd agent | `~/Library/LaunchAgents/com.gravitek.calmirror.sync.plist` |

## Uninstall

```bash
# Stop the agent
launchctl bootout gui/$(id -u)/com.gravitek.calmirror.sync

# Remove installed files
rm -rf /Applications/CalMirror.app
sudo rm /usr/local/bin/calmirror
rm ~/Library/LaunchAgents/com.gravitek.calmirror.sync.plist
```

## Dependencies

| Dependency | Purpose | Source |
|------------|---------|--------|
| EventKit | Calendar read/write | Apple SDK |
| CryptoKit | Content hashing | Apple SDK |
| Swift Argument Parser | CLI command parsing | SPM (Apple) |
