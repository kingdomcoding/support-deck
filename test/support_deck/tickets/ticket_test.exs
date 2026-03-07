defmodule SupportDeck.Tickets.TicketTest do
  use SupportDeck.DataCase, async: true
  import SupportDeck.Factory

  test "creates a ticket" do
    ticket = create_ticket!()
    assert ticket.subject == "Test ticket"
    assert ticket.state == :new
  end

  test "transitions new -> triaging" do
    ticket = create_ticket!()
    {:ok, ticket} = SupportDeck.Tickets.begin_triage(ticket)
    assert ticket.state == :triaging
  end

  test "transitions new -> assigned" do
    ticket = create_ticket!()
    {:ok, ticket} = SupportDeck.Tickets.assign_ticket(ticket, "agent@test.com")
    assert ticket.state == :assigned
    assert ticket.assignee == "agent@test.com"
  end

  test "transitions assigned -> resolved -> closed" do
    ticket = create_ticket!()
    {:ok, ticket} = SupportDeck.Tickets.assign_ticket(ticket, "agent@test.com")
    {:ok, ticket} = SupportDeck.Tickets.resolve_ticket(ticket)
    assert ticket.state == :resolved
    {:ok, ticket} = SupportDeck.Tickets.close_ticket(ticket)
    assert ticket.state == :closed
  end

  test "escalation increments level" do
    ticket = create_ticket!()
    {:ok, ticket} = SupportDeck.Tickets.escalate_ticket(ticket)
    assert ticket.state == :escalated
    assert ticket.escalation_level == 1
  end

  test "lists open tickets" do
    create_ticket!()
    {:ok, tickets} = SupportDeck.Tickets.list_open_tickets()
    assert length(tickets) >= 1
  end

  test "SLA deadline is set based on tier and severity" do
    ticket = create_ticket!(%{subscription_tier: :enterprise, severity: :critical})
    assert ticket.sla_deadline != nil
  end
end
