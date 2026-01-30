---
description: Execute the implementation plan by processing and executing all tasks defined in tasks.md
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Outline

### Step 1: Initialize Context

Run `.specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks` from repo root and parse FEATURE_DIR and AVAILABLE_DOCS list. All paths must be absolute. For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").

### Step 2: Check Checklists Status

If FEATURE_DIR/checklists/ exists:

Scan all checklist files in the checklists/ directory. For each checklist, count:

- Total items: All lines matching `- [ ]` or `- [X]` or `- [x]`
- Completed items: Lines matching `- [X]` or `- [x]`
- Incomplete items: Lines matching `- [ ]`

Create a status table:

```text
| Checklist   | Total | Completed | Incomplete | Status |
|-------------|-------|-----------|------------|--------|
| ux.md       | 12    | 12        | 0          | ✓ PASS |
| test.md     | 8     | 5         | 3          | ✗ FAIL |
| security.md | 6     | 6         | 0          | ✓ PASS |
```

**If any checklist is incomplete**:

- Display the table with incomplete item counts
- **STOP** and ask: "Some checklists are incomplete. Do you want to proceed with implementation anyway? (yes/no)"
- Wait for user response before continuing
- If user says "no" or "wait" or "stop", halt execution
- If user says "yes" or "proceed" or "continue", proceed to step 3

**If all checklists are complete**: Display the table showing all checklists passed, automatically proceed to step 3.

### Step 3: Load Implementation Context

**REQUIRED**:

- Read tasks.md for the complete task list and execution plan
- Read plan.md for tech stack, architecture, and file structure

**IF EXISTS**:

- Read data-model.md for entities and relationships
- Read contracts/ for API specifications and test requirements
- Read research.md for technical decisions and constraints
- Read quickstart.md for integration scenarios

### Step 4: Project Setup Verification

Create/verify ignore files based on actual project setup.

**Detection Logic**:

- Git repo check: `git rev-parse --git-dir 2>/dev/null` → create/verify .gitignore
- Dockerfile\* exists or Docker in plan.md → create/verify .dockerignore
- .eslintrc\* exists → create/verify .eslintignore
- eslint.config.\* exists → ensure config's `ignores` entries cover required patterns
- .prettierrc\* exists → create/verify .prettierignore
- .npmrc or package.json exists → create/verify .npmignore (if publishing)
- terraform files (\*.tf) exist → create/verify .terraformignore
- helm charts present → create/verify .helmignore

**If ignore file already exists**: Verify it contains essential patterns, append missing critical patterns only.
**If ignore file missing**: Create with full pattern set for detected technology.

**Common Patterns by Technology** (from plan.md tech stack):

- **Node.js/JavaScript/TypeScript**: `node_modules/`, `dist/`, `build/`, `*.log`, `.env*`
- **Python**: `__pycache__/`, `*.pyc`, `.venv/`, `venv/`, `dist/`, `*.egg-info/`
- **Java**: `target/`, `*.class`, `*.jar`, `.gradle/`, `build/`
- **C#/.NET**: `bin/`, `obj/`, `*.user`, `*.suo`, `packages/`
- **Go**: `*.exe`, `*.test`, `vendor/`, `*.out`
- **Ruby**: `.bundle/`, `log/`, `tmp/`, `*.gem`, `vendor/bundle/`
- **PHP**: `vendor/`, `*.log`, `*.cache`, `*.env`
- **Rust**: `target/`, `debug/`, `release/`, `*.rs.bk`, `*.rlib`, `*.prof*`, `.idea/`, `*.log`, `.env*`
- **Kotlin**: `build/`, `out/`, `.gradle/`, `.idea/`, `*.class`, `*.jar`, `*.iml`, `*.log`, `.env*`
- **C++**: `build/`, `bin/`, `obj/`, `out/`, `*.o`, `*.so`, `*.a`, `*.exe`, `*.dll`, `.idea/`, `*.log`, `.env*`
- **C**: `build/`, `bin/`, `obj/`, `out/`, `*.o`, `*.a`, `*.so`, `*.exe`, `Makefile`, `config.log`, `.idea/`, `*.log`, `.env*`
- **Swift**: `.build/`, `DerivedData/`, `*.swiftpm/`, `Packages/`
- **R**: `.Rproj.user/`, `.Rhistory`, `.RData`, `.Ruserdata`, `*.Rproj`, `packrat/`, `renv/`
- **Universal**: `.DS_Store`, `Thumbs.db`, `*.tmp`, `*.swp`, `.vscode/`, `.idea/`

**Tool-Specific Patterns**:

- **Docker**: `node_modules/`, `.git/`, `Dockerfile*`, `.dockerignore`, `*.log*`, `.env*`, `coverage/`
- **ESLint**: `node_modules/`, `dist/`, `build/`, `coverage/`, `*.min.js`
- **Prettier**: `node_modules/`, `dist/`, `build/`, `coverage/`, `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`
- **Terraform**: `.terraform/`, `*.tfstate*`, `*.tfvars`, `.terraform.lock.hcl`
- **Kubernetes/k8s**: `*.secret.yaml`, `secrets/`, `.kube/`, `kubeconfig*`, `*.key`, `*.crt`

### Step 5: Parse Tasks Structure

Extract from tasks.md:

- **Task phases**: Setup, Tests, Core, Integration, Polish
- **Task dependencies**: Sequential vs parallel execution rules
- **Task details**: ID, description, file paths, parallel markers [P]
- **Execution flow**: Order and dependency requirements

### Step 6: Execute Implementation

**Phase-by-phase execution**: Complete each phase before moving to the next.

**Sequential tasks**: Execute in order, wait for completion before next task.

**Parallel tasks [P]**: Launch simultaneously using Task tool.

**Parallel Execution Protocol**

When encountering tasks marked with [P] in the same phase:

**6.1 Group parallel tasks** - Identify all [P] tasks that can run together:

- Same phase
- No file path conflicts
- No dependency on each other

**6.2 Launch as subagents simultaneously** (single response with multiple Task calls):

```text
For each parallel task group:
  Task 1 [P]: "Implement [description]. Files: [paths]. Follow plan.md patterns."
  Task 2 [P]: "Implement [description]. Files: [paths]. Follow plan.md patterns."
  Task 3 [P]: "Implement [description]. Files: [paths]. Follow plan.md patterns."
```

**6.3 Wait for all to complete** before proceeding to next group or phase.

**6.4 Conflict detection** - If two [P] tasks affect the same file:

- Execute them sequentially despite [P] marker
- Log: "Tasks X and Y share files, executing sequentially"

**Background Agents for Long Tasks**

For tasks involving test suites, builds, or installations:

- Launch as background agent (user can Ctrl+B to continue)
- Example: "Running full test suite in background..."
- Notify on completion

**TDD flow preserved**: Test tasks still execute before their implementation tasks, but multiple test tasks can run in parallel.

**Validation checkpoints**: After each phase, verify completion before proceeding.

### Step 7: Implementation Execution Rules

- **Setup first**: Initialize project structure, dependencies, configuration
- **Tests before code**: Write tests for contracts, entities, and integration scenarios
- **Core development**: Implement models, services, CLI commands, endpoints
- **Integration work**: Database connections, middleware, logging, external services
- **Polish and validation**: Unit tests, performance optimization, documentation

### Step 8: Progress Tracking and Error Handling

**After each task completion**:

- Mark task as [X] in tasks.md
- Report: "✓ Task [ID]: [description] completed"

**Parallel task monitoring** - When parallel tasks complete:

```text
Parallel batch completed:
✓ Task 2.1 [P]: Create user entity
✓ Task 2.2 [P]: Create order entity
✗ Task 2.3 [P]: Create payment entity (FAILED: [reason])

Proceeding with successful tasks. Failed task queued for retry.
```

**Error handling strategy**:

- Sequential task fails → HALT, report error, suggest fix
- Parallel task fails → Continue others, report at batch end
- Multiple failures in batch → HALT after batch, summarize all errors

**Progress file** (optional, for long implementations) - Create `.claude/progress/[feature-name].md`:

```markdown
## Implementation Progress

Started: [timestamp]
Current Phase: 3/5

### Completed

- [x] Phase 1: Setup (5/5 tasks)
- [x] Phase 2: Tests (8/8 tasks)
- [ ] Phase 3: Core (3/7 tasks) ← IN PROGRESS

### Failed Tasks (pending retry)

- Task 3.4: [error summary]
```

### Step 9: Completion Validation

**Launch parallel validation agents**:

**Agent 1: Spec Compliance Check** (subagent_type: general-purpose)

```text
Compare implemented features against spec.md:
- All functional requirements addressed
- Non-functional requirements met
- Edge cases handled
Output: Compliance report
```

**Agent 2: Test Verification** (subagent_type: general-purpose)

```text
Verify test status:
- All tests pass
- Coverage meets requirements (if specified in constitution)
- No skipped critical tests
Output: Test summary
```

**Agent 3: Code Quality Scan** (subagent_type: Explore)

```text
Quick scan for common issues:
- Debug code left behind (console.log, TODO, etc.)
- Commented-out code blocks
- Missing error handling
Output: Cleanup recommendations
```

**Wait for all validators**, then produce final report:

```markdown
## Implementation Complete

**Tasks**: [X]/[Y] completed
**Tests**: [PASS/FAIL] ([coverage]%)
**Spec Compliance**: [FULL/PARTIAL]

### Summary

- [Key accomplishments]

### Recommendations

- [Any cleanup needed]

### Next Steps

- Run `/speckit.analyze` to verify consistency
- Create PR for review
```

## Note

This command assumes a complete task breakdown exists in tasks.md. If tasks are incomplete or missing, suggest running `/speckit.tasks` first to regenerate the task list.
