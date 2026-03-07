defmodule SupportDeck.Observability.Health do
  def check do
    %{
      status: "ok",
      checks: %{
        database: check_database(),
        circuit_breakers: check_circuit_breakers()
      },
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
