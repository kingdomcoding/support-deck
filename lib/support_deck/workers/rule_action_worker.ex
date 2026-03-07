defmodule SupportDeck.Workers.RuleActionWorker do
  use Oban.Worker, queue: :automations, max_attempts: 5

  alias SupportDeck.Tickets
  alias SupportDeck.Integrations

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"ticket_id" => id, "action_type" => type, "params" => params}}) do
    case Tickets.get_ticket(id) do
      {:error, _} -> {:cancel, "ticket #{id} not found"}
      {:ok, ticket} -> execute_action(ticket, type, params)
    end
  end

  defp execute_action(ticket, type, params) do

    case type do
      "slack_notify" ->
        channel = params["channel"] || "#support-escalations"
        msg = params["message"] || default_message(ticket)
        Integrations.Slack.Client.post_message(channel, msg, thread_ts: ticket.slack_thread_ts)

      "linear_create" ->
        case Integrations.Linear.Client.create_issue(%{
               title: "[Support] #{ticket.subject}",
               description:
                 "**Customer:** #{ticket.customer_email}\n**Severity:** #{ticket.severity}\n**Tier:** #{ticket.subscription_tier}\n\n---\n\n#{ticket.body}",
               team_id: params["team_id"],
               priority: params["priority"] || 4,
               label_ids: params["label_ids"]
             }) do
          {:ok, %{"id" => issue_id, "identifier" => identifier}} ->
            Tickets.link_linear_issue(ticket, issue_id)

            Integrations.Linear.Client.create_attachment(issue_id, %{
              title: "Support Ticket ##{ticket.id |> String.slice(0..7)}",
              subtitle: "#{ticket.severity} — #{ticket.subscription_tier}",
              url: "#{SupportDeckWeb.Endpoint.url()}/tickets/#{ticket.id}",
              metadata: %{ticket_id: ticket.id, source: to_string(ticket.source)}
            })

            Tickets.log_activity(
              ticket.id,
              "Created Linear issue #{identifier}",
              "system"
            )

          error ->
            error
        end

      "assign" ->
        Tickets.assign_ticket(ticket, params["to"] || "on_call")

      "escalate" ->
        Tickets.escalate_ticket(ticket)

      "set_severity" ->
        Tickets.apply_ai_results(ticket, %{severity: String.to_existing_atom(params["value"])})

      "set_product_area" ->
        Tickets.apply_ai_results(ticket, %{product_area: String.to_existing_atom(params["value"])})

      _ ->
        {:error, "unknown action type: #{type}"}
    end
  end

  defp default_message(ticket) do
    ":rotating_light: *#{ticket.subject}*\n#{ticket.severity} | #{ticket.product_area} | #{ticket.subscription_tier}"
  end
end
