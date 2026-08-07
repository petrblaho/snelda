defmodule Snelda.Socket.Handler do
  @moduledoc false
  use GenServer
  require Logger

  @type state :: %{socket: :gen_tcp.socket() | port(), subscriptions: MapSet.t()}

  # called by GenServer.start/2 in the Acceptor
  @impl true
  @spec init(:gen_tcp.socket() | port()) :: {:ok, state()}
  def init(socket) do
    # we store the socket in out state, but we do not start reading yet
    # we must wait for the Acceptor to transfer ownership and send :takeover
    {:ok, %{socket: socket, subscriptions: MapSet.new()}}
  end

  # this handle the :takeover message sent by the Acceptor
  @impl true
  @spec handle_info(
          :takeover
          | {:tcp, port(), binary()}
          | {:tcp_closed, port()}
          | {:tcp_error, port(), term()},
          state()
        ) :: {:noreply, state()} | {:stop, :normal, state()}
  def handle_info(:takeover, state) do
    # now we own the socket, we will tell the OS to send us exactly one line of text
    :inet.setopts(state.socket, active: :once)
    {:noreply, state}
  end

  # when active: :once is set the OS send the line as a message to our mailbox
  def handle_info({:tcp, socket, data}, state) do
    case Jason.decode(data) do
      {:ok, %{"type" => "execute", "config" => config_path, "vars" => vars}} ->
        response_payload = execute_task(config_path, vars)

        response = Jason.encode!(response_payload) <> "\n"
        :gen_tcp.send(socket, response)
        :inet.setopts(socket, active: :once)
        {:noreply, state}

      {:ok, %{"type" => "prompt", "session_id" => sid, "text" => text}} ->
        new_state = process_prompt(state, sid, text)
        :inet.setopts(socket, active: :once)
        {:noreply, new_state}

      {:ok, _other} ->
        reply_error(socket, "Unknown protocol message")
        :inet.setopts(socket, active: :once)
        {:noreply, state}

      {:error, _reason} ->
        reply_error(socket, "Invalid JSON")
        :inet.setopts(socket, active: :once)
        {:noreply, state}
    end
  end

  def handle_info(%Snelda.Event{type: :state_updated, payload: history}, state) do
    response = Jason.encode!(%{type: "history", data: history}) <> "\n"
    :gen_tcp.send(state.socket, response)
    {:noreply, state}
  end

  # Ignore other events like our own :user_prompt broadcast
  def handle_info(%Snelda.Event{}, state) do
    {:noreply, state}
  end

  # handle the client disconnecting
  def handle_info({:tcp_closed, _socket}, state) do
    Logger.info("Client disconnected")
    {:stop, :normal, state}
  end

  # handle socket errors (e.g. connection reset by peer)
  def handle_info({:tcp_error, _socket, reason}, state) do
    Logger.error("TCP Error: #{inspect(reason)}")
    {:stop, :normal, state}
  end

  # --- private helpers ---
  defp execute_task(config_path, vars) do
    with {:ok, file} <- File.read(config_path),
         {:ok, config} <- Jason.decode(file) do
      prompt = Snelda.TaskConfig.render_prompt(config["user_prompt"], vars)

      opts = %{
        proxy_url: config["proxy_url"] || "http://localhost:4000/v1/chat/completions",
        model: config["model"],
        system_prompt: config["system_prompt"],
        user_prompt: prompt
      }

      run_llm_and_evaluate(opts, config)
    else
      {:error, err} ->
        %{
          "type" => "execution_result",
          "exit_code" => 1,
          "feedback" => "Config error: #{inspect(err)}"
        }
    end
  end

  defp run_llm_and_evaluate(opts, config) do
    case Snelda.LLM.execute(opts) do
      {:ok, result} ->
        # MVP evaluation: just check if the boolean key from success condition matches.
        # We parse a naive condition like "valid == true"
        condition = config["success_condition"] || ""
        [key, "==", expected] = String.split(condition, " ", parts: 3)
        expected_bool = expected == "true"

        is_success = Map.get(result, key) == expected_bool
        exit_code = if is_success, do: 0, else: 1
        feedback = Map.get(result, "feedback", "No feedback provided")

        %{"type" => "execution_result", "exit_code" => exit_code, "feedback" => feedback}

      {:error, msg} ->
        %{"type" => "execution_result", "exit_code" => 1, "feedback" => "LLM Error: #{msg}"}
    end
  end

  defp process_prompt(state, sid, text) do
    {:ok, _session_pid} = Snelda.Session.Supervisor.ensure_session(sid)

    new_state =
      if MapSet.member?(state.subscriptions, sid) do
        state
      else
        Phoenix.PubSub.subscribe(Snelda.PubSub, "session:#{sid}")
        %{state | subscriptions: MapSet.put(state.subscriptions, sid)}
      end

    Phoenix.PubSub.broadcast(
      Snelda.PubSub,
      "session:#{sid}",
      %Snelda.Event{session_id: sid, type: :user_prompt, payload: text}
    )

    new_state
  end

  defp reply_error(socket, message) do
    response = Jason.encode!(%{type: "error", message: message}) <> "\n"
    :gen_tcp.send(socket, response)
  end
end
