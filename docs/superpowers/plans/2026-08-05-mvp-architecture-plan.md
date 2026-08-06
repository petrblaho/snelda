# Snelda MVP Server/Client Architecture Plan

**Goal:** Implement a minimal, structurally sound Elixir client/server MVP using Unix Domain Sockets. This establishes the fault-tolerant OTP foundation (Acceptors, Handlers, Sessions, and Registry) required before introducing complex state machines or LLM integration.

## Constraints & Principles
- **OTP Purity:** Strict separation of Acceptor (network listener), Handler (per-client connection manager), and Session (long-lived conversational state).
- **Fault Isolation:** A crashing client connection must not affect other clients or the background session state. A crashing session must not crash the network listener.
- **Backpressure:** Network reads must use `active: :once`. The Handler must use synchronous blocking calls to the Session to prevent mailbox flooding.
- **Dynamic Routing:** Elixir `Registry` must be used for mapping `session_id`s to `Session` PIDs to avoid atom exhaustion.

## Phase 1: Core Supervision & Registry
Define the fault-domain hierarchy for the application.
- **Files:** `lib/snelda/application.ex`
- **Details:** 
  - Define `start/2` callback.
  - Start `Registry` with `keys: :unique` and `name: Snelda.SessionRegistry`.
  - Start `DynamicSupervisor` with `name: Snelda.Session.Supervisor` for dynamic session spawning.
  - Supervision strategy must be `:one_for_one`.

## Phase 2: Session State Management (The "Agent" Core)
Build the isolated state container for a conversation.
- **Files:** `lib/snelda/session.ex`
- **Details:**
  - Implement a `GenServer`.
  - `start_link/1`: Accept a `session_id` and register via `{:via, Registry, {Snelda.SessionRegistry, session_id}}`.
  - `init/1`: Initialize state with `%{session_id: id, history: []}`.
  - `handle_call({:prompt, text}, _from, state)`: Append the text to history and return the updated history to the caller.

## Phase 3: Network Ingress & Egress
Build the boundary layer that isolates network failure from session state.
- **Files:** `lib/snelda/socket/acceptor.ex`, `lib/snelda/socket/handler.ex`
- **Details:**
  - **Acceptor (Task):**
    - Loop `:gen_tcp.accept/1` on `/tmp/snelda.sock`.
    - Upon connection, spawn a `Snelda.Socket.Handler` GenServer.
    - Transfer socket ownership via `:gen_tcp.controlling_process/2`.
  - **Handler (GenServer):**
    - `init/1`: Wait for the `:takeover` message to set `active: :once`.
    - `handle_info({:tcp, socket, data}, state)`: Parse incoming JSON.
      - Protocol: `{"type": "prompt", "session_id": "123", "text": "hello"}`.
      - Use `Jason.decode/1` (safe decode).
      - Ensure the Session exists via `DynamicSupervisor.start_child/2`.
      - Route the prompt via a synchronous `GenServer.call` to the Session.
      - Send the resulting history back to the client via `:gen_tcp.send/2`.
      - Call `:inet.setopts(socket, active: :once)` *only* after processing is complete to enforce backpressure.
    - Error Handling: If JSON parsing fails (e.g., malformed protocol), catch the error, send `{"error": "bad_json"}` back to the client, and gracefully terminate the connection by stopping the Handler. Crashing on malformed input is acceptable in some domains, but explicitly rejecting bad protocol messages provides better UX for a CLI harness.
