defmodule Snelda.OS.SystemTest do
  use ExUnit.Case, async: true
  alias Snelda.OS.System, as: OSSystem

  test "spawn_detached handles execution errors" do
    # Passing an invalid executable to trigger rescue block
    assert {:error, "Failed to spawn daemon process."} = OSSystem.spawn_detached("/invalid/executable/does/not/exist", [])
  end

  test "spawn_detached executes correctly" do
    assert :ok = OSSystem.spawn_detached("/usr/bin/true", [])
  end
end
