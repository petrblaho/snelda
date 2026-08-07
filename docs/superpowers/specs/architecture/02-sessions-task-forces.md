# Sessions (The "Task Forces")

The concept of a "Session" is expanded from a simple conversation history into an active, multi-agent collaboration space driven by a PubSub-Mediated Event Log.

*   **The Append-Only Log:** The canonical state (history) of a Session is maintained by a single, dedicated `Session` GenServer acting as an Append-Only Log. This is the single source of truth, enforcing causal consistency and sequence.
*   **Pub-Sub Boundaries:** Collaboration happens over a logical, isolated **Pub-Sub Channel**. External clients (via Handlers) and Agents do not interact with the Session state directly; they broadcast intent (e.g., `:user_prompt`) and react to state changes (e.g., `:state_updated`).
*   **Multi-Agent Collaboration:** Multiple autonomous agent processes (e.g., Code Writer, Reviewer) and external human clients can join the same Session ID. They listen for state updates, perform work independently, and submit results to the Log.
*   **Context Isolation:** Messages broadcast within a Session are only heard by members of that specific Session, ensuring agents remain focused on their designated task.
*   **Location Transparency:** Because they are backed by Phoenix.PubSub, Sessions span across all connected machines in the Snelda cluster transparently. An agent on Machine A and an agent on Machine B can collaborate in the same Session seamlessly.