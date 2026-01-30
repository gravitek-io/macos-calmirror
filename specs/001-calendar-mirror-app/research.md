# Research Summary: CalMirror

**Branch**: `001-calendar-mirror-app` | **Date**: 2026-01-30

## Decisions Made

| Topic                        | Decision                                                        | Rationale                                                                                              | Alternatives Rejected                                  |
| ---------------------------- | --------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ | ------------------------------------------------------ |
| Language / Runtime           | Swift 5.10+, macOS 14+ (Sonoma)                                | Native EventKit access, SwiftUI for GUI, Swift Package Manager for code sharing between app and CLI    | Rust (no EventKit), Python (resource footprint)        |
| UI Framework                 | SwiftUI with MenuBarExtra                                       | Lightweight menu bar app fits the "configure and forget" usage pattern; native macOS look               | AppKit (more boilerplate), Electron (heavy)            |
| App Architecture             | SwiftUI native patterns (@Observable, @AppStorage)              | KISS — settings app is simple; no TCA/MVVM overhead needed                                             | TCA, MVVM with view models                             |
| Code Sharing                 | Swift Package with shared CalmMirrorCore library                | Standard SPM approach; both GUI app and CLI tool depend on the same core logic                          | Separate repos, copy-paste                             |
| Config Storage               | UserDefaults with shared suite (com.gravitek.calmirror)         | Built-in, fast, shared between app and CLI via suite name, integrates with @AppStorage                 | JSON file (manual I/O), SQLite (overkill), CoreData    |
| Sync State Storage           | JSON file for source-to-blocker mapping                         | UserDefaults not suitable for potentially large dictionaries; JSON file is simple and inspectable       | SQLite (overkill for v1), CoreData (too heavy)         |
| Blocker Identification       | Dedicated CalMirror calendar + local JSON mapping + notes tag   | Calendar acts as primary tag; JSON mapping keeps source IDs private; notes tag as safety net            | Notes-only (visible), URL field (provider issues)      |
| Event Tagging in Notes       | `"Managed by CalMirror"` (no source data)                       | Identifies managed events without leaking any source event information                                  | Source event hash in notes (privacy concern)            |
| Calendar Permissions         | requestFullAccessToEvents() async (macOS 14+)                   | App needs read + write; modern API, no legacy fallback needed for macOS 14+ target                     | requestAccess(to:) deprecated on macOS 14+             |
| Recurring Events             | Let predicateForEvents expand occurrences automatically         | Built-in EventKit behavior; each occurrence returned as standalone EKEvent                              | Manual recurrence rule parsing (complex, error-prone)  |
| Blocker Recurrence           | Standalone events (one blocker per occurrence)                  | Handles individual occurrence changes naturally; no need to replicate recurrence rules                  | Mirrored recurrence rules (fragile)                    |
| Batch Operations             | eventStore.save(commit: false) + commit() in batches of ~50-100 | Atomic commits; avoids memory accumulation; single EKEventStoreChangedNotification per batch            | Individual commits (N notifications, slow)             |
| Background Sync              | launchd agent with StartInterval = 900                          | OS-managed, zero resources between runs, auto-restart on failure                                       | Always-running service (wastes resources)              |
| Homebrew Distribution        | Formula for CLI + brew services; optional cask for .app later   | CLI + launchd is the core value; cask for GUI can come later                                           | Single cask (can't use brew services)                  |
| Thread Safety                | @MainActor for GUI; serial execution for CLI                    | EKEventStore is not Sendable; CLI is short-lived process                                               | Actor isolation (complex for EventKit)                 |
| Minimum Deployment Target    | macOS 14 (Sonoma)                                               | Required for requestFullAccessToEvents(), modern SwiftUI features, MenuBarExtra                        | macOS 13 (would need legacy permission API fallback)   |

## Codebase Patterns Found

- **Greenfield project**: No existing source code, build files, or Xcode projects. All patterns to be established from scratch.
- **Architecture overview exists**: `.claude/context/architecture-overview.md` confirms SwiftUI UI + launchd daemon pattern.
- **Conventions from CLAUDE.md**: English code/comments, conventional commits, clean code with responsibility separation, pragmatic unit tests.

## Technical Clarifications

### EventKit Specifics

- **EKEventStore must be a singleton** — creating multiple instances causes calaccessd connection exhaustion and spurious authorization denial on macOS 14+.
- **predicateForEvents max range is 4 years** — well within our 7-30 day window.
- **EKEventStoreChangedNotification has no payload** — when it fires, all cached EKEvent objects are stale and must be refetched. Debounce the handler.
- **refreshSourcesIfNecessary() is unreliable** — does not guarantee immediate data refresh; do not depend on it.
- **iCloud calendars report as .calDAV** with source.title == "iCloud".
- **allowsContentModifications** is the correct check for target calendar writability (not isImmutable).
- **calendarItemExternalIdentifier can change** after Exchange sync — store both eventIdentifier and externalIdentifier with fallback search.

### Blocker Creation Safety

- **Never copy an EKEvent wholesale** — construct a new event and set only: calendar, startDate, endDate, isAllDay, title (label), availability (.busy), and notes (tag).
- **Explicitly leave nil**: location, structuredLocation, URL, alarms, recurrenceRules. Attendees and organizer are read-only and not set on new events.

### Failure Modes

- **Access revoked at runtime**: authorizationStatus returns .denied; no notification sent. Check before each sync cycle.
- **Target calendar deleted**: eventStore.calendar(withIdentifier:) returns nil. Detect and recreate or warn user.
- **Offline calendars**: EventKit works from local cache. Blockers persist locally and sync when connectivity returns.
- **Event conflicts (TOCTOU)**: Use event.refresh() before creating blockers. Eventual consistency is acceptable.
- **Calendar sync latency**: iCloud 5-30s, Google 15s-minutes, Exchange 10-60s. Out of CalMirror's control.

### EKError Codes to Handle

- `.noCalendar` — target calendar deleted
- `.calendarReadOnly` — target calendar changed permissions
- `.eventStoreNotAuthorized` — access revoked
- `.internalFailure` — retry-worthy
- `.sourceDoesNotAllowCalendarAddDelete` — cannot create CalMirror calendar in this source

### Homebrew Packaging

- **Formula** for CLI binary (swift build --configuration release with universal binary arm64+x86_64)
- **brew services** block handles launchd plist installation/management automatically
- **Cask** for .app bundle (distributes pre-built .app in .dmg or .zip) — deferred to post-v1
- Custom tap at `gravitek/homebrew-tap`

### launchd Configuration

- Plist at `~/Library/LaunchAgents/com.gravitek.calmirror.sync.plist`
- `StartInterval: 900` (15 minutes)
- `ProcessType: Background` for low-priority scheduling
- Stdout/stderr to `/tmp/calmirror.stdout.log` and `/tmp/calmirror.stderr.log`
- No `KeepAlive` — process starts, syncs, exits
- Modern `launchctl bootstrap/bootout gui/<uid>` commands
- File permissions: 644 owned by current user
