# CI: Adopt schnur's Improvements (parallelize + pin versions + PLT prebuild) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut snelda CI wall time and add a warnings-as-errors gate by porting schnur's CI improvements: pin Elixir/OTP via workflow `env:`, remove the `setup` gate so jobs run in parallel, make `test` own the deps cache + compile gate, and prebuild the dialyzer PLT keyed on `mix.exs`.

**Architecture:** Single-workflow edit (`.github/workflows/ci.yml`) plus one `mix.exs` alias. Delete the `setup` job and its `needs: setup` gates; each of `test/format/lint/typecheck` becomes a self-sufficient cache consumer (restore cache, install deps on miss). `test` is the cache owner and gains `mix compile --warnings-as-errors`. Versions move into top-level `env:` and drift is corrected to match the local toolchain.

**Tech Stack:** GitHub Actions (`actions/cache@v4`, `erlef/setup-beam@v1`), Elixir/Mix, Dialyxir. snelda is a plain escript — no Ecto/Postgres, no `test/support/`, no `plt_add_apps`.

## Global Constraints

- Elixir `1.20.3`, OTP `29.0`; `MIX_ENV: test` globally. (Local toolchain confirmed: Elixir 1.20.3 / OTP 29.)
- Required status checks on `main` (verified via `gh api`): **Test, Format, Lint, Typecheck, Lint Commit Messages**. "Setup and Compile" is NOT required — safe to remove.
- `enforce_admins: true`, `allow_force_pushes: false` on `main` — never force-push `main`; feature-branch force-push is fine.
- `actions/cache@v4`: an entry is saved in the post step only on a primary-key miss at restore; keys are immutable. A stable key never re-saves.
- Commit style: Scoped Commits `<scope>: <description>` (repo convention: lowercase description; regex `^[a-zA-Z0-9_\-]+: [A-Z0-9a-z].*`). Repo pre-commit hook runs format + credo — never `--no-verify`.
- Out of scope (deliberate): dialyzer test-env parity in pre-push (schnur item #5) buys nothing here — snelda has no `test/support/` and no `plt_add_apps`, so `mix dialyzer` analyzes the same modules regardless of env.

## Baseline (snelda ci.yml today)

- `setup` job compiles, then `test/format/lint/typecheck` each `needs: setup` (serialized start + provisioning gap).
- Versions hardcoded 5× as `elixir "1.20.2"` / `otp "29.0"` (Elixir drift vs local 1.20.3).
- `test` restores cache with no `id`/`restore-keys`, no install-on-miss, no warnings-as-errors.
- Typecheck PLT cache key uses only `mix.lock` + literal `1.20.2-29.0`; no PLT prebuild step.

---

### Task 1: Pin & correct Elixir/OTP versions via workflow `env:`

**Files:** Modify `.github/workflows/ci.yml`

- [ ] Add to the top-level `env:` block: `ELIXIR_VERSION: "1.20.3"` and `OTP_VERSION: "29.0"` (keep `MIX_ENV: test`).
- [ ] Replace every `elixir-version: "1.20.2"` with `elixir-version: ${{ env.ELIXIR_VERSION }}` and every `otp-version: "29.0"` with `otp-version: ${{ env.OTP_VERSION }}` (all 5 jobs, once the setup job still exists; count updates again after Task 3).
- [ ] Validate YAML: `ruby -ryaml -e 'YAML.load_file(".github/workflows/ci.yml")'` (or `python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))' .github/workflows/ci.yml`).
- [ ] Commit: `ci: pin elixir and otp versions via workflow env`

### Task 2: Make `test` own the deps cache and add the compile gate

**Files:** Modify `.github/workflows/ci.yml` (test job)

- [ ] Add `id: mix-cache` and a `restore-keys: |` fallback (`${{ runner.os }}-mix-`) to the test job's "Restore dependencies cache" step.
- [ ] Add an `Install dependencies` step gated on `if: steps.mix-cache.outputs.cache-hit != 'true'` running `mix deps.get`.
- [ ] Add a `Compile (warnings as errors)` step running `mix compile --warnings-as-errors`, placed before "Run tests with coverage".
- [ ] Validate YAML.
- [ ] Commit: `ci: make test job own deps cache and add compile gate`

### Task 3: Remove the `setup` job and make consumers self-sufficient

**Files:** Modify `.github/workflows/ci.yml`

- [ ] Delete the `setup` job entirely.
- [ ] Remove `needs: setup` from `test`, `format`, `lint`, `typecheck`.
- [ ] For `format`, `lint`, `typecheck`: add `id: mix-cache` + `restore-keys` to their cache step and add an `Install dependencies` step (`if: steps.mix-cache.outputs.cache-hit != 'true'`, `mix deps.get`) so cold-cache runs still have deps (previously provided by `setup`).
- [ ] Validate YAML.
- [ ] Commit: `ci: run checks in parallel by removing setup gate`

### Task 4: Prebuild the dialyzer PLT, keyed on mix.exs

**Files:** Modify `mix.exs` (aliases), `.github/workflows/ci.yml` (typecheck job)

- [ ] Add `aliases/0` to `mix.exs` project config with `"dialyzer.build": ["dialyzer --plt"]`, and wire `aliases: aliases()` into `project/0`.
- [ ] In the typecheck job, change the PLT cache `key` to `${{ runner.os }}-plt-${{ hashFiles('mix.lock', 'mix.exs') }}-${{ env.ELIXIR_VERSION }}-${{ env.OTP_VERSION }}` and update `restore-keys` accordingly (drop the literal `1.20.2-29.0`).
- [ ] Add a `Build PLT` step (`if: steps.plt-cache.outputs.cache-hit != 'true'`) running `mkdir -p .plts && mix dialyzer.build`, placed before "Run dialyzer".
- [ ] Verify locally: `mix dialyzer.build` runs; `mix format --check-formatted` clean on `mix.exs`.
- [ ] Validate YAML.
- [ ] Commit: `ci: prebuild dialyzer plt and key cache on mix.exs`

### Task 5: Validate on a PR

- [ ] Push branch, open PR.
- [ ] Wait for CI; confirm Test/Format/Lint/Typecheck/Lint Commit Messages all pass; note wall time vs baseline.
- [ ] Prove the compile gate: push a throwaway commit adding an unused variable, confirm `Test` fails at the compile step, then drop it and confirm green.
- [ ] Leave PR for review (no auto-merge).

## Self-Review

- **Spec coverage:** version pinning (Task 1), parallelization (Task 3), test-owns-cache + compile gate (Task 2), PLT prebuild (Task 4), validation (Task 5). schnur item #5 deliberately excluded with rationale in Global Constraints.
- **Cache-owner correctness:** after `setup` is gone, `test` owns the primary `${{ runner.os }}-mix-${{ hashFiles('**/mix.lock') }}` key; consumers restore via the same key + restore-keys and install on miss, so cold starts are correct and only one job needs to save.
- **Placeholder scan:** none — every edit specifies the exact step and condition.
- **Consistency:** all jobs reference `${{ env.ELIXIR_VERSION }}`/`${{ env.OTP_VERSION }}`; the PLT key uses the same env vars, so a version bump invalidates the PLT automatically.
