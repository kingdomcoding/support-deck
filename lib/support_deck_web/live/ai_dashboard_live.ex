defmodule SupportDeckWeb.AIDashboardLive do
  use SupportDeckWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    since = DateTime.add(DateTime.utc_now(), -7 * 24 * 3600)

    results = case SupportDeck.AI.list_recent_triage(since) do
      {:ok, r} -> r
      _ -> []
    end

    {:ok,
     socket
     |> assign(:page_title, "AI Dashboard")
     |> assign(:current_path, ~p"/ai")
     |> assign(:results, results)
     |> assign(:stats, compute_stats(results))}
  end

  @impl true
  def handle_event("refresh", _, socket) do
    since = DateTime.add(DateTime.utc_now(), -7 * 24 * 3600)

    results = case SupportDeck.AI.list_recent_triage(since) do
      {:ok, r} -> r
      _ -> []
    end

    {:noreply,
     socket
     |> assign(:results, results)
     |> assign(:stats, compute_stats(results))}
  end

  defp compute_stats(results) do
    total = length(results)

    avg_confidence =
      if total > 0 do
        results
        |> Enum.filter(& &1.confidence)
        |> Enum.map(& &1.confidence)
        |> case do
          [] -> 0.0
          confs -> Enum.sum(confs) / length(confs)
        end
      else
        0.0
      end

    %{total: total, avg_confidence: Float.round(avg_confidence * 100, 1)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto px-6 py-6">
      <.tech_banner patterns={["Prompt-backed actions", "Oban workers", "AI metrics"]} />

      <div class="flex items-center justify-between mb-6">
        <h1 class="text-2xl font-bold text-gray-900">AI Dashboard</h1>
        <div class="flex gap-3">
          <button phx-click="refresh" class="px-3 py-2 text-sm border border-gray-300 rounded-lg hover:bg-gray-50">
            Refresh
          </button>
          <a href={~p"/simulator"} class="px-3 py-2 text-sm bg-indigo-600 text-white rounded-lg hover:bg-indigo-700">
            Trigger Triage
          </a>
        </div>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-8">
        <div class="bg-white rounded-lg border border-gray-200 p-4">
          <p class="text-sm text-gray-500">Total Triages (7d)</p>
          <p class="text-2xl font-bold text-purple-600">{@stats.total}</p>
        </div>
        <div class="bg-white rounded-lg border border-gray-200 p-4">
          <p class="text-sm text-gray-500">Avg Confidence</p>
          <p class="text-2xl font-bold text-purple-600">{@stats.avg_confidence}%</p>
        </div>
      </div>

      <h2 class="text-xl font-semibold text-gray-900 mb-4">Recent Triage Results</h2>

      <div :if={@results == []} class="text-center py-12 bg-white rounded-lg border border-gray-200">
        <p class="text-gray-500">No triage results yet.</p>
        <a href={~p"/simulator"} class="text-indigo-600 hover:text-indigo-700 text-sm mt-2 inline-block">
          Run a triage in the Simulator
        </a>
      </div>

      <div :if={@results != []} class="bg-white rounded-lg border border-gray-200 overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Ticket</th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Category</th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Severity</th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Confidence</th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Created</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-200">
            <tr :for={result <- @results} class="hover:bg-gray-50">
              <td class="px-4 py-3">
                <a href={~p"/tickets/#{result.ticket_id}"} class="text-indigo-600 hover:text-indigo-700 text-sm font-mono">
                  {String.slice(result.ticket_id, 0..7)}...
                </a>
              </td>
              <td class="px-4 py-3 text-sm text-gray-700">{result.predicted_category || "—"}</td>
              <td class="px-4 py-3 text-sm text-gray-700">{result.predicted_severity || "—"}</td>
              <td class="px-4 py-3 text-sm text-gray-700">
                {if result.confidence, do: "#{Float.round(result.confidence * 100, 1)}%", else: "—"}
              </td>
              <td class="px-4 py-3 text-sm text-gray-500">
                {Calendar.strftime(result.inserted_at, "%Y-%m-%d %H:%M")}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end
end
