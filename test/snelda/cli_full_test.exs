defmodule Snelda.CLIFullTest do
  use ExUnit.Case, async: true
  alias Snelda.CLI

  import ExUnit.CaptureIO

  test "do_main/1 prints error to stderr and returns 1 on invalid command" do
    output =
      capture_io(:stderr, fn ->
        assert CLI.do_main(["invalid"]) == 1
      end)

    assert String.contains?(output, "Unknown command")
  end

  test "parse_kv returns error on malformed kv" do
    assert {:error, "Malformed --var" <> _} =
             CLI.parse_args(["execute", "--config", "d", "--var", "foo"])
  end

  test "parse_file_kv returns error on malformed file kv" do
    assert {:error, "Malformed --var-file" <> _} =
             CLI.parse_args(["execute", "--config", "d", "--var-file", "foo"])
  end

  test "parse_file_kv returns error on missing file" do
    assert {:error, "Could not read file" <> _} =
             CLI.parse_args(["execute", "--config", "d", "--var-file", "foo=missing.txt"])
  end

  test "parse_stdin returns error on multiple stdins" do
    assert {:error, "Only one --var-stdin is allowed"} =
             CLI.parse_args(["execute", "--config", "d", "--var-stdin", "a", "--var-stdin", "b"])
  end
end
