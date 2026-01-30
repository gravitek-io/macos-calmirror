---
description: Full automated Spec Kit workflow from idea to PR
---

## User Input

```text
$ARGUMENTS
```

## Prerequisites

Run `.specify/scripts/bash/check-prerequisites.sh --json` to get FEATURE_DIR.
If no feature branch exists yet, one will be created during Phase 1.

## Workflow: Idea to PR

Execute the complete Spec-Driven Development pipeline automatically.

### Initialization

Create or load workflow progress file at `FEATURE_DIR/workflow-progress.md` using template from `.specify/templates/workflow-progress-template.md`.

Set initial status:

```yaml
status: IN_PROGRESS
current_phase: 1
started_at: [timestamp]
```

---

### Phase 1: Specification

**1.1 Run /speckit.specify**

```
Create specification from: "$ARGUMENTS"
```

Update progress: `Phase 1: Specification → IN_PROGRESS`

**1.2 Self-review for clarity**

After spec.md is created, launch clarification agent:

**Spec Clarifier** (subagent_type: general-purpose)

```
Analyze spec.md for:
- Vague requirements (missing measurable criteria)
- Ambiguous acceptance criteria
- Unclear scope boundaries
- Missing edge cases
- Conflicting requirements

Output: List of clarification questions (if any)
```

**If clarifications needed**:

- Update progress: Add intervention request
- Display questions clearly numbered
- STOP and wait for user answers
- After answers received, update spec.md
- Log answers in workflow-progress.md
- Continue to Phase 2

**If spec is clear**:

- Update progress: `Phase 1: Specification → COMPLETE`
- Proceed to Phase 2

---

### Phase 2: Planning

Update progress: `Phase 2: Planning → IN_PROGRESS`

**2.1 Run /speckit.plan with parallel agents**

Execute Phase 0 (Research) and Phase 1 (Design) with parallel subagents as defined in the optimized plan.md command.

**2.2 Validate plan completeness**

Check that plan.md contains:

- [ ] Tech stack resolved (no NEEDS CLARIFICATION remaining)
- [ ] Data model defined in data-model.md
- [ ] Architecture decisions documented
- [ ] All research questions answered in research.md

**If unresolved items found**:

- Attempt auto-resolution via additional research agents
- If still unresolved after 2 attempts, STOP and ask user
- Log intervention in workflow-progress.md

**If complete**:

- Update progress: `Phase 2: Planning → COMPLETE`
- Proceed to Phase 3

---

### Phase 3: Task Breakdown & Analysis

Update progress: `Phase 3: Tasks → IN_PROGRESS`

**3.1 Run /speckit.tasks**

```
Generate tasks.md from plan.md with:
- Phase grouping
- Parallel markers [P]
- File path specifications
- Checkpoint markers
```

**3.2 Run /speckit.analyze with parallel agents**

Launch 6 parallel validation agents as defined in optimized analyze.md.

**3.3 Evaluate analysis results**

**If CRITICAL issues found**:

- Update progress: Add blocker
- Display analysis report
- STOP and ask: "Critical issues found. Review report and decide: fix now or proceed anyway?"
- Wait for user decision
- Log decision in workflow-progress.md

**If only LOW/MEDIUM issues**:

- Log warnings in workflow-progress.md
- Update progress: `Phase 3: Tasks → COMPLETE (with N warnings)`
- Auto-proceed to Phase 4

**If no issues**:

- Update progress: `Phase 3: Tasks → COMPLETE`
- Proceed to Phase 4

---

### Phase 4: Implementation

Update progress: `Phase 4: Implementation → IN_PROGRESS`

**4.1 Run /speckit.implement with parallel execution**

Execute all tasks following optimized implement.md:

- Parallel execution for [P] tasks
- Background agents for long-running tasks
- Phase-by-phase with checkpoints

**4.2 Monitor and update progress**

After each phase completion in tasks.md:

- Update workflow-progress.md with task counts
- Format: `Implementation: [completed]/[total] tasks`

**4.3 Handle failures**

**On task failure**:

- Attempt auto-fix (analyze error, propose solution, retry)
- Max 2 retries per task
- Log each attempt in workflow-progress.md

**On persistent failure** (after 2 retries):

- Update progress: Add blocker
- STOP and report:
  - Which task failed
  - Error details
  - Attempted fixes
  - Suggested manual resolution
- Wait for user guidance
- Log resolution in workflow-progress.md

**If all tasks complete**:

- Update progress: `Phase 4: Implementation → COMPLETE`
- Proceed to Phase 5

---

### Phase 5: Finalization & PR

Update progress: `Phase 5: PR → IN_PROGRESS`

**5.1 Final validation - Launch parallel agents**

**Agent 1: Spec Compliance** (subagent_type: general-purpose)

```
Compare implementation against spec.md:
- All functional requirements addressed
- Non-functional requirements met
- Edge cases handled
Output: Compliance checklist with pass/fail
```

**Agent 2: Test Verification** (subagent_type: general-purpose)

```
Verify test status:
- Run test suite
- Check coverage against constitution requirements
- Identify skipped or failing tests
Output: Test summary with metrics
```

**Agent 3: Code Cleanup** (subagent_type: Explore)

```
Scan for cleanup needs:
- console.log / debug statements
- TODO / FIXME comments
- Commented-out code blocks
- Unused imports
Output: Cleanup task list
```

**Wait for all agents to complete.**

**5.2 Auto-cleanup**

Execute cleanup tasks identified by Agent 3:

- Remove debug code
- Run linter and auto-fix
- Format code

**5.3 Generate PR content**

**PR Writer** (subagent_type: general-purpose)

```
From spec.md, plan.md, tasks.md, and implementation:
- Generate PR title (conventional commit format)
- Write summary from spec overview
- List key changes from tasks.md
- Include test results from validation
- Add any breaking changes or migration notes
Output: Complete PR description in markdown
```

**5.4 Confirm and create PR**

Display PR preview:

```
──────────────────────────────────────
PR Preview
──────────────────────────────────────
Title: feat(auth): Add user authentication with JWT

## Summary
[Generated summary]

## Changes
[Generated changes]

## Testing
[Test results]
──────────────────────────────────────
```

**STOP and ask**: "Ready to create PR. Confirm? (yes/edit/cancel)"

- **yes**: Create PR and push
- **edit**: Open PR description for manual editing, then confirm again
- **cancel**: Abort PR creation, keep branch local

**5.5 Create PR**

```bash
# Ensure on feature branch
current_branch=$(git branch --show-current)
if [[ ! "$current_branch" =~ ^[0-9]{3}- ]]; then
    echo "Warning: Not on a feature branch. Creating one..."
    feature_name=$(basename "$FEATURE_DIR")
    git checkout -b "$feature_name"
fi

# Stage all changes
git add -A

# Commit with conventional commit message
git commit -m "feat: [feature-name]

[Summary from spec]

Implemented via Spec Kit automated workflow
Spec: specs/[feature-name]/spec.md"

# Push branch
git push -u origin "$(git branch --show-current)"

# Create PR using gh CLI
gh pr create \
    --title "[Generated title]" \
    --body "[Generated body]" \
    --draft  # Create as draft for review
```

**5.6 Complete workflow**

- Update progress: `Phase 5: PR → COMPLETE`
- Set workflow status: `COMPLETE`
- Record total duration and metrics
- Display final summary

---

## Intervention Summary

The workflow STOPS and waits for user input only at these points:

| Phase | Trigger                        | User Action Required           |
| ----- | ------------------------------ | ------------------------------ |
| 1     | Ambiguous spec                 | Answer clarification questions |
| 2     | Unresolved after auto-research | Provide technical decisions    |
| 3     | CRITICAL analysis issues       | Decide: fix or proceed         |
| 4     | Persistent task failure        | Provide fix guidance           |
| 5     | PR ready                       | Confirm creation               |

All other steps proceed automatically.

---

## Resume Support

If workflow is interrupted (user closes session, error, etc.):

Run `/sk-resume` to continue from last checkpoint.

The workflow reads `FEATURE_DIR/workflow-progress.md` to determine:

- Current phase
- Completed steps
- Pending interventions

---

## Abort / Rollback

To abort workflow at any point, user can type: `abort workflow`

This will:

1. Mark workflow-progress.md as ABORTED
2. List completed changes
3. Offer to reset to pre-workflow state (git stash)
