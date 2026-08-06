# Excoveralls Integration Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate `excoveralls` to track and enforce test coverage percentages in the CI pipeline, working in a dedicated feature branch and opening a GitHub Pull Request upon completion.

**Architecture:** We will add `excoveralls` as a test dependency, configure `mix.exs` and a new `coveralls.json` file. We will update the GitHub Actions CI pipeline to run `mix coveralls`, and finally submit these changes via a `gh` pull request.

**Tech Stack:** Elixir, ExUnit, Excoveralls, GitHub Actions, Git, GitHub CLI (`gh`).

## Global Constraints

- Must achieve 100% test coverage minimum requirement
- Must ignore `lib/snelda/application.ex` and `lib/snelda.ex`

---

### Task 1: Create Feature Branch

**Files:** None

**Interfaces:**
- Consumes: `main` branch state
- Produces: `feature/excoveralls-integration` branch

- [ ] **Step 1: Checkout new branch**

```bash
git checkout -b feature/excoveralls-integration
```

### Task 2: Add and configure Excoveralls dependency

**Files:**
- Modify: `mix.exs:4-21,24-32`
- Create: `coveralls.json`

**Interfaces:**
- Consumes: Standard Mix project structure.
- Produces: `mix coveralls` command capability.

- [ ] **Step 1: Update `mix.exs` dependencies and project configuration**

Update `mix.exs` to include `excoveralls` in `deps/0` and configure the test coverage tool in `project/0`.

```elixir
  def project do
    [
      app: :snelda,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: [
        plt_local_path: ".plts",
        plt_core_path: ".plts"
      ],
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.github": :test
      ]
    ]
  end

  # ...

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end
```

- [ ] **Step 2: Fetch dependencies**

```bash
mix deps.get
```

- [ ] **Step 3: Create `coveralls.json` configuration**

Create the configuration file to enforce 100% coverage and ignore the application entry point.

```json
{
  "coverage_options": {
    "treat_no_relevant_lines_as_covered": true,
    "minimum_coverage": 100
  },
  "skip_files": [
    "lib/snelda/application.ex",
    "lib/snelda.ex"
  ]
}
```

- [ ] **Step 4: Run test to verify it passes with coverage**

```bash
MIX_ENV=test mix coveralls
```

- [ ] **Step 5: Commit**

```bash
git add mix.exs mix.lock coveralls.json
git commit -m "build: add excoveralls for test coverage enforcement"
```

### Task 3: Update CI Pipeline

**Files:**
- Modify: `.github/workflows/ci.yml:37-47`

**Interfaces:**
- Consumes: The `coveralls` capability added in Task 1.
- Produces: Failing CI if test coverage drops.

- [ ] **Step 1: Modify the `test` job in `ci.yml`**

Change the `Run tests` step to use `mix coveralls`.

```yaml
      - name: Run tests with coverage
        run: mix coveralls
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: enforce test coverage in pipeline"
```

### Task 4: Push Branch and Create Pull Request

**Files:** None

**Interfaces:**
- Consumes: Local commits
- Produces: Remote pull request

- [ ] **Step 1: Push branch to origin**

```bash
git push -u origin HEAD
```

- [ ] **Step 2: Create PR using GitHub CLI**

```bash
gh pr create --title "ci: enforce test coverage with excoveralls" --body "This PR integrates \`excoveralls\` to enforce 100% test coverage in our CI pipeline. It updates the \`mix.exs\` file, adds a \`coveralls.json\` config, and modifies the CI workflow to use \`mix coveralls\` instead of \`mix test\`."
```
