defmodule SupportDeck.AI.TriageResult do
  use Ash.Resource,
    domain: SupportDeck.AI,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "ai_triage_results"
    repo SupportDeck.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :predicted_category, :string, public?: true
    attribute :predicted_severity, :string, public?: true
    attribute :confidence, :float, public?: true
    attribute :is_repetitive, :boolean, default: false, public?: true
    attribute :draft_response, :string, public?: true
    attribute :human_accepted, :boolean, public?: true
    attribute :human_override_category, :string, public?: true
    attribute :response_used, :boolean, public?: true
    attribute :processing_time_ms, :integer, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :ticket, SupportDeck.Tickets.Ticket, allow_nil?: false
  end

  actions do
    defaults [:read]

    create :record do
      accept [
        :predicted_category, :predicted_severity, :confidence,
        :is_repetitive, :draft_response, :processing_time_ms
      ]
      argument :ticket_id, :uuid, allow_nil?: false
      change manage_relationship(:ticket_id, :ticket, type: :append)
    end

    update :record_human_feedback do
      accept [:human_accepted, :human_override_category, :response_used]
    end

    read :for_ticket do
      argument :ticket_id, :uuid, allow_nil?: false
      filter expr(ticket_id == ^arg(:ticket_id))
      prepare fn query, _ctx -> Ash.Query.sort(query, inserted_at: :desc) end
    end

    read :recent do
      argument :since, :utc_datetime, allow_nil?: false
      filter expr(inserted_at >= ^arg(:since))
    end
  end
end
