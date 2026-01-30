# Feature Specification: CalMirror - Calendar Event Mirroring

**Feature Branch**: `001-calendar-mirror-app`
**Created**: 2026-01-30
**Status**: Draft
**Input**: User description: "Native macOS application that mirrors calendar events from a source calendar to a target calendar as blocker entries, working exclusively through Apple Calendar to avoid third-party data exposure"

## Clarifications

### Session 2026-01-30

- Q: What daemon architecture should the background sync use — always-running service, scheduled agent (launchd), or embedded in the UI app? → A: Scheduled launchd agent (periodic job, not a long-running process)
- Q: Should the sync frequency be user-configurable in V1, or fixed at a default interval? → A: Fixed default (15 min), not exposed in the UI

## User Scenarios & Testing _(mandatory)_

### User Story 1 - Configure a Calendar Mirror Rule (Priority: P1)

As a user with multiple calendars synced in Apple Calendar (Google, Microsoft O365), I want to configure a mirroring rule that copies events from one calendar as "busy" blockers in another calendar, so that my availability is accurately reflected across all calendars without exposing sensitive event details.

**Why this priority**: This is the foundational capability. Without the ability to configure a mirror rule, the application has no purpose. It delivers the core value proposition immediately.

**Independent Test**: Can be fully tested by opening the app, selecting a source calendar, a target calendar, a time window, and a blocker label, then verifying the configuration is saved and displayed in the UI.

**Acceptance Scenarios**:

1. **Given** the user opens CalMirror for the first time, **When** they click to add a new mirror rule, **Then** they see a list of all calendars available in Apple Calendar grouped by account (Google, Microsoft, iCloud, etc.)
2. **Given** the user is creating a new mirror rule, **When** they select a source calendar, a target calendar, a sliding window (e.g. 30 days), and a blocker label (e.g. "[Client] Busy"), **Then** the rule is saved and appears in the main rules list
3. **Given** a mirror rule exists, **When** the user edits it, **Then** they can modify any of its parameters (source, target, window, label) and save the changes
4. **Given** a mirror rule exists, **When** the user deletes it, **Then** the rule is removed from the list and all associated blockers in the target calendar are cleaned up
5. **Given** the user is creating a new mirror rule, **When** they select the same calendar as both source and target, **Then** the application prevents this configuration and displays an error message

---

### User Story 2 - Automatic Event Synchronization (Priority: P1)

As a user with configured mirror rules, I want the application to automatically synchronize events at regular intervals, creating blocker entries in my target calendar for each event found in my source calendar, so that my availability is always up to date without manual intervention.

**Why this priority**: This is equally critical as configuration — without automated sync, the user would have to manually trigger updates, defeating the purpose of the application.

**Independent Test**: Can be tested by configuring a rule, waiting for a sync cycle, and verifying that blocker events appear in the target calendar with the correct time slots and label.

**Acceptance Scenarios**:

1. **Given** a mirror rule is configured with a 30-day window, **When** a sync cycle runs, **Then** blocker events are created in the target calendar for every event in the source calendar within the next 30 days
2. **Given** blockers already exist in the target calendar, **When** a sync cycle runs and a source event has been deleted, **Then** the corresponding blocker is removed from the target calendar
3. **Given** blockers already exist in the target calendar, **When** a sync cycle runs and a source event's time has changed, **Then** the corresponding blocker is updated to reflect the new time
4. **Given** a sync cycle runs, **When** it completes, **Then** no events in the source calendar are modified in any way (read-only access)
5. **Given** a sync cycle runs, **When** it completes, **Then** no events in the target calendar other than managed blockers are modified
6. **Given** a blocker is created, **When** the user inspects it in Apple Calendar, **Then** it shows only the configured label text (e.g. "[Client] Busy") with no details from the original event (title, attendees, description, location)

---

### User Story 3 - View Synchronization Logs (Priority: P2)

As a user, I want to view logs for each synchronization execution so that I can verify what happened and troubleshoot any issues.

**Why this priority**: While not needed for core functionality, log visibility builds trust in the application and is essential for diagnosing problems. It can be delivered after the core sync works.

**Independent Test**: Can be tested by running a sync, opening the logs view, and verifying that the execution details (configuration used, blockers added, blockers removed) are accurately displayed.

**Acceptance Scenarios**:

1. **Given** a sync cycle has completed, **When** the user opens the logs section, **Then** they see a chronological list of sync executions
2. **Given** the user selects a specific sync execution log, **When** it expands, **Then** they see: the mirror rule configuration used, the number and list of blockers added, and the number and list of blockers removed
3. **Given** a sync execution encountered an error (e.g. calendar access denied), **When** the user views the log, **Then** the error is clearly displayed with a human-readable description

---

### User Story 4 - Manage Multiple Mirror Rules (Priority: P2)

As a user with multiple calendar accounts, I want to configure and run several mirror rules simultaneously, each with its own source, target, window, and label, so that I can mirror events from multiple sources.

**Why this priority**: Multi-rule support is important for the complete use case but a single rule already delivers significant value.

**Independent Test**: Can be tested by creating two or more rules with different source/target combinations and verifying that each syncs independently without interference.

**Acceptance Scenarios**:

1. **Given** the user has two mirror rules configured (Rule A: Calendar X → Calendar Y, Rule B: Calendar Z → Calendar Y), **When** sync runs, **Then** both rules execute and create separate sets of blockers in Calendar Y
2. **Given** multiple rules target the same calendar, **When** sync runs, **Then** blockers from different rules are independently managed (deleting Rule A does not affect blockers from Rule B)
3. **Given** the user enables or disables individual rules, **When** sync runs, **Then** only enabled rules are executed

---

### User Story 5 - Background Daemon Operation (Priority: P3)

As a user, I want the synchronization to run as a scheduled background job managed by macOS launchd, so that sync executes at regular intervals without requiring the UI to be open or a long-running process to consume resources.

**Why this priority**: Background operation is important for convenience, but the user can initially trigger sync manually or through the UI. The launchd agent improves the experience once core functionality is stable.

**Independent Test**: Can be tested by installing the launchd agent, closing the UI, and verifying that sync continues to run at the configured interval.

**Acceptance Scenarios**:

1. **Given** the application is installed, **When** the user logs in to macOS, **Then** the launchd agent is loaded and begins scheduling sync at regular intervals
2. **Given** the launchd agent is active, **When** the user closes the UI window, **Then** synchronization continues at scheduled intervals
3. **Given** a scheduled sync encounters an error, **When** it fails, **Then** the error is logged and the next scheduled run proceeds normally

---

### User Story 6 - Install via Homebrew (Priority: P3)

As a user, I want to install CalMirror via Homebrew with a single command that sets up both the UI and the background daemon, so that installation is simple and follows macOS conventions.

**Why this priority**: Homebrew packaging is a distribution concern that can be addressed after the core application is functional.

**Independent Test**: Can be tested by running the brew install command on a clean macOS machine and verifying both the UI app and daemon are properly installed and operational.

**Acceptance Scenarios**:

1. **Given** the user has Homebrew installed, **When** they run the install command, **Then** both the UI application and the background daemon are installed
2. **Given** the application is installed via Homebrew, **When** the user runs the uninstall command, **Then** the application, daemon, and all managed configuration are removed

---

### Edge Cases

- What happens when a source calendar is removed from Apple Calendar while a mirror rule references it? The application should detect this and mark the rule as inactive with a warning.
- What happens when the target calendar is read-only? The application should detect this during rule creation and reject the configuration.
- What happens when two mirror rules create overlapping blockers in the same target calendar? Each rule manages its own blockers independently; overlapping time slots result in multiple blocker events (which is the desired behavior to show accurate blocking).
- What happens when the source calendar has recurring events? The sync should process each occurrence within the sliding window individually.
- What happens when the source calendar has all-day events? All-day events should be mirrored as all-day blockers.
- What happens when the source calendar has cancelled events? Cancelled events should not be mirrored; if a blocker exists for a subsequently cancelled event, it should be removed.
- What happens during initial sync with hundreds of events? The sync should handle large volumes gracefully, processing events in batches if necessary to avoid overwhelming Apple Calendar.

## Requirements _(mandatory)_

### Functional Requirements

- **FR-001**: System MUST list all calendars available in Apple Calendar, grouped by account, for source and target selection
- **FR-002**: System MUST allow users to create mirror rules specifying: source calendar, target calendar, sliding time window, and blocker label text
- **FR-003**: System MUST prevent creating a rule where source and target calendars are identical
- **FR-004**: System MUST persist mirror rule configurations across application restarts
- **FR-005**: System MUST allow users to edit, enable/disable, and delete existing mirror rules
- **FR-006**: System MUST execute synchronization every 15 minutes for all enabled rules (fixed interval, not user-configurable in V1)
- **FR-007**: System MUST create blocker events in the target calendar for each event found in the source calendar within the configured time window
- **FR-008**: System MUST remove blocker events from the target calendar when corresponding source events no longer exist or fall outside the time window
- **FR-009**: System MUST update blocker events when corresponding source events have changed (time, duration)
- **FR-010**: Blocker events MUST contain only the configured label text — no event title, attendees, description, location, or any other data from the source event may be exposed
- **FR-011**: System MUST NOT modify any events in the source calendar under any circumstances
- **FR-012**: System MUST NOT modify any events in the target calendar other than blockers it manages
- **FR-013**: System MUST uniquely identify managed blockers to distinguish them from user-created events in the target calendar
- **FR-014**: System MUST log each sync execution including: rule configuration used, blockers added (with time slots), blockers removed (with time slots), and any errors encountered
- **FR-015**: System MUST provide a UI to view sync execution logs in chronological order
- **FR-016**: System MUST run synchronization as a scheduled macOS launchd agent that operates independently of the UI
- **FR-017**: System MUST clean up all managed blockers when a mirror rule is deleted
- **FR-018**: System MUST handle recurring events by processing each occurrence within the sliding window
- **FR-019**: System MUST handle all-day events by creating all-day blocker events
- **FR-020**: System MUST detect and report when a referenced calendar becomes unavailable (removed or access revoked)
- **FR-021**: System MUST be installable as a single package (UI + daemon) via Homebrew

### Key Entities

- **Mirror Rule**: A configuration defining a source-target calendar pair, a sliding time window (duration in days), a blocker label, and an enabled/disabled state. A user can have multiple rules.
- **Blocker Event**: A calendar event created and managed by CalMirror in a target calendar. It has the configured label as title, matches the time slot of a source event, and contains no other details. Each blocker is uniquely linked to both a mirror rule and a specific source event occurrence.
- **Sync Execution Log**: A record of a single synchronization run, containing the timestamp, the mirror rule used, the list of blockers added, the list of blockers removed, and any errors encountered.
- **Calendar**: Represents a calendar available in Apple Calendar, belonging to an account (Google, Microsoft, iCloud, etc.). CalMirror reads from source calendars and writes blockers to target calendars.

## Success Criteria _(mandatory)_

### Measurable Outcomes

- **SC-001**: Users can configure a mirror rule in under 1 minute from opening the application
- **SC-002**: Blocker events appear in the target calendar within one sync cycle after a source event is created
- **SC-003**: Orphaned blockers (source event deleted) are removed within one sync cycle
- **SC-004**: Zero data leakage: blocker events contain only the configured label — no source event metadata is ever exposed
- **SC-005**: The sync agent consumes zero resources between scheduled runs (no long-running process)
- **SC-006**: The launchd agent runs reliably without user intervention, recovering gracefully from transient errors
- **SC-007**: Users can identify and troubleshoot sync issues within 2 minutes using the logs view
- **SC-008**: Installation and setup can be completed in under 5 minutes on a macOS machine with Homebrew

## Assumptions

- The user has Apple Calendar installed and configured with at least two calendar accounts synced (e.g., Google and Microsoft O365)
- Apple Calendar provides programmatic access (via EventKit or similar) to read events and create/modify/delete events in calendars the user has write access to
- The macOS permissions model allows the application to request and obtain calendar access from the user
- The sync frequency is fixed at 15 minutes for V1 (not user-configurable); this may be exposed as a setting in a future iteration
- The sliding time window starts from "today" and extends forward by the configured number of days
- The application targets macOS only — no cross-platform support is planned
- Log retention follows a rolling window (e.g., last 30 days of logs) to prevent unbounded storage growth
