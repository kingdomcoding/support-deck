defmodule SupportDeckWeb.Router do
  use SupportDeckWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SupportDeckWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :webhooks do
    plug :accepts, ["json"]
    plug SupportDeckWeb.Plugs.CacheRawBody
  end

  scope "/webhooks", SupportDeckWeb do
    pipe_through :webhooks

    post "/:source", WebhookController, :receive
  end

  scope "/api", SupportDeckWeb do
    pipe_through :api

    get "/health", HealthController, :index
  end

  live_session :dashboard,
    layout: {SupportDeckWeb.Layouts, :app},
    on_mount: [{SupportDeckWeb.Hooks.SidebarCounts, :default}] do
    scope "/", SupportDeckWeb do
      pipe_through :browser

      live "/", OverviewLive, :index
      live "/tour", GuidedTourLive, :index
      live "/tickets", TicketQueueLive, :index
      live "/tickets/:id", TicketDetailLive, :show
      live "/sla", SLADashboardLive, :index
      live "/sla/policies", SLAPoliciesLive, :index
      live "/integrations", IntegrationHealthLive, :index
      live "/ai", AIDashboardLive, :index
      live "/rules", RulesLive, :index
      live "/rules/new", RulesLive, :new
      live "/rules/:id/edit", RulesLive, :edit
      live "/knowledge", KnowledgeLive, :index

      live "/settings", SettingsLive, :index
    end
  end
end
