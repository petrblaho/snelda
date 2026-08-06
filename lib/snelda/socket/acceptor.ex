defmodule Snelda.Socket.Acceptor do
  @moduledoc false
  use Task, restart: :permanent
  require Logger

  # called by the supervisor
  def start_link(opts) do
    Task.start_link(__MODULE__, :accept, [opts[:socket_path]])
  end

  # entry point for the Task process
  def accept(socket_path) do
    # remove old socket file if it exists (crashed previous run)
    File.rm(socket_path)

    # open the listening socket
    {:ok, listen_socket} =
      :gen_tcp.listen(0, [
        :binary,
        {:ifaddr, {:local, socket_path}},
        packet: :line,
        active: false,
        reuseaddr: true
      ])

    # secure the socket
    File.chmod!(socket_path, 0o600)

    Logger.info("Listening on #{socket_path}")

    # enter infinite loop
    loop_acceptor(listen_socket)
  end

  defp loop_acceptor(listen_socket) do
    # block until client connects
    case :gen_tcp.accept(listen_socket) do
      {:ok, client_socket} ->
        # spawn a dedicated Handler process
        {:ok, handler_pid} = GenServer.start(Snelda.Socket.Handler, client_socket)

        # transfer ownership of the socket to the new handler
        :ok = :gen_tcp.controlling_process(client_socket, handler_pid)

        # tell the handler it is safe to start reading
        send(handler_pid, :takeover)

        # recourse to accept next connection
        loop_acceptor(listen_socket)

      {:error, reason} ->
        # if accept fails, crash this process, supervisor will restart it
        exit({:error, reason})
    end
  end
end
