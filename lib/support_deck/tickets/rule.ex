defmodule SupportDeck.Tickets.Rule do
  use Ash.Resource,
    domain: SupportDeck.Tickets,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "rules"
    repo SupportDeck.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, allow_nil?: false, public?: true
    attribute :description, :string, public?: true

    attribute :trigger, :atom do
      constraints one_of: [:ticket_created, :ticket_updated, :sla_breach, :customer_reply, :escalation]
      allow_nil? false
      public? true
    end

    attribute :conditions, :map, default: %{"all" => []}, allow_nil?: false, public?: true

    attribute :actions_list, {:array, :map}, default: [], allow_nil?: false, public?: true

    attribute :enabled, :boolean, default: true, public?: true
    attribute :priority, :integer, default: 0, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :description, :trigger, :conditions, :actions_list, :enabled, :priority]
    end

    update :update do
      accept [:name, :description, :trigger, :conditions, :actions_list, :enabled, :priority]
    end

    read :enabled_for_trigger do
      argument :trigger, :atom, allow_nil?: false

      filter expr(enabled == true and trigger == ^arg(:trigger))

      prepare fn query, _ctx ->
        Ash.Query.sort(query, priority: :desc)
      end
    end

    read :all_rules do
      prepare fn query, _ctx ->
        Ash.Query.sort(query, priority: :desc)
      end
    end
  end
end
