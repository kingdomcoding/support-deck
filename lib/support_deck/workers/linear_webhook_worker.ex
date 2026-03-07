defmodule SupportDeck.Workers.LinearWebhookWorker do
  use Oban.Worker, queue: :webhooks, max_attempts: 5

  alias SupportDeck.Tickets

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"payload" => %{"type" => "Issue", "action" => action} = payload}}) do
    issue_id = get_in(payload, ["data", "id"])

    case Tickets.get_by_linear_issue(issue_id) do
      {:ok, ticket} ->
        handle_issue_event(action, payload, ticket)

      _ ->
        Logger.info("linear.webhook.no_linked_ticket", issue_id: issue_id)
    end

    :ok
  end

  def perform(%Oban.Job{
        args: %{"payload" => %{"type" => "Comment", "action" => "create"} = payload}
      }) do
    issue_id = get_in(payload, ["data", "issueId"])

    case Tickets.get_by_linear_issue(issue_id) do
      {:ok, ticket} ->
        actor_name = get_in(payload, ["actor", "name"]) || "Linear user"
        comment_body = get_in(payload, ["data", "body"]) || ""

        Tickets.log_activity(
          ticket.id,
          "[Linear] #{actor_name}: #{comment_body}",
          "linear_sync"
        )

      _ ->
        :ok
    end

    :ok
  end

  def perform(_job), do: :ok

  defp handle_issue_event("update", payload, ticket) do
    state_name = get_in(payload, ["data", "state", "name"])
    state_type = get_in(payload, ["data", "state", "type"])

    case state_type do
      "completed" ->
        Tickets.resolve_ticket(ticket)

        Tickets.log_activity(
          ticket.id,
          "Resolved via Linear issue #{get_in(payload, ["data", "identifier"])}",
          "linear_sync"
        )

      "canceled" ->
        Tickets.resolve_ticket(ticket)

        Tickets.log_activity(
          ticket.id,
          "Linear issue #{get_in(payload, ["data", "identifier"])} was canceled",
          "linear_sync"
        )

      _ ->
        Logger.debug("linear.issue.state_change", state: state_name, ticket_id: ticket.id)
    end
  end

  defp handle_issue_event(_action, _payload, _ticket), do: :ok
end
