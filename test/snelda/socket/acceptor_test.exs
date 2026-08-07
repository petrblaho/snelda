defmodule Snelda.Socket.AcceptorTest do
  use ExUnit.Case
  import ExUnit.CaptureLog

  test "acceptor exits on accept error" do
    capture_log(fn ->
      socket_path = "/tmp/snelda_acceptor_test.sock"
      File.rm(socket_path)

      # Start the acceptor
      pid = start_supervised!({Snelda.Socket.Acceptor, socket_path: socket_path})
      # let it open the socket
      Process.sleep(100)

      # Find the port owned by pid
      {:links, links} = Process.info(pid, :links)
      ports = Enum.filter(links, &is_port/1)

      [listen_socket] = ports

      # Monitor the acceptor
      ref = Process.monitor(pid)

      # Close the socket
      Port.close(listen_socket)

      # Acceptor should exit with {:error, :closed}
      assert_receive {:DOWN, ^ref, :process, ^pid, {:error, :closed}}, 1000
    end)
  end
end
