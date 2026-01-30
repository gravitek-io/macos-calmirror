# .claude/ — Claude Code Project Structure

This directory contains the structured workflow files used by Claude Code to manage development on this project.

## Directory Structure

```
.claude/
├── templates/       # Analysis & plan templates (reusable starting points)
├── analysis/        # Work-in-progress feature/bug/refactor analyses
├── plans/           # Implementation plans for current work
├── decisions/       # Architecture decision records (ADRs)
├── context/         # Persistent project context (architecture, conventions)
├── archive/         # Completed work items (for reference)
├── .gitignore       # Excludes WIP files, keeps templates and context
└── README.md        # This file
```

## Workflow

### Starting New Work

```
/work-start <description>
```

Creates an analysis file from the appropriate template in `analysis/` and begins the investigation phase.

### Working on a Feature/Bug/Refactor

```
/work <description>
```

Iterates on implementation based on the current analysis and plan.

### Checking Status

```
/work-status
```

Displays progress on the current work item.

### Committing Work

```
/work-commit <description>
```

Finalizes the current work item for commit or PR.

## Templates

| Template | Purpose |
|----------|---------|
| `feature-analysis.md` | New feature analysis and planning |
| `bug-analysis.md` | Bug investigation and fix planning |
| `refactor-analysis.md` | Refactoring scope and approach |

## Context Files

- `context/architecture-overview.md` — High-level architecture, components, and key concepts for CalMirror

## What Gets Committed

- `templates/` — Shared across the team
- `context/` — Architecture docs, conventions
- `decisions/` — ADRs for important choices
- `README.md` — This file

## What Stays Local (via .gitignore)

- `analysis/` — Work-in-progress analysis (per-developer)
- `plans/` — Active implementation plans
- `archive/` — Completed work items
