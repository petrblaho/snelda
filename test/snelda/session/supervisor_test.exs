defmodule Snelda.Session.SupervisorTest do
  use ExUnit.Case

  test "ensure_session/2 handles other errors" do
    # Start a mock one with max_children: 0 and a unique name
    supervisor_name = :test_mock_supervisor

    start_supervised!(
      {DynamicSupervisor, name: supervisor_name, strategy: :one_for_one, max_children: 0}
    )

    # ensure_session should return the error from the underlying DynamicSupervisor
    assert {:error, :max_children} =
             Snelda.Session.Supervisor.ensure_session("will_fail", supervisor_name)
  end
end
