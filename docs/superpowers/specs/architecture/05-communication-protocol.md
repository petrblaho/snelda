# Communication Protocol

Snelda employs a dual-protocol strategy to optimize both internal swarm speed and external accessibility. All messages follow an Event Envelope format (containing `session_id`, `type`, `payload`, and potentially an `index` for causal ordering).

*   **External Interface (Client ↔ Hub):**
    *   **Transport:** Multiplexed JSON over a UNIX domain socket or TCP connection.
    *   **Use Case:** This is how external CLI tools, web interfaces, or trigger systems communicate with the swarm.
    *   **Function:** Connections are managed by a `Socket.Handler` which translates JSON payloads into internal PubSub events asynchronously. Handlers listen to the Session's PubSub channel and stream JSON representations of state updates back to the connected client.

*   **Internal Interface (Agent ↔ Agent ↔ Log):**
    *   **Transport:** Native Erlang messages broadcasted via Phoenix.PubSub.
    *   **Use Case:** This is how agents collaborate and how external inputs reach the canonical Append-Only Log.
    *   **Function:** Bypasses JSON serialization overhead, utilizing the BEAM's highly optimized, location-transparent message passing. The central `Session` GenServer ingests commands/prompts from the PubSub topic, updates its log, and broadcasts `:state_updated` events back out, maintaining strict ordering without synchronous blocking constraints on the workers.