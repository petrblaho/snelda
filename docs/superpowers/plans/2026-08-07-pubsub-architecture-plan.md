# Asynchronous Event Log Architecture (Phase 2)

**Goal:** Break the synchronous link between `Snelda.Socket.Handler` and `Snelda.Session`. Use `Phoenix.PubSub` to pass immutable events between them, establishing the foundation for asynchronous, multi-agent collaboration via an Append-Only Log.

## Step 1: Add Phoenix.PubSub Dependency
Add `{:phoenix_pubsub, "~> 2.1"}` to the `deps` list in `mix.exs` and fetch dependencies.

## Step 2: Initialize the PubSub Registry
Add `{Phoenix.PubSub, name: Snelda.PubSub}` to the supervision tree in `lib/snelda/application.ex`, placed *before* the `Session.Supervisor`.

## Step 3: Define the Event Structs
Create `lib/snelda/events.ex` to define explicit structures for PubSub messages, guaranteeing type safety.

```elixir
defmodule Snelda.Event do
  @enforce_keys [:session_id, :type, :payload]
  defstruct [:session_id, :type, :payload, :index]
end
```

## Step 4: Refactor `Snelda.Session` (The Log Manager)
Convert the Session into a reactive event consumer and broadcaster.
1. **Remove `handle_call`:** Delete the synchronous `handle_call({:prompt, text}, ...)`.
2. **Subscribe on Init:** In `init/1`, subscribe: `Phoenix.PubSub.subscribe(Snelda.PubSub, "session:#{session_id}")`.
3. **Handle `:user_prompt`:** Add `handle_info/2` to catch `%Snelda.Event{type: :user_prompt}`.
4. **Append and Broadcast:** Upon receiving `:user_prompt`, append to history, calculate the index, and broadcast `%Snelda.Event{type: :state_updated}` back to the topic.

## Step 5: Refactor `Snelda.Socket.Handler` (The External Agent)
The Handler must emit events and listen for state updates asynchronously.
1. **Track Subscriptions:** The Handler state must track which sessions it has subscribed to (e.g., `%{socket: socket, subscriptions: MapSet.new()}`).
2. **Subscribe Lazily:** In `process_prompt/3`, before broadcasting, check if subscribed. If not, subscribe to `session:#{sid}` and add to state.
3. **Publish, Don't Call:** Replace the blocking `GenServer.call` with an asynchronous broadcast of `%Snelda.Event{type: :user_prompt}`.
4. **Handle `:state_updated`:** Add `handle_info/2` to catch `%Snelda.Event{type: :state_updated}`. Format the payload and send it down the TCP socket.

## Step 6: Fix the Test Suite
Ensure `test/snelda/socket/handler_test.exs` handles the asynchronous nature of PubSub. Test timeouts or assertions may need minor adjustments to account for BEAM scheduler propagation delays.

## Open Architectural Questions
1. **Multiplexing:** Does a single TCP connection handle multiple `session_id`s simultaneously? (The current design implies yes, hence tracking subscriptions).
2. **Backpressure:** Without `GenServer.call` blocking, how is TCP backpressure enforced if agents are slower than the client input stream? (Consider watermarking or flow-control tokens in the future).