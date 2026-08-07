defmodule Snelda.CLITest do
  use ExUnit.Case, async: true
  alias Snelda.CLI

  test "parses literal variables gracefully" do
    args = ["execute", "--config", "task.json", "--var", "foo=bar"]

    assert {:ok, %{command: :execute, config: "task.json", vars: %{"foo" => "bar"}}} =
             CLI.parse_args(args)
  end

  test "returns error for malformed --var" do
    assert {:error, _} =
             CLI.parse_args(["execute", "--config", "t.json", "--var", "invalid_format"])
  end

  test "parses --var-file and reads contents" do
    path = "test_var_file.txt"
    File.write!(path, "file content")

    assert {:ok, %{vars: %{"msg" => "file content"}}} =
             CLI.parse_args(["execute", "--config", "c.json", "--var-file", "msg=#{path}"])

    File.rm!(path)
  end
end
