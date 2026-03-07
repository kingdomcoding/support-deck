defmodule SupportDeck.Settings.Credential do
  @moduledoc """
  Encrypted credential storage for runtime integration configuration.

  Reviewers can paste API keys in the `/settings` LiveView page instead of
  configuring env vars. Values are encrypted at rest with AES-256-GCM
  (key derived from SECRET_KEY_BASE) and cached in ETS by the Resolver.

  Each credential is uniquely identified by {integration, key_name}:
    - {:front, :api_token}
    - {:front, :webhook_secret}
    - {:slack, :bot_token}
    - {:slack, :signing_secret}
    - {:linear, :api_key}
    - {:linear, :webhook_secret}
    - {:openai, :api_key}
    - {:anthropic, :api_key}
  """

  use Ash.Resource,
    domain: SupportDeck.Settings,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("credentials")
    repo(SupportDeck.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :integration, :atom do
      constraints(one_of: [:front, :slack, :linear, :openai, :anthropic])
      allow_nil?(false)
      public?(true)
    end

    attribute :key_name, :atom do
      constraints(
        one_of: [
          :api_token,
          :api_key,
          :bot_token,
          :webhook_secret,
          :signing_secret
        ]
      )

      allow_nil?(false)
      public?(true)
    end

    attribute(:encrypted_value, :string, allow_nil?: false)

    attribute(:value_hint, :string, public?: true)

    attribute :last_test_status, :atom do
      constraints(one_of: [:untested, :ok, :error])
      default(:untested)
      public?(true)
    end

    attribute(:last_test_message, :string, public?: true)
    attribute(:last_tested_at, :utc_datetime, public?: true)

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  identities do
    identity(:unique_integration_key, [:integration, :key_name])
  end

  actions do
    defaults([:read, :destroy])

    create :store do
      accept([:integration, :key_name])

      argument(:plaintext_value, :string, allow_nil?: false, sensitive?: true)

      change(fn changeset, _context ->
        plaintext = Ash.Changeset.get_argument(changeset, :plaintext_value)
        encrypted = SupportDeck.Settings.Vault.encrypt!(plaintext)
        hint = String.slice(plaintext, -4..-1//1)

        changeset
        |> Ash.Changeset.force_change_attribute(:encrypted_value, encrypted)
        |> Ash.Changeset.force_change_attribute(:value_hint, "•••• #{hint}")
        |> Ash.Changeset.force_change_attribute(:last_test_status, :untested)
      end)

      upsert?(true)
      upsert_identity(:unique_integration_key)
      upsert_fields([:encrypted_value, :value_hint, :last_test_status, :updated_at])
    end

    update :record_test_result do
      accept([])

      argument(:status, :atom, allow_nil?: false, constraints: [one_of: [:ok, :error]])
      argument(:message, :string)

      change(set_attribute(:last_test_status, arg(:status)))
      change(set_attribute(:last_test_message, arg(:message)))
      change(set_attribute(:last_tested_at, &DateTime.utc_now/0))
    end

    read :for_integration do
      argument(:integration, :atom, allow_nil?: false)

      filter(expr(integration == ^arg(:integration)))
    end

    read :all_credentials do
      description("All stored credentials (encrypted values excluded from serialization).")
    end
  end
end
