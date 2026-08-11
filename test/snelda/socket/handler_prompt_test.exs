defmodule Snelda.Socket.HandlerPromptTest do
  use ExUnit.Case, async: true

  setup do
    socket_path = "/tmp/snelda_prompt_test_#{System.unique_integer([:positive])}.sock"
    File.rm(socket_path)

    {:ok, sup} =
      Supervisor.start_link(
        [
          {Registry, keys: :unique, name: String.to_atom("Registry_#{System.unique_integer()}")},
          {DynamicSupervisor,
           strategy: :one_for_one, name: String.to_atom("Dynamic_#{System.unique_integer()}")},
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

  test "processes prompt and returns history", %{socket: socket} do
    sid = "session_#{System.unique_integer()}"
    payload = Jason.encode!(%{"type" => "prompt", "session_id" => sid, "text" => "hello"}) <> "\n"
    :ok = :gen_tcp.send(socket, payload)

    # We are using PubSub which is global for the whole node, so this works even
    # if we started a new Supervisor above, the handler will publish to global PubSub
    {:ok, response} = :gen_tcp.recv(socket, 0, 1000)
    assert %{"type" => "history", "data" => ["hello"]} = Jason.decode!(response)

    payload2 =
      Jason.encode!(%{"type" => "prompt", "session_id" => sid, "text" => "world"}) <> "\n"

    :ok = :gen_tcp.send(socket, payload2)

    {:ok, response2} = :gen_tcp.recv(socket, 0, 1000)
    assert %{"type" => "history", "data" => ["hello", "world"]} = Jason.decode!(response2)
  end

  alias Snelda.Socket.Handler

  test "handler correctly ignores unexpected PubSub messages" do
    {:ok, state} = Handler.init(nil)

    assert {:noreply, ^state} =
             Handler.handle_info(
               %Snelda.Event{session_id: "test", type: :unknown, payload: ""},
               state
             )
  end

  test "session correctly ignores unexpected PubSub messages" do
    # For this one we need a real pubsub sub, so we just use the global one since it's already there
    {:ok, state} = Snelda.Session.init(session_id: "123")

    assert {:noreply, ^state} =
             Snelda.Session.handle_info(
               %Snelda.Event{session_id: "123", type: :unknown, payload: ""},
               state
             )
  end
end
