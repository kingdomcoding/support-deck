defmodule SupportDeck.Tickets.RuleEngineTest do
  use SupportDeck.DataCase, async: true
  import SupportDeck.Factory

  test "matches rule with matching conditions" do
    create_rule!(%{
      trigger: :ticket_created,
      conditions: %{"all" => [%{"field" => "severity", "op" => "eq", "value" => "critical"}]},
      actions_list: [%{"type" => "escalate"}]
    })

    ticket = create_ticket!(%{severity: :critical})
    assert SupportDeck.Tickets.RuleEngine.matches?(ticket, %{"all" => [%{"field" => "severity", "op" => "eq", "value" => "critical"}]})
  end

  test "skips non-matching conditions" do
    ticket = create_ticket!(%{severity: :low})
    refute SupportDeck.Tickets.RuleEngine.matches?(ticket, %{"all" => [%{"field" => "severity", "op" => "eq", "value" => "critical"}]})
  end
end
