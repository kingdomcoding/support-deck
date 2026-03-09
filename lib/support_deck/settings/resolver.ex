defmodule SupportDeck.Settings.Resolver do
  @moduledoc """
  Credential resolution with ETS caching.

  Resolution order:
    1. ETS cache (populated from DB on boot and after saves)
    2. Environment variables (Application.get_env)

  This GenServer loads all credentials from the DB on startup, decrypts them,
  and stores plaintext values in an ETS table for fast reads. Integration
  clients call `Resolver.get/2` instead of `Application.get_env` directly.
  """

  use GenServer

  require Logger

  @table :credential_cache

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Resolve a credential value. Checks ETS cache first, falls back to env var.
  """
  def get(integration, key_name) do
    case :ets.lookup(@table, {integration, key_name}) do
      [{_, value}] -> value
      [] -> get_from_env(integration, key_name)
    end
  end

  def configured?(integration, key_name) do
    get(integration, key_name) != nil
  end

  def integration_status(integration) do
    required_keys = required_keys_for(integration)

    statuses =
      Enum.map(required_keys, fn key ->
        {key, configured?(integration, key)}
      end)

    all_configured = Enum.all?(statuses, fn {_, v} -> v end)
    any_configured = Enum.any?(statuses, fn {_, v} -> v end)

    cond do
      all_configured -> :configured
      any_configured -> :partial
      true -> :not_configured
    end
  end

  def reload_credential(integration, key_name) do
    GenServer.cast(__MODULE__, {:reload, integration, key_name})
  end

  def invalidate_credential(integration, key_name) do
    :ets.delete(@table, {integration, key_name})
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    load_all_credentials()
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:reload, integration, key_name}, state) do
    case SupportDeck.Settings.list_for_integration(integration) do
      {:ok, creds} ->
        case Enum.find(creds, &(&1.key_name == key_name)) do
          nil ->
            :ets.delete(@table, {integration, key_name})

          cred ->
            plaintext = SupportDeck.Settings.Vault.decrypt!(cred.encrypted_value)
            :ets.insert(@table, {{integration, key_name}, plaintext})
        end

      _ ->
        :ok
    end

    {:noreply, state}
  end

  defp load_all_credentials do
    case SupportDeck.Settings.list_all_credentials() do
      {:ok, creds} ->
        Enum.each(creds, fn cred ->
          try do
            plaintext = SupportDeck.Settings.Vault.decrypt!(cred.encrypted_value)
            :ets.insert(@table, {{cred.integration, cred.key_name}, plaintext})
          rescue
            e ->
              Logger.warning(
                "Failed to decrypt credential #{cred.integration}/#{cred.key_name}: #{inspect(e)}"
              )
          end
        end)

        Logger.info("credential_resolver.loaded", count: length(creds))

      {:error, reason} ->
        Logger.warning("credential_resolver.load_failed", reason: inspect(reason))
    end
  end

  defp get_from_env(integration, key_name) do
    case Application.get_env(:support_deck, :integrations) do
      nil ->
        nil

      integrations ->
        case Keyword.get(integrations, integration) do
          nil -> nil
          config -> Keyword.get(config, key_name)
        end
    end
  end

  defp required_keys_for(:front), do: [:api_token, :webhook_secret]
  defp required_keys_for(:slack), do: [:bot_token, :signing_secret]
  defp required_keys_for(:linear), do: [:api_key, :webhook_secret]
  defp required_keys_for(:openai), do: [:api_key]
  defp required_keys_for(_), do: []
end
