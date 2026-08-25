defmodule Snelda.LLM do
  @moduledoc """
  Stateless OpenAI-format chat completion client.

  `chat/1` is the public library entry point. It holds no configuration and
  persists nothing: the provider URL, model, credentials, prompts, and desired
  response format are all passed per call. Credentials are never logged and
  never embedded in returned errors.
  """

  @type auth :: {:bearer, String.t()} | {:headers, [{String.t(), String.t()}]} | nil

  @type opts :: %{
          required(:proxy_url) => String.t(),
          required(:model) => String.t(),
          required(:system_prompt) => String.t(),
          required(:user_prompt) => String.t(),
          optional(:auth) => auth(),
          optional(:response_format) => :json | :text,
          optional(:req_opts) => keyword()
        }

  @doc """
  Perform a single chat completion.

  Returns `{:ok, map}` for `response_format: :json` (default) and
  `{:ok, binary}` for `response_format: :text`. Errors are structured:
  `{:error, {:invalid_json, raw}}`, `{:error, {:http, status, body}}`,
  `{:error, {:request_failed, reason}}`.
  """
  @spec chat(opts()) ::
          {:ok, map()}
          | {:ok, String.t()}
          | {:error, {:invalid_json, String.t()}}
          | {:error, {:http, non_neg_integer(), term()}}
          | {:error, {:request_failed, term()}}
  def chat(opts) do
    proxy_url = Map.fetch!(opts, :proxy_url)
    model = Map.fetch!(opts, :model)
    sys = Map.fetch!(opts, :system_prompt)
    usr = Map.fetch!(opts, :user_prompt)
    format = Map.get(opts, :response_format, :json)
    req_opts = Map.get(opts, :req_opts, [])
    auth = Map.get(opts, :auth)

    payload = build_payload(model, sys, usr, format)
    request_opts = [json: payload] ++ auth_opts(auth) ++ req_opts

    case Req.post(proxy_url, request_opts) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        content = get_in(body, ["choices", Access.at(0), "message", "content"]) || ""
        parse_content(content, format)

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http, status, body}}

      {:error, exception} ->
        {:error, {:request_failed, exception}}
    end
  end

  defp build_payload(model, sys, usr, :json) do
    %{
      model: model,
      response_format: %{type: "json_object"},
      messages: [
        %{role: "system", content: sys <> "\n\nRespond strictly in JSON."},
        %{role: "user", content: usr}
      ]
    }
  end

  defp build_payload(model, sys, usr, :text) do
    %{
      model: model,
      messages: [
        %{role: "system", content: sys},
        %{role: "user", content: usr}
      ]
    }
  end

  defp parse_content(content, :json) do
    case Jason.decode(content) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, _} -> {:error, {:invalid_json, content}}
    end
  end

  defp parse_content(content, :text), do: {:ok, content}

  defp auth_opts(nil), do: []
  defp auth_opts({:bearer, key}), do: [auth: {:bearer, key}]
  defp auth_opts({:headers, headers}), do: [headers: headers]
end
