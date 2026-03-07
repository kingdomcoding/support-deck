defmodule SupportDeck.Workers.SlackWebhookWorker do
  use Oban.Worker, queue: :webhooks, max_attempts: 5

  alias SupportDeck.Tickets

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"payload" => payload}}) do
    event = payload["event"] || %{}

    case event["type"] do
      "message" -> handle_message(event)
      "reaction_added" -> handle_reaction(event)
      "app_mention" -> handle_mention(event)
      _ -> :ok
    end
  end

  defp handle_message(%{"channel" => ch, "ts" => ts, "text" => text} = event) do
    thread_ts = event["thread_ts"] || ts

    case Tickets.get_by_slack_thread(ch, thread_ts) do
      {:ok, ticket} ->
        Tickets.customer_replied(ticket)

      _ ->
        unless event["thread_ts"] do
          Tickets.open_ticket(%{
            external_id: "slack_#{ch}_#{ts}",
            source: :slack,
            subject: String.slice(text || "", 0..120),
            body: text,
            slack_channel_id: ch,
            slack_thread_ts: ts
          })
        end
    end

    :ok
  end

  defp handle_reaction(%{"reaction" => emoji, "item" => %{"channel" => ch, "ts" => ts}}) do
    case Tickets.get_by_slack_thread(ch, ts) do
      {:ok, ticket} ->
        case emoji do
          "white_check_mark" ->
            Tickets.resolve_ticket(ticket, %{resolution_note: "Resolved via Slack reaction"})

          "eyes" ->
            Tickets.begin_triage(ticket)

          _ ->
            :ok
        end

      _ ->
        :ok
    end
  end

  defp handle_reaction(_), do: :ok

  defp handle_mention(%{"channel" => ch, "ts" => ts, "text" => text}) do
    Tickets.open_ticket(%{
      external_id: "slack_mention_#{ch}_#{ts}",
      source: :slack,
      subject: String.slice(text || "", 0..120),
      body: text,
      slack_channel_id: ch,
      slack_thread_ts: ts
    })

    :ok
  end
end
