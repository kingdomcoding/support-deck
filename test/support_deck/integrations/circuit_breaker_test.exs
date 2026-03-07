defmodule SupportDeck.Integrations.CircuitBreakerTest do
  use ExUnit.Case

  setup do
    SupportDeck.Integrations.CircuitBreaker.reset(:front)
    :ok
  end

  test "starts in closed state" do
    status = SupportDeck.Integrations.CircuitBreaker.get_status(:front)
    assert status.state == :closed
  end

  test "passes through successful calls" do
    result = SupportDeck.Integrations.CircuitBreaker.call(:front, fn -> {:ok, "success"} end)
    assert result == {:ok, "success"}
  end

  test "records failures and opens after threshold" do
    for _ <- 1..5 do
      SupportDeck.Integrations.CircuitBreaker.call(:front, fn -> {:error, "fail"} end)
    end
    status = SupportDeck.Integrations.CircuitBreaker.get_status(:front)
    assert status.state == :open
  end

  test "rejects calls when open" do
    for _ <- 1..5 do
      SupportDeck.Integrations.CircuitBreaker.call(:front, fn -> {:error, "fail"} end)
    end
    result = SupportDeck.Integrations.CircuitBreaker.call(:front, fn -> {:ok, "test"} end)
    assert result == {:error, :circuit_open}
  end

  test "reset returns to closed" do
    for _ <- 1..5 do
      SupportDeck.Integrations.CircuitBreaker.call(:front, fn -> {:error, "fail"} end)
    end
    SupportDeck.Integrations.CircuitBreaker.reset(:front)
    status = SupportDeck.Integrations.CircuitBreaker.get_status(:front)
    assert status.state == :closed
  end
end
