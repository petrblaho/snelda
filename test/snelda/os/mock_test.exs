defmodule Snelda.OS.MockTest do
  use ExUnit.Case, async: true
  alias Snelda.OS.Mock

  test "spawn_detached returns :ok" do
    assert :ok = Mock.spawn_detached("foo", [])
  end
end
