defmodule Snelda.Application do
  @moduledoc false

  @doc """
  Start the daemon supervision tree (PubSub, registry, session supervisor,
  socket acceptor). Called explicitly by the CLI daemon entry point. Loading
  the `:snelda` application does NOT call this — the library is side-effect-free
  on boot so it can be embedded without spawning a socket daemon.
  """
  @spec start_daemon() :: {:ok, pid()} | {:error, term()}
  def start_daemon do
    socket_path = Application.get_env(:snelda, :socket_path, "/tmp/snelda.sock")

    children = [
      {Phoenix.PubSub, name: Snelda.PubSub},
      {Registry, keys: :unique, name: Snelda.SessionRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: Snelda.Session.Supervisor},
      {Snelda.Socket.Acceptor, socket_path: socket_path}
    ]

    opts = [strategy: :rest_for_one, name: Snelda.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
