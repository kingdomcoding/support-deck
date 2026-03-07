defmodule SupportDeck.Integrations.WebhookEvent do
  use Ash.Resource,
    domain: SupportDeck.IntegrationsDomain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "webhook_events"
    repo SupportDeck.Repo

    custom_indexes do
      index [:source, :external_id], unique: true
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :source, :atom do
      constraints one_of: [:front, :slack, :linear]
      allow_nil? false
      public? true
    end

    attribute :external_id, :string, allow_nil?: false, public?: true
    attribute :event_type, :string, allow_nil?: false, public?: true
    attribute :payload, :map, allow_nil?: false, public?: true
    attribute :processed_at, :utc_datetime, public?: true

    create_timestamp :inserted_at
  end

  identities do
    identity :unique_source_event, [:source, :external_id]
  end

  actions do
    defaults [:read]

    create :store do
      accept [:source, :external_id, :event_type, :payload]
    end

    update :mark_processed do
      accept []
      change set_attribute(:processed_at, &DateTime.utc_now/0)
    end
  end
end
