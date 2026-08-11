defmodule Snelda.OS.Mock do
  @moduledoc false

  @spec spawn_detached(String.t(), [String.t()]) :: :ok
  def spawn_detached(_executable, _args) do
    :ok
  end
end
