defmodule Snelda.LLMTest do
  use ExUnit.Case, async: true
  alias Snelda.LLM

  test "formats openai request and parses response" do
    Req.Test.stub(Snelda.LLM, fn conn ->
      Req.Test.json(conn, %{
        "choices" => [
          %{
            "message" => %{
              "content" => "{\"valid\": false, \"feedback\": \"Bad commit\"}"
            }
          }
        ]
      })
    end)

    opts = %{
      proxy_url: "http://localhost:4000/v1/chat/completions",
      model: "test-model",
      system_prompt: "sys",
      user_prompt: "usr",
      req_opts: [plug: {Req.Test, Snelda.LLM}]
    }

    assert {:ok, %{"valid" => false, "feedback" => "Bad commit"}} = LLM.execute(opts)
  end

  test "returns error on invalid json from LLM" do
    Req.Test.stub(Snelda.LLMInvalid, fn conn ->
      Req.Test.json(conn, %{
        "choices" => [%{"message" => %{"content" => "not valid json"}}]
      })
    end)

    opts = %{
      proxy_url: "http://localhost",
      model: "m",
      system_prompt: "s",
      user_prompt: "u",
      req_opts: [plug: {Req.Test, Snelda.LLMInvalid}]
    }

    assert {:error, "LLM returned invalid JSON" <> _} = LLM.execute(opts)
  end

  test "returns error on proxy HTTP error" do
    Req.Test.stub(Snelda.LLMHttpError, fn conn ->
      Plug.Conn.send_resp(conn, 500, "Internal Server Error")
    end)

    opts = %{
      proxy_url: "http://localhost",
      model: "m",
      system_prompt: "s",
      user_prompt: "u",
      req_opts: [plug: {Req.Test, Snelda.LLMHttpError}]
    }

    assert {:error, "Proxy returned HTTP 500" <> _} = LLM.execute(opts)
  end

  test "returns error on network failure" do
    # Simulating a network error by querying a broken URL without a plug
    opts = %{
      proxy_url: "http://localhost:9999/broken",
      model: "m",
      system_prompt: "s",
      user_prompt: "u",
      req_opts: [retry: false]
    }

    assert {:error, "Request failed" <> _} = LLM.execute(opts)
  end
end
