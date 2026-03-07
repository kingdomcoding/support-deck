import Config

if System.get_env("PHX_SERVER") do
  config :support_deck, SupportDeckWeb.Endpoint, server: true
end

config :support_deck, SupportDeckWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4500"))]

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise "DATABASE_URL not set"

  config :support_deck, SupportDeck.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "SECRET_KEY_BASE not set"

  host = System.get_env("PHX_HOST") || "localhost"
  port = String.to_integer(System.get_env("PORT") || "4500")

  config :support_deck, SupportDeckWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0}, port: port],
    check_origin: [
      "https://#{host}",
      "https://www.#{host}"
    ],
    secret_key_base: secret_key_base
end
