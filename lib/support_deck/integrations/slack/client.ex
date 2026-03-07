defmodule SupportDeck.Integrations.Slack.Client do
  @moduledoc """
  Slack Web API client.

  Base URL: https://slack.com/api/{method}
  Auth: Bearer bot token (xoxb-...)
  Rate limits: tier-based per method, 429 + Retry-After header
  Responses always HTTP 200 with {"ok": true/false} -- check "ok" field, not status.

  Required bot scopes: channels:history, channels:read, chat:write,
  reactions:write, reactions:read, app_mentions:read
  """

  @behaviour SupportDeck.Integrations.Slack.ClientBehaviour

  alias SupportDeck.Integrations.CircuitBreaker

  @base_url "https://slack.com/api"

  @impl true
  def post_message(channel, text, opts \\ []) do
    CircuitBreaker.call(:slack, fn ->
      params =
        %{channel: channel, text: text, unfurl_links: false}
        |> maybe_put(:thread_ts, Keyword.get(opts, :thread_ts))
        |> maybe_put(:blocks, Keyword.get(opts, :blocks))

      slack_request("chat.postMessage", params)
    end)
  end

  @impl true
  def add_reaction(channel, timestamp, emoji) do
    CircuitBreaker.call(:slack, fn ->
      slack_request("reactions.add", %{channel: channel, timestamp: timestamp, name: emoji})
    end)
  end

  @impl true
  def get_channel_history(channel, opts \\ []) do
    CircuitBreaker.call(:slack, fn ->
      params =
        %{channel: channel, limit: Keyword.get(opts, :limit, 100)}
        |> maybe_put(:cursor, Keyword.get(opts, :cursor))

      slack_request("conversations.history", params)
    end)
  end

  defp slack_request(method, params) do
    token = SupportDeck.Settings.Resolver.get(:slack, :bot_token)

    case Req.post(
           url: "#{@base_url}/#{method}",
           headers: [
             {"authorization", "Bearer #{token}"},
             {"content-type", "application/json; charset=utf-8"}
           ],
           json: params
         ) do
      {:ok, %{status: 200, body: %{"ok" => true} = body}} -> {:ok, body}
      {:ok, %{status: 200, body: %{"ok" => false, "error" => e}}} -> {:error, e}
      {:ok, %{status: 429, headers: h}} -> {:error, {:rate_limited, parse_retry_after(h)}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, val), do: Map.put(map, key, val)

  defp parse_retry_after(headers) do
    case List.keyfind(headers, "retry-after", 0) do
      {_, v} -> String.to_integer(v)
      nil -> 30
    end
  end
end
