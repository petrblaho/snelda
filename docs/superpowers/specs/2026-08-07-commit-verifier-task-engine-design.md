# Snelda: Config-Driven LLM Task Engine
**Date**: 2026-08-07
**Status**: Approved

## Purpose
Snelda is a generic, config-driven LLM task engine. While it can be used for any LLM-based text processing task, its MVP use case is acting as a `commit-msg` git hook to verify that git commits adhere to a strict semantic standard (specifically, the "Stop Using Conventional Commits" philosophy).

## Architecture
Snelda utilizes an "emacsclient" architectural pattern to ensure zero-latency execution for frequent tasks (like git hooks) without requiring manual daemon management.

1. **Escript CLI**: Snelda is compiled into a globally installable binary (`escript`).
2. **Daemon-or-Spawn**: When the CLI is invoked (e.g., `snelda execute ...`), it attempts to connect to a local TCP socket (`/tmp/snelda.sock`).
   - If the connection fails, the CLI transparently spawns a detached background instance of itself (`snelda daemon`), waits for the socket to initialize, and reconnects.
3. **Payload Transmission**: The CLI sends a JSON payload containing the task configuration path and execution variables to the background daemon over TCP.

## Task Configuration
Tasks are not hardcoded into Snelda. Instead, they are defined in configuration files (JSON) that instruct Snelda how to construct the prompt and evaluate the response.

A task configuration contains:
- **LLM Settings**: Model preference, temperature, etc.
- **System Prompt**: The persona and instructions for the LLM.
- **User Prompt Template**: A template string with placeholders (e.g., `{{diff}}` and `{{message}}`) that Snelda will populate at runtime using CLI arguments.
- **Output Schema**: The expected JSON structure the LLM should return.
- **Success Condition**: A rule to map the LLM's JSON response to a system exit code (e.g., if `valid == true`, exit `0`; else print `feedback` and exit `1`).

## Execution & Output Flow
1. The user triggers the task (e.g., via a git hook executing `snelda execute --config .snelda/commit-verify.json --var diff="..." --var message="..."`).
2. The Snelda daemon interpolates the variables into the prompt and queries the LLM API.
3. The LLM returns a structured JSON response (e.g., `{"valid": false, "feedback": "Missing imperative mood."}`).
4. The daemon evaluates the success condition and sends the result back to the short-lived CLI process.
5. The CLI prints any feedback to standard error and exits with the appropriate code (e.g., `0` for pass, `1` for fail).

## MVP Use Case: Commit Verifier
The first configuration implemented will be the Commit Verifier.
- **Trigger**: `.githooks/commit-msg`
- **Context Passed**: `git diff --cached` and the commit message text.
- **LLM Task**: Evaluate if the message explains *what* and *why* (meaning), uses imperative mood, and avoids conventional commit prefixes.
- **UX**: If the LLM deems the commit poor, the git hook aborts, and the developer sees the LLM's actionable feedback in their terminal.
