defmodule Snelda.Socket.HandlerExecuteTest do
  use ExUnit.Case, async: true

  test "handles execute payload and evaluates condition" do
    Application.put_env(:snelda, :socket_path, "/tmp/snelda_test_exec.sock")
    File.rm("/tmp/snelda_test_exec.sock")

    # Write a temporary config
    File.write!(
      "test_task.json",
      Jason.encode!(%{
        "proxy_url" => "http://localhost/v1",
        "model" => "gpt",
        "system_prompt" => "sys",
        "user_prompt" => "{{diff}}",
        "success_condition" => "valid == true"
      })
    )

    {:ok, sup} =
      Supervisor.start_link(
        [
          {Snelda.Socket.Acceptor, socket_path: "/tmp/snelda_test_exec.sock"}
        ],
        strategy: :one_for_one
      )

    Process.sleep(50)

    {:ok, socket} =
      :gen_tcp.connect({:local, "/tmp/snelda_test_exec.sock"}, 0, [
        :binary,
        active: false,
        packet: 4
      ])

    # Send payload
    payload =
      Jason.encode!(%{
        "type" => "execute",
        "config" => "test_task.json",
        "vars" => %{"diff" => "mock"}
      }) <> "\n"

    :ok = :gen_tcp.send(socket, payload)

    # We expect an error response because the LLM proxy is unreachable in the real handler
    {:ok, response} = :gen_tcp.recv(socket, 0, 1000)

    assert %{"type" => "execution_result", "exit_code" => 1, "feedback" => feedback} =
             Jason.decode!(response)

    assert String.contains?(feedback, "Request failed")

    File.rm!("test_task.json")
    Process.exit(sup, :normal)
  end
end
