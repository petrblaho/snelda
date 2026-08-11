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
        packet: 4,
        active: false,
        reuseaddr: true
      ])

    task =
      Task.async(fn ->
        {:ok, client} = :gen_tcp.accept(listen_socket)
        # First connection is ping from ensure_daemon_running
        {:ok, _data} = :gen_tcp.recv(client, 0)
        :gen_tcp.send(client, Jason.encode!(%{"type" => "pong"}))
        :gen_tcp.close(client)

        # Second connection is the actual execute payload
        {:ok, client2} = :gen_tcp.accept(listen_socket)
        {:ok, _data} = :gen_tcp.recv(client2, 0)
        :gen_tcp.send(client2, Jason.encode!(%{"exit_code" => 0, "feedback" => "Success"}))
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
        packet: 4,
        active: false,
        reuseaddr: true
      ])

    task =
      Task.async(fn ->
        {:ok, client} = :gen_tcp.accept(listen_socket)
        # First connection is ping from ensure_daemon_running
        {:ok, _data} = :gen_tcp.recv(client, 0)
        :gen_tcp.send(client, Jason.encode!(%{"type" => "pong"}))
        :gen_tcp.close(client)

        # Second connection is the actual execute payload
        {:ok, client2} = :gen_tcp.accept(listen_socket)
        {:ok, _data} = :gen_tcp.recv(client2, 0)

        :gen_tcp.send(
          client2,
          Jason.encode!(%{"exit_code" => 1, "feedback" => "Failed check"})
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
        packet: 4,
        active: false,
        reuseaddr: true
      ])

    task =
      Task.async(fn ->
        {:ok, client} = :gen_tcp.accept(listen_socket)
        # First connection is ping from ensure_daemon_running
        {:ok, _data} = :gen_tcp.recv(client, 0)
        :gen_tcp.send(client, Jason.encode!(%{"type" => "pong"}))
        :gen_tcp.close(client)

        # Second connection is the actual execute payload
        {:ok, client2} = :gen_tcp.accept(listen_socket)
        {:ok, _data} = :gen_tcp.recv(client2, 0)
        # Close abruptly without sending JSON
        :gen_tcp.close(client2)
      end)

    output =
      capture_io(:stderr, fn ->
        assert CLI.do_main(["execute", "--config", "test.json"]) == 1
      end)

    assert String.contains?(output, "Error receiving from daemon")
    Task.await(task)
  end

  test "run_execute fails and outputs error if daemon doesn't start", %{socket_path: _socket_path} do
    # We do NOT start a listen socket here.
    # The client will try to ping, fail, call spawn_detached (mocked to do nothing), poll, and fail.
    # We expect an error output to stderr and exit code 1.
    output =
      capture_io(:stderr, fn ->
        assert CLI.do_main(["execute", "--config", "test.json"]) == 1
      end)

    assert String.contains?(output, "Failed to start daemon")
  end
end
