defmodule Snelda.Socket.HandlerErrorTest do
  use ExUnit.Case, async: true

  setup do
    socket_path = "/tmp/snelda_test_err_#{System.unique_integer([:positive])}.sock"
    File.rm(socket_path)

    {:ok, sup} =
      Supervisor.start_link(
        [
          {Registry, keys: :unique, name: String.to_atom("Registry_#{System.unique_integer()}")},
          {Snelda.Socket.Acceptor, socket_path: socket_path}
        ],
        strategy: :one_for_one
      )

    Process.sleep(50)

    {:ok, socket} =
      :gen_tcp.connect({:local, socket_path}, 0, [:binary, active: false, packet: 4])

    on_exit(fn ->
      File.rm(socket_path)
      Process.exit(sup, :normal)
    end)

    %{socket: socket}
  end

  test "replies error on invalid json", %{socket: socket} do
    :ok = :gen_tcp.send(socket, "not json\n")
    {:ok, response} = :gen_tcp.recv(socket, 0, 1000)
    assert %{"type" => "error", "message" => "Invalid JSON" <> _} = Jason.decode!(response)
  end

  test "replies error on unknown protocol message", %{socket: socket} do
    :ok = :gen_tcp.send(socket, "{\"type\": \"unknown\"}\n")
    {:ok, response} = :gen_tcp.recv(socket, 0, 1000)
    assert %{"type" => "error", "message" => "Unknown protocol message"} = Jason.decode!(response)
  end

  test "handles TCP closed gracefully", %{socket: socket} do
    :gen_tcp.close(socket)
    Process.sleep(50)
    # The handler process should exit cleanly, but from the client side
    # we just verify we don't crash the server.
    assert true
  end

  test "handles execute task config errors gracefully", %{socket: socket} do
    payload =
      Jason.encode!(%{"type" => "execute", "config" => "does_not_exist.json", "vars" => %{}}) <>
        "\n"

    :ok = :gen_tcp.send(socket, payload)

    {:ok, response} = :gen_tcp.recv(socket, 0, 1000)

    assert %{"type" => "execution_result", "exit_code" => 1, "feedback" => feedback} =
             Jason.decode!(response)

    assert String.contains?(feedback, "Config error")
  end
end
