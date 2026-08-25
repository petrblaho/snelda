defmodule Snelda.CLI do
  @moduledoc false

  @spec main([String.t()]) :: no_return()
  def main(args) do
    System.halt(do_main(args))
  end

  @spec do_main([String.t()]) :: non_neg_integer()
  def do_main(args) do
    case parse_args(args) do
      {:ok, %{command: :daemon_run}} ->
        setup_daemon_logging()
        run_daemon_blocking()
        0

      {:ok, %{command: :daemon_start}} ->
        disable_logging()
        run_daemon_start()

      {:ok, %{command: :daemon_status}} ->
        disable_logging()
        run_daemon_status()

      {:ok, %{command: :daemon_stop}} ->
        disable_logging()
        run_daemon_stop()

      {:ok, %{command: :execute, config: config, vars: vars}} ->
        disable_logging()

        case run_execute(config, vars) do
          {:ok, code} -> code
          {:error, code} -> code
        end

      {:error, msg} ->
        disable_logging()
        IO.puts(:stderr, msg)
        1
    end
  end

  defp disable_logging do
    :logger.set_primary_config(:level, :none)
  end

  defp setup_daemon_logging do
    timestamp = DateTime.utc_now() |> Calendar.strftime("%Y%m%d_%H%M%S")
    log_path = "/tmp/snelda_daemon_#{timestamp}.log"

    # We add a file backend to the logger for the daemon process.
    # We DO NOT remove the :default handler, so it continues logging to stdout.
    :logger.add_handler(:snelda_file_log, :logger_std_h, %{
      config: %{
        file: String.to_charlist(log_path)
      },
      formatter:
        {:logger_formatter,
         %{
           template: [:time, " ", :level, ": ", :msg, "\n"]
         }}
    })

    require Logger
    Logger.info("Snelda daemon logging started at #{log_path}")
  end

  @spec ping_daemon(String.t()) :: {:ok, map()} | {:error, term()}
  defp ping_daemon(socket_path) do
    case :gen_tcp.connect({:local, socket_path}, 0, [:binary, active: false, packet: 4]) do
      {:ok, socket} ->
        payload = Jason.encode!(%{"type" => "ping"})
        :gen_tcp.send(socket, payload)
        result = do_ping_recv(socket)
        :gen_tcp.close(socket)
        result

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_ping_recv(socket) do
    case :gen_tcp.recv(socket, 0, 1000) do
      {:ok, data} ->
        case Jason.decode(data) do
          {:ok, %{"type" => "pong"} = pong} -> {:ok, pong}
          _ -> {:error, :invalid_response}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec ensure_daemon_running() :: :ok | {:error, String.t()}
  defp ensure_daemon_running do
    socket_path = Application.get_env(:snelda, :socket_path, "/tmp/snelda.sock")

    case ping_daemon(socket_path) do
      {:ok, _pong} ->
        :ok

      {:error, _} ->
        executable =
          try do
            :escript.script_name() |> List.to_string()
          catch
            :error, :undef -> System.argv() |> hd()
          end

        os_adapter = Application.get_env(:snelda, :os_adapter, Snelda.OS.System)

        case os_adapter.spawn_detached(executable, ["daemon", "run"]) do
          :ok ->
            poll_daemon_start(socket_path, 10)

          {:error, msg} ->
            {:error, msg}
        end
    end
  end

  defp poll_daemon_start(_socket_path, 0) do
    {:error, "Failed to start daemon. Check logs."}
  end

  defp poll_daemon_start(socket_path, attempts_left) do
    Process.sleep(100)

    case ping_daemon(socket_path) do
      {:ok, _pong} ->
        :ok

      {:error, _} ->
        poll_daemon_start(socket_path, attempts_left - 1)
    end
  end

  defp run_daemon_blocking do
    socket_path = Application.get_env(:snelda, :socket_path, "/tmp/snelda.sock")

    # Pre-flight check
    case ping_daemon(socket_path) do
      {:ok, _pong} ->
        IO.puts("Daemon is already running.")
        System.halt(0)

      {:error, _} ->
        # The library no longer auto-starts; start the daemon tree explicitly.
        {:ok, _} = Application.ensure_all_started(:snelda)
        {:ok, _} = Snelda.Application.start_daemon()
        require Logger
        Logger.info("Daemon running in foreground. Press Ctrl+C to stop.")
        Process.sleep(:infinity)
        :ok
    end
  end

  defp run_daemon_start do
    case ensure_daemon_running() do
      :ok ->
        socket_path = Application.get_env(:snelda, :socket_path, "/tmp/snelda.sock")

        case ping_daemon(socket_path) do
          {:ok, %{"pid" => pid}} ->
            IO.puts("Daemon started successfully (PID: #{pid}, socket: #{socket_path}).")
            0

          _ ->
            IO.puts("Daemon is already running.")
            0
        end

      {:error, msg} ->
        IO.puts(:stderr, msg)
        1
    end
  end

  @spec run_daemon_status() :: non_neg_integer()
  defp run_daemon_status do
    socket_path = Application.get_env(:snelda, :socket_path, "/tmp/snelda.sock")

    case ping_daemon(socket_path) do
      {:ok, %{"pid" => pid} = pong} ->
        mode = Map.get(pong, "mode", "unknown")
        IO.puts("Daemon is running (PID: #{pid}, socket: #{socket_path}, mode: #{mode}).")
        0

      {:error, :invalid_response} ->
        IO.puts(:stderr, "Daemon returned unexpected response.")
        1

      {:error, _} ->
        IO.puts("Daemon is not running.")
        1
    end
  end

  defp run_daemon_stop do
    socket_path = Application.get_env(:snelda, :socket_path, "/tmp/snelda.sock")

    case :gen_tcp.connect({:local, socket_path}, 0, [:binary, active: false, packet: 4]) do
      {:ok, socket} ->
        payload = Jason.encode!(%{"type" => "stop"})
        :gen_tcp.send(socket, payload)
        do_stop_recv(socket)

      {:error, _} ->
        IO.puts("Daemon is not running.")
        0
    end
  end

  defp do_stop_recv(socket) do
    case :gen_tcp.recv(socket, 0, 1000) do
      {:ok, data} ->
        case Jason.decode(data) do
          {:ok, %{"type" => "stopping"}} ->
            IO.puts("Daemon stopped.")
            0

          _ ->
            IO.puts(:stderr, "Daemon returned unexpected response.")
            1
        end

      {:error, _} ->
        IO.puts(:stderr, "Error receiving from daemon.")
        1
    end
  end

  @spec run_execute(String.t(), map()) :: {:ok, non_neg_integer()} | {:error, non_neg_integer()}
  def run_execute(config, vars) do
    case ensure_daemon_running() do
      :ok ->
        socket_path = Application.get_env(:snelda, :socket_path, "/tmp/snelda.sock")
        send_payload(socket_path, config, vars)

      {:error, msg} ->
        IO.puts(:stderr, msg)
        {:error, 1}
    end
  end

  @spec send_payload(String.t(), String.t(), map()) ::
          {:ok, non_neg_integer()} | {:error, non_neg_integer()}
  defp send_payload(socket_path, config, vars) do
    case :gen_tcp.connect({:local, socket_path}, 0, [:binary, active: false, packet: 4]) do
      {:ok, socket} ->
        handle_connection(socket, config, vars)

      {:error, _} ->
        IO.puts(
          :stderr,
          "Failed to connect to daemon at #{socket_path}. Please start it using 'snelda daemon start'."
        )

        {:error, 1}
    end
  end

  @spec handle_connection(:gen_tcp.socket(), String.t(), map()) ::
          {:ok, non_neg_integer()} | {:error, non_neg_integer()}
  defp handle_connection(socket, config, vars) do
    payload = Jason.encode!(%{"type" => "execute", "config" => config, "vars" => vars})

    :gen_tcp.send(socket, payload)

    case :gen_tcp.recv(socket, 0) do
      {:ok, data} ->
        %{"exit_code" => code, "feedback" => feedback} = Jason.decode!(data)
        if code != 0, do: IO.puts(:stderr, feedback)
        {:ok, code}

      {:error, _} ->
        IO.puts(:stderr, "Error receiving from daemon")
        {:error, 1}
    end
  end

  def parse_args(["daemon", "run"]), do: {:ok, %{command: :daemon_run}}
  def parse_args(["daemon", "start"]), do: {:ok, %{command: :daemon_start}}
  def parse_args(["daemon", "status"]), do: {:ok, %{command: :daemon_status}}
  def parse_args(["daemon", "stop"]), do: {:ok, %{command: :daemon_stop}}
  def parse_args(["daemon"]), do: {:ok, %{command: :daemon_run}}

  def parse_args(["execute" | rest]) do
    {parsed, _args, _invalid} =
      OptionParser.parse(rest,
        strict: [config: :string, var: :keep, var_file: :keep, var_stdin: :keep]
      )

    config = Keyword.get(parsed, :config)

    if is_nil(config) do
      {:error, "--config is required"}
    else
      with {:ok, vars_literal} <- parse_kv(Keyword.get_values(parsed, :var)),
           {:ok, vars_file} <- parse_file_kv(Keyword.get_values(parsed, :var_file)),
           {:ok, vars_stdin} <- parse_stdin(Keyword.get_values(parsed, :var_stdin)) do
        all_vars = Enum.reduce([vars_literal, vars_file, vars_stdin], %{}, &Map.merge(&2, &1))
        {:ok, %{command: :execute, config: Path.expand(config), vars: all_vars}}
      end
    end
  end

  def parse_args(_),
    do:
      {:error,
       "Unknown command. Use 'daemon run', 'daemon start', 'daemon status', 'daemon stop', or 'execute --config <path>'"}

  defp parse_kv(items) do
    Enum.reduce_while(items, {:ok, %{}}, fn item, {:ok, acc} ->
      case String.split(item, "=", parts: 2) do
        [k, v] -> {:cont, {:ok, Map.put(acc, k, v)}}
        _ -> {:halt, {:error, "Malformed --var. Expected key=value, got: #{item}"}}
      end
    end)
  end

  defp parse_file_kv(items) do
    Enum.reduce_while(items, {:ok, %{}}, fn item, {:ok, acc} ->
      case String.split(item, "=", parts: 2) do
        [k, path] ->
          read_file_and_update(acc, k, path)

        _ ->
          {:halt, {:error, "Malformed --var-file. Expected key=path"}}
      end
    end)
  end

  defp read_file_and_update(acc, k, path) do
    case File.read(path) do
      {:ok, content} -> {:cont, {:ok, Map.put(acc, k, content)}}
      {:error, _} -> {:halt, {:error, "Could not read file for variable #{k}: #{path}"}}
    end
  end

  defp parse_stdin([]), do: {:ok, %{}}

  defp parse_stdin([key]) do
    # Suppress the strict Dialyzer warning by trusting IO.stream
    content =
      IO.stream(:stdio, :line)
      |> Enum.join()

    {:ok, %{key => content}}
  end

  defp parse_stdin(_), do: {:error, "Only one --var-stdin is allowed"}
end
