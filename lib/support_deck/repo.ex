defmodule SupportDeck.Repo do
  use AshPostgres.Repo,
    otp_app: :support_deck

  def installed_extensions do
    ["uuid-ossp", "citext"]
  end
end
