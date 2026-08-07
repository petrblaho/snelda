defmodule Snelda.CLINetworkTest do
  use ExUnit.Case, async: false
  alias Snelda.CLI
  import ExUnit.CaptureIO

  setup do
    socket_path = "/tmp/snelda_cli_test_#{System.unique_integer([:positive])}.sock"
    Application.put_env(:snelda, :socket_path, socket_path)

    on_exit(fn ->
      File.rm(socket_path)
    end)

    %{socket_path: socket_path}
  end

  test "run_execute connects to socket and gets successful exit code 0", %{
    socket_path: socket_path
  } do
    # Start a dummy server to emulate Snelda daemon
    {:ok, listen_socket} =
      :gen_tcp.listen(0, [
        :binary,
        {:ifaddr, {:local, socket_path}},
        packet: :line,
        active: false,
        reuseaddr: true
      ])

    task =
      Task.async(fn ->
        {:ok, client} = :gen_tcp.accept(listen_socket)
        {:ok, _data} = :gen_tcp.recv(client, 0)
        :gen_tcp.send(client, Jason.encode!(%{"exit_code" => 0, "feedback" => "Success"}) <> "\n")
      end)

    assert CLI.do_main(["execute", "--config", "test.json"]) == 0
    Task.await(task)
  end

  test "run_execute prints feedback to stderr and returns exit code 1", %{
    socket_path: socket_path
  } do
    {:ok, listen_socket} =
      :gen_tcp.listen(0, [
        :binary,
        {:ifaddr, {:local, socket_path}},
        packet: :line,
        active: false,
        reuseaddr: true
      ])

    task =
      Task.async(fn ->
        {:ok, client} = :gen_tcp.accept(listen_socket)
        {:ok, _data} = :gen_tcp.recv(client, 0)

        :gen_tcp.send(
          client,
          Jason.encode!(%{"exit_code" => 1, "feedback" => "Failed check"}) <> "\n"
        )
      end)

    output =
      capture_io(:stderr, fn ->
        assert CLI.do_main(["execute", "--config", "test.json"]) == 1
      end)

    assert String.contains?(output, "Failed check")
    Task.await(task)
  end

  test "run_execute returns 1 when receiving garbage from daemon", %{socket_path: socket_path} do
    {:ok, listen_socket} =
      :gen_tcp.listen(0, [
        :binary,
        {:ifaddr, {:local, socket_path}},
        packet: :line,
        active: false,
        reuseaddr: true
      ])

    task =
      Task.async(fn ->
        {:ok, client} = :gen_tcp.accept(listen_socket)
        {:ok, _data} = :gen_tcp.recv(client, 0)
        # Close abruptly without sending JSON
        :gen_tcp.close(client)
      end)

    output =
      capture_io(:stderr, fn ->
        assert CLI.do_main(["execute", "--config", "test.json"]) == 1
      end)

    assert String.contains?(output, "Error receiving from daemon")
    Task.await(task)
  end

  test "retry_connection eventually fails if daemon doesn't start", %{socket_path: socket_path} do
    # Temporarily set backoff to 1ms to make the test super fast
    Application.put_env(:snelda, :backoff_multiplier, 1)

    # We do NOT start a listen socket here.
    # The client will try to connect, fail, call spawn_daemon(), and retry 6 times.
    # We expect an error output to stderr and exit code 1.
    output =
      capture_io(:stderr, fn ->
        assert CLI.do_main(["execute", "--config", "test.json"]) == 1
      end)

    assert String.contains?(output, "Failed to connect to daemon at #{socket_path}")
  end
end
