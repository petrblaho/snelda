defmodule Snelda.Socket.HandlerTest do
  use ExUnit.Case
  import ExUnit.CaptureLog

  setup do
    socket_path = "/tmp/snelda_test.sock"
    File.rm(socket_path)

    capture_log(fn ->
      start_supervised!({Snelda.Socket.Acceptor, socket_path: socket_path})

      # Give the acceptor a moment to create the socket file
      Process.sleep(100)
    end)

    %{socket_path: socket_path}
  end

  test "accepts a connection, routes to session, and replies", %{socket_path: socket_path} do
    capture_log(fn ->
      {:ok, socket} =
        :gen_tcp.connect({:local, socket_path}, 0, [:binary, packet: 4, active: false])

      msg = Jason.encode!(%{type: "prompt", session_id: "test1", text: "hello"}) <> "\n"
      :ok = :gen_tcp.send(socket, msg)

      {:ok, response} = :gen_tcp.recv(socket, 0, 5000)
      assert Jason.decode!(response) == %{"type" => "history", "data" => ["hello"]}

      # To prevent race conditions in the test, we wait a moment.
      Process.sleep(50)

      # Send second prompt to ensure state is maintained
      msg2 = Jason.encode!(%{type: "prompt", session_id: "test1", text: "world"}) <> "\n"
      :ok = :gen_tcp.send(socket, msg2)

      {:ok, response2} = :gen_tcp.recv(socket, 0, 5000)
      assert Jason.decode!(response2) == %{"type" => "history", "data" => ["hello", "world"]}

      :gen_tcp.close(socket)

      # Wait a tiny bit for the async disconnect log to happen while we are still capturing
      Process.sleep(50)
    end)
  end

  test "replies with Invalid JSON error", %{socket_path: socket_path} do
    capture_log(fn ->
      {:ok, socket} =
        :gen_tcp.connect({:local, socket_path}, 0, [:binary, packet: 4, active: false])

      msg = "not json\n"
      :ok = :gen_tcp.send(socket, msg)

      {:ok, response} = :gen_tcp.recv(socket, 0, 1000)
      assert %{"type" => "error", "message" => "Invalid JSON" <> _} = Jason.decode!(response)

      :gen_tcp.close(socket)
      Process.sleep(50)
    end)
  end

  test "replies with Unknown protocol message error", %{socket_path: socket_path} do
    capture_log(fn ->
      {:ok, socket} =
        :gen_tcp.connect({:local, socket_path}, 0, [:binary, packet: 4, active: false])

      msg = Jason.encode!(%{type: "unknown"}) <> "\n"
      :ok = :gen_tcp.send(socket, msg)

      {:ok, response} = :gen_tcp.recv(socket, 0, 1000)

      assert Jason.decode!(response) == %{
               "type" => "error",
               "message" => "Unknown protocol message"
             }

      :gen_tcp.close(socket)
      Process.sleep(50)
    end)
  end

  test "handles tcp_error message" do
    capture_log(fn ->
      {:ok, handler} = GenServer.start(Snelda.Socket.Handler, :dummy_socket)
      Process.monitor(handler)
      send(handler, {:tcp_error, :dummy_socket, :econnreset})
      assert_receive {:DOWN, _, :process, ^handler, :normal}
    end)
  end
end
