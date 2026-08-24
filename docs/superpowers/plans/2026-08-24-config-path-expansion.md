# Config Path Expansion Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the bug where `snelda execute --config <relative-path>` is resolved relative to the daemon's working directory instead of the client's, causing the wrong config (and thus wrong prompt) to be loaded across repositories.

**Architecture:** The `snelda` CLI is a thin client that sends the raw `--config` string over a UNIX socket to a long-lived background daemon. The daemon calls `File.read/1` on that string relative to *its own* CWD (where it was first spawned). The fix is to expand the config path to an absolute path in the CLI client (`parse_args/1`), before it is ever sent to the daemon, so the daemon always reads the file the user intended regardless of where the daemon was started.

**Tech Stack:** Elixir 1.20, escript, `:gen_tcp` UNIX domain sockets, Jason, ExUnit.

## Global Constraints

- Elixir `~> 1.20`.
- 100% test coverage enforced via `mix coveralls`.
- `mix format --check-formatted`, `mix credo --strict`, and `mix dialyzer` must all pass.
- Commit messages follow the `scope: Description` Scoped Commits format (e.g. `cli: Expand config path to absolute before dispatch`).
- No new runtime dependencies.

---

### Task 1: Expand `--config` to an absolute path in the CLI client

**Files:**
- Modify: `lib/snelda/cli.ex:290-308` (the `parse_args(["execute" | rest])` clause)
- Test: `test/snelda/cli_test.exs`

**Interfaces:**
- Consumes: nothing new — reuses the existing `OptionParser` result inside `parse_args/1`.
- Produces: `parse_args(["execute", "--config", <path>, ...])` returns `{:ok, %{command: :execute, config: <absolute path>, vars: ...}}` where `config` is `Path.expand(<path>)`. The `:daemon_*` clauses and error clauses are unchanged.

- [ ] **Step 1: Write the failing test**

Add to `test/snelda/cli_test.exs`:

```elixir
test "expands relative --config to an absolute path" do
  {:ok, %{config: config}} =
    CLI.parse_args(["execute", "--config", ".snelda/commit-verify.json"])

  assert config == Path.expand(".snelda/commit-verify.json")
  assert String.starts_with?(config, "/")
end

test "leaves an already-absolute --config unchanged" do
  abs = "/tmp/some/config.json"

  {:ok, %{config: config}} =
    CLI.parse_args(["execute", "--config", abs])

  assert config == abs
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `mix test test/snelda/cli_test.exs`
Expected: FAIL — first new test fails because `config` is the raw relative string `".snelda/commit-verify.json"`, not the expanded absolute path.

- [ ] **Step 3: Implement the minimal change**

In `lib/snelda/cli.ex`, inside the `parse_args(["execute" | rest])` clause, change the config extraction so the path is expanded once it is confirmed present. Replace:

```elixir
    config = Keyword.get(parsed, :config)

    if is_nil(config) do
      {:error, "--config is required"}
    else
      with {:ok, vars_literal} <- parse_kv(Keyword.get_values(parsed, :var)),
           {:ok, vars_file} <- parse_file_kv(Keyword.get_values(parsed, :var_file)),
           {:ok, vars_stdin} <- parse_stdin(Keyword.get_values(parsed, :var_stdin)) do
        all_vars = Enum.reduce([vars_literal, vars_file, vars_stdin], %{}, &Map.merge(&2, &1))
        {:ok, %{command: :execute, config: config, vars: all_vars}}
      end
    end
```

with:

```elixir
    config = Keyword.get(parsed, :config)

    if is_nil(config) do
      {:error, "--config is required"}
    else
      with {:ok, vars_literal} <- parse_kv(Keyword.get_values(parsed, :var)),
           {:ok, vars_file} <- parse_file_kv(Keyword.get_values(parsed, :var_file)),
           {:ok, vars_stdin} <- parse_stdin(Keyword.get_values(parsed, :var_stdin)) do
        all_vars = Enum.reduce([vars_literal, vars_file, vars_stdin], %{}, &Map.merge(&2, &1))
        {:ok, %{command: :execute, config: Path.expand(config), vars: all_vars}}
      end
    end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `mix test test/snelda/cli_test.exs`
Expected: PASS — both new tests pass, and the pre-existing `"parses literal variables gracefully"` test still passes because `Path.expand("task.json")` is deterministic; if that pre-existing test now fails on the literal `"task.json"` assertion, update its expected `config` to `Path.expand("task.json")` in the same step.

- [ ] **Step 5: Commit**

```bash
git add lib/snelda/cli.ex test/snelda/cli_test.exs
git commit -m "cli: Expand config path to absolute before daemon dispatch"
```

---

### Task 2: Update pre-existing CLI tests that assert on the raw config string

**Files:**
- Modify: `test/snelda/cli_test.exs:5-10` (the `"parses literal variables gracefully"` test)
- Test: `test/snelda/cli_test.exs`

**Interfaces:**
- Consumes: the `parse_args/1` behaviour from Task 1 (config is now `Path.expand/1`-ed).
- Produces: a green test suite where every assertion on `config` expects the expanded absolute path.

- [ ] **Step 1: Run the full suite to find any remaining stale assertions**

Run: `mix test`
Expected: If Task 1 Step 4 already fixed `"parses literal variables gracefully"`, this passes. If any test still asserts a bare relative `config` string, it FAILS here — note the file and line.

- [ ] **Step 2: Update the stale assertion (if not already done)**

In `test/snelda/cli_test.exs`, ensure the `"parses literal variables gracefully"` test reads:

```elixir
  test "parses literal variables gracefully" do
    args = ["execute", "--config", "task.json", "--var", "foo=bar"]

    assert {:ok, %{command: :execute, config: config, vars: %{"foo" => "bar"}}} =
             CLI.parse_args(args)

    assert config == Path.expand("task.json")
  end
```

- [ ] **Step 3: Run the full suite to verify green**

Run: `mix test`
Expected: PASS — `39+` tests pass, 0 failures.

- [ ] **Step 4: Commit**

```bash
git add test/snelda/cli_test.exs
git commit -m "cli: Update tests to expect absolute config path"
```

---

### Task 3: Run full CI gate and rebuild the escript binary

**Files:**
- No source changes. Produces the reinstalled global `snelda` binary.

**Interfaces:**
- Consumes: the fixed `Snelda.CLI` from Tasks 1-2.
- Produces: a `snelda` escript on `$PATH` (`~/.mix/escripts` or `~/.local/bin`) that expands config paths.

- [ ] **Step 1: Run coverage**

Run: `mix coveralls`
Expected: 100% coverage, 0 failures.

- [ ] **Step 2: Run formatter check**

Run: `mix format --check-formatted`
Expected: exit 0 (no output).

- [ ] **Step 3: Run credo**

Run: `mix credo --strict`
Expected: exit 0, no issues.

- [ ] **Step 4: Run dialyzer**

Run: `mix dialyzer`
Expected: exit 0, `done (passed successfully)`.

- [ ] **Step 5: Rebuild and reinstall the escript**

Run: `MIX_ENV=prod mix escript.install --force`
Expected: `snelda` reinstalled to the escript bin dir.

- [ ] **Step 6: Restart the daemon so it picks up the new binary**

Run:
```bash
snelda daemon stop
snelda daemon start
```
Expected: `Daemon stopped.` then `Daemon started successfully (...)`.

---

### Task 4: Verify the fix end-to-end across both repositories

**Files:**
- No changes. Verification only.

**Interfaces:**
- Consumes: the reinstalled binary and restarted daemon from Task 3.
- Produces: evidence that a relative `--config` now resolves per-repository.

- [ ] **Step 1: Verify compliance-backend passes its own Conventional Commits config via relative path**

Run:
```bash
cd /home/peblaho/workspace/redhatinsights/compliance-backend
tmp_msg=$(mktemp)
echo "feat(cyndi): RHINENG-23305 add cleanup rake task to remove leftover DB objects" > "$tmp_msg"
echo "diff --git a/lib/tasks/cyndi.rake b/lib/tasks/cyndi.rake" | snelda execute \
  --config .snelda/commit-verify.json \
  --var-file message="$tmp_msg" \
  --var-stdin diff
echo "exit=$?"
rm -f "$tmp_msg"
```
Expected: `exit=0` (no feedback printed). Previously this FAILED with a "violates Scoped Commits" message.

- [ ] **Step 2: Verify snelda repo still rejects a Conventional Commit via relative path**

Run:
```bash
cd /home/peblaho/workspace/snelda
tmp_msg=$(mktemp)
echo "feat(core): add a thing" > "$tmp_msg"
echo "diff --git a/lib/snelda.ex b/lib/snelda.ex" | snelda execute \
  --config .snelda/commit-verify.json \
  --var-file message="$tmp_msg" \
  --var-stdin diff
echo "exit=$?"
rm -f "$tmp_msg"
```
Expected: `exit=1` with Scoped Commits feedback — confirming snelda's own config is still enforced and there is no cross-repo bleed.

---

## Self-Review

**1. Spec coverage:** The root cause (daemon resolves relative `--config` against its own CWD) is fixed at the single choke point — the CLI client's `parse_args/1` — so every code path that dispatches an execute payload (Git hooks, manual runs) benefits. Covered by Task 1.

**2. Placeholder scan:** No TBD/TODO/"handle edge cases" placeholders; all code and commands are concrete.

**3. Type consistency:** `config` remains a `String.t()` throughout (`Path.expand/1` returns a binary); the `%{command: :execute, config: String.t(), vars: map()}` shape used by `do_main/1` and `run_execute/2` is unchanged, so no downstream signature breaks. `@spec run_execute(String.t(), map())` still holds.

**4. Ambiguity check:** Expansion happens in `parse_args/1` (not `send_payload/2`) so the absolute path is present in the parsed struct, is unit-testable without a socket, and covers both the execute command path and any future consumer of the parsed result.
