defmodule SneldaTest do
  use ExUnit.Case
  doctest Snelda

  test "greets the world" do
    assert Snelda.hello() == :world
  end
end
