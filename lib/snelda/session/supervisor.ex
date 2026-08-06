defmodule Snelda.Session.Supervisor do
  @moduledoc false
  # this module just provides helpers to interact with the
  # DynamicSupervisor we started in application.ex

  def ensure_session(session_id, supervisor_name \\ __MODULE__) do
    # the child specification tells the supervisor how to start the session
    spec = {Snelda.Session, session_id: session_id}

    # we ask the DynamicSupervisor (using its registered name) to start it
    case DynamicSupervisor.start_child(supervisor_name, spec) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        # if it already running, we just return the PID
        {:ok, pid}

      error ->
        error
    end
  end
end
