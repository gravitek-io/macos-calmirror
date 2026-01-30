# Homebrew Tap for CalMirror

This is the official [Homebrew](https://brew.sh) tap for [CalMirror](https://github.com/gravitek/calmirror), a calendar event mirroring tool for macOS.

## Installation

```bash
brew tap gravitek/tap
brew install calmirror
```

## Available Formulae

| Formula | Description |
|---------|-------------|
| `calmirror` | Calendar event mirroring tool for macOS |

## Background Sync

CalMirror includes a Homebrew services integration for automatic background synchronization via launchd:

```bash
# Start background sync (every 15 minutes)
brew services start calmirror

# Check service status
brew services info calmirror

# Stop background sync
brew services stop calmirror
```

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15.0 or later (build dependency)
- Full Calendar Access permission (System Settings > Privacy & Security > Calendars)

## Quick Start

```bash
# List available calendars
calmirror calendars

# Add a mirror rule
calmirror rules add --source <source-cal-id> --target <target-cal-id> --window 30 --label "Busy"

# Run a sync
calmirror sync

# Enable automatic background sync
brew services start calmirror
```
