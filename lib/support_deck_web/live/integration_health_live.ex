defmodule SupportDeckWeb.IntegrationHealthLive do
  use SupportDeckWeb, :live_view

  @integrations [:front, :slack, :linear]

  @impl true
  def mount(_params, _session, socket) do
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
      <.tech_banner patterns={["Circuit breaker", "GenServer", "ETS state"]} />

      <div class="flex items-center justify-between mb-6">
        <h1 class="text-2xl font-bold text-gray-900">Integration Health</h1>
        <div class="flex gap-3">
          <button
            phx-click="refresh"
            class="px-3 py-2 text-sm border border-gray-300 rounded-lg hover:bg-gray-50"
          >
            Refresh
          </button>
          <a
            href={~p"/settings"}
            class="px-3 py-2 text-sm bg-indigo-600 text-white rounded-lg hover:bg-indigo-700"
          >
            Configure Credentials
          </a>
        </div>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
        <div :for={{name, status} <- @statuses} class="bg-white rounded-lg border border-gray-200 p-6">
          <div class="flex items-center justify-between mb-4">
            <h3 class="text-lg font-semibold text-gray-900 capitalize">{name}</h3>
            <.state_indicator state={status.state} />
          </div>

          <dl class="space-y-2 text-sm">
            <div class="flex justify-between">
              <dt class="text-gray-500">State</dt>
              <dd class="font-medium">{format_state(status.state)}</dd>
            </div>
            <div class="flex justify-between">
              <dt class="text-gray-500">Failures</dt>
              <dd class="font-medium">{status.failures}</dd>
            </div>
            <div class="flex justify-between">
              <dt class="text-gray-500">Last Failure</dt>
              <dd class="font-medium text-gray-600">{format_last_failure(status.last_failure_at)}</dd>
            </div>
          </dl>
        </div>
      </div>
    </div>
    """
  end

  defp state_indicator(assigns) do
    color =
      case assigns.state do
        :closed -> "bg-green-500"
        :open -> "bg-red-500"
        :half_open -> "bg-yellow-500"
        _ -> "bg-gray-400"
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
  defp format_last_failure(_mono_time), do: "Recent"
end
