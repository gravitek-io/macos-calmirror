# CalMirror CLI Contract

**Version**: 1.0.0
**Binary**: `calmirror`
**Created**: 2026-01-30
**Status**: Draft

## Overview

The `calmirror` CLI is the primary executable for calendar synchronization. It is invoked automatically by a launchd agent every 15 minutes and can also be used interactively by the user. It shares the `CalmMirrorCore` library with the SwiftUI GUI application.

### Shared Resources

| Resource | Location |
|----------|----------|
| Configuration | UserDefaults shared suite `com.gravitek.calmirror` |
| Sync state | `~/Library/Application Support/CalMirror/sync/` |
| Sync logs | `~/Library/Application Support/CalMirror/logs/` |
| launchd plist | `~/Library/LaunchAgents/com.gravitek.calmirror.sync.plist` |

### Global Conventions

- **Stdout**: Structured output (human-readable by default, JSON when `--json` is passed).
- **Stderr**: Errors, warnings, and diagnostic messages. Never mixed with structured output.
- **Exit codes**: Consistent across all subcommands (see table below).
- **No color** is emitted when stdout is not a TTY (piped or redirected), unless `--color` is explicitly passed.
- **Quiet mode** (`-q` / `--quiet`): Suppresses all stdout output. Exit code still reflects outcome.

### Global Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | Partial failure (some operations succeeded, some failed) |
| `2` | Critical error (no operations succeeded, or unrecoverable error) |
| `3` | Configuration error (invalid config, missing required fields) |
| `4` | Calendar access denied (EventKit authorization missing or revoked) |

### Global Options

| Option | Short | Type | Description |
|--------|-------|------|-------------|
| `--help` | `-h` | flag | Show help for the command or subcommand |
| `--version` | `-v` | flag | Show version string |
| `--quiet` | `-q` | flag | Suppress stdout output |
| `--json` | | flag | Force JSON output (where applicable) |
| `--verbose` | | flag | Increase log verbosity on stderr |

---

## Command Tree

```
calmirror
  ├── sync [--rule <uuid>] [--dry-run]
  ├── rules
  │   ├── list [--json]
  │   ├── add --source <cal-id> --target <cal-id> --window <days> --label <text>
  │   ├── remove <uuid>
  │   ├── enable <uuid>
  │   └── disable <uuid>
  ├── status [--json]
  ├── logs [--rule <uuid>] [--last <n>] [--json]
  ├── calendars [--json]
  ├── agent
  │   ├── install
  │   ├── uninstall
  │   └── status [--json]
  └── version
```

---

## Subcommands

### 1. `calmirror sync`

Run synchronization for all enabled rules, or a specific rule. This is the command invoked by the launchd agent.

#### Arguments & Options

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `--rule` | UUID string | No | _(all enabled rules)_ | Run only the rule with this identifier |
| `--dry-run` | flag | No | `false` | Simulate sync: compute changes but do not write to calendars |

#### Behavior

1. Check EventKit authorization. If denied, exit with code `4`.
2. Load rules from configuration. If `--rule` is provided, filter to that single rule.
3. For each enabled rule:
   a. Fetch source calendar events within the rule's time window (today + N days).
   b. Load existing blocker mapping from sync state.
   c. Compute diff: blockers to add, blockers to remove, blockers to update.
   d. Apply changes to target calendar (unless `--dry-run`).
   e. Update sync state mapping.
   f. Write sync log entry.
4. Print summary to stdout.
5. Exit with appropriate code.

#### Stdout (human-readable, default)

```
Sync completed: 2 rules processed
  Rule "Work -> Personal" (a1b2c3d4): +3 added, -1 removed, ~0 updated
  Rule "Client -> Work" (e5f6g7h8): +0 added, -0 removed, ~2 updated
Total: 3 added, 1 removed, 2 updated
```

#### Stdout (`--dry-run`)

```
Dry run: 2 rules processed (no changes applied)
  Rule "Work -> Personal" (a1b2c3d4): +3 to add, -1 to remove, ~0 to update
  Rule "Client -> Work" (e5f6g7h8): +0 to add, -0 to remove, ~2 to update
Total: 3 to add, 1 to remove, 2 to update
```

#### Stdout (`--json`)

```json
{
  "timestamp": "2026-01-30T14:30:00Z",
  "dryRun": false,
  "rules": [
    {
      "id": "a1b2c3d4-...",
      "label": "Work -> Personal",
      "added": 3,
      "removed": 1,
      "updated": 0,
      "errors": []
    }
  ],
  "totals": {
    "added": 3,
    "removed": 1,
    "updated": 0,
    "rulesProcessed": 2,
    "rulesFailed": 0
  }
}
```

#### Stderr (errors)

```
error: Rule e5f6g7h8: target calendar "Personal" not found (deleted or access revoked)
warning: Rule a1b2c3d4: source calendar slow to respond, retrying...
```

#### Exit Codes

| Code | Condition |
|------|-----------|
| `0` | All rules synced successfully |
| `1` | Some rules failed, others succeeded |
| `2` | All rules failed or critical error (e.g., state file corrupt) |
| `3` | No rules configured, or specified `--rule` UUID not found |
| `4` | Calendar access denied |

#### Error Cases

- **No rules configured**: Exit `3`, stderr: `error: no sync rules configured. Use 'calmirror rules add' to create one.`
- **Rule UUID not found** (with `--rule`): Exit `3`, stderr: `error: rule <uuid> not found.`
- **Calendar access denied**: Exit `4`, stderr: `error: calendar access denied. Grant Full Access in System Settings > Privacy & Security > Calendars.`
- **Source calendar missing**: Rule fails with error in log, other rules continue. Exit `1`.
- **Target calendar missing**: Rule fails with error in log, other rules continue. Exit `1`.
- **Target calendar read-only**: Rule fails with error in log, other rules continue. Exit `1`.
- **State file corrupt**: Exit `2`, stderr: `error: sync state file is corrupt. Delete <path> to reset.`

---

### 2. `calmirror rules list`

List all configured sync rules.

#### Arguments & Options

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `--json` | flag | No | `false` | Output as JSON array |

#### Stdout (human-readable, default)

```
ID        LABEL                SOURCE              TARGET              WINDOW  STATUS
a1b2c3d4  Work -> Personal     Work (Google)       Personal (iCloud)   30d     enabled
e5f6g7h8  Client -> Work       Client (O365)       Work (Google)       14d     disabled
```

#### Stdout (`--json`)

```json
[
  {
    "id": "a1b2c3d4-....",
    "label": "Work -> Personal",
    "sourceCalendarId": "F4A1D...",
    "sourceCalendarTitle": "Work",
    "sourceAccountName": "Google",
    "targetCalendarId": "B8C3E...",
    "targetCalendarTitle": "Personal",
    "targetAccountName": "iCloud",
    "windowDays": 30,
    "enabled": true
  }
]
```

#### Exit Codes

| Code | Condition |
|------|-----------|
| `0` | Rules listed (including empty list) |
| `2` | Failed to read configuration |

#### Error Cases

- **Configuration unreadable**: Exit `2`, stderr: `error: failed to read configuration from UserDefaults.`

---

### 3. `calmirror rules add`

Add a new sync rule.

#### Arguments & Options

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `--source` | string | Yes | | Calendar identifier for the source (use `calmirror calendars` to find IDs) |
| `--target` | string | Yes | | Calendar identifier for the target |
| `--window` | integer | Yes | | Number of days in the sliding time window (1-365) |
| `--label` | string | Yes | | Text label for blocker events (e.g., `"[Client] Busy"`) |

#### Behavior

1. Validate that source and target calendar IDs exist and are different.
2. Validate that the target calendar allows content modifications.
3. Validate that window is within range (1-365).
4. Generate a UUID for the new rule.
5. Save rule to UserDefaults.
6. Print confirmation with the new rule UUID.

#### Stdout

```
Rule created: a1b2c3d4-5678-9abc-def0-123456789abc
  Source: Work (Google)
  Target: Personal (iCloud)
  Window: 30 days
  Label:  [Client] Busy
```

#### Stdout (`--json`)

```json
{
  "id": "a1b2c3d4-5678-9abc-def0-123456789abc",
  "label": "[Client] Busy",
  "sourceCalendarId": "F4A1D...",
  "sourceCalendarTitle": "Work",
  "targetCalendarId": "B8C3E...",
  "targetCalendarTitle": "Personal",
  "windowDays": 30,
  "enabled": true
}
```

#### Exit Codes

| Code | Condition |
|------|-----------|
| `0` | Rule created successfully |
| `3` | Validation error (see below) |
| `4` | Calendar access denied |

#### Error Cases

- **Source calendar not found**: Exit `3`, stderr: `error: source calendar '<id>' not found.`
- **Target calendar not found**: Exit `3`, stderr: `error: target calendar '<id>' not found.`
- **Same source and target**: Exit `3`, stderr: `error: source and target calendars must be different.`
- **Target not writable**: Exit `3`, stderr: `error: target calendar '<title>' is read-only.`
- **Window out of range**: Exit `3`, stderr: `error: window must be between 1 and 365 days.`
- **Missing required option**: Exit `3`, stderr: `error: missing required option '--<option>'.`
- **Calendar access denied**: Exit `4`, stderr: `error: calendar access denied. Grant Full Access in System Settings > Privacy & Security > Calendars.`

---

### 4. `calmirror rules remove <uuid>`

Remove a rule and clean up all its managed blockers from the target calendar.

#### Arguments & Options

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `<uuid>` | UUID string | Yes | | Identifier of the rule to remove |

#### Behavior

1. Look up the rule by UUID.
2. Load blocker mapping for this rule from sync state.
3. Delete all managed blocker events from the target calendar.
4. Remove the rule from UserDefaults.
5. Remove the mapping state file for this rule.
6. Print confirmation.

#### Stdout

```
Rule removed: a1b2c3d4-5678-9abc-def0-123456789abc ("Work -> Personal")
Cleaned up 12 blocker events from "Personal" calendar.
```

#### Stdout (`--json`)

```json
{
  "id": "a1b2c3d4-5678-9abc-def0-123456789abc",
  "label": "Work -> Personal",
  "blockersRemoved": 12
}
```

#### Exit Codes

| Code | Condition |
|------|-----------|
| `0` | Rule removed and blockers cleaned up |
| `1` | Rule removed but some blockers could not be deleted (partial cleanup) |
| `3` | Rule UUID not found |
| `4` | Calendar access denied |

#### Error Cases

- **UUID not found**: Exit `3`, stderr: `error: rule '<uuid>' not found.`
- **Target calendar missing during cleanup**: Exit `1`, stderr: `warning: target calendar not found, blocker cleanup skipped. Rule removed.`
- **Calendar access denied**: Exit `4`, stderr: `error: calendar access denied. Grant Full Access in System Settings > Privacy & Security > Calendars.`

---

### 5. `calmirror rules enable <uuid>`

Enable a previously disabled rule.

#### Arguments & Options

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `<uuid>` | UUID string | Yes | | Identifier of the rule to enable |

#### Stdout

```
Rule enabled: a1b2c3d4 ("Work -> Personal")
```

#### Stdout (`--json`)

```json
{
  "id": "a1b2c3d4-5678-9abc-def0-123456789abc",
  "enabled": true
}
```

#### Exit Codes

| Code | Condition |
|------|-----------|
| `0` | Rule enabled (or was already enabled) |
| `3` | Rule UUID not found |

#### Error Cases

- **UUID not found**: Exit `3`, stderr: `error: rule '<uuid>' not found.`

---

### 6. `calmirror rules disable <uuid>`

Disable a rule so it is skipped during sync. Existing blockers are not removed.

#### Arguments & Options

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `<uuid>` | UUID string | Yes | | Identifier of the rule to disable |

#### Stdout

```
Rule disabled: a1b2c3d4 ("Work -> Personal")
Existing blockers are preserved. Use 'calmirror rules remove' to also clean up blockers.
```

#### Stdout (`--json`)

```json
{
  "id": "a1b2c3d4-5678-9abc-def0-123456789abc",
  "enabled": false
}
```

#### Exit Codes

| Code | Condition |
|------|-----------|
| `0` | Rule disabled (or was already disabled) |
| `3` | Rule UUID not found |

#### Error Cases

- **UUID not found**: Exit `3`, stderr: `error: rule '<uuid>' not found.`

---

### 7. `calmirror status`

Show the overall daemon status, last sync time, and next scheduled run.

#### Arguments & Options

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `--json` | flag | No | `false` | Output as JSON |

#### Stdout (human-readable)

```
CalMirror Status
  Agent:       running (PID 12345)
  Last sync:   2026-01-30 14:15:00 (15 minutes ago)
  Next sync:   2026-01-30 14:30:00 (in < 1 minute)
  Rules:       3 configured (2 enabled, 1 disabled)
  Last result: OK (3 added, 1 removed)
```

#### Stdout (`--json`)

```json
{
  "agent": {
    "installed": true,
    "running": true,
    "pid": 12345
  },
  "lastSync": {
    "timestamp": "2026-01-30T14:15:00Z",
    "result": "success",
    "added": 3,
    "removed": 1,
    "updated": 0
  },
  "nextSync": "2026-01-30T14:30:00Z",
  "rules": {
    "total": 3,
    "enabled": 2,
    "disabled": 1
  }
}
```

#### Stdout (agent not installed)

```
CalMirror Status
  Agent:       not installed
  Last sync:   never
  Rules:       0 configured
  Run 'calmirror agent install' to set up the background agent.
```

#### Exit Codes

| Code | Condition |
|------|-----------|
| `0` | Status retrieved successfully |
| `2` | Failed to read configuration or state |

#### Error Cases

- **State directory missing**: Exit `0` (treat as first run, show "never synced").
- **Configuration unreadable**: Exit `2`, stderr: `error: failed to read configuration.`

---

### 8. `calmirror logs`

Show recent synchronization logs.

#### Arguments & Options

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `--rule` | UUID string | No | _(all rules)_ | Filter logs to a specific rule |
| `--last` | integer | No | `10` | Number of most recent log entries to show (1-1000) |
| `--json` | flag | No | `false` | Output as JSON array |

#### Stdout (human-readable)

```
2026-01-30 14:15:00  OK     Rule "Work -> Personal" (a1b2c3d4): +3 -1 ~0
2026-01-30 14:15:01  OK     Rule "Client -> Work" (e5f6g7h8): +0 -0 ~2
2026-01-30 14:00:00  ERROR  Rule "Work -> Personal" (a1b2c3d4): target calendar not found
2026-01-30 13:45:00  OK     Rule "Work -> Personal" (a1b2c3d4): +1 -0 ~0
```

#### Stdout (`--json`)

```json
[
  {
    "timestamp": "2026-01-30T14:15:00Z",
    "ruleId": "a1b2c3d4-...",
    "ruleLabel": "Work -> Personal",
    "result": "success",
    "added": 3,
    "removed": 1,
    "updated": 0,
    "errors": [],
    "durationMs": 450
  },
  {
    "timestamp": "2026-01-30T14:00:00Z",
    "ruleId": "a1b2c3d4-...",
    "ruleLabel": "Work -> Personal",
    "result": "error",
    "added": 0,
    "removed": 0,
    "updated": 0,
    "errors": ["target calendar 'Personal' not found (deleted or access revoked)"],
    "durationMs": 12
  }
]
```

#### Exit Codes

| Code | Condition |
|------|-----------|
| `0` | Logs retrieved (including empty result) |
| `3` | Specified `--rule` UUID not found |
| `2` | Failed to read log files |

#### Error Cases

- **Rule UUID not found** (with `--rule`): Exit `3`, stderr: `error: rule '<uuid>' not found.`
- **No log files**: Exit `0`, stdout: `No sync logs found.`
- **Log file corrupt**: Exit `2`, stderr: `error: failed to parse log file '<path>'.`
- **`--last` out of range**: Exit `3`, stderr: `error: --last must be between 1 and 1000.`

---

### 9. `calmirror calendars`

List all calendars available in Apple Calendar, grouped by account. Used to find calendar identifiers for `rules add`.

#### Arguments & Options

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `--json` | flag | No | `false` | Output as JSON |

#### Stdout (human-readable)

```
Google (thomas@gmail.com)
  F4A1D...  Work              read/write
  7B2CE...  Personal Events   read/write

Microsoft (thomas@company.com)
  B8C3E...  Calendar          read/write
  D9F4A...  Team Calendar     read-only

iCloud
  A1B2C...  Home              read/write
```

#### Stdout (`--json`)

```json
[
  {
    "accountName": "Google",
    "accountIdentifier": "thomas@gmail.com",
    "accountType": "calDAV",
    "calendars": [
      {
        "id": "F4A1D...",
        "title": "Work",
        "color": "#4285F4",
        "writable": true
      },
      {
        "id": "7B2CE...",
        "title": "Personal Events",
        "color": "#0B8043",
        "writable": true
      }
    ]
  }
]
```

#### Exit Codes

| Code | Condition |
|------|-----------|
| `0` | Calendars listed (including empty list) |
| `4` | Calendar access denied |

#### Error Cases

- **Calendar access denied**: Exit `4`, stderr: `error: calendar access denied. Grant Full Access in System Settings > Privacy & Security > Calendars.`
- **No calendars found**: Exit `0`, stdout: `No calendars found in Apple Calendar.`

---

### 10. `calmirror agent install`

Install the launchd agent plist and load it. The agent will run `calmirror sync` every 15 minutes.

#### Arguments & Options

None.

#### Behavior

1. Generate the plist file with the correct binary path and configuration.
2. Write to `~/Library/LaunchAgents/com.gravitek.calmirror.sync.plist`.
3. Load the agent with `launchctl bootstrap gui/<uid> <plist-path>`.
4. Verify the agent is loaded.

#### Stdout

```
Agent installed and loaded.
  Plist: ~/Library/LaunchAgents/com.gravitek.calmirror.sync.plist
  Interval: every 15 minutes
  Status: running
```

#### Exit Codes

| Code | Condition |
|------|-----------|
| `0` | Agent installed and loaded successfully |
| `1` | Plist written but launchctl load failed |
| `2` | Failed to write plist file |

#### Error Cases

- **Already installed**: Exit `0`, stdout: `Agent is already installed and running. Use 'calmirror agent uninstall' first to reinstall.`
- **Plist write failure**: Exit `2`, stderr: `error: failed to write plist to '<path>': <system error>.`
- **launchctl failure**: Exit `1`, stderr: `error: plist written but 'launchctl bootstrap' failed: <system error>. Try manually: launchctl bootstrap gui/<uid> <path>.`

---

### 11. `calmirror agent uninstall`

Unload and remove the launchd agent plist.

#### Arguments & Options

None.

#### Behavior

1. Unload the agent with `launchctl bootout gui/<uid>/<service-label>`.
2. Delete the plist file.

#### Stdout

```
Agent unloaded and removed.
```

#### Exit Codes

| Code | Condition |
|------|-----------|
| `0` | Agent unloaded and plist removed |
| `1` | Agent unloaded but plist deletion failed (or vice versa) |
| `2` | Agent was not installed |

#### Error Cases

- **Not installed**: Exit `2`, stderr: `error: agent is not installed. Nothing to uninstall.`
- **launchctl failure**: Exit `1`, stderr: `warning: launchctl bootout failed: <system error>. Plist removed anyway.`

---

### 12. `calmirror agent status`

Show the launchd agent status.

#### Arguments & Options

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `--json` | flag | No | `false` | Output as JSON |

#### Stdout (human-readable)

```
Agent Status
  Installed: yes
  Running:   yes (PID 12345)
  Plist:     ~/Library/LaunchAgents/com.gravitek.calmirror.sync.plist
  Interval:  900s (15 minutes)
```

#### Stdout (`--json`)

```json
{
  "installed": true,
  "running": true,
  "pid": 12345,
  "plistPath": "~/Library/LaunchAgents/com.gravitek.calmirror.sync.plist",
  "intervalSeconds": 900
}
```

#### Exit Codes

| Code | Condition |
|------|-----------|
| `0` | Status retrieved |

#### Error Cases

- **Not installed**: Exit `0`, stdout shows `Installed: no`.

---

### 13. `calmirror version`

Print the version string and exit.

#### Arguments & Options

None.

#### Stdout

```
calmirror 1.0.0
```

#### Stdout (`--json`)

```json
{
  "version": "1.0.0",
  "build": "abc1234",
  "swift": "5.10"
}
```

#### Exit Codes

| Code | Condition |
|------|-----------|
| `0` | Always |

---

## Implementation Notes

### Recommended Swift Framework

Use [Swift Argument Parser](https://github.com/apple/swift-argument-parser) (`ArgumentParser`) for CLI parsing. It natively supports:
- Subcommand trees (`ParsableCommand` with subcommands)
- Typed options and arguments
- Automatic help generation
- Exit code handling via `ExitCode`

### UUID Display Convention

When displaying UUIDs in human-readable output, use the first 8 characters (short form) for brevity. The full UUID is always shown in JSON output and accepted as input (both short and full forms).

### Signal Handling

The `sync` command should handle `SIGTERM` and `SIGINT` gracefully:
1. Finish the current rule's commit batch.
2. Write partial sync state (completed rules only).
3. Write a log entry noting the interruption.
4. Exit with code `1`.

This ensures launchd stop/restart does not leave orphaned or incomplete state.

### Concurrency

The CLI runs all rules sequentially in a single thread. No concurrent calendar access is attempted, since `EKEventStore` is not `Sendable` and the CLI is a short-lived process.

### TTY Detection

The CLI detects whether stdout is a terminal:
- **TTY**: Human-readable table output with aligned columns.
- **Non-TTY** (piped/redirected): Same table output but without ANSI escape codes.
- **`--json`**: JSON output regardless of TTY state.
