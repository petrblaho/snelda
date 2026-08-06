defmodule Snelda.Socket.HandlerTest do
  use ExUnit.Case

  setup do
    socket_path = "/tmp/snelda_test.sock"
    File.rm(socket_path)

    start_supervised!({Snelda.Socket.Acceptor, socket_path: socket_path})

    # Give the acceptor a moment to create the socket file
    Process.sleep(100)

    %{socket_path: socket_path}
  end

  test "accepts a connection, routes to session, and replies", %{socket_path: socket_path} do
    {:ok, socket} =
      :gen_tcp.connect({:local, socket_path}, 0, [:binary, packet: :line, active: false])

    msg = Jason.encode!(%{type: "prompt", session_id: "test1", text: "hello"}) <> "\n"
    :ok = :gen_tcp.send(socket, msg)

    {:ok, response} = :gen_tcp.recv(socket, 0, 1000)
    assert Jason.decode!(response) == %{"type" => "history", "data" => ["hello"]}

    # Send second prompt to ensure state is maintained
    msg2 = Jason.encode!(%{type: "prompt", session_id: "test1", text: "world"}) <> "\n"
    :ok = :gen_tcp.send(socket, msg2)

    {:ok, response2} = :gen_tcp.recv(socket, 0, 1000)
    assert Jason.decode!(response2) == %{"type" => "history", "data" => ["hello", "world"]}

    :gen_tcp.close(socket)
  end

  test "replies with Invalid JSON error", %{socket_path: socket_path} do
    {:ok, socket} =
      :gen_tcp.connect({:local, socket_path}, 0, [:binary, packet: :line, active: false])

    msg = "not json\n"
    :ok = :gen_tcp.send(socket, msg)

    {:ok, response} = :gen_tcp.recv(socket, 0, 1000)
    assert Jason.decode!(response) == %{"type" => "error", "message" => "Invalid JSON"}
  end

  test "replies with Unknown protocol message error", %{socket_path: socket_path} do
    {:ok, socket} =
      :gen_tcp.connect({:local, socket_path}, 0, [:binary, packet: :line, active: false])

    msg = Jason.encode!(%{type: "unknown"}) <> "\n"
    :ok = :gen_tcp.send(socket, msg)

    {:ok, response} = :gen_tcp.recv(socket, 0, 1000)

    assert Jason.decode!(response) == %{
             "type" => "error",
             "message" => "Unknown protocol message"
           }
  end

  test "handles tcp_error message" do
    {:ok, handler} = GenServer.start(Snelda.Socket.Handler, :dummy_socket)
    Process.monitor(handler)
    send(handler, {:tcp_error, :dummy_socket, :econnreset})
    assert_receive {:DOWN, _, :process, ^handler, :normal}
  end
end
