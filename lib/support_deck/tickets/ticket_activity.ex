defmodule SupportDeck.Tickets.TicketActivity do
  use Ash.Resource,
    domain: SupportDeck.Tickets,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("ticket_activities")
    repo(SupportDeck.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute(:action, :string, allow_nil?: false, public?: true)
    attribute(:actor, :string, allow_nil?: false, public?: true)
    attribute(:from_value, :string, public?: true)
    attribute(:to_value, :string, public?: true)
    attribute(:metadata, :map, default: %{}, public?: true)

    create_timestamp(:inserted_at)
  end

  relationships do
    belongs_to :ticket, SupportDeck.Tickets.Ticket, allow_nil?: false
  end

  actions do
    defaults([:read])

    create :log do
      accept([:action, :actor, :from_value, :to_value, :metadata])
      argument(:ticket_id, :uuid, allow_nil?: false)
      change(manage_relationship(:ticket_id, :ticket, type: :append))
    end

    read :for_ticket do
      argument(:ticket_id, :uuid, allow_nil?: false)
      filter(expr(ticket_id == ^arg(:ticket_id)))
      prepare(fn query, _ctx -> Ash.Query.sort(query, inserted_at: :asc) end)
    end
  end
end
