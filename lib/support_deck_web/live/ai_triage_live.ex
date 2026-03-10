defmodule SupportDeckWeb.AITriageLive do
  use SupportDeckWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    results =
      case SupportDeck.AI.list_all_triage() do
        {:ok, r} -> r
        _ -> []
      end

    {:ok,
     socket
     |> assign(:page_title, "AI Triage")
     |> assign(:current_path, ~p"/ai")
     |> assign(:results, results)
     |> assign(:metrics, compute_metrics(results))}
  end

  defp compute_metrics(results) do
    total = length(results)
    with_feedback = Enum.filter(results, &(not is_nil(&1.human_accepted)))
    accepted = Enum.count(with_feedback, & &1.human_accepted)
    feedback_count = length(with_feedback)

    confidences = Enum.map(results, & &1.confidence) |> Enum.reject(&is_nil/1)
    avg_conf = if confidences != [], do: Enum.sum(confidences) / length(confidences), else: 0.0

    times = Enum.map(results, & &1.processing_time_ms) |> Enum.reject(&is_nil/1)
    avg_time = if times != [], do: div(Enum.sum(times), length(times)), else: 0

    by_category =
      results
      |> Enum.frequencies_by(& &1.predicted_category)
      |> Enum.sort_by(fn {_, count} -> count end, :desc)

    %{
      total: total,
      acceptance_rate: if(feedback_count > 0, do: accepted / feedback_count * 100, else: 0.0),
      avg_confidence: avg_conf,
      avg_processing_ms: avg_time,
      by_category: by_category,
      high_conf: Enum.count(results, &(&1.confidence != nil and &1.confidence >= 0.85)),
      med_conf: Enum.count(results, &(&1.confidence != nil and &1.confidence >= 0.50 and &1.confidence < 0.85)),
      low_conf: Enum.count(results, &(&1.confidence != nil and &1.confidence < 0.50)),
      with_feedback: feedback_count,
      accepted: accepted,
      rejected: feedback_count - accepted
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto px-6 py-6">
      <.page_header
        title="AI Triage"
        description="Classification performance, acceptance rates, and confidence distribution."
      />

      <div class="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-6">
        <.stat_card label="Total Triages" value={@metrics.total} variant="info" />
        <.stat_card
          label="Acceptance Rate"
          value={"#{Float.round(@metrics.acceptance_rate, 1)}%"}
          variant="success"
        />
        <.stat_card
          label="Avg Confidence"
          value={"#{Float.round(@metrics.avg_confidence * 100, 1)}%"}
          variant="accent"
        />
        <.stat_card
          label="Avg Processing"
          value={"#{@metrics.avg_processing_ms}ms"}
          variant="info"
        />
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-6">
        <div class="bg-base-100 rounded-lg border border-base-300 p-4">
          <h3 class="text-sm font-semibold text-base-content mb-3">Category Distribution</h3>
          <div :if={@metrics.by_category == []} class="text-sm text-base-content/40">
            No triage data yet.
          </div>
          <div class="space-y-2">
            <div :for={{category, count} <- @metrics.by_category} class="flex items-center gap-3">
              <span class="w-20 text-xs text-base-content/60 text-right truncate">{category}</span>
              <div class="flex-1 bg-base-200 rounded-full h-5 overflow-hidden">
                <div
                  class="bg-primary/70 h-full rounded-full flex items-center justify-end pr-2"
                  style={"width: #{if @metrics.total > 0, do: count / @metrics.total * 100, else: 0}%"}
                >
                  <span class="text-[10px] font-medium text-primary-content">{count}</span>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div class="bg-base-100 rounded-lg border border-base-300 p-4">
          <h3 class="text-sm font-semibold text-base-content mb-3">Confidence Distribution</h3>
          <div class="space-y-3">
            <.conf_bar label="High (≥85%)" count={@metrics.high_conf} total={@metrics.total} class="bg-success/70" />
            <.conf_bar label="Medium (50–84%)" count={@metrics.med_conf} total={@metrics.total} class="bg-warning/70" />
            <.conf_bar label="Low (<50%)" count={@metrics.low_conf} total={@metrics.total} class="bg-error/70" />
          </div>

          <div class="mt-4 pt-3 border-t border-base-300">
            <h4 class="text-xs font-semibold text-base-content/60 mb-2">Human Feedback</h4>
            <div class="flex gap-4 text-xs">
              <span class="text-success">
                <span class="font-bold">{@metrics.accepted}</span> accepted
              </span>
              <span class="text-error">
                <span class="font-bold">{@metrics.rejected}</span> rejected
              </span>
              <span class="text-base-content/40">
                {@metrics.total - @metrics.with_feedback} pending
              </span>
            </div>
          </div>
        </div>
      </div>

      <div class="bg-base-100 rounded-lg border border-base-300 overflow-hidden">
        <div class="px-4 py-3 border-b border-base-300">
          <h3 class="text-sm font-semibold text-base-content">Recent Results</h3>
        </div>
        <div :if={@results == []} class="p-8 text-center text-base-content/50 text-sm">
          No triage results yet. Run AI triage on a ticket to see results here.
        </div>
        <div :if={@results != []} class="overflow-x-auto max-h-96 overflow-y-auto">
          <table class="min-w-full divide-y divide-base-300 text-sm">
            <thead class="bg-base-200 sticky top-0">
              <tr>
                <th class="px-4 py-2 text-left text-xs font-medium text-base-content/60 uppercase">Category</th>
                <th class="px-4 py-2 text-left text-xs font-medium text-base-content/60 uppercase">Severity</th>
                <th class="px-4 py-2 text-left text-xs font-medium text-base-content/60 uppercase">Confidence</th>
                <th class="px-4 py-2 text-left text-xs font-medium text-base-content/60 uppercase">Status</th>
                <th class="px-4 py-2 text-left text-xs font-medium text-base-content/60 uppercase">Time (ms)</th>
                <th class="px-4 py-2 text-left text-xs font-medium text-base-content/60 uppercase">Date</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-base-300">
              <tr :for={result <- @results} class="hover:bg-base-200/50">
                <td class="px-4 py-2 text-base-content/80">{result.predicted_category || "—"}</td>
                <td class="px-4 py-2 text-base-content/80">{result.predicted_severity || "—"}</td>
                <td class="px-4 py-2">
                  <span class={confidence_class(result.confidence)}>
                    {if result.confidence, do: "#{Float.round(result.confidence * 100, 1)}%", else: "—"}
                  </span>
                </td>
                <td class="px-4 py-2">
                  <span :if={is_nil(result.human_accepted)} class="text-base-content/40 text-xs">Pending</span>
                  <span :if={result.human_accepted == true} class="text-success text-xs font-medium">Accepted</span>
                  <span :if={result.human_accepted == false} class="text-error text-xs font-medium">Rejected</span>
                </td>
                <td class="px-4 py-2 text-base-content/60 font-mono text-xs">{result.processing_time_ms || "—"}</td>
                <td class="px-4 py-2 text-base-content/40 text-xs">{Calendar.strftime(result.inserted_at, "%b %d %H:%M")}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :variant, :string, required: true

  defp stat_card(assigns) do
    classes = %{
      "info" => "text-info",
      "success" => "text-success",
      "accent" => "text-accent",
      "error" => "text-error"
    }

    assigns = assign(assigns, :variant_class, Map.get(classes, assigns.variant, "text-base-content"))

    ~H"""
    <div class="bg-base-100 rounded-lg border border-base-300 p-4">
      <p class="text-xs text-base-content/50 mb-1">{@label}</p>
      <p class={["text-2xl font-bold", @variant_class]}>{@value}</p>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :count, :integer, required: true
  attr :total, :integer, required: true
  attr :class, :string, required: true

  defp conf_bar(assigns) do
    pct = if assigns.total > 0, do: assigns.count / assigns.total * 100, else: 0
    assigns = assign(assigns, :pct, pct)

    ~H"""
    <div>
      <div class="flex justify-between text-xs mb-1">
        <span class="text-base-content/60">{@label}</span>
        <span class="font-medium text-base-content/80">{@count}</span>
      </div>
      <div class="bg-base-200 rounded-full h-3 overflow-hidden">
        <div class={["h-full rounded-full", @class]} style={"width: #{@pct}%"} />
      </div>
    </div>
    """
  end

  defp confidence_class(nil), do: "text-base-content/40"
  defp confidence_class(c) when c >= 0.85, do: "text-success font-medium"
  defp confidence_class(c) when c >= 0.50, do: "text-warning font-medium"
  defp confidence_class(_), do: "text-error font-medium"
end
