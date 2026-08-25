defmodule Snelda.ApplicationTest do
  use ExUnit.Case, async: true

  test "loading :snelda does not auto-start the daemon supervision tree" do
    # Library-safety guarantee: the root daemon supervisor must NOT be running
    # merely because :snelda is loaded as a dependency. (test_helper.exs starts
    # the shared infra under the separate name Snelda.TestInfra, never
    # Snelda.Supervisor, so this assertion holds.)
    assert Process.whereis(Snelda.Supervisor) == nil
  end

  test "start_daemon/0 genuinely attempts to build the real daemon tree" do
    # The shared daemon singletons (PubSub, SessionRegistry, Session.Supervisor)
    # are already running (started by test_helper.exs), so calling start_daemon/0
    # here collides on those global names. This proves start_daemon/0 is not a
    # no-op: it tries to start the real children and fails on the already-started
    # singleton. Because Supervisor.start_link links the failing supervisor to
    # us, we trap exits to observe the failure without crashing the test.
    # End-to-end boot from a clean VM is covered by the CLI daemon smoke test.
    Process.flag(:trap_exit, true)

    result =
      try do
        Snelda.Application.start_daemon()
      catch
        :exit, reason -> {:exit, reason}
      end

    assert match?(
             {:error, {:shutdown, {:failed_to_start_child, _, {:already_started, _}}}},
             result
           ) or
             match?(
               {:exit, {:shutdown, {:failed_to_start_child, _, {:already_started, _}}}},
               result
             )
  end
end
