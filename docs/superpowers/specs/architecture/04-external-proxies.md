# External Proxies (The Security Layer)

To maintain the "Zero-Trust Agent" model while allowing agents to perform meaningful work, Snelda relies heavily on external proxy services.

*   **LLM Proxy:** 
    *   Agents do not connect directly to OpenAI, Anthropic, or local Ollama instances with raw credentials.
    *   Instead, they format their requests according to the standard OpenAI API schema and send them to a configured external proxy URL (e.g., a local `LiteLLM` container).
    *   The external proxy holds the actual API keys, handles routing, enforces global rate limits, and returns the response to the agent.
*   **MCP Proxy:**
    *   Agents do not mount Model Context Protocol (MCP) servers directly, as this often requires exposing sensitive authentication tokens (e.g., GitHub PATs, Slack tokens) to the agent's environment.
    *   Agents connect to an external MCP router/host service. This external service securely manages the tool configurations and credentials, exposing only the safe execution endpoints to the agent via JSON-RPC.