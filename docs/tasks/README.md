# Task Tracking System

<!-- DOC_KIND: index -->
<!-- DOC_ROLE: canonical -->
<!-- READ_WHEN: Read when you need the task system workflow, state transitions, and provider rules. -->
<!-- SKIP_WHEN: Skip when you only need the live board or a specific task artifact. -->
<!-- PRIMARY_SOURCES: .hex-skills/environment_state.json, docs/tasks/kanban_board.md -->
<!-- SCOPE: Task tracking system workflow and rules ONLY. Contains task lifecycle, naming conventions, and Linear integration rules. -->
<!-- DO NOT add here: actual task details → Linear issues, kanban status → kanban_board.md -->

## Quick Navigation

- [Kanban Board](kanban_board.md)
- [Reference Hub](../reference/README.md)
- [Database Schema](../project/database_schema.md)

## Agent Entry

| Signal | Value |
|--------|-------|
| Purpose | Defines task workflow, provider rules, status meanings, and task-document conventions for Digital Forest Twin Database. |
| Read When | You need workflow rules, provider behavior, or task lifecycle guidance. |
| Skip When | You only need current active items. |
| Canonical | Yes |
| Next Docs | [Kanban Board](kanban_board.md), [Reference Hub](../reference/README.md) |
| Primary Sources | `docs/tasks/kanban_board.md`, Linear (XRFF team, geosense-ufr workspace) |

---

## Overview

Task provider: **Linear** (`workspace: geosense-ufr`, `team: XR Future Forests`, `key: XRFF`).

All Epics, User Stories, and Tasks tracked in Linear via `mcp__linear__*` MCP methods. Linear is single source of truth.

### Folder Structure

```
docs/tasks/
├── README.md           # This file — workflow and rules
└── kanban_board.md     # Live navigation to active tasks
```

**Live Navigation**: [Kanban Board](kanban_board.md)

---

## Core Concepts

### Task Lifecycle

**Workflow:**

```
Backlog/Postponed → Todo → In Progress → To Review → Done
                                              ↓
                                         To Rework → (back to In Progress)
```

**Statuses:**

| Status | Meaning |
|--------|---------|
| Backlog | New items requiring estimation and approval |
| Postponed | Deferred for future iterations |
| Todo | Approved, ready for development |
| In Progress | Currently being developed |
| To Review | Awaiting code review and validation |
| To Rework | Needs fixes after review |
| Done | Completed, reviewed, tested, approved |

**Manual statuses (not in workflow):** Canceled, Duplicate

### Epic Structure

| Level | Linear Entity | Format |
|-------|--------------|--------|
| Epic | Linear Project | Name + description + target date |
| User Story | Linear Issue with label `user-story` | "As a… I want… So that…" + Given-When-Then AC |
| Task | Linear sub-issue of Story | Context + requirements + acceptance criteria |

### Foundation-First Execution

Critical Rule: Foundation tasks (schema migrations, DB setup) execute BEFORE consumer tasks (scripts, API clients, dashboards) for testability.

---

## Critical Rules

### Rule 1: Linear Integration

**CRITICAL:** Use `mcp__linear__*` MCP methods for all task operations. Do NOT use direct Linear REST API or GitHub CLI.

### Rule 2: Tests in Story Finalizer Only

Tests created ONLY in final Story task (Story Finalizer test task). No separate test tasks during implementation.

### Rule 3: Documentation in Feature Tasks

Documentation updates ALWAYS part of same task as implementation. No separate "Update README" tasks.

### Rule 4: Kanban Context Budget

`kanban_board.md` contains ONLY links and titles. No descriptions, no implementation notes.

---

## Linear Integration

### Team Configuration

| Variable | Value |
|----------|-------|
| Workspace | `geosense-ufr` |
| Team Name | XR Future Forests |
| Team Key | XRFF |
| Team UUID | 5e3b87df-5f1a-4f70-8621-4ced0ed7bdcf |
| Linear URL | `https://linear.app/geosense-ufr` |

### Epic Operations

| Operation | MCP Method |
|-----------|-----------|
| List Epics | `mcp__linear__list_projects(team="XR Future Forests")` |
| Get Epic | `mcp__linear__get_project(query="Epic N")` |
| Create Epic | `mcp__linear__save_project({name, description, team, state: "planned"})` |
| Update Epic | `mcp__linear__save_project({id, state, description})` |

### Story Operations

| Operation | MCP Method |
|-----------|-----------|
| List Stories | `mcp__linear__list_issues(project=epicId, label="user-story")` |
| Get Story | `mcp__linear__get_issue(id=storyId)` |
| Create Story | `mcp__linear__save_issue({title: "US{NNN}: Title", project: epicId, team, labels: ["user-story"], state: "Backlog"})` |
| Update status | `mcp__linear__save_issue({id, state: "In Progress"})` |

### Task Operations

| Operation | MCP Method |
|-----------|-----------|
| List Tasks | `mcp__linear__list_issues(parentId=storyId)` |
| Get Task | `mcp__linear__get_issue(id=taskId)` |
| Create Task | `mcp__linear__save_issue({title: "T{NNN}: Title", parentId: storyId, team, labels: ["implementation"], state: "Backlog"})` |
| Update status | `mcp__linear__save_issue({id, state: "Done"})` |

### Common Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `team` | string | "XR Future Forests" or UUID |
| `state` | string | Backlog, Todo, In Progress, To Review, To Rework, Done |
| `labels` | string[] | user-story, implementation, tests, refactoring, bug |
| `limit` | number | Max results (default 50, max 250) |

---

## Task Workflow

### Planning Guidelines

| Criterion | Rule |
|-----------|------|
| Optimal task size | 3-5 hours per task |
| Too small | < 2 hours → merge with related task |
| Too large | > 8 hours → split into subtasks |
| Story limit | Max 6 implementation tasks + 1 finalizer test task |

### Workflow Skills

| Category | Skill | Purpose |
|----------|-------|---------|
| Planning | ln-210-epic-coordinator | Decompose scope → 3-7 Epics |
| Planning | ln-220-story-coordinator | Decompose Epic → 5-10 Stories |
| Planning | ln-300-task-coordinator | Decompose Story → 1-6 Tasks |
| Validation | ln-310-multi-agent-validator | Validate Stories/Tasks (Backlog → Todo) |
| Execution | ln-400-story-executor | Orchestrate Story execution |
| Execution | ln-401-task-executor | Execute implementation tasks |
| Review | ln-402-task-reviewer | Review tasks (To Review → Done/Rework) |

---

## Task Templates

### User Story Template

```
Title: US{NNN}: [Feature name]
Labels: user-story
Project: [Epic Name]
State: Backlog

As a [role], I want [feature], so that [benefit].

Acceptance Criteria:
- Given [context], when [action], then [result]
```

### Implementation Task Template

```
Title: T{NNN}: [Action + Component]
Labels: implementation
Parent: [Story ID]
State: Backlog

Context: [Why this task exists]
Requirements: [What must be built]
Acceptance Criteria: [Verifiable done conditions]
```

### Story Finalizer Test Task Template

```
Title: T{NNN}: Tests — [Story Name]
Labels: tests
Parent: [Story ID]
State: Backlog (created after all implementation tasks are Done)
```

---

## Label Taxonomy

| Category | Labels |
|----------|--------|
| Functional | feature, bug, refactoring, documentation, testing, infrastructure, database |
| Type | user-story, implementation-task, test-task |
| Status (auto) | backlog, todo, in-progress, to-review, to-rework, done, canceled |

---

## Maintenance

**Update Triggers:**
- When Linear workspace or team changes
- When workflow skills are added or renamed
- When task lifecycle statuses change

**Verification:**
- [ ] Linear team coordinates match kanban_board.md
- [ ] Workflow skills table matches available skills
- [ ] Critical Rules align with current principles

**Last Updated:** 2026-05-11
