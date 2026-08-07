# Snelda

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `snelda` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:snelda, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/snelda>.


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
