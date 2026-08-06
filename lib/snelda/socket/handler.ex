defmodule Snelda.Socket.Handler do
  @moduledoc false
  use GenServer
  require Logger

  # called by GenServer.start/2 in the Acceptor
  def init(socket) do
    # we store the socket in out state, but we do not start reading yet
    # we must wait for the Acceptor to transfer ownership and send :takeover
    {:ok, %{socket: socket}}
  end

  # this handle the :takeover message sent by the Acceptor
  def handle_info(:takeover, state) do
    # now we own the socket, we will tell the OS to send us exactly one line of text
    :inet.setopts(state.socket, active: :once)
    {:noreply, state}
  end

  # when active: :once is set the OS send the line as a message to our mailbox
  def handle_info({:tcp, socket, data}, state) do
    case Jason.decode(data) do
      {:ok, %{"type" => "prompt", "session_id" => sid, "text" => text}} ->
        process_prompt(socket, sid, text)

      {:ok, _other} ->
        reply_error(socket, "Unknown protocol message")

      {:error, _reason} ->
        reply_error(socket, "Invalid JSON")
    end

    # we have finished processing the line, tell the OS to send next once
    # this is the backpressure mechanism
    :inet.setopts(socket, active: :once)
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
  defp process_prompt(socket, sid, text) do
    # ask the DynamicSupervisor to ensure a Session exists for this ID
    {:ok, session_pid} = Snelda.Session.Supervisor.ensure_session(sid)

    # make a synchronous blocking call to the Session
    # if the session takes 5 seconds to process this the Handler hangs here for 5 seconds
    # because it hangs here it does not reach the `Linet.setopts` line above
    # because it does not set `active: :once` the OS stops reading from the TCP buffer
    # this forces the client to wait - backpressure achieved
    history = GenServer.call(session_pid, {:prompt, text})

    # send the results back to the client
    response = Jason.encode!(%{type: "history", data: history}) <> "\n"
    :gen_tcp.send(socket, response)
  end

  defp reply_error(socket, message) do
    response = Jason.encode!(%{type: "error", message: message}) <> "\n"
    :gen_tcp.send(socket, response)
  end
end
