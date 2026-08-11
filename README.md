# Snelda

Snelda is a lightweight, config-driven LLM task engine built in Elixir. It is designed to evaluate text payloads (like Git commit messages, PR descriptions, or source code diffs) against configurable LLM prompts and rules.

Its primary design goal is **zero-latency execution** for repetitive command-line tasks (like Git hooks). To achieve this, Snelda uses an `emacsclient`-style architecture: the CLI acts as a thin client that talks to a background daemon over a local TCP socket. If the daemon isn't running, the CLI seamlessly spawns it, waits for it to boot, and connects.

## Features

- **Config-Driven:** Define your LLM prompts, models, and success conditions in simple JSON files. Snelda handles the rest.
- **Zero-Latency Execution:** The heavy Elixir VM runs in the background. The CLI executes instantly via TCP.
- **Provider Agnostic:** Uses the standard OpenAI JSON format. Point it to a local LiteLLM proxy to route to Anthropic, OpenAI, or local models.
- **Massive Payload Support:** Pass massive context variables (like `git diff`) safely via `--var-stdin` or `--var-file` to bypass OS `ARG_MAX` limits.

## Installation

Snelda is compiled as a standalone `escript` executable. You must have Elixir installed on your system.

```bash
# Fetch dependencies
mix deps.get

# Build the executable for your global bin directory (~/.mix/escripts)
# Note: MIX_ENV=prod is required so the background daemon does not emit debug logs to stdout
MIX_ENV=prod mix escript.install
```

Ensure `~/.mix/escripts` is in your system `$PATH`.

### Local Development Build

If you are developing Snelda and want to test it locally without installing it globally, use `escript.build`:

```bash
# Creates a 'snelda' executable in the current directory
MIX_ENV=prod mix escript.build

# You can then run it directly
./snelda execute --config ...
```

## Daemon Lifecycle

Snelda runs a background daemon to quickly evaluate tasks without booting the Erlang VM every time.

- `snelda daemon start`: Starts the daemon in the background (detached).
- `snelda daemon stop`: Stops the background daemon.
- `snelda daemon status`: Checks if the daemon is running (and reports its PID and TTY mode).
- `snelda daemon run`: Runs the daemon in the foreground (blocking).

If you run `snelda execute ...`, it will automatically check if the daemon is running and start it in the background if necessary.

## Usage Example: Git Commit Verifier

Snelda's MVP use-case is a Git `commit-msg` hook that ensures commits follow the "Stop Using Conventional Commits" philosophy.

1. **Create a configuration file (`.snelda/commit-verify.json`):**

```json
{
  "proxy_url": "http://localhost:4000/v1/chat/completions",
  "model": "claude-3-5-sonnet-20240620",
  "system_prompt": "You enforce the 'Stop Using Conventional Commits' philosophy. Ensure the commit explains what changed and why, uses the imperative mood, and has no conventional prefixes like feat: or fix:.",
  "user_prompt": "Evaluate this commit:\nMessage:\n{{message}}\n\nDiff:\n{{diff}}",
  "success_condition": "valid == true"
}
```

2. **Run Snelda from your Git hook (`.githooks/commit-msg`):**

```bash
#!/bin/bash
MESSAGE_FILE=$1

# Safely pass large diff via stdin, and message via file
git diff --cached | snelda execute \
  --config .snelda/commit-verify.json \
  --var-file message="$MESSAGE_FILE" \
  --var-stdin diff
```

When you commit, Snelda will silently spawn the background daemon (if needed), pass the diff and message to the LLM, evaluate the JSON response, and exit with `0` (allowing the commit) or print the LLM's feedback and exit with `1` (blocking the commit).


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

### Local Git Hooks (Opt-In)

To automatically enforce formatting, linting, and commit message standards locally before pushing to CI, you can configure git to use the repository's custom hooks:

```bash
git config core.hooksPath .githooks
```

- **On `commit`**: Runs formatting and credo checks. (Use `git commit -n` to bypass).
- **On `push`**: Runs tests, dialyzer, and enforces the `scope: Description` commit message format. (Use `git push --no-verify` to bypass).
