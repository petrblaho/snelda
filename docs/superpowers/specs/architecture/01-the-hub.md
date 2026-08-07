# The Hub (Snelda Daemon)

The Hub acts as the foundational orchestration layer for the multi-agent system.

*   **Lifecycle Management:** It is the central Elixir application (`Application.ex`) responsible for starting, supervising, and gracefully terminating the system's core registries and connection acceptors.
*   **External Gateway:** It maintains the external connection points (UNIX domain socket, e.g., `/tmp/snelda.sock`, or TCP sockets) allowing external clients (CLI, web UIs, external triggers) to connect to the swarm.
*   **Infrastructure Provider:** It provides the necessary internal primitives (Process Registries via `Registry`, Pub-Sub topics via `:pg` or `Phoenix.PubSub`) that enable agents to discover and communicate with each other.
*   **Hands-Off Orchestration:** Crucially, the Hub itself does *not* execute LLM prompts or mount MCP tools. It merely provides the arena where agents perform these tasks.
*   **Scalability:** By leveraging native Erlang distribution, multiple Hubs on different physical machines can cluster together seamlessly, allowing the swarm to scale horizontally.