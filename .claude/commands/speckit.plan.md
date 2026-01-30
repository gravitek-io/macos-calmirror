---
description: Execute the implementation planning workflow using the plan template to generate design artifacts.
handoffs:
  - label: Create Tasks
    agent: speckit.tasks
    prompt: Break the plan into tasks
    send: true
  - label: Create Checklist
    agent: speckit.checklist
    prompt: Create a checklist for the following domain...
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Outline

1. **Setup**: Run `.specify/scripts/bash/setup-plan.sh --json` from repo root and parse JSON for FEATURE_SPEC, IMPL_PLAN, SPECS_DIR, BRANCH. For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").

2. **Load context**: Read FEATURE_SPEC and `.specify/memory/constitution.md`. Load IMPL_PLAN template (already copied).

3. **Execute plan workflow**: Follow the structure in IMPL_PLAN template to:
   - Fill Technical Context (mark unknowns as "NEEDS CLARIFICATION")
   - Fill Constitution Check section from constitution
   - Evaluate gates (ERROR if violations unjustified)
   - Phase 0: Generate research.md (resolve all NEEDS CLARIFICATION)
   - Phase 1: Generate data-model.md, contracts/, quickstart.md
   - Phase 1: Update agent context by running the agent script
   - Re-evaluate Constitution Check post-design

4. **Stop and report**: Command ends after Phase 2 planning. Report branch, IMPL_PLAN path, and generated artifacts.

## Phases

### Phase 0: Outline & Research

**Step 1: Identify research needs**
Extract from Technical Context above:

- Items marked NEEDS CLARIFICATION → research tasks
- Technology choices → best practices tasks
- External integrations → patterns tasks

**Step 2: Launch parallel research agents**

Use the Task tool to spawn these subagents **simultaneously in a single response**:

1. **Codebase Patterns** (subagent_type: Explore)

```
   Search the existing codebase for:
   - Similar features or patterns we can reuse
   - Existing abstractions (repositories, services, components)
   - Current conventions and naming patterns
   Output: List of relevant files and reusable patterns
```

2. **Tech Stack Research** (subagent_type: general-purpose)

```
   For each NEEDS CLARIFICATION in Technical Context:
   - Research current best practices
   - Check latest stable versions
   - Identify breaking changes or migrations
   Output: Recommendations with rationale
```

3. **Integration Patterns** (subagent_type: general-purpose)

```
   For each external dependency or API:
   - Find official documentation patterns
   - Search for common pitfalls
   - Identify security considerations
   Output: Integration guidelines
```

**IMPORTANT**: Launch all three agents in parallel (single message with multiple Task calls), then wait for all to complete before proceeding.

**Step 3: Consolidate in research.md**

After all agents complete, synthesize findings:

```markdown
## Research Summary

### Decisions Made

| Topic | Decision | Rationale | Alternatives |
| ----- | -------- | --------- | ------------ |
| ...   | ...      | ...       | ...          |

### Codebase Patterns Found

- [Pattern]: [File path] - [How to reuse]

### Technical Clarifications

- [Item]: [Resolution]
```

**Output**: research.md with all NEEDS CLARIFICATION resolved

**GATE**: All research agents must complete before Phase 1.

### Phase 1: Design & Contracts

**Prerequisites:** `research.md` complete with all NEEDS CLARIFICATION resolved

**Step 1: Parallel design agents**

Launch these subagents **simultaneously** using Task tool:

1. **Data Model Designer** (subagent_type: general-purpose)

```
   From spec.md and research.md, extract:
   - Entities: name, fields, types, relationships
   - Validation rules from requirements
   - State transitions if applicable
   - Invariants and business rules

   Cross-reference with existing data-model patterns found in research.md
   Output: Draft data-model.md following DDD conventions
```

2. **API Contract Designer** (subagent_type: general-purpose)

```
   From spec.md functional requirements:
   - Map each user action to endpoint
   - Apply REST/GraphQL patterns from research.md
   - Include request/response schemas
   - Define error responses

   Output: OpenAPI or GraphQL schema files
```

3. **Existing Contracts Scanner** (subagent_type: Explore)

```
   Search codebase for:
   - Existing API patterns in /contracts/ or /api/
   - Current entity definitions
   - Shared types or DTOs
   - Naming conventions used

   Output: List of patterns to align with
```

**IMPORTANT**: Launch all three agents in parallel, wait for completion.

**Step 2: Consolidate and align**

After all agents complete:

1. Review Existing Contracts Scanner output
2. Align data-model.md with existing conventions
3. Ensure API contracts follow established patterns
4. Resolve any conflicts between new design and existing code

**Step 3: Generate outputs**

Create/update these files:

- `data-model.md` - Entity definitions with relationships
- `/contracts/*.yaml` or `/contracts/*.graphql` - API schemas
- `questions.md` - Any unresolved design decisions (if any)

**Step 4: Agent context update**

```bash
.specify/scripts/bash/update-agent-context.sh claude
```

This script:

- Detects active AI agent
- Updates agent-specific context file
- Adds new technology from current plan
- Preserves manual additions between markers

**Output**: data-model.md, /contracts/\*, quickstart.md, agent context updated

**GATE**: All design documents must be internally consistent before Phase 2.

## Key rules

- Use absolute paths
- ERROR on gate failures or unresolved clarifications
