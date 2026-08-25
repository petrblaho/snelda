# Snelda LLM Client Library Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Snelda an embeddable, per-call-configurable LLM client library (`Snelda.LLM.chat/1`) that other Elixir apps can depend on, without booting Snelda's daemon, and without breaking the existing CLI/daemon.

**Architecture:** Two independent changes. (1) Decouple library from daemon: remove `mod: {Snelda.Application, []}` so loading `:snelda` starts no processes; the CLI starts the daemon supervision tree explicitly. (2) Public API: add documented, stateless `Snelda.LLM.chat/1` with per-call provider URL, model, `auth`, prompts, and `response_format` (`:json` default | `:text`), returning structured tagged-tuple errors; refactor the daemon's `execute` path and the old `execute/1` to go through `chat/1`.

**Tech Stack:** Elixir 1.20.3 / OTP 29, `Req` (HTTP), `Jason` (JSON), ExUnit + `Req.Test`/`Plug` (test proxy), `Supervisor`.

## Global Constraints

- Elixir `1.20.3`, OTP `29.0`; runtime deps limited to existing set (`req`, `jason`, `phoenix_pubsub`) — no new runtime deps.
- Snelda persists nothing and logs no credentials; `auth`/secret headers must never appear in returned errors or logs.
- `response_format` defaults to `:json`; `:text` is the only other value.
- Structured error tuples only: `{:error, {:invalid_json, raw}}`, `{:error, {:http, status, body}}`, `{:error, {:request_failed, reason}}`.
- CI gates must pass: `mix coveralls` (100%), `mix format --check-formatted`, `mix credo --strict`, `mix dialyzer`.
- Commit style: Scoped Commits `<scope>: <description>` (repo regex `^[a-zA-Z0-9_\-]+: [A-Z0-9a-z].*`, lowercase description is the repo norm). Repo pre-commit hook runs format + credo — never `--no-verify`.
- The CLI/daemon (`daemon run/start/status/stop`, socket `execute`/`ping`/`stop`) must remain functionally unchanged after decoupling.

## File Structure

- `lib/snelda/llm.ex` — the public library API. Grows from an internal `execute/1` into a documented `chat/1` (+ private helpers for auth headers, response parsing, error shaping). Sole responsibility: one stateless OpenAI-format chat call.
- `lib/snelda/application.ex` — drop `mod:` responsibility; provide a start helper the CLI calls to boot the daemon tree.
- `lib/snelda/cli.ex` — daemon commands start the supervision tree explicitly instead of relying on `Application` auto-start.
- `mix.exs` — `application/0` loses `mod:`.
- `lib/snelda/socket/handler.ex` — `execute_task/2` LLM call routed through `chat/1`.
- `test/snelda/llm_test.exs` — expanded for `chat/1` (json/text, auth, structured errors).
- `test/snelda/application_test.exs` (new) — regression: loading `:snelda` starts no daemon/socket.

---

### Task 1: Add `Snelda.LLM.chat/1` (json + text + auth + structured errors)

**Files:**
- Modify: `lib/snelda/llm.ex`
- Test: `test/snelda/llm_test.exs`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `Snelda.LLM.chat/1`:
  - Input map keys: `:proxy_url` (String, required), `:model` (String, required), `:system_prompt` (String, required), `:user_prompt` (String, required), `:auth` (`{:bearer, String} | {:headers, [{String, String}]} | nil`, optional), `:response_format` (`:json | :text`, optional, default `:json`), `:req_opts` (keyword, optional).
  - Returns: `{:ok, map()}` (json), `{:ok, String.t()}` (text), `{:error, {:invalid_json, String.t()}}`, `{:error, {:http, non_neg_integer(), term()}}`, `{:error, {:request_failed, term()}}`.

- [ ] **Step 1: Write failing tests for `chat/1`**

Add these tests to `test/snelda/llm_test.exs` (keep existing `execute/1` tests for now; Task 3 handles them):

```elixir
  describe "chat/1" do
    test "json mode parses object" do
      Req.Test.stub(Snelda.LLMChatJson, fn conn ->
        Req.Test.json(conn, %{
          "choices" => [%{"message" => %{"content" => "{\"ok\": true}"}}]
        })
      end)

      opts = %{
        proxy_url: "http://localhost",
        model: "m",
        system_prompt: "s",
        user_prompt: "u",
        req_opts: [plug: {Req.Test, Snelda.LLMChatJson}]
      }

      assert {:ok, %{"ok" => true}} = LLM.chat(opts)
    end

    test "json mode returns structured invalid_json error" do
      Req.Test.stub(Snelda.LLMChatBad, fn conn ->
        Req.Test.json(conn, %{
          "choices" => [%{"message" => %{"content" => "nope"}}]
        })
      end)

      opts = %{
        proxy_url: "http://localhost",
        model: "m",
        system_prompt: "s",
        user_prompt: "u",
        req_opts: [plug: {Req.Test, Snelda.LLMChatBad}]
      }

      assert {:error, {:invalid_json, "nope"}} = LLM.chat(opts)
    end

    test "text mode returns raw string and omits response_format" do
      Req.Test.stub(Snelda.LLMChatText, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        refute Map.has_key?(decoded, "response_format")
        Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => "hello world"}}]})
      end)

      opts = %{
        proxy_url: "http://localhost",
        model: "m",
        system_prompt: "s",
        user_prompt: "u",
        response_format: :text,
        req_opts: [plug: {Req.Test, Snelda.LLMChatText}]
      }

      assert {:ok, "hello world"} = LLM.chat(opts)
    end

    test "bearer auth sets Authorization header" do
      Req.Test.stub(Snelda.LLMChatBearer, fn conn ->
        assert ["Bearer sk-test"] = Plug.Conn.get_req_header(conn, "authorization")
        Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => "{}"}}]})
      end)

      opts = %{
        proxy_url: "http://localhost",
        model: "m",
        system_prompt: "s",
        user_prompt: "u",
        auth: {:bearer, "sk-test"},
        req_opts: [plug: {Req.Test, Snelda.LLMChatBearer}]
      }

      assert {:ok, %{}} = LLM.chat(opts)
    end

    test "headers auth merges custom headers" do
      Req.Test.stub(Snelda.LLMChatHeaders, fn conn ->
        assert ["k-123"] = Plug.Conn.get_req_header(conn, "x-api-key")
        Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => "{}"}}]})
      end)

      opts = %{
        proxy_url: "http://localhost",
        model: "m",
        system_prompt: "s",
        user_prompt: "u",
        auth: {:headers, [{"x-api-key", "k-123"}]},
        req_opts: [plug: {Req.Test, Snelda.LLMChatHeaders}]
      }

      assert {:ok, %{}} = LLM.chat(opts)
    end

    test "nil auth sends no authorization header" do
      Req.Test.stub(Snelda.LLMChatNoAuth, fn conn ->
        assert [] = Plug.Conn.get_req_header(conn, "authorization")
        Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => "{}"}}]})
      end)

      opts = %{
        proxy_url: "http://localhost",
        model: "m",
        system_prompt: "s",
        user_prompt: "u",
        req_opts: [plug: {Req.Test, Snelda.LLMChatNoAuth}]
      }

      assert {:ok, %{}} = LLM.chat(opts)
    end

    test "http error returns structured tuple" do
      Req.Test.stub(Snelda.LLMChatHttp, fn conn ->
        Plug.Conn.send_resp(conn, 429, "rate limited")
      end)

      opts = %{
        proxy_url: "http://localhost",
        model: "m",
        system_prompt: "s",
        user_prompt: "u",
        req_opts: [plug: {Req.Test, Snelda.LLMChatHttp}]
      }

      assert {:error, {:http, 429, _body}} = LLM.chat(opts)
    end

    test "transport failure returns request_failed" do
      opts = %{
        proxy_url: "http://localhost:9999/broken",
        model: "m",
        system_prompt: "s",
        user_prompt: "u",
        req_opts: [retry: false]
      }

      assert {:error, {:request_failed, _reason}} = LLM.chat(opts)
    end
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/snelda/llm_test.exs`
Expected: the new `describe "chat/1"` tests FAIL with `undefined function Snelda.LLM.chat/1`; existing `execute/1` tests still pass.

- [ ] **Step 3: Implement `chat/1`**

Replace the entire contents of `lib/snelda/llm.ex` with:

```elixir
defmodule Snelda.LLM do
  @moduledoc """
  Stateless OpenAI-format chat completion client.

  `chat/1` is the public library entry point. It holds no configuration and
  persists nothing: the provider URL, model, credentials, prompts, and desired
  response format are all passed per call. Credentials are never logged and
  never embedded in returned errors.
  """

  @type auth :: {:bearer, String.t()} | {:headers, [{String.t(), String.t()}]} | nil

  @type opts :: %{
          required(:proxy_url) => String.t(),
          required(:model) => String.t(),
          required(:system_prompt) => String.t(),
          required(:user_prompt) => String.t(),
          optional(:auth) => auth(),
          optional(:response_format) => :json | :text,
          optional(:req_opts) => keyword()
        }

  @doc """
  Perform a single chat completion.

  Returns `{:ok, map}` for `response_format: :json` (default) and
  `{:ok, binary}` for `response_format: :text`. Errors are structured:
  `{:error, {:invalid_json, raw}}`, `{:error, {:http, status, body}}`,
  `{:error, {:request_failed, reason}}`.
  """
  @spec chat(opts()) ::
          {:ok, map()}
          | {:ok, String.t()}
          | {:error, {:invalid_json, String.t()}}
          | {:error, {:http, non_neg_integer(), term()}}
          | {:error, {:request_failed, term()}}
  def chat(opts) do
    proxy_url = Map.fetch!(opts, :proxy_url)
    model = Map.fetch!(opts, :model)
    sys = Map.fetch!(opts, :system_prompt)
    usr = Map.fetch!(opts, :user_prompt)
    format = Map.get(opts, :response_format, :json)
    req_opts = Map.get(opts, :req_opts, [])
    auth = Map.get(opts, :auth)

    payload = build_payload(model, sys, usr, format)
    request_opts = [json: payload] ++ auth_opts(auth) ++ req_opts

    case Req.post(proxy_url, request_opts) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        content = get_in(body, ["choices", Access.at(0), "message", "content"]) || ""
        parse_content(content, format)

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http, status, body}}

      {:error, exception} ->
        {:error, {:request_failed, exception}}
    end
  end

  defp build_payload(model, sys, usr, :json) do
    %{
      model: model,
      response_format: %{type: "json_object"},
      messages: [
        %{role: "system", content: sys <> "\n\nRespond strictly in JSON."},
        %{role: "user", content: usr}
      ]
    }
  end

  defp build_payload(model, sys, usr, :text) do
    %{
      model: model,
      messages: [
        %{role: "system", content: sys},
        %{role: "user", content: usr}
      ]
    }
  end

  defp parse_content(content, :json) do
    case Jason.decode(content) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, _} -> {:error, {:invalid_json, content}}
    end
  end

  defp parse_content(content, :text), do: {:ok, content}

  defp auth_opts(nil), do: []
  defp auth_opts({:bearer, key}), do: [auth: {:bearer, key}]
  defp auth_opts({:headers, headers}), do: [headers: headers]
end
```

Note: `Req` supports `auth: {:bearer, key}` natively (sets `Authorization: Bearer`), and `headers: [...]` merges request headers — this is why the two auth variants map cleanly.

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/snelda/llm_test.exs`
Expected: all `chat/1` tests PASS. The existing `execute/1` tests will now FAIL with `undefined function Snelda.LLM.execute/1` because `execute/1` was removed — that is expected and fixed in Task 3. (If running only this task in isolation, temporarily note the failures belong to Task 3.)

- [ ] **Step 5: Commit**

```bash
git add lib/snelda/llm.ex test/snelda/llm_test.exs
git commit -m "llm: add per-call chat/1 with json/text and structured errors"
```

---

### Task 2: Route the daemon execute path and old `execute/1` through `chat/1`

**Files:**
- Modify: `lib/snelda/llm.ex` (add back a thin `execute/1` wrapper)
- Modify: `lib/snelda/socket/handler.ex:110-131` (`execute_task/2`) — no signature change; it keeps calling `Snelda.LLM`
- Test: `test/snelda/llm_test.exs`

**Interfaces:**
- Consumes: `Snelda.LLM.chat/1` from Task 1.
- Produces: `Snelda.LLM.execute/1` — same input map as before (`proxy_url`, `model`, `system_prompt`, `user_prompt`, `req_opts`), returning `{:ok, map}` | `{:error, String.t()}` (flat string, preserving the daemon's existing feedback format), implemented as a `chat/1` wrapper in `:json` mode.

- [ ] **Step 1: Restore/keep the existing `execute/1` tests and confirm the contract**

The four original tests in `test/snelda/llm_test.exs` (the top-level `test "..."` blocks for `execute/1`) already assert the flat-string contract:
- `{:ok, %{...}}` on valid JSON
- `{:error, "LLM returned invalid JSON" <> _}`
- `{:error, "Proxy returned HTTP 500" <> _}`
- `{:error, "Request failed" <> _}`

Leave them as-is. They are the spec for the wrapper.

- [ ] **Step 2: Run tests to verify `execute/1` currently fails**

Run: `mix test test/snelda/llm_test.exs`
Expected: the four `execute/1` tests FAIL with `undefined function Snelda.LLM.execute/1` (removed in Task 1).

- [ ] **Step 3: Add the `execute/1` wrapper over `chat/1`**

Append this function to `lib/snelda/llm.ex` (inside the module, after `chat/1`):

```elixir
  @doc """
  Backwards-compatible JSON execute used by the daemon's `execute` task.

  Wraps `chat/1` in `:json` mode and maps structured errors back to the flat
  string messages the socket protocol has always returned.
  """
  @spec execute(map()) :: {:ok, map()} | {:error, String.t()}
  def execute(opts) do
    case chat(Map.put(opts, :response_format, :json)) do
      {:ok, parsed} when is_map(parsed) ->
        {:ok, parsed}

      {:error, {:invalid_json, raw}} ->
        {:error, "LLM returned invalid JSON: #{raw}"}

      {:error, {:http, status, body}} ->
        {:error, "Proxy returned HTTP #{status}: #{inspect(body)}"}

      {:error, {:request_failed, exception}} ->
        {:error, "Request failed: #{inspect(exception)}"}
    end
  end
```

- [ ] **Step 4: Run tests to verify everything passes**

Run: `mix test test/snelda/llm_test.exs`
Expected: all tests PASS — both the `chat/1` describe block and the four `execute/1` tests.

- [ ] **Step 5: Verify the daemon execute path still works end-to-end**

Run: `mix test test/snelda/socket/handler_execute_test.exs`
Expected: PASS — `Snelda.Socket.Handler.execute_task/2` still calls `Snelda.LLM.execute/1`, whose behavior is unchanged.

- [ ] **Step 6: Commit**

```bash
git add lib/snelda/llm.ex
git commit -m "llm: reimplement execute/1 as a chat/1 wrapper"
```

---

### Task 3: Decouple the library from the daemon (no auto-start)

**Files:**
- Modify: `mix.exs:34-40` (`application/0`)
- Modify: `lib/snelda/application.ex`
- Modify: `lib/snelda/cli.ex:141-158` (`run_daemon_blocking`)
- Test: `test/snelda/application_test.exs` (create)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `Snelda.Application.start_daemon/0` — starts the daemon supervision tree (PubSub, registry, session supervisor, socket acceptor) and returns `{:ok, pid}`; called by the CLI. Loading the `:snelda` application starts **no** processes.

- [ ] **Step 1: Write the failing regression test**

Create `test/snelda/application_test.exs`:

```elixir
defmodule Snelda.ApplicationTest do
  use ExUnit.Case, async: true

  test "loading :snelda does not auto-start the daemon supervision tree" do
    # The root daemon supervisor must NOT be running merely because :snelda
    # is loaded as a dependency (library-safety guarantee).
    assert Process.whereis(Snelda.Supervisor) == nil
  end

  test "start_daemon/0 starts the supervision tree" do
    socket_path = "/tmp/snelda_app_test_#{System.unique_integer([:positive])}.sock"
    Application.put_env(:snelda, :socket_path, socket_path)

    on_exit(fn ->
      File.rm(socket_path)
      Application.delete_env(:snelda, :socket_path)
    end)

    assert {:ok, sup} = Snelda.Application.start_daemon()
    assert is_pid(sup)
    assert Process.alive?(sup)

    Supervisor.stop(sup)
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `mix test test/snelda/application_test.exs`
Expected: FAIL — `start_daemon/0` is undefined, and (because `mod:` still auto-starts) `Snelda.Supervisor` is running, so the first assertion also fails.

- [ ] **Step 3: Rewrite `Snelda.Application` to expose `start_daemon/0` and stop being an app callback**

Replace the entire contents of `lib/snelda/application.ex` with:

```elixir
defmodule Snelda.Application do
  @moduledoc false

  @doc """
  Start the daemon supervision tree (PubSub, registry, session supervisor,
  socket acceptor). Called explicitly by the CLI daemon entry point. Loading
  the `:snelda` application does NOT call this — the library is side-effect-free
  on boot so it can be embedded without spawning a socket daemon.
  """
  @spec start_daemon() :: {:ok, pid()} | {:error, term()}
  def start_daemon do
    socket_path = Application.get_env(:snelda, :socket_path, "/tmp/snelda.sock")

    children = [
      {Phoenix.PubSub, name: Snelda.PubSub},
      {Registry, keys: :unique, name: Snelda.SessionRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: Snelda.Session.Supervisor},
      {Snelda.Socket.Acceptor, socket_path: socket_path}
    ]

    opts = [strategy: :rest_for_one, name: Snelda.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

(Note: this also fixes the long-standing `stratedy:` typo from the original `DynamicSupervisor` child spec.)

- [ ] **Step 4: Remove `mod:` from `application/0` in `mix.exs`**

Change `mix.exs` `application/0` from:

```elixir
  def application do
    [
      extra_applications: [:logger],
      mod: {Snelda.Application, []}
    ]
  end
```

to:

```elixir
  def application do
    [
      extra_applications: [:logger]
    ]
  end
```

- [ ] **Step 5: Update the CLI to start the tree explicitly**

In `lib/snelda/cli.ex`, in `run_daemon_blocking/0`, replace:

```elixir
      {:error, _} ->
        # Starting Snelda without auto-start
        {:ok, _} = Application.ensure_all_started(:snelda)
        require Logger
        Logger.info("Daemon running in foreground. Press Ctrl+C to stop.")
        Process.sleep(:infinity)
        :ok
```

with:

```elixir
      {:error, _} ->
        # The library no longer auto-starts; start the daemon tree explicitly.
        {:ok, _} = Application.ensure_all_started(:snelda)
        {:ok, _} = Snelda.Application.start_daemon()
        require Logger
        Logger.info("Daemon running in foreground. Press Ctrl+C to stop.")
        Process.sleep(:infinity)
        :ok
```

(`ensure_all_started(:snelda)` still loads deps like `phoenix_pubsub`; `start_daemon/0` now does the actual tree boot.)

- [ ] **Step 6: Run the regression test to verify it passes**

Run: `mix test test/snelda/application_test.exs`
Expected: PASS — `Snelda.Supervisor` is not running at rest; `start_daemon/0` boots and returns a live supervisor pid.

- [ ] **Step 7: Run the full suite**

Run: `mix test`
Expected: PASS — all tests green. The daemon/CLI and socket tests still pass because the daemon is started explicitly wherever it is needed.

- [ ] **Step 8: Commit**

```bash
git add mix.exs lib/snelda/application.ex lib/snelda/cli.ex test/snelda/application_test.exs
git commit -m "app: stop auto-starting daemon so snelda is embeddable as a library"
```

---

### Task 4: Manual daemon smoke test + full CI gate + version tag

**Files:** No source changes. Verifies the branch and cuts the `v0.2.0` tag consumers depend on.

**Interfaces:**
- Consumes: Tasks 1-3.
- Produces: a green CI gate and a `v0.2.0` git tag.

- [ ] **Step 1: Full coverage**

Run: `mix coveralls`
Expected: 100% coverage, 0 failures. (If `chat/1`'s `:text` branch or an auth branch is uncovered, add the missing case to `test/snelda/llm_test.exs` — every branch of `auth_opts/1`, `build_payload/4`, and `parse_content/2` must be exercised.)

- [ ] **Step 2: Format / credo / dialyzer**

Run: `mix format --check-formatted`
Expected: exit 0.

Run: `mix credo --strict`
Expected: exit 0, no issues.

Run: `mix dialyzer`
Expected: exit 0, `done (passed successfully)` — the `@spec` on `chat/1` and `execute/1` must typecheck.

- [ ] **Step 3: Manual daemon smoke test (unchanged behavior)**

Run:
```bash
MIX_ENV=prod mix escript.build
./snelda daemon stop || true
./snelda daemon start
./snelda daemon status
./snelda daemon stop
```
Expected: `daemon start` reports "started successfully", `status` reports running, `stop` reports "stopped" — proving the explicit `start_daemon/0` path works end-to-end via the CLI.

- [ ] **Step 4: Bump version and tag**

In `mix.exs`, change `version: "0.1.0"` to `version: "0.2.0"`, then:

```bash
git add mix.exs
git commit -m "release: bump version to 0.2.0 for llm client library"
git tag v0.2.0
```
Expected: tag `v0.2.0` created (this is the tag the schnur specs reference for the git dependency). Pushing the tag happens at PR/merge time, not here.

---

## Self-Review

**1. Spec coverage:**
- Component 1 (decouple library from daemon) → Task 3.
- Component 2 (`chat/1` API: per-call url/model/auth/prompt/response_format, structured errors, statelessness) → Task 1.
- Component 3 (reconcile internal `execute/1`) → Task 2.
- Component 4 (git-tag install) → Task 4 (version bump + `v0.2.0` tag).
- Testing section (json/text/auth/errors, library-safety regression, daemon/CLI still pass) → Tasks 1, 3, 4.
- Multiagent future is non-goal — no task, correct.

**2. Placeholder scan:** No TBD/TODO/"handle edge cases". Every code step shows complete code; every run step shows the command and expected result.

**3. Type consistency:** `chat/1` returns `{:ok, map} | {:ok, String.t()} | {:error, {:invalid_json,..} | {:http,..} | {:request_failed,..}}` in Task 1 and is consumed unchanged by `execute/1` in Task 2 and referenced consistently in Task 4's coverage note. `start_daemon/0` returns `{:ok, pid}` in Task 3's interface, implementation, and test. `auth` variants (`{:bearer,_}`, `{:headers,_}`, `nil`) are consistent between the `@type`, `auth_opts/1`, and the Task 1 tests.
