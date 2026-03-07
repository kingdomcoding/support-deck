defmodule SupportDeck.SLA.Policy do
  use Ash.Resource,
    domain: SupportDeck.SLADomain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("sla_policies")
    repo(SupportDeck.Repo)

    custom_indexes do
      index([:subscription_tier, :severity], unique: true)
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute(:name, :string, allow_nil?: false, public?: true)

    attribute :subscription_tier, :atom do
      constraints(one_of: [:free, :pro, :team, :enterprise])
      allow_nil?(false)
      public?(true)
    end

    attribute :severity, :atom do
      constraints(one_of: [:low, :medium, :high, :critical])
      allow_nil?(false)
      public?(true)
    end

    attribute(:first_response_minutes, :integer, allow_nil?: false, public?: true)
    attribute(:resolution_minutes, :integer, public?: true)

    attribute(:escalation_thresholds, :map, allow_nil?: false, public?: true)

    attribute(:enabled, :boolean, default: true, public?: true)

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  identities do
    identity(:unique_tier_severity, [:subscription_tier, :severity])
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([
        :name,
        :subscription_tier,
        :severity,
        :first_response_minutes,
        :resolution_minutes,
        :escalation_thresholds,
        :enabled
      ])
    end

    update :update do
      accept([
        :name,
        :first_response_minutes,
        :resolution_minutes,
        :escalation_thresholds,
        :enabled
      ])
    end

    read :for_tier_and_severity do
      argument(:subscription_tier, :atom, allow_nil?: false)
      argument(:severity, :atom, allow_nil?: false)

      filter(
        expr(
          subscription_tier == ^arg(:subscription_tier) and
            severity == ^arg(:severity) and
            enabled == true
        )
      )
    end

    read :all_policies do
      prepare(fn query, _ctx ->
        Ash.Query.sort(query, [:subscription_tier, :severity])
      end)
    end
  end
end
