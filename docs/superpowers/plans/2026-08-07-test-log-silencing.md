# Test Log Silencing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clean up the `mix test` output by silencing `Logger` output for passing tests.

**Architecture:** Modify `ExUnit.start()` to enable `capture_log: true`.

**Tech Stack:** Elixir, ExUnit

## Global Constraints

- Must rely only on standard ExUnit mechanisms.

---

### Task 1: Enable Log Capturing

**Files:**
- Modify: `test/test_helper.exs:1`

**Interfaces:**
- Consumes: N/A
- Produces: Cleaner test output

- [ ] **Step 1: Write the failing check**

Run: `mix test` and observe if the output is polluted by Logger (it is, currently).

- [ ] **Step 2: Write minimal implementation**

Edit `test/test_helper.exs`:

```elixir
ExUnit.start(capture_log: true)
```

- [ ] **Step 3: Run test to verify it passes**

Run: `mix test`
Expected: PASS, and the output should no longer contain `[info]` log lines from passing tests.

- [ ] **Step 4: Commit**

```bash
git add test/test_helper.exs
git commit -m "test: Silence logs for passing tests"
```

