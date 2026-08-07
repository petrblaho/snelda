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

  test "parses --var-stdin and reads contents" do
    original_gl = Process.group_leader()
    {:ok, string_io} = StringIO.open("stdin content")
    Process.group_leader(self(), string_io)

    assert {:ok, %{vars: %{"in" => "stdin content"}}} =
             CLI.parse_args(["execute", "--config", "c.json", "--var-stdin", "in"])

    Process.group_leader(self(), original_gl)
  end

  test "parse_args returns error on missing config" do
    assert {:error, "--config is required"} = CLI.parse_args(["execute"])
  end
end
