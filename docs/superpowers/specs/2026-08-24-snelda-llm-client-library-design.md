# Design Spec: Snelda as an Embeddable LLM Client Library

Date: 2026-08-24
Status: Approved

## Overview

Make Snelda usable as a per-call-configurable LLM client **library** that any
Elixir application can add as a dependency and call in-process. The first
consumer is [schnur](https://github.com/petrblaho/schnur) (its "Scribe" makes
structured LLM calls), but the API is generic.

This spec covers the **Snelda side only**: exposing a clean, documented,
stateless public LLM API and making Snelda safe to embed without booting its
daemon. The consumer-side integration (schnur's Scribe adapter, per-Game
credential storage, UI) is covered by separate specs in the schnur repo.

## Goals

- Any Elixir app can depend on Snelda and call `Snelda.LLM.chat/1` in-process —
  no daemon, no socket, no serialization.
- The LLM call is **fully per-call configurable**: provider URL, model,
  credentials, prompt, and response format are all arguments. Snelda holds no
  global config and persists nothing.
- Adding Snelda as a dependency must **not** start Snelda's background daemon
  (socket acceptor / PubSub) in the consumer's VM.
- The existing CLI + daemon (git-hook use case) keeps working unchanged.

## Non-Goals (explicitly deferred)

- Snelda's multiagent machinery (Session / Agent / PubSub collaboration).
  The `chat/1` API is designed so this can be added later as **additive**
  modules a consumer opts into, without changing the basic chat call.
- schnur's Scribe adapter, per-Game credential table/model, encryption, and UI —
  all live in the schnur repo (separate specs).
- Publishing Snelda to Hex (consumers use a git-tag dependency).
- Streaming responses, tool/function calling, multi-turn conversation state.

## Background: the zero-trust contradiction (resolved)

Snelda's architecture docs (`03-agents-zero-trust`, `04-external-proxies`) state
agents never hold credentials — a central LLM proxy does. schnur's requirement is
the opposite: each Game's players supply their own provider URL + credentials +
model, stored per-Game and switchable at runtime.

**Resolution — credential-agnostic API (Model C) + consumer-side storage
(Model A):**
- Snelda's `chat/1` takes URL + auth + model **per call** and authenticates with
  whatever the caller passes. Snelda itself holds no keys and persists nothing —
  zero-trust is preserved *for Snelda*.
- Where credentials physically live is the **consumer's** decision. schnur will
  store raw per-Game credentials encrypted at rest and pass them in at call time
  (Model A). A deployment that prefers a LiteLLM proxy with virtual keys (Model
  2) works too — Snelda is agnostic. This policy choice never enters Snelda.

## Component 1: Decouple the library from the daemon (linchpin)

### Problem
`mix.exs` currently declares:

```elixir
def application do
  [extra_applications: [:logger], mod: {Snelda.Application, []}]
end
```

`Snelda.Application.start/2` boots the full daemon supervision tree —
`Phoenix.PubSub`, `Snelda.SessionRegistry`, `Snelda.Session.Supervisor`, and
`Snelda.Socket.Acceptor` (which binds `/tmp/snelda.sock`). If a consumer adds
Snelda as a dependency as-is, **the consumer's VM auto-starts Snelda's socket
daemon on boot** — binding a UNIX socket and starting a PubSub it does not use.
This is unacceptable for an embeddable library.

### Resolution
Snelda must not auto-start its daemon when loaded as a dependency. The
conventional Elixir pattern for a library-that-also-ships-a-CLI:

- Remove `mod: {Snelda.Application, []}` from `application/0`. Keep
  `extra_applications: [:logger]`. Loading `:snelda` then starts **no
  processes**.
- Move responsibility for starting the daemon supervision tree to the **CLI
  entrypoint** (`Snelda.CLI`). The daemon commands (`daemon run`, and the
  auto-start path invoked by `execute`) explicitly start the supervision tree
  (via `Supervisor.start_link/2` or `Application.ensure_all_started` of a
  dedicated child spec) instead of relying on the application `mod:` callback.

### Consequence
- `Snelda.LLM` becomes genuinely side-effect-free on load: it is a plain
  function module depending only on `Req` + `Jason`.
- The escript/daemon behavior for the git-hook use case is unchanged — the CLI
  starts the tree exactly as before, just explicitly rather than implicitly.

## Component 2: Public API — `Snelda.LLM.chat/1`

Today `Snelda.LLM` is `@moduledoc false`, forces `response_format:
json_object`, always JSON-decodes, and returns stringly-typed errors. The
library needs a documented, stable, stateless public function.

### Signature

```elixir
@type auth :: {:bearer, String.t()} | {:headers, [{String.t(), String.t()}]} | nil

@type opts :: %{
  # provider target (per-call; Model C)
  required(:proxy_url) => String.t(),
  required(:model) => String.t(),
  optional(:auth) => auth(),

  # prompt
  required(:system_prompt) => String.t(),
  required(:user_prompt) => String.t(),

  # behavior
  optional(:response_format) => :json | :text,   # default :json
  optional(:req_opts) => keyword()               # raw Req escape hatch
}

@spec chat(opts()) ::
        {:ok, map()}                                  # response_format: :json
        | {:ok, String.t()}                           # response_format: :text
        | {:error, {:invalid_json, String.t()}}
        | {:error, {:http, non_neg_integer(), term()}}
        | {:error, {:request_failed, term()}}
def chat(opts)
```

### Behavior

- **Credential-agnostic auth (Model C):** `auth` is a first-class field, not
  buried in `req_opts`.
  - `{:bearer, key}` → adds `Authorization: Bearer <key>` header.
  - `{:headers, [{k, v}, ...]}` → merges the given headers (e.g.
    `{"x-api-key", "..."}` for Anthropic-style, or a proxy virtual key).
  - `nil` / omitted → no auth header (e.g. a local proxy that needs none).
  - `req_opts` remains the raw escape hatch for timeouts, retries, extra headers.
    If `req_opts` also sets headers, `auth`-derived headers take precedence for
    the auth header key.
- **Response format (per call):**
  - `:json` (default) → sends `response_format: %{type: "json_object"}`, appends
    the existing "Respond strictly in JSON." instruction to the system prompt,
    parses the returned content, returns `{:ok, map}`. Unparseable content →
    `{:error, {:invalid_json, raw_content}}`.
  - `:text` → does **not** set `response_format`, returns the raw assistant
    message string as `{:ok, string}`.
- **Statelessness:** Snelda persists nothing and logs no credentials. The `auth`
  value and any secret headers must never appear in returned errors or logs.
- **Request shape:** unchanged OpenAI Chat Completions schema —
  `POST proxy_url` with `%{model, messages: [system, user], response_format?}`.

### Errors (structured tagged tuples)

Replaces today's flat strings so consumers can pattern-match:

- `{:error, {:http, status, body}}` — non-2xx from the provider/proxy (e.g.
  `{:http, 429, _}` is retryable; the consumer decides).
- `{:error, {:invalid_json, raw}}` — 200 OK but content was not valid JSON
  (only in `:json` mode). `raw` is the offending content for debugging.
- `{:error, {:request_failed, reason}}` — transport failure (Req exception).

Error values must not embed the request's `auth`/secret headers.

## Component 3: Reconcile the internal `execute/1` path

The daemon's `execute` task (`Snelda.Socket.Handler`) currently calls
`Snelda.LLM.execute/1`. To keep one code path:

- Refactor the daemon's LLM call to go through the new `chat/1` (JSON mode).
- `execute/1` is either removed or becomes a thin internal wrapper over
  `chat/1`. The socket `execute` protocol's external behavior (config-file
  driven, `success_condition` evaluation, `execution_result` response) is
  preserved — only the underlying call is unified.

## Component 4: Installation as a dependency

Consumers add Snelda as a **git-tag dependency**:

```elixir
{:snelda, git: "https://github.com/petrblaho/snelda", tag: "v0.2.0"}
```

- No Hex publishing. Version pinned via tags.
- Snelda keeps its `escript:` config; the library API and CLI coexist.
- Snelda's runtime deps (`req`, `jason`) resolve for library consumers.
  `phoenix_pubsub` remains a runtime dep (used by the daemon) but starts no
  processes in a consumer because Component 1 removed the auto-start; it is
  loaded but idle. (A later optimization could make PubSub daemon-only, but that
  is out of scope here.)

## Testing

- **`chat/1` unit tests** (using the existing `Plug`-based test proxy in
  `test/`):
  - `:json` mode returns `{:ok, map}` on valid JSON content.
  - `:json` mode returns `{:error, {:invalid_json, raw}}` on non-JSON content.
  - `:text` mode returns `{:ok, string}` and does not set `response_format`.
  - `auth: {:bearer, k}` produces an `Authorization: Bearer` header.
  - `auth: {:headers, [...]}` merges the given headers.
  - `auth: nil`/omitted sends no auth header.
  - non-2xx → `{:error, {:http, status, body}}`.
  - transport failure → `{:error, {:request_failed, reason}}`.
  - returned errors contain no credential material.
- **Library-safety regression test:** starting only the `:snelda` application
  (as a dependency would) binds **no** socket and starts no daemon process —
  i.e. `Snelda.Application` no longer auto-starts the tree.
- **Daemon/CLI tests** continue to pass: the daemon still starts (now via the
  CLI entrypoint), the socket `execute`/`ping`/`stop` protocol works, and the
  git-hook path is unaffected.
- CI gates unchanged: `mix coveralls` (100%), `mix format --check-formatted`,
  `mix credo --strict`, `mix dialyzer`.

## Future: multiagent (additive, not now)

The single `chat/1` call is the stable primitive. When Snelda's
Session/Agent/PubSub collaboration is ready, it will be exposed as **additional**
modules (e.g. a session/agent API) that a consumer opts into — layered on top of,
not replacing, `chat/1`. schnur's Scribe adapter is intentionally the *only*
seam that references Snelda, so adopting the multiagent API later changes exactly
one module on the consumer side.
