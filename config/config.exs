# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :support_deck,
  ecto_repos: [SupportDeck.Repo],
  generators: [timestamp_type: :utc_datetime]

config :support_deck, SupportDeckWeb.Endpoint,
  url: [host: "localhost"],
  http: [port: 4500],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: SupportDeckWeb.ErrorHTML, json: SupportDeckWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: SupportDeck.PubSub,
  live_view: [signing_salt: "K0yYnq4I"]

config :support_deck,
  ash_domains: [
    SupportDeck.Tickets,
    SupportDeck.SLADomain,
    SupportDeck.IntegrationsDomain,
    SupportDeck.AI,
    SupportDeck.Settings
  ]

config :support_deck, Oban,
  engine: Oban.Engines.Basic,
  repo: SupportDeck.Repo,
  queues: [
    webhooks: 10,
    automations: 5,
    ai_triage: 3,
    sla: 2,
    sync: 2,
    maintenance: 2
  ],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7}
  ]

config :support_deck, :integrations,
  front: [
    api_token: System.get_env("FRONT_API_TOKEN"),
    webhook_secret: System.get_env("FRONT_WEBHOOK_SECRET")
  ],
  slack: [
    bot_token: System.get_env("SLACK_BOT_TOKEN"),
    signing_secret: System.get_env("SLACK_SIGNING_SECRET")
  ],
  linear: [
    api_key: System.get_env("LINEAR_API_KEY"),
    webhook_secret: System.get_env("LINEAR_WEBHOOK_SECRET")
  ]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  support_deck: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  support_deck: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
