defmodule SupportDeck.Workers.FrontWebhookWorker do
  use Oban.Worker, queue: :webhooks, max_attempts: 5

  alias SupportDeck.Tickets

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"payload" => payload}}) do
    case payload["type"] do
      "inbound" ->
        handle_inbound(payload)

      "outbound_reply" ->
        handle_reply(payload)

      "assign" ->
        handle_assignment(payload)

      "tag" ->
        handle_tag(payload)

      _ ->
        Logger.info("front.webhook.ignored", type: payload["type"])
        :ok
    end
  end

  defp handle_inbound(payload) do
    conversation = payload["conversation"] || %{}
    message = get_in(payload, ["target", "data"]) || %{}

    attrs = %{
      external_id: conversation["id"],
      source: :front,
      subject: conversation["subject"] || message["subject"] || "Untitled",
      body: message["body"],
      front_conversation_id: conversation["id"],
      customer_email: get_in(message, ["author", "email"]),
      subscription_tier: infer_tier(conversation["tags"] || [])
    }

    case Tickets.upsert_ticket(attrs) do
      {:ok, ticket} ->
        if ticket.state == :new do
          %{"ticket_id" => ticket.id}
          |> SupportDeck.Workers.AITriageWorker.new()
          |> Oban.insert()
        end

        SupportDeck.Tickets.RuleEngine.evaluate(ticket, :ticket_created)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_reply(payload) do
    conv_id = get_in(payload, ["conversation", "id"])

    case Tickets.get_by_source(:front, conv_id) do
      {:ok, ticket} -> Tickets.wait_on_customer(ticket)
      _ -> :ok
    end

    :ok
  end

  defp handle_assignment(payload) do
    conv_id = get_in(payload, ["conversation", "id"])
    assignee_email = get_in(payload, ["target", "data", "email"])

    case Tickets.get_by_source(:front, conv_id) do
      {:ok, ticket} -> Tickets.assign_ticket(ticket, %{assignee: assignee_email})
      _ -> :ok
    end

    :ok
  end

  defp handle_tag(payload) do
    conv_id = get_in(payload, ["conversation", "id"])
    tag_name = get_in(payload, ["target", "data", "name"])

    if tag_name in ["enterprise", "team", "pro", "free"] do
      case Tickets.get_by_source(:front, conv_id) do
        {:ok, ticket} ->
          new_tier = String.to_existing_atom(tag_name)
          Tickets.apply_ai_results(ticket, %{subscription_tier: new_tier})

        _ ->
          :ok
      end
    end

    :ok
  end

  defp infer_tier(tags) do
    names = Enum.map(tags, & &1["name"])

    cond do
      "enterprise" in names -> :enterprise
      "team" in names -> :team
      "pro" in names -> :pro
      true -> :free
    end
  end
end
