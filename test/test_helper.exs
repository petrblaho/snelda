# test_helper.exs
ExUnit.start()

# Snelda no longer auto-starts its daemon supervision tree (it is an embeddable
# library; see lib/snelda/application.ex). Tests that exercise the daemon's
# session/prompt routing still need the shared infrastructure — PubSub, the
# session Registry, and the Session DynamicSupervisor — running under stable
# global names. Start them here (but NOT the socket Acceptor: individual tests
# start their own Acceptor on isolated socket paths).
children = [
  {Phoenix.PubSub, name: Snelda.PubSub},
  {Registry, keys: :unique, name: Snelda.SessionRegistry},
  {DynamicSupervisor, strategy: :one_for_one, name: Snelda.Session.Supervisor}
]

Supervisor.start_link(children, strategy: :one_for_one, name: Snelda.TestInfra)
