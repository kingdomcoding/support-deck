defmodule SupportDeck.Factory do
  def ticket_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        external_id: "test-#{System.unique_integer([:positive])}",
        source: :manual,
        subject: "Test ticket",
        body: "Test body",
        severity: :low,
        subscription_tier: :free,
        customer_email: "test@example.com"
      },
      overrides
    )
  end

  def create_ticket!(overrides \\ %{}) do
    attrs = ticket_attrs(overrides)
    {:ok, ticket} = SupportDeck.Tickets.open_ticket(attrs.subject, Map.delete(attrs, :subject))
    ticket
  end

  def rule_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        name: "Test Rule #{System.unique_integer([:positive])}",
        trigger: :ticket_created,
        conditions: %{"all" => []},
        actions_list: [%{"type" => "slack_notify", "params" => %{"channel" => "#test"}}],
        enabled: true,
        priority: 0
      },
      overrides
    )
  end

  def create_rule!(overrides \\ %{}) do
    {:ok, rule} = SupportDeck.Tickets.create_rule(rule_attrs(overrides))
    rule
  end

  def policy_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        name: "test-policy",
        subscription_tier: :free,
        severity: :low,
        first_response_minutes: 480,
        resolution_minutes: 1920,
        escalation_thresholds: %{"L1" => 240, "L2" => 480},
        enabled: true
      },
      overrides
    )
  end

  def knowledge_doc_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        content: "Test knowledge doc content",
        content_type: :doc,
        source_url: "https://example.com/doc"
      },
      overrides
    )
  end
end
