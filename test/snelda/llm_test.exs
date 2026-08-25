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

  test "execute/1 does not crash when the LLM returns non-object JSON" do
    Req.Test.stub(Snelda.LLMExecList, fn conn ->
      Req.Test.json(conn, %{
        "choices" => [%{"message" => %{"content" => "[1, 2, 3]"}}]
      })
    end)

    opts = %{
      proxy_url: "http://localhost",
      model: "m",
      system_prompt: "s",
      user_prompt: "u",
      req_opts: [plug: {Req.Test, Snelda.LLMExecList}]
    }

    assert {:error, "LLM returned invalid JSON" <> _} = LLM.execute(opts)
  end

  describe "chat/1" do
    test "json mode parses object" do
      Req.Test.stub(Snelda.LLMChatJson, fn conn ->
        Req.Test.json(conn, %{
          "choices" => [%{"message" => %{"content" => "{\"ok\": true}"}}]
        })
      end)

      opts = %{
        proxy_url: "http://localhost",
        model: "m",
        system_prompt: "s",
        user_prompt: "u",
        req_opts: [plug: {Req.Test, Snelda.LLMChatJson}]
      }

      assert {:ok, %{"ok" => true}} = LLM.chat(opts)
    end

    test "json mode returns structured invalid_json error" do
      Req.Test.stub(Snelda.LLMChatBad, fn conn ->
        Req.Test.json(conn, %{
          "choices" => [%{"message" => %{"content" => "nope"}}]
        })
      end)

      opts = %{
        proxy_url: "http://localhost",
        model: "m",
        system_prompt: "s",
        user_prompt: "u",
        req_opts: [plug: {Req.Test, Snelda.LLMChatBad}]
      }

      assert {:error, {:invalid_json, "nope"}} = LLM.chat(opts)
    end

    test "text mode returns raw string and omits response_format" do
      Req.Test.stub(Snelda.LLMChatText, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        refute Map.has_key?(decoded, "response_format")
        Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => "hello world"}}]})
      end)

      opts = %{
        proxy_url: "http://localhost",
        model: "m",
        system_prompt: "s",
        user_prompt: "u",
        response_format: :text,
        req_opts: [plug: {Req.Test, Snelda.LLMChatText}]
      }

      assert {:ok, "hello world"} = LLM.chat(opts)
    end

    test "bearer auth sets Authorization header" do
      Req.Test.stub(Snelda.LLMChatBearer, fn conn ->
        assert ["Bearer sk-test"] = Plug.Conn.get_req_header(conn, "authorization")
        Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => "{}"}}]})
      end)

      opts = %{
        proxy_url: "http://localhost",
        model: "m",
        system_prompt: "s",
        user_prompt: "u",
        auth: {:bearer, "sk-test"},
        req_opts: [plug: {Req.Test, Snelda.LLMChatBearer}]
      }

      assert {:ok, %{}} = LLM.chat(opts)
    end

    test "headers auth merges custom headers" do
      Req.Test.stub(Snelda.LLMChatHeaders, fn conn ->
        assert ["k-123"] = Plug.Conn.get_req_header(conn, "x-api-key")
        Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => "{}"}}]})
      end)

      opts = %{
        proxy_url: "http://localhost",
        model: "m",
        system_prompt: "s",
        user_prompt: "u",
        auth: {:headers, [{"x-api-key", "k-123"}]},
        req_opts: [plug: {Req.Test, Snelda.LLMChatHeaders}]
      }

      assert {:ok, %{}} = LLM.chat(opts)
    end

    test "nil auth sends no authorization header" do
      Req.Test.stub(Snelda.LLMChatNoAuth, fn conn ->
        assert [] = Plug.Conn.get_req_header(conn, "authorization")
        Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => "{}"}}]})
      end)

      opts = %{
        proxy_url: "http://localhost",
        model: "m",
        system_prompt: "s",
        user_prompt: "u",
        req_opts: [plug: {Req.Test, Snelda.LLMChatNoAuth}]
      }

      assert {:ok, %{}} = LLM.chat(opts)
    end

    test "http error returns structured tuple" do
      Req.Test.stub(Snelda.LLMChatHttp, fn conn ->
        Plug.Conn.send_resp(conn, 429, "rate limited")
      end)

      opts = %{
        proxy_url: "http://localhost",
        model: "m",
        system_prompt: "s",
        user_prompt: "u",
        req_opts: [plug: {Req.Test, Snelda.LLMChatHttp}]
      }

      assert {:error, {:http, 429, _body}} = LLM.chat(opts)
    end

    test "transport failure returns request_failed" do
      opts = %{
        proxy_url: "http://localhost:9999/broken",
        model: "m",
        system_prompt: "s",
        user_prompt: "u",
        req_opts: [retry: false]
      }

      assert {:error, {:request_failed, _reason}} = LLM.chat(opts)
    end
  end
end
