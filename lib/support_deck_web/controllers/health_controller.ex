defmodule SupportDeckWeb.HealthController do
  use SupportDeckWeb, :controller

  def index(conn, _params) do
    health = SupportDeck.Observability.Health.check()
    json(conn, health)
  end
end
