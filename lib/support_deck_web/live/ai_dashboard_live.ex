defmodule SupportDeckWeb.AIDashboardLive do
  use SupportDeckWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    since = DateTime.add(DateTime.utc_now(), -7 * 24 * 3600)

    results =
      case SupportDeck.AI.list_recent_triage(since) do
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

    results =
      case SupportDeck.AI.list_recent_triage(since) do
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
      <.page_header
        title="AI Triage"
        description="Automated ticket classification and severity prediction. Tracks confidence and accuracy over time."
        patterns={["Prompt-backed actions", "Oban workers", "AI metrics"]}
      >
        <:actions>
          <button
            phx-click="refresh"
            class="px-3 py-1.5 text-sm border border-base-300 rounded-lg hover:bg-base-200"
          >
            Refresh
          </button>
          <.link
            navigate={~p"/simulator"}
            class="px-3 py-1.5 text-sm bg-primary text-primary-content rounded-lg hover:bg-primary/90"
          >
            Trigger Triage
          </.link>
        </:actions>
      </.page_header>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-8">
        <div class="bg-base-100 rounded-lg border border-base-300 p-4">
          <p class="text-sm text-base-content/60">Total Triages (7d)</p>
          <p class="text-2xl font-bold text-secondary">{@stats.total}</p>
        </div>
        <div class="bg-base-100 rounded-lg border border-base-300 p-4">
          <p class="text-sm text-base-content/60">Avg Confidence</p>
          <p class="text-2xl font-bold text-secondary">{@stats.avg_confidence}%</p>
        </div>
      </div>

      <h2 class="text-xl font-semibold text-base-content mb-4">Recent Triage Results</h2>

      <div
        :if={@results == []}
        class="text-center py-12 bg-base-100 rounded-lg border border-base-300"
      >
        <p class="text-base-content/60">No triage results yet.</p>
        <.link
          navigate={~p"/simulator"}
          class="text-primary hover:text-primary/80 text-sm mt-2 inline-block"
        >
          Run a triage in the Simulator
        </.link>
      </div>

      <div
        :if={@results != []}
        class="bg-base-100 rounded-lg border border-base-300 overflow-hidden"
      >
        <table class="min-w-full divide-y divide-base-300">
          <thead class="bg-base-200">
            <tr>
              <th class="px-4 py-3 text-left text-xs font-medium text-base-content/60 uppercase">
                Ticket
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-base-content/60 uppercase">
                Category
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-base-content/60 uppercase">
                Severity
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-base-content/60 uppercase">
                Confidence
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-base-content/60 uppercase">
                Created
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-base-300">
            <tr
              :for={result <- @results}
              class="hover:bg-base-200 cursor-pointer"
              phx-click={JS.navigate(~p"/tickets/#{result.ticket_id}?from=/ai")}
            >
              <td class="px-4 py-3">
                <span class="text-primary text-sm font-mono" title={result.ticket_id}>
                  {String.slice(result.ticket_id, 0..7)}...
                </span>
              </td>
              <td class="px-4 py-3 text-sm text-base-content/80">
                {result.predicted_category || "—"}
              </td>
              <td class="px-4 py-3 text-sm text-base-content/80">
                {result.predicted_severity || "—"}
              </td>
              <td class="px-4 py-3 text-sm text-base-content/80">
                {if result.confidence, do: "#{Float.round(result.confidence * 100, 1)}%", else: "—"}
              </td>
              <td class="px-4 py-3 text-sm text-base-content/60">
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
