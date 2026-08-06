defmodule Snelda.Session do
  @moduledoc false
  use GenServer
  require Logger

  # --- public API ---

  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    # register this process in the SessionRegistry using the session_id
    name = {:via, Registry, {Snelda.SessionRegistry, session_id}}
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  # --- callbacks ---
  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    Logger.info("Starting Session #{session_id}")

    # the sate is a map holding the id and the history list
    {:ok, %{session_id: session_id, history: []}}
  end

  @impl true
  def handle_call({:prompt, text}, _from, state) do
    # update the history (prepending is O(1) in Elixir, appending is O(N))
    # we prepend here and will reverse it when sending to the client
    new_history = [text | state.history]

    # update the state
    new_state = %{state | history: new_history}

    # reply to the caller (Handler)
    # return format: {:reply, response_payload, next_state}
    {:reply, Enum.reverse(new_history), new_state}
  end
end
