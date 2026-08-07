# Config-Driven LLM Task Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a generic, config-driven LLM task engine in Elixir that operates as an `escript` CLI with an auto-spawning background daemon, safely handling large inputs, concurrency, and integrating with a LiteLLM proxy via the OpenAI API format.

**Architecture:** We will update `mix.exs` to compile Snelda into an `escript` (`Snelda.CLI`) with `app: nil` to prevent auto-starting the server. The CLI will parse arguments and attempt to forward `execute` commands to the existing TCP socket. If the socket is unavailable, the CLI forks `snelda daemon` to the background, waits with exponential backoff, and retries. The backend will parse a JSON configuration file, interpolate variables into prompts, and use `Req` to query a LiteLLM proxy (OpenAI format). The response is evaluated against a success condition to determine the exit code.

**Tech Stack:** Elixir, Mix (Escript), Jason (JSON parsing), Req (HTTP client).

## Global Constraints
- Elixir 1.20 required.
- 100% test coverage enforced (`mix coveralls`).
- Commit messages *to this repository* must follow Conventional Commits.
- All checks (`mix coveralls`, `mix format --check-formatted`, `mix credo --strict`, `mix dialyzer`) must pass.

---

### Task 1: CLI Argument Parsing and Input Handling

**Files:**
- Modify: `mix.exs`
- Create: `lib/snelda/cli.ex`
- Create: `test/snelda/cli_test.exs`

**Interfaces:**
- Consumes: User command line arguments, files, and standard input.
- Produces: `Snelda.CLI.parse_args(args) :: {:ok, map()} | {:error, String.t()}`

- [ ] **Step 1: Add escript config to `mix.exs`**

```elixir
# Update the `project/0` function in mix.exs to include `escript: [main_module: Snelda.CLI, app: nil]`
def project do
  [
    app: :snelda,
    version: "0.1.0",
    elixir: "~> 1.20",
    start_permanent: Mix.env() == :prod,
    escript: [main_module: Snelda.CLI, app: nil],
    deps: deps(),
    dialyzer: [
      plt_local_path: ".plts",
      plt_core_path: ".plts"
    ],
    test_coverage: [tool: ExCoveralls]
  ]
end
```

- [ ] **Step 2: Write failing tests for robust CLI parsing**

```elixir
# test/snelda/cli_test.exs
defmodule Snelda.CLITest do
  use ExUnit.Case, async: true
  alias Snelda.CLI

  test "parses literal variables gracefully" do
    args = ["execute", "--config", "task.json", "--var", "foo=bar"]
    assert {:ok, %{command: :execute, config: "task.json", vars: %{"foo" => "bar"}}} = CLI.parse_args(args)
  end

  test "returns error for malformed --var" do
    assert {:error, _} = CLI.parse_args(["execute", "--config", "t.json", "--var", "invalid_format"])
  end
  
  test "parses --var-file and reads contents" do
    path = "test_var_file.txt"
    File.write!(path, "file content")
    assert {:ok, %{vars: %{"msg" => "file content"}}} = CLI.parse_args(["execute", "--config", "c.json", "--var-file", "msg=#{path}"])
    File.rm!(path)
  end
end
```

- [ ] **Step 3: Verify tests fail**

Run: `mix test test/snelda/cli_test.exs`
Expected: Compilation error or failure on missing `Snelda.CLI`.

- [ ] **Step 4: Implement `Snelda.CLI.parse_args/1`**

```elixir
# lib/snelda/cli.ex
defmodule Snelda.CLI do
  @moduledoc false

  def main(args) do
    case parse_args(args) do
      {:ok, opts} -> IO.inspect(opts)
      {:error, msg} -> IO.puts(:stderr, msg); System.halt(1)
    end
  end

  def parse_args(["daemon"]), do: {:ok, %{command: :daemon}}
  
  def parse_args(["execute" | rest]) do
    {parsed, _args, _invalid} = OptionParser.parse(rest, strict: [config: :string, var: :keep, var_file: :keep, var_stdin: :keep])
    
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
          case File.read(path) do
            {:ok, content} -> {:cont, {:ok, Map.put(acc, k, content)}}
            {:error, _} -> {:halt, {:error, "Could not read file for variable #{k}: #{path}"}}
          end
        _ -> {:halt, {:error, "Malformed --var-file. Expected key=path"}}
      end
    end)
  end

  defp parse_stdin([]), do: {:ok, %{}}
  defp parse_stdin([key]) do
    content = IO.read(:stdio, :all) || ""
    {:ok, %{key => content}}
  end
  defp parse_stdin(_), do: {:error, "Only one --var-stdin is allowed"}
end
```

- [ ] **Step 5: Verify tests pass**

Run: `mix test test/snelda/cli_test.exs`
Expected: PASS

- [ ] **Step 6: Commit changes**

```bash
git add mix.exs lib/snelda/cli.ex test/snelda/cli_test.exs
git commit -m "feat: add robust escript CLI parser with file and stdin support"
```

---

### Task 2: Add Req Dependency and Task Configuration Parser

**Files:**
- Modify: `mix.exs`
- Create: `lib/snelda/task_config.ex`
- Create: `test/snelda/task_config_test.exs`

**Interfaces:**
- Consumes: A JSON configuration map and a variables map.
- Produces: `Snelda.TaskConfig.render_prompt(template, vars) :: String.t()`

- [ ] **Step 1: Add `Req` to `mix.exs`**

```elixir
# In mix.exs deps/0, add Req:
  defp deps do
    [
      {:req, "~> 0.5.0"},
      {:jason, "~> 1.4"},
      # ... keep existing deps
    ]
  end
```
Run `mix deps.get`.

- [ ] **Step 2: Write failing tests for templating**

```elixir
# test/snelda/task_config_test.exs
defmodule Snelda.TaskConfigTest do
  use ExUnit.Case, async: true
  alias Snelda.TaskConfig

  test "replaces variables in template" do
    template = "Message: {{message}}\nDiff: {{diff}}"
    vars = %{"message" => "fix stuff", "diff" => "+ code"}
    assert TaskConfig.render_prompt(template, vars) == "Message: fix stuff\nDiff: + code"
  end
end
```

- [ ] **Step 3: Implement templating logic**

```elixir
# lib/snelda/task_config.ex
defmodule Snelda.TaskConfig do
  @moduledoc false

  def render_prompt(template, vars) do
    Enum.reduce(vars, template, fn {key, value}, acc ->
      String.replace(acc, "{{#{key}}}", value)
    end)
  end
end
```

- [ ] **Step 4: Verify and Commit**
Run `mix test test/snelda/task_config_test.exs`. Commit.
```bash
git add mix.exs mix.lock lib/snelda/task_config.ex test/snelda/task_config_test.exs
git commit -m "feat: add req dependency and prompt templating"
```

---

### Task 3: Implement LLM Connector

**Files:**
- Create: `lib/snelda/llm.ex`
- Create: `test/snelda/llm_test.exs`

**Interfaces:**
- Consumes: `proxy_url`, `model`, `system_prompt`, `user_prompt`
- Produces: `Snelda.LLM.execute(opts) :: {:ok, map()} | {:error, String.t()}`

- [ ] **Step 1: Write mock tests for LLM connector**

```elixir
# test/snelda/llm_test.exs
defmodule Snelda.LLMTest do
  use ExUnit.Case, async: true
  alias Snelda.LLM

  test "formats openai request and parses response" do
    # Req provides a handy test plug mechanism
    Req.Test.stub(Snelda.LLM, fn conn ->
      Req.Test.json(conn, %{
        "choices" => [%{
          "message" => %{
            "content" => "{\"valid\": false, \"feedback\": \"Bad commit\"}"
          }
        }]
      })
    end)

    opts = %{
      proxy_url: "http://localhost:4000/v1/chat/completions",
      model: "test-model",
      system_prompt: "sys",
      user_prompt: "usr",
      req_opts: [plug: Snelda.LLM] # Inject test plug
    }

    assert {:ok, %{"valid" => false, "feedback" => "Bad commit"}} = LLM.execute(opts)
  end
end
```

- [ ] **Step 2: Implement LLM Connector**

```elixir
# lib/snelda/llm.ex
defmodule Snelda.LLM do
  @moduledoc false

  def execute(opts) do
    proxy_url = Map.fetch!(opts, :proxy_url)
    model = Map.fetch!(opts, :model)
    sys = Map.fetch!(opts, :system_prompt)
    usr = Map.fetch!(opts, :user_prompt)
    req_opts = Map.get(opts, :req_opts, [])
    
    payload = %{
      model: model,
      response_format: %{type: "json_object"},
      messages: [
        %{role: "system", content: sys <> "\n\nRespond strictly in JSON."},
        %{role: "user", content: usr}
      ]
    }

    case Req.post(proxy_url, [json: payload] ++ req_opts) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        content = get_in(body, ["choices", Access.at(0), "message", "content"])
        case Jason.decode(content || "") do
          {:ok, parsed} -> {:ok, parsed}
          {:error, _} -> {:error, "LLM returned invalid JSON: #{content}"}
        end
      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, "Proxy returned HTTP #{status}: #{inspect(body)}"}
      {:error, exception} ->
        {:error, "Request failed: #{inspect(exception)}"}
    end
  end
end
```

- [ ] **Step 3: Verify and Commit**
Run `mix test test/snelda/llm_test.exs`. Commit.
```bash
git add lib/snelda/llm.ex test/snelda/llm_test.exs
git commit -m "feat: implement openai-compatible llm connector using req"
```

---

### Task 4: Connect Execute Task Payload to LLM

**Files:**
- Modify: `lib/snelda/socket/handler.ex`
- Create: `test/snelda/socket/handler_execute_test.exs`

**Interfaces:**
- Consumes: JSON payload over TCP. Reads the config file. Uses `Snelda.LLM`.

- [ ] **Step 1: Write test for execute payload**

```elixir
# test/snelda/socket/handler_execute_test.exs
defmodule Snelda.Socket.HandlerExecuteTest do
  use ExUnit.Case, async: true

  test "handles execute payload and evaluates condition" do
    Application.put_env(:snelda, :socket_path, "/tmp/snelda_test_exec.sock")
    File.rm("/tmp/snelda_test_exec.sock")
    
    # Write a temporary config
    File.write!("test_task.json", Jason.encode!(%{
      "proxy_url" => "http://localhost/v1",
      "model" => "gpt",
      "system_prompt" => "sys",
      "user_prompt" => "{{diff}}",
      "success_condition" => "valid == true"
    }))
    
    {:ok, sup} = Supervisor.start_link([
      {Registry, keys: :unique, name: Snelda.SessionRegistry},
      {Phoenix.PubSub, name: Snelda.PubSub},
      {DynamicSupervisor, strategy: :one_for_one, name: Snelda.Session.Supervisor},
      {Snelda.Socket.Acceptor, socket_path: "/tmp/snelda_test_exec.sock"}
    ], strategy: :one_for_one)

    Process.sleep(50)
    {:ok, socket} = :gen_tcp.connect({:local, "/tmp/snelda_test_exec.sock"}, 0, [:binary, active: false, packet: :line])
    
    # Send payload
    payload = Jason.encode!(%{"type" => "execute", "config" => "test_task.json", "vars" => %{"diff" => "mock"}}) <> "\n"
    :ok = :gen_tcp.send(socket, payload)
    
    # We expect an error response because the LLM proxy is unreachable in the real handler
    {:ok, response} = :gen_tcp.recv(socket, 0, 1000)
    assert %{"type" => "execution_result", "exit_code" => 1, "feedback" => feedback} = Jason.decode!(response)
    assert String.contains?(feedback, "Request failed")

    File.rm!("test_task.json")
    Process.exit(sup, :normal)
  end
end
```

- [ ] **Step 2: Implement execution handler (Config Read + LLM + Eval)**

```elixir
# In lib/snelda/socket/handler.ex, update handle_info({:tcp, socket, data}, state)

  def handle_info({:tcp, socket, data}, state) do
    case Jason.decode(data) do
      {:ok, %{"type" => "execute", "config" => config_path, "vars" => vars}} ->
        response_payload = execute_task(config_path, vars)
        
        response = Jason.encode!(response_payload) <> "\n"
        :gen_tcp.send(socket, response)
        :inet.setopts(socket, active: :once)
        {:noreply, state}

      # ... existing clauses ...
  end

  defp execute_task(config_path, vars) do
    with {:ok, file} <- File.read(config_path),
         {:ok, config} <- Jason.decode(file) do
      
      prompt = Snelda.TaskConfig.render_prompt(config["user_prompt"], vars)
      
      opts = %{
        proxy_url: config["proxy_url"] || "http://localhost:4000/v1/chat/completions",
        model: config["model"],
        system_prompt: config["system_prompt"],
        user_prompt: prompt
      }
      
      case Snelda.LLM.execute(opts) do
        {:ok, result} ->
          # MVP evaluation: just check if the boolean key from success condition matches.
          # We parse a naive condition like "valid == true"
          condition = config["success_condition"] || ""
          [key, "==", expected] = String.split(condition, " ", parts: 3)
          expected_bool = expected == "true"
          
          is_success = Map.get(result, key) == expected_bool
          exit_code = if is_success, do: 0, else: 1
          feedback = Map.get(result, "feedback", "No feedback provided")
          
          %{"type" => "execution_result", "exit_code" => exit_code, "feedback" => feedback}
          
        {:error, msg} ->
          %{"type" => "execution_result", "exit_code" => 1, "feedback" => "LLM Error: #{msg}"}
      end
    else
      {:error, err} -> 
        %{"type" => "execution_result", "exit_code" => 1, "feedback" => "Config error: #{inspect(err)}"}
    end
  end
```

- [ ] **Step 3: Verify and Commit**
Run `mix test test/snelda/socket/handler_execute_test.exs`. Commit.
```bash
git add lib/snelda/socket/handler.ex test/snelda/socket/handler_execute_test.exs
git commit -m "feat: handle task execution via socket and invoke llm"
```

---

### Task 5: CLI Client with Exponential Backoff

**Files:**
- Modify: `lib/snelda/cli.ex`

- [ ] **Step 1: Implement Daemon Command**

```elixir
# Add to lib/snelda/cli.ex
  def main(args) do
    case parse_args(args) do
      {:ok, %{command: :daemon}} -> run_daemon()
      {:ok, %{command: :execute, config: config, vars: vars}} -> run_execute(config, vars)
      {:error, msg} -> IO.puts(:stderr, msg); System.halt(1)
    end
  end

  defp run_daemon do
    Mix.env(:prod)
    {:ok, _} = Application.ensure_all_started(:snelda)
    Process.sleep(:infinity)
  end
```

- [ ] **Step 2: Implement Execute Command (Exponential Backoff)**

```elixir
# Add to lib/snelda/cli.ex
  defp run_execute(config, vars) do
    socket_path = Application.get_env(:snelda, :socket_path, "/tmp/snelda.sock")
    send_payload(socket_path, config, vars, 0)
  end

  defp send_payload(socket_path, config, vars, attempt) when attempt < 6 do
    case :gen_tcp.connect({:local, socket_path}, 0, [:binary, active: false, packet: :line]) do
      {:ok, socket} ->
        payload = Jason.encode!(%{"type" => "execute", "config" => config, "vars" => vars}) <> "\n"
        :gen_tcp.send(socket, payload)
        
        case :gen_tcp.recv(socket, 0) do
          {:ok, data} ->
            %{"exit_code" => code, "feedback" => feedback} = Jason.decode!(data)
            if code != 0, do: IO.puts(:stderr, feedback)
            System.halt(code)
          {:error, _} ->
            IO.puts(:stderr, "Error receiving from daemon")
            System.halt(1)
        end
        
      {:error, _} ->
        if attempt == 0, do: spawn_daemon()
        
        # Exponential backoff: 50, 100, 200, 400, 800ms
        backoff = 50 * Integer.pow(2, attempt)
        Process.sleep(backoff)
        send_payload(socket_path, config, vars, attempt + 1)
    end
  end
  
  defp send_payload(socket_path, _config, _vars, _) do
    IO.puts(:stderr, "Failed to connect to daemon at #{socket_path} after multiple retries.")
    System.halt(1)
  end

  defp spawn_daemon do
    bin = System.find_executable("snelda") || :escript.script_name() |> to_string()
    Port.open({:spawn_executable, bin}, [:detached, args: ["daemon"]])
  end
```

- [ ] **Step 3: Run Dialyzer, test compilation, and Commit**
Run `mix credo --strict && mix dialyzer`. Run `mix escript.build`. Commit.
```bash
git add lib/snelda/cli.ex
git commit -m "feat: implement escript client and daemon backoff spawner"
```

---

### Task 6: The MVP Configuration and Sample Git Hook

**Files:**
- Create: `.snelda/commit-verify.json`
- Create: `.githooks/sample-commit-msg`

- [ ] **Step 1: Create the config JSON**

```json
{
  "proxy_url": "http://localhost:4000/v1/chat/completions",
  "model": "claude-3-5-sonnet-20240620",
  "system_prompt": "You enforce the 'Stop Using Conventional Commits' philosophy...",
  "user_prompt": "Evaluate this commit:\nMessage:\n{{message}}\n\nDiff:\n{{diff}}",
  "success_condition": "valid == true"
}
```

- [ ] **Step 2: Create the sample git hook script**

```bash
#!/bin/bash
# .githooks/sample-commit-msg

MESSAGE_FILE=$1

# Safely pass large diff via stdin, and message via file
git diff --cached | snelda execute \
  --config .snelda/commit-verify.json \
  --var-file message="$MESSAGE_FILE" \
  --var-stdin diff
```

- [ ] **Step 3: Commit changes**
`chmod +x .githooks/sample-commit-msg` and commit.
```bash
git add .snelda/commit-verify.json .githooks/sample-commit-msg
git commit -m "docs: add MVP configuration and sample git hook"
```
