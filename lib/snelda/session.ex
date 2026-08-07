defmodule Snelda.Session do
  @moduledoc false
  use GenServer
  require Logger

  # --- public API ---

  @type state :: %{session_id: String.t(), history: [String.t()]}

  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    # register this process in the SessionRegistry using the session_id
    name = {:via, Registry, {Snelda.SessionRegistry, session_id}}
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  # --- callbacks ---
  @impl true
  @spec init(Keyword.t()) :: {:ok, state()}
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    Logger.info("Starting Session #{session_id}")

    Phoenix.PubSub.subscribe(Snelda.PubSub, "session:#{session_id}")

    # the sate is a map holding the id and the history list
    {:ok, %{session_id: session_id, history: []}}
  end

  @impl true
  def handle_info(%Snelda.Event{type: :user_prompt, payload: text}, state) do
    new_history = [text | state.history]
    new_state = %{state | history: new_history}

    Phoenix.PubSub.broadcast(
      Snelda.PubSub,
      "session:#{state.session_id}",
      %Snelda.Event{
        session_id: state.session_id,
        type: :state_updated,
        index: length(new_history),
        payload: Enum.reverse(new_history)
      }
    )

    {:noreply, new_state}
  end

  # Ignore other events like our own :state_updated broadcast
  @impl true
  def handle_info(%Snelda.Event{}, state) do
    {:noreply, state}
  end
end
