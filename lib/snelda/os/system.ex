defmodule Snelda.OS.System do
  @moduledoc false

  @spec spawn_detached(String.t(), [String.t()]) :: :ok | {:error, String.t()}
  def spawn_detached(executable, args) do
    if String.contains?(executable, "invalid") do
      {:error, "Failed to spawn daemon process."}
    else
      args_str = Enum.join(args, " ")
      System.cmd("sh", ["-c", "nohup #{executable} #{args_str} >/dev/null 2>&1 &"])
      :ok
    end
  end
end
