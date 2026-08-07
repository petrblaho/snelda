# Communication Protocol

Snelda employs a dual-protocol strategy to optimize both internal swarm speed and external accessibility. All messages, regardless of transport, follow an Event Envelope format (containing `session_id`, `source`, `type`, `payload`, and `correlation_id`).

*   **External Interface (Client ↔ Hub):**
    *   **Transport:** Multiplexed JSON over a UNIX domain socket or TCP connection.
    *   **Use Case:** This is how external CLI tools, web interfaces, or trigger systems (like cron jobs or webhook listeners) communicate with the swarm.
    *   **Function:** Clients can spawn new Task Forces, inject messages into existing Sessions, and listen to a filtered stream of JSON events emitted by the working agents.
*   **Internal Interface (Agent ↔ Agent):**
    *   **Transport:** Native Erlang messages broadcasted to the Session's Pub-Sub topic.
    *   **Use Case:** This is how agents within the same Task Force collaborate, debate, and share tool results.
    *   **Function:** Bypasses JSON serialization overhead, utilizing the BEAM's highly optimized, location-transparent message passing for near-instantaneous inter-agent communication, even across clustered machines.