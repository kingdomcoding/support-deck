defmodule SupportDeck.Workers.AITriageWorkerTest do
  use SupportDeck.DataCase, async: true
  import SupportDeck.Factory

  test "performs triage on a ticket" do
    ticket =
      create_ticket!(%{subject: "Database connection error", body: "Cannot connect to postgres"})

    assert :ok ==
             SupportDeck.Workers.AITriageWorker.perform(%Oban.Job{
               args: %{"ticket_id" => ticket.id}
             })

    {:ok, results} = SupportDeck.AI.list_triage_for_ticket(ticket.id)
    assert length(results) >= 1
  end
end
