defmodule SupportDeck.SLADomain do
  use Ash.Domain

  resources do
    resource SupportDeck.SLA.Policy do
      define(:create_policy, action: :create)
      define(:update_policy, action: :update)
      define(:delete_policy, action: :destroy)

      define(:get_policy,
        action: :for_tier_and_severity,
        args: [:subscription_tier, :severity],
        get?: true
      )

      define(:list_all_policies, action: :all_policies)
    end
  end

  defdelegate deadline_minutes(tier, severity), to: SupportDeck.SLA.Defaults
end
