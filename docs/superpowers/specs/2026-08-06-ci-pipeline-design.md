# Snelda CI Pipeline Design

## Overview
Implement a continuous integration (CI) pipeline using GitHub Actions to automatically verify code quality, formatting, and tests on every push and pull request to the `main` branch. 

## Goals
- Provide granular, clear feedback in the GitHub Pull Request UI (separate checkmarks for Test, Format, and Lint).
- Optimize execution time by avoiding duplicate dependency fetching and compilation across parallel jobs.
- Use the official `erlef/setup-beam` action for Erlang/Elixir environment provisioning.

## Architecture: "Build & Cache" Pattern

To achieve distinct PR checks without sacrificing speed, the workflow will use a setup-and-fan-out matrix:

1. **`setup` Job:**
   - Checks out the repository.
   - Provisions Erlang (OTP 29) and Elixir (1.20).
   - Restores the `_build` and `deps` cache based on the `mix.lock` hash.
   - Runs `mix deps.get` and `mix compile`.
   - Saves the cache if there were changes.

2. **Parallel Check Jobs (`test`, `format`, `lint`):**
   - Wait for `setup` to complete (`needs: setup`).
   - Check out code and provision Elixir.
   - Restore the exact same cache generated/verified by the `setup` job.
   - Run their specific checks (`mix test`, `mix format --check-formatted`, `mix credo --strict`).
   - Because the app and dependencies are already compiled in the cache, these jobs start nearly instantly.

## Secrets & Permissions
- No special secrets required.
- Standard `contents: read` permissions for the workflow.

## Future Enhancements
- Integrate `dialyxir` for type checking (requires dedicated PLT caching strategies).
- Integrate `excoveralls` to enforce test coverage percentages.
