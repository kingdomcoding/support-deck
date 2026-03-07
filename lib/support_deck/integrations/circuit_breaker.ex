defmodule SupportDeck.Integrations.CircuitBreaker do
  @moduledoc """
  ETS-backed circuit breaker per integration.

  States:
    :closed    - healthy, all calls pass through
    :open      - failing, calls rejected for cooldown_ms
    :half_open - testing, one call allowed to probe recovery

  After `failure_threshold` consecutive failures the breaker opens.
  After `cooldown_ms` in :open it transitions to :half_open.
  Success in :half_open resets to :closed. Failure reopens.
  """

  use GenServer
  require Logger

  @default_failure_threshold 5
  @default_cooldown_ms 30_000

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: process_name(name))
  end

  defp process_name(name), do: :"#{__MODULE__}.#{name}"

  def call(breaker_name, fun) do
    case get_state(breaker_name) do
      :open ->
        if cooldown_expired?(breaker_name) do
          set_state(breaker_name, :half_open)
          execute_and_record(breaker_name, fun)
        else
          {:error, :circuit_open}
        end

      state when state in [:closed, :half_open] ->
        execute_and_record(breaker_name, fun)
    end
  end

  def get_status(breaker_name) do
    case :ets.lookup(:circuit_breakers, breaker_name) do
      [{_, state, failures, last_failure_at, _opts}] ->
        %{state: state, failures: failures, last_failure_at: last_failure_at}

      [] ->
        %{state: :closed, failures: 0, last_failure_at: nil}
    end
  end

  def reset(breaker_name) do
    :ets.update_element(:circuit_breakers, breaker_name, [{2, :closed}, {3, 0}, {4, nil}])
    :ok
  end

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    threshold = Keyword.get(opts, :failure_threshold, @default_failure_threshold)
    cooldown = Keyword.get(opts, :cooldown_ms, @default_cooldown_ms)

    if :ets.whereis(:circuit_breakers) == :undefined do
      :ets.new(:circuit_breakers, [:named_table, :public, :set])
    end

    :ets.insert(
      :circuit_breakers,
      {name, :closed, 0, nil, %{threshold: threshold, cooldown: cooldown}}
    )

    {:ok, %{name: name}}
  end

  defp execute_and_record(name, fun) do
    case fun.() do
      {:ok, _} = ok ->
        record_success(name)
        ok

      {:error, _} = err ->
        record_failure(name)
        err
    end
  end

  defp record_success(name) do
    set_state(name, :closed)
    :ets.update_element(:circuit_breakers, name, {3, 0})
  end

  defp record_failure(name) do
    [{_, _, failures, _, opts}] = :ets.lookup(:circuit_breakers, name)
    new_failures = failures + 1
    now = System.monotonic_time(:millisecond)
    :ets.update_element(:circuit_breakers, name, [{3, new_failures}, {4, now}])

    if new_failures >= opts.threshold do
      set_state(name, :open)
      Logger.warning("circuit_breaker.opened", integration: name, failures: new_failures)
    end
  end

  defp get_state(name) do
    case :ets.lookup(:circuit_breakers, name) do
      [{_, state, _, _, _}] -> state
      [] -> :closed
    end
  end

  defp set_state(name, state) do
    :ets.update_element(:circuit_breakers, name, {2, state})
  end

  defp cooldown_expired?(name) do
    [{_, _, _, last_at, opts}] = :ets.lookup(:circuit_breakers, name)
    last_at == nil or System.monotonic_time(:millisecond) - last_at >= opts.cooldown
  end
end
