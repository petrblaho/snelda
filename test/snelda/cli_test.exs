defmodule Snelda.CLITest do
  use ExUnit.Case, async: true
  alias Snelda.CLI

  test "parses literal variables gracefully" do
    args = ["execute", "--config", "task.json", "--var", "foo=bar"]

    assert {:ok, %{command: :execute, config: config, vars: %{"foo" => "bar"}}} =
             CLI.parse_args(args)

    assert config == Path.expand("task.json")
  end

  test "expands relative --config to an absolute path" do
    {:ok, %{config: config}} =
      CLI.parse_args(["execute", "--config", ".snelda/commit-verify.json"])

    assert config == Path.expand(".snelda/commit-verify.json")
    assert String.starts_with?(config, "/")
  end

  test "leaves an already-absolute --config unchanged" do
    abs = "/tmp/some/config.json"

    {:ok, %{config: config}} =
      CLI.parse_args(["execute", "--config", abs])

    assert config == abs
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

  test "parses daemon commands" do
    assert {:ok, %{command: :daemon_run}} = CLI.parse_args(["daemon", "run"])
    assert {:ok, %{command: :daemon_start}} = CLI.parse_args(["daemon", "start"])
    assert {:ok, %{command: :daemon_status}} = CLI.parse_args(["daemon", "status"])
    assert {:ok, %{command: :daemon_stop}} = CLI.parse_args(["daemon", "stop"])
  end
end
