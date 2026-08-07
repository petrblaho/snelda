defmodule Snelda.CLI do
  @moduledoc false

  def main(args) do
    case parse_args(args) do
      {:ok, _opts} ->
        :ok

      {:error, msg} ->
        IO.puts(:stderr, msg)
        System.halt(1)
    end
  end

  def parse_args(["daemon"]), do: {:ok, %{command: :daemon}}

  def parse_args(["execute" | rest]) do
    {parsed, _args, _invalid} =
      OptionParser.parse(rest,
        strict: [config: :string, var: :keep, var_file: :keep, var_stdin: :keep]
      )

    config = Keyword.get(parsed, :config)

    with true <- config != nil || {:error, "--config is required"},
         {:ok, vars_literal} <- parse_kv(Keyword.get_values(parsed, :var)),
         {:ok, vars_file} <- parse_file_kv(Keyword.get_values(parsed, :var_file)),
         {:ok, vars_stdin} <- parse_stdin(Keyword.get_values(parsed, :var_stdin)) do
      all_vars = Enum.reduce([vars_literal, vars_file, vars_stdin], %{}, &Map.merge(&2, &1))
      {:ok, %{command: :execute, config: config, vars: all_vars}}
    else
      {:error, msg} -> {:error, msg}
      false -> {:error, "--config is required"}
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
    content = IO.read(:stdio, :all) || ""
    {:ok, %{key => content}}
  end

  defp parse_stdin(_), do: {:error, "Only one --var-stdin is allowed"}
end
