defmodule SupportDeck.Integrations.Front.Client do
  @moduledoc """
  Front Core API client.

  Base URL: https://api2.frontapp.com
  Auth: Bearer token
  Rate limits: 50-500 req/min (plan-dependent), burst 5 req/s/resource
  Pagination: cursor-based via `_pagination.next` URL and `page_token` param
  """

  @behaviour SupportDeck.Integrations.Front.ClientBehaviour

  alias SupportDeck.Integrations.CircuitBreaker

  @base_url "https://api2.frontapp.com"

  @impl true
  def list_conversations(opts \\ []) do
    CircuitBreaker.call(:front, fn ->
      params =
        %{}
        |> maybe_put(:limit, Keyword.get(opts, :limit, 50))
        |> maybe_put(:page_token, Keyword.get(opts, :page_token))

      request(:get, "/conversations", nil, params: params)
    end)
  end

  @impl true
  def get_conversation(id) do
    CircuitBreaker.call(:front, fn -> request(:get, "/conversations/#{id}") end)
  end

  @impl true
  def get_conversation_messages(id) do
    CircuitBreaker.call(:front, fn -> request(:get, "/conversations/#{id}/messages") end)
  end

  @impl true
  def reply_to_conversation(id, body, opts \\ []) do
    CircuitBreaker.call(:front, fn ->
      request(:post, "/conversations/#{id}/messages", %{
        body: body,
        type: Keyword.get(opts, :type, "reply"),
        sender_name: Keyword.get(opts, :sender_name, "SupportDeck Bot")
      })
    end)
  end

  @impl true
  def add_comment(conversation_id, body) do
    CircuitBreaker.call(:front, fn ->
      request(:post, "/conversations/#{conversation_id}/comments", %{body: body})
    end)
  end

  @impl true
  def tag_conversation(conversation_id, tag_ids) when is_list(tag_ids) do
    CircuitBreaker.call(:front, fn ->
      request(:post, "/conversations/#{conversation_id}/tags", %{tag_ids: tag_ids})
    end)
  end

  @impl true
  def assign_conversation(conversation_id, teammate_id) do
    CircuitBreaker.call(:front, fn ->
      request(:patch, "/conversations/#{conversation_id}", %{assignee_id: teammate_id})
    end)
  end

  defp request(method, path, body \\ nil, opts \\ []) do
    token = SupportDeck.Settings.Resolver.get(:front, :api_token)

    req =
      Req.new(
        base_url: @base_url,
        headers: [{"authorization", "Bearer #{token}"}]
      )

    result =
      case method do
        :get -> Req.get(req, url: path, params: Keyword.get(opts, :params, %{}))
        :post -> Req.post(req, url: path, json: body)
        :patch -> Req.patch(req, url: path, json: body)
      end

    case result do
      {:ok, %{status: s, body: resp_body}} when s in 200..299 -> {:ok, resp_body}
      {:ok, %{status: 429, headers: h}} -> {:error, {:rate_limited, parse_retry_after(h)}}
      {:ok, %{status: s, body: b}} -> {:error, %{status: s, body: b}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_retry_after(headers) do
    case List.keyfind(headers, "retry-after", 0) do
      {_, v} -> String.to_integer(v)
      nil -> 60
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, val), do: Map.put(map, key, val)
end
