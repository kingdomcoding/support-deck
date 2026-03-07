defmodule SupportDeck.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SupportDeckWeb.Telemetry,
      SupportDeck.Repo,
      {DNSCluster, query: Application.get_env(:support_deck, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: SupportDeck.PubSub},
      {Oban, Application.fetch_env!(:support_deck, Oban)},
      SupportDeck.Settings.Resolver,
      Supervisor.child_spec({SupportDeck.Integrations.CircuitBreaker, name: :front}, id: :cb_front),
      Supervisor.child_spec({SupportDeck.Integrations.CircuitBreaker, name: :slack}, id: :cb_slack),
      Supervisor.child_spec({SupportDeck.Integrations.CircuitBreaker, name: :linear}, id: :cb_linear),
      SupportDeckWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: SupportDeck.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    SupportDeckWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
