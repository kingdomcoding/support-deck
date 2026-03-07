defmodule SupportDeckWeb.TicketDetailLive do
  use SupportDeckWeb, :live_view
  alias SupportDeckWeb.ErrorHelpers

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case SupportDeck.Tickets.get_ticket(id) do
      {:ok, ticket} ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(SupportDeck.PubSub, "tickets:updates")
        end

        activities =
          case SupportDeck.Tickets.list_activities_for_ticket(ticket.id) do
            {:ok, a} -> a
            _ -> []
          end

        triage_results =
          case SupportDeck.AI.list_triage_for_ticket(ticket.id) do
            {:ok, t} -> t
            _ -> []
          end

        {:ok,
         socket
         |> assign(:page_title, ticket.subject)
         |> assign(:current_path, ~p"/tickets/#{id}")
         |> assign(:ticket, ticket)
         |> assign(:activities, activities)
         |> assign(:triage_results, triage_results)}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "Ticket not found")
         |> push_navigate(to: ~p"/tickets")}
    end
  end

  @impl true
  def handle_event("transition", %{"action" => action}, socket) do
    ticket = socket.assigns.ticket

    result =
      case action do
        "begin_triage" -> SupportDeck.Tickets.begin_triage(ticket)
        "assign" -> SupportDeck.Tickets.assign_ticket(ticket, "agent@support.dev")
        "wait_on_customer" -> SupportDeck.Tickets.wait_on_customer(ticket)
        "customer_replied" -> SupportDeck.Tickets.customer_replied(ticket)
        "escalate" -> SupportDeck.Tickets.escalate_ticket(ticket)
        "resolve" -> SupportDeck.Tickets.resolve_ticket(ticket)
        "close" -> SupportDeck.Tickets.close_ticket(ticket)
        _ -> {:error, "Unknown action"}
      end

    case result do
      {:ok, updated} ->
        activities =
          case SupportDeck.Tickets.list_activities_for_ticket(updated.id) do
            {:ok, a} -> a
            _ -> socket.assigns.activities
          end

        {:noreply, socket |> assign(:ticket, updated) |> assign(:activities, activities)}

      {:error, err} ->
        {:noreply, put_flash(socket, :error, "Transition failed: #{ErrorHelpers.format_error(err)}")}
    end
  end

  def handle_event("trigger_triage", _, socket) do
    ticket = socket.assigns.ticket
    SupportDeck.Workers.AITriageWorker.new(%{ticket_id: ticket.id}) |> Oban.insert()
    {:noreply, put_flash(socket, :info, "AI triage queued")}
  end

  @impl true
  def handle_info({:ticket_updated, updated}, socket) do
    if updated.id == socket.assigns.ticket.id do
      {:noreply, assign(socket, :ticket, updated)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-6 py-6">
      <div class="flex items-center gap-3 mb-2">
        <a href={~p"/tickets"} class="text-base-content/40 hover:text-base-content/60 text-sm">&larr; Back</a>
      </div>
      <.page_header
        title={@ticket.subject}
        description={"#{@ticket.source} ticket — #{@ticket.severity} severity — #{@ticket.subscription_tier} tier"}
        patterns={["AshStateMachine transitions", "PubSub", "Oban AI triage", "Activity timeline"]}
      />

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div class="lg:col-span-2 space-y-6">
          <div class="bg-base-100 rounded-lg border border-base-300 p-4">
            <h3 class="font-medium text-base-content mb-2">Details</h3>
            <dl class="grid grid-cols-2 gap-2 text-sm">
              <dt class="text-base-content/60">Status</dt>
              <dd>
                <span class="px-2 py-1 text-xs rounded-full bg-info/15 text-info">
                  {@ticket.state}
                </span>
              </dd>
              <dt class="text-base-content/60">Severity</dt>
              <dd>{@ticket.severity}</dd>
              <dt class="text-base-content/60">Source</dt>
              <dd>{@ticket.source}</dd>
              <dt class="text-base-content/60">Tier</dt>
              <dd>{@ticket.subscription_tier}</dd>
              <dt class="text-base-content/60">Assignee</dt>
              <dd>{@ticket.assignee || "Unassigned"}</dd>
              <dt class="text-base-content/60">Customer</dt>
              <dd>{@ticket.customer_email || "—"}</dd>
            </dl>
          </div>

          <div :if={@ticket.body} class="bg-base-100 rounded-lg border border-base-300 p-4">
            <h3 class="font-medium text-base-content mb-2">Description</h3>
            <p class="text-sm text-base-content/80 whitespace-pre-wrap">{@ticket.body}</p>
          </div>

          <div class="bg-base-100 rounded-lg border border-base-300 p-4">
            <h3 class="font-medium text-base-content mb-4">Activity Timeline</h3>
            <div :if={@activities == []} class="text-sm text-base-content/60">No activity yet.</div>
            <div :for={activity <- @activities} class="flex gap-3 mb-3 last:mb-0">
              <div class="w-2 h-2 mt-1.5 rounded-full bg-primary flex-shrink-0" />
              <div>
                <p class="text-sm text-base-content/80">
                  <span class="font-medium">{activity.actor}</span> — {activity.action}
                  <span :if={activity.to_value} class="text-base-content/60">
                    &rarr; {activity.to_value}
                  </span>
                </p>
                <p class="text-xs text-base-content/40">
                  {Calendar.strftime(activity.inserted_at, "%Y-%m-%d %H:%M")}
                </p>
              </div>
            </div>
          </div>
        </div>

        <div class="space-y-6">
          <div class="bg-base-100 rounded-lg border border-base-300 p-4">
            <h3 class="font-medium text-base-content mb-3">Actions</h3>
            <div class="space-y-2">
              <button
                :for={action <- available_transitions(@ticket.state)}
                phx-click="transition"
                phx-value-action={action}
                class="w-full px-3 py-2 text-sm text-left border border-base-300 rounded-lg hover:bg-base-200"
              >
                {humanize_action(action)}
              </button>
            </div>
          </div>

          <div class="bg-base-100 rounded-lg border border-base-300 p-4">
            <h3 class="font-medium text-base-content mb-3">AI Triage</h3>
            <button
              phx-click="trigger_triage"
              class="w-full px-3 py-2 text-sm bg-secondary text-secondary-content rounded-lg hover:bg-secondary/90"
            >
              Run AI Triage
            </button>
            <div :for={result <- @triage_results} class="mt-3 p-2 bg-base-200 rounded text-sm">
              <p>Category: {result.predicted_category || "—"}</p>
              <p>Severity: {result.predicted_severity || "—"}</p>
              <p>Confidence: {result.confidence && Float.round(result.confidence * 100, 1)}%</p>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp available_transitions(:new), do: ["begin_triage", "assign", "escalate", "close"]
  defp available_transitions(:triaging), do: ["assign", "escalate", "close"]
  defp available_transitions(:assigned), do: ["wait_on_customer", "escalate", "resolve", "close"]

  defp available_transitions(:waiting_on_customer),
    do: ["customer_replied", "escalate", "resolve", "close"]

  defp available_transitions(:escalated), do: ["assign", "resolve", "close"]
  defp available_transitions(:resolved), do: ["close"]
  defp available_transitions(_), do: []

  defp humanize_action(action) do
    action |> String.replace("_", " ") |> String.capitalize()
  end
end
