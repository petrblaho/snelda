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
