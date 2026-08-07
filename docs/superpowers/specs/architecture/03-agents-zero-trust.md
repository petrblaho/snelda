# Agents (Zero-Trust Workers)

Agents are the active workers within the Snelda ecosystem, designed for extreme autonomy and security.

*   **Process Model:** Each agent is an ephemeral Elixir process (a `GenServer` or `Task`) spawned and attached to a specific Session (Task Force).
*   **Homogeneous Codebase:** Every agent process runs the exact same core engine. This engine handles event parsing, structuring LLM prompts (OpenAI format), and negotiating tool execution.
*   **Heterogeneous Roles:** While the code is identical, agents take on highly specialized roles (e.g., Code Writer, Security Reviewer, Coordinator). This specialization is defined purely by the injected **System Prompt** and the allowed list of **Tools** provided when the agent is spawned.
*   **Zero-Trust Security:** Agents are fundamentally untrusted with raw secrets. They do *not* hold API keys in their state, nor do they access environment variables for credentials. They must rely on the External Proxies layer to interact with the outside world.