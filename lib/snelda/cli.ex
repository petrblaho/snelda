defmodule Snelda.CLI do
  @moduledoc false

  @spec main([String.t()]) :: no_return()
  def main(args) do
    System.halt(do_main(args))
  end

  @spec do_main([String.t()]) :: non_neg_integer()
  def do_main(args) do
    case parse_args(args) do
      {:ok, %{command: :daemon}} ->
        run_daemon()
        0

      {:ok, %{command: :execute, config: config, vars: vars}} ->
        case run_execute(config, vars) do
          {:ok, code} -> code
          {:error, code} -> code
        end

      {:error, msg} ->
        IO.puts(:stderr, msg)
        1
    end
  end

  @spec run_daemon() :: :ok
  defp run_daemon do
    # Starting Snelda without auto-start
    {:ok, _} = Application.ensure_all_started(:snelda)
    Process.sleep(:infinity)
    :ok
  end

  @spec run_execute(String.t(), map()) :: {:ok, non_neg_integer()} | {:error, non_neg_integer()}
  def run_execute(config, vars) do
    socket_path = Application.get_env(:snelda, :socket_path, "/tmp/snelda.sock")
    send_payload(socket_path, config, vars, 0)
  end

  @spec send_payload(String.t(), String.t(), map(), non_neg_integer()) ::
          {:ok, non_neg_integer()} | {:error, non_neg_integer()}
  defp send_payload(socket_path, config, vars, attempt) when attempt < 6 do
    case :gen_tcp.connect({:local, socket_path}, 0, [:binary, active: false, packet: :line]) do
      {:ok, socket} ->
        handle_connection(socket, config, vars)

      {:error, _} ->
        retry_connection(socket_path, config, vars, attempt)
    end
  end

  defp send_payload(socket_path, _config, _vars, _) do
    IO.puts(:stderr, "Failed to connect to daemon at #{socket_path} after multiple retries.")
    {:error, 1}
  end

  @spec handle_connection(:gen_tcp.socket(), String.t(), map()) ::
          {:ok, non_neg_integer()} | {:error, non_neg_integer()}
  defp handle_connection(socket, config, vars) do
    payload =
      Jason.encode!(%{"type" => "execute", "config" => config, "vars" => vars}) <> "\n"

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

  @dialyzer {:nowarn_function, retry_connection: 4}
  @spec retry_connection(String.t(), String.t(), map(), non_neg_integer()) ::
          {:ok, non_neg_integer()} | {:error, non_neg_integer()} | no_return()
  defp retry_connection(socket_path, config, vars, attempt) do
    if attempt == 0 do
      spawn_daemon()
    end

    # Exponential backoff: 50, 100, 200, 400, 800ms
    # For tests, we use 1ms backoff so tests don't take ages
    backoff = Application.get_env(:snelda, :backoff_multiplier, 50) * Integer.pow(2, attempt)
    Process.sleep(backoff)
    send_payload(socket_path, config, vars, attempt + 1)
  end

  @dialyzer {:nowarn_function, spawn_daemon: 0}
  @spec spawn_daemon() :: port() | no_return() | :ok
  defp spawn_daemon do
    if Mix.env() == :test do
      :ok
    else
      bin =
        System.find_executable("snelda") || :escript.script_name() |> to_string() || "snelda"

      try do
        Port.open({:spawn_executable, bin}, [:detached, args: ["daemon"]])
      rescue
        _ ->
          IO.puts(:stderr, "Failed to spawn daemon process.")
          System.halt(1)
      end
    end
  end

  def parse_args(["daemon"]), do: {:ok, %{command: :daemon}}

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
        {:ok, %{command: :execute, config: config, vars: all_vars}}
      end
    end
  end

  def parse_args(_), do: {:error, "Unknown command. Use 'daemon' or 'execute --config <path>'"}

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
