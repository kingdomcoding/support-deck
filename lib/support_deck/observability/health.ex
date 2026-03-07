defmodule SupportDeck.Observability.Health do
  def check do
    db = check_database()
    cbs = check_circuit_breakers()

    any_cb_open = Enum.any?(cbs, fn {_, s} -> s.state == :open end)

    overall =
      cond do
        db.status == "error" -> "error"
        any_cb_open -> "degraded"
        true -> "ok"
      end

    %{
      status: overall,
      checks: %{database: db, circuit_breakers: cbs},
      timestamp: DateTime.utc_now()
    }
  end

  defp check_database do
    case SupportDeck.Repo.query("SELECT 1") do
      {:ok, _} -> %{status: "ok"}
      {:error, err} -> %{status: "error", message: inspect(err)}
    end
  end

  defp check_circuit_breakers do
    %{
      front: SupportDeck.Integrations.CircuitBreaker.get_status(:front),
      slack: SupportDeck.Integrations.CircuitBreaker.get_status(:slack),
      linear: SupportDeck.Integrations.CircuitBreaker.get_status(:linear)
    }
  end
end
