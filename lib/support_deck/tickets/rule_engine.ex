defmodule SupportDeck.Tickets.RuleEngine do
  require Logger

  def evaluate(ticket, trigger) do
    rules = SupportDeck.Tickets.list_rules_for_trigger!(trigger)

    Enum.each(rules, fn rule ->
      if matches?(ticket, rule.conditions) do
        Logger.info("rule.matched", rule: rule.name, ticket: ticket.id)
        execute_actions(ticket, rule.actions_list)
      end
    end)
  end

  def matches?(ticket, %{"all" => conditions}) do
    Enum.all?(conditions, &evaluate_condition(ticket, &1))
  end

  def matches?(ticket, %{"any" => conditions}) do
    Enum.any?(conditions, &evaluate_condition(ticket, &1))
  end

  def matches?(_ticket, _), do: true

  defp evaluate_condition(ticket, %{"field" => field, "op" => op, "value" => value}) do
    ticket_val = get_field(ticket, field)

    case op do
      "eq"       -> to_string(ticket_val) == value
      "neq"      -> to_string(ticket_val) != value
      "contains" -> is_binary(ticket_val) and String.contains?(ticket_val, value)
      "in"       -> to_string(ticket_val) in List.wrap(value)
      "gt"       -> is_number(ticket_val) and ticket_val > value
      _          -> false
    end
  end

  defp get_field(ticket, "severity"), do: ticket.severity
  defp get_field(ticket, "status"), do: ticket.status
  defp get_field(ticket, "product_area"), do: ticket.product_area
  defp get_field(ticket, "subscription_tier"), do: ticket.subscription_tier
  defp get_field(ticket, "assignee"), do: ticket.assignee
  defp get_field(ticket, "escalation_level"), do: ticket.escalation_level
  defp get_field(ticket, "subject"), do: ticket.subject
  defp get_field(_ticket, _), do: nil

  defp execute_actions(ticket, actions) do
    Enum.each(actions, fn action ->
      %{
        "ticket_id" => ticket.id,
        "action_type" => action["type"],
        "params" => action["params"] || %{}
      }
      |> SupportDeck.Workers.RuleActionWorker.new()
      |> Oban.insert()
    end)
  end
end
