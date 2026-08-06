defmodule Snelda.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # fetch config or default to /tmp/snelda.sock
    socket_path = Application.get_env(:snelda, :socket_path, "/tmp/snelda.sock")

    # the list of children to supervise in precise startup order
    children = [
      {Registry, keys: :unique, name: Snelda.SessionRegistry},
      {DynamicSupervisor, stratedy: :one_for_one, name: Snelda.Session.Supervisor},
      {Snelda.Socket.Acceptor, socket_path: socket_path}
    ]

    opts = [strategy: :rest_for_one, name: Snelda.Supervisor]

    # start the root supervisor
    # this blocks until all children are started
    Supervisor.start_link(children, opts)
  end
end
