defmodule SupportDeckWeb.IntegrationHealthLive do
  use SupportDeckWeb, :live_view

  @integrations [:front, :slack, :linear]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: schedule_refresh()

    {:ok,
     socket
     |> assign(:page_title, "Integrations")
     |> assign(:current_path, ~p"/integrations")
     |> load_statuses()}
  end

  @impl true
  def handle_event("refresh", _, socket) do
    {:noreply, load_statuses(socket)}
  end

  def handle_event("reset_breaker", %{"name" => name}, socket) do
    SupportDeck.Integrations.CircuitBreaker.reset(String.to_existing_atom(name))
    {:noreply, socket |> put_flash(:info, "#{name} breaker reset") |> load_statuses()}
  end

  @impl true
  def handle_info(:refresh, socket) do
    schedule_refresh()
    {:noreply, load_statuses(socket)}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  defp schedule_refresh, do: Process.send_after(self(), :refresh, 5_000)

  defp load_statuses(socket) do
    statuses =
      Enum.map(@integrations, fn name ->
        {name, SupportDeck.Integrations.CircuitBreaker.get_status(name)}
      end)

    assign(socket, :statuses, statuses)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto px-6 py-6">
      <.page_header
        title="Integrations"
        description="Circuit breaker health for Front, Slack, and Linear. Auto-trips after consecutive failures."
        patterns={["Circuit breaker", "GenServer", "ETS state"]}
      >
        <:actions>
          <button
            phx-click="refresh"
            class="px-3 py-1.5 text-sm border border-base-300 rounded-lg hover:bg-base-200"
          >
            Refresh
          </button>
          <.link
            navigate={~p"/settings"}
            class="px-3 py-1.5 text-sm bg-primary text-primary-content rounded-lg hover:bg-primary/90"
          >
            Credentials
          </.link>
        </:actions>
      </.page_header>

      <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
        <div
          :for={{name, status} <- @statuses}
          class="bg-base-100 rounded-lg border border-base-300 p-6"
        >
          <div class="flex items-center justify-between mb-4">
            <h3 class="text-lg font-semibold text-base-content capitalize">{name}</h3>
            <.state_indicator state={status.state} />
          </div>

          <dl class="space-y-2 text-sm">
            <div class="flex justify-between">
              <dt class="text-base-content/60">State</dt>
              <dd class="font-medium">{format_state(status.state)}</dd>
            </div>
            <div class="flex justify-between">
              <dt class="text-base-content/60">Failures</dt>
              <dd class="font-medium">{status.failures}</dd>
            </div>
            <div class="flex justify-between">
              <dt class="text-base-content/60">Last Failure</dt>
              <dd class="font-medium text-base-content/60">
                {format_last_failure(status.last_failure_at)}
              </dd>
            </div>
          </dl>
          <button
            :if={status.state != :closed}
            phx-click="reset_breaker"
            phx-value-name={name}
            class="mt-3 w-full px-3 py-1.5 text-sm bg-success/15 text-success rounded-lg hover:bg-success/25"
          >
            Reset Breaker
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp state_indicator(assigns) do
    color =
      case assigns.state do
        :closed -> "bg-success"
        :open -> "bg-error"
        :half_open -> "bg-warning"
        _ -> "bg-base-content/40"
      end

    assigns = assign(assigns, :color, color)

    ~H"""
    <span class={["inline-block w-3 h-3 rounded-full", @color]} />
    """
  end

  defp format_state(:closed), do: "Closed (Healthy)"
  defp format_state(:open), do: "Open (Failing)"
  defp format_state(:half_open), do: "Half-Open (Testing)"
  defp format_state(other), do: to_string(other)

  defp format_last_failure(nil), do: "Never"

  defp format_last_failure(mono_time) do
    elapsed_ms = System.monotonic_time(:millisecond) - mono_time
    elapsed_s = div(elapsed_ms, 1000)

    cond do
      elapsed_s < 60 -> "#{elapsed_s}s ago"
      elapsed_s < 3600 -> "#{div(elapsed_s, 60)}m ago"
      true -> "#{div(elapsed_s, 3600)}h ago"
    end
  end
end
