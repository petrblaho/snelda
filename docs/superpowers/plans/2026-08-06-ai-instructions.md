# AI Instructions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Set up project-wide AI instructions adhering to DRY principles, using `README.md` as the single source of truth, with `AGENTS.md` and `CLAUDE.md` acting as pointers.

**Architecture:** A markdown-based configuration strategy where `README.md` contains the primary directives and workflows for both humans and AI agents. `AGENTS.md` directs agents to `README.md`. `CLAUDE.md` is a plain text file (not a symlink, avoiding cross-platform fragility) pointing to `AGENTS.md`.

**Tech Stack:** Markdown, Git, Elixir (Mix tasks referenced)

## Global Constraints
- Target Files: `AGENTS.md`, `CLAUDE.md`, `README.md`
- Core AI instructions MUST include: Outside-In TDD process, exact CI verification commands, and a strict rule to never skip tests.
- DRY Constraint: Instructions must live in one place only (`README.md`).
- Compatibility Constraint: Do not use symlinks to prevent Windows checkout issues.

---

### Task 1: Update `README.md` with Source of Truth Instructions

**Files:**
- Modify: `README.md`

**Interfaces:**
- Produces: An updated `README.md` with human and bot-readable workflow instructions.

- [x] **Step 1: Check existing `README.md`**
Verify the file exists before appending to ensure idempotency.
```bash
if [ -f README.md ]; then echo "README.md exists"; fi
```

- [x] **Step 2: Append the Development section**
Append the content using `cat << 'EOF' >> README.md` to avoid vague directives:

```bash
cat << 'EOF' >> README.md

## Development

### AI & Human Contributor Guidelines

1. **Never skip tests.**
2. **All CI checks must pass locally** before you declare a task finished or ready for review.

Contributors and AI agents are expected to follow an **Outside-In TDD (Test-Driven Development)** approach:
1. Write a failing integration/feature test.
2. Write failing unit tests for individual modules.
3. Implement the minimum code required to pass the tests.
4. Refactor while maintaining 100% test coverage.

Before submitting a pull request, ensure all local checks pass. Run the following commands:
- `mix coveralls` (Enforces 100% test coverage)
- `mix format --check-formatted` (Checks code formatting)
- `mix credo --strict` (Lints the code)
- `mix dialyzer` (Runs typechecking)

Additionally, this project strictly adheres to [Conventional Commits](https://www.conventionalcommits.org/) for all commit messages.
EOF
```

- [x] **Step 3: Verify the changes**
Run: `grep -q "Outside-In TDD" README.md && echo "Success"`
Expected: Output showing "Success"

- [x] **Step 4: Commit**
```bash
git add README.md
git commit -m "docs: add development workflow and CI check requirements to README"
```

---

### Task 2: Create `AGENTS.md` (Pointer to README)

**Files:**
- Create: `AGENTS.md`

**Interfaces:**
- Produces: A markdown file that redirects AI agents to `README.md`.

- [x] **Step 1: Write `AGENTS.md` content**
Create the file with pointer content:
```bash
cat << 'EOF' > AGENTS.md
# AI Agent Instructions

All instructions for AI agents, including core directives, CI commands, and TDD workflows, have been consolidated into `README.md` to maintain a single source of truth for both humans and bots.

Please read the `## Development` section in `README.md`.
EOF
```

- [x] **Step 2: Commit**
```bash
git add AGENTS.md
git commit -m "docs: create AGENTS.md redirecting AI agents to README.md"
```

---

### Task 3: Create Local Tooling File (`CLAUDE.md`)

**Files:**
- Create: `CLAUDE.md`

**Interfaces:**
- Consumes: `AGENTS.md` (from Task 2)
- Produces: `CLAUDE.md` file for local agent automation.

- [x] **Step 1: Create the pointer file**
Run the following command to create the file without symlink fragility:
```bash
echo "Please read \`AGENTS.md\` for AI instructions." > CLAUDE.md
```

- [x] **Step 2: Commit**
```bash
git add CLAUDE.md
git commit -m "build: add CLAUDE.md file pointing to AGENTS.md"
```