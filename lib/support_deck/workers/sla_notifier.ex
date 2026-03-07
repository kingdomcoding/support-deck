defmodule SupportDeck.Workers.SLANotifier do
  use Oban.Worker, queue: :automations, max_attempts: 3

  alias SupportDeck.Integrations.Slack

  def enqueue(ticket) do
    %{"ticket_id" => ticket.id, "level" => ticket.escalation_level}
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"ticket_id" => ticket_id, "level" => level}}) do
    {:ok, ticket} = SupportDeck.Tickets.get_ticket(ticket_id)
    {channel, mention} = escalation_target(ticket.subscription_tier, level)

    message = """
    :rotating_light: *SLA Breach — Level #{level}*
    #{mention}
    *Subject:* #{ticket.subject}
    *Severity:* #{ticket.severity} | *Tier:* #{ticket.subscription_tier}
    *Customer:* #{ticket.customer_email || "unknown"}
    """

    case Slack.Client.post_message(channel, message, thread_ts: ticket.slack_thread_ts) do
      {:ok, _} -> :ok
      {:error, {:rate_limited, seconds}} -> {:snooze, seconds}
      {:error, reason} -> {:error, reason}
    end
  end

  defp escalation_target(tier, level) do
    channel = "#support-escalations"
    mention = case {tier, level} do
      {:enterprise, 1} -> "cc: support engineers"
      {:enterprise, 2} -> "cc: @on-shift specialist"
      {:enterprise, 3} -> "cc: <!subteam^support-group>"
      {:enterprise, _} -> "cc: @head-of-success"
      {_, 1} -> ""
      {_, 2} -> "cc: @on-shift specialist"
      {_, _} -> "cc: <!subteam^support-group>"
    end
    {channel, mention}
  end
end
