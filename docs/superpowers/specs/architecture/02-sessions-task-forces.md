# Sessions (The "Task Forces")

The concept of a "Session" is expanded from a simple conversation history into an active, multi-agent collaboration space.

*   **Pub-Sub Boundaries:** A Session is no longer just state held in a single GenServer; it is a logical, isolated **Pub-Sub Channel**.
*   **Multi-Agent Collaboration:** Multiple agent processes (e.g., Code Writer, Reviewer) and external human clients can join the same Session ID.
*   **Context Isolation:** Messages broadcast within a Session are only heard by members of that specific Session, preventing context bloat and ensuring agents remain focused on their designated task.
*   **Location Transparency:** Because they are backed by BEAM process groups, Sessions span across all connected machines in the Snelda cluster transparently. An agent on Machine A and an agent on Machine B can collaborate in the same Session seamlessly.