defmodule Snelda.LLMTest do
  use ExUnit.Case, async: true
  alias Snelda.LLM

  test "formats openai request and parses response" do
    # Req provides a handy test plug mechanism
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
      # Inject test plug
      req_opts: [plug: {Req.Test, Snelda.LLM}]
    }

    assert {:ok, %{"valid" => false, "feedback" => "Bad commit"}} = LLM.execute(opts)
  end
end
