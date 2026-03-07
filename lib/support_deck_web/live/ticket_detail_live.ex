defmodule SupportDeckWeb.TicketDetailLive do
  use SupportDeckWeb, :live_view
  alias SupportDeckWeb.ErrorHelpers

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    back_path = params["from"] || ~p"/tickets"

    back_label =
      cond do
        String.starts_with?(back_path, "/sla") -> "Back to SLA Monitor"
        String.starts_with?(back_path, "/ai") -> "Back to AI Triage"
        back_path == "/" -> "Back to Dashboard"
        true -> "Back to Tickets"
      end
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
         |> assign(:back_path, back_path)
         |> assign(:back_label, back_label)
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
        {:noreply,
         put_flash(socket, :error, "Transition failed: #{ErrorHelpers.format_error(err)}")}
    end
  end

  def handle_event("trigger_triage", _, socket) do
    ticket = socket.assigns.ticket

    case SupportDeck.Workers.AITriageWorker.new(%{ticket_id: ticket.id}) |> Oban.insert() do
      {:ok, _} ->
        Process.send_after(self(), :refresh_triage, 2000)
        {:noreply, put_flash(socket, :info, "AI triage queued")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to queue triage")}
    end
  end

  @impl true
  def handle_info({event, updated}, socket) when event in [:ticket_updated, :ticket_escalated] do
    if updated.id == socket.assigns.ticket.id do
      activities =
        case SupportDeck.Tickets.list_activities_for_ticket(updated.id) do
          {:ok, a} -> a
          _ -> socket.assigns.activities
        end

      {:noreply, socket |> assign(:ticket, updated) |> assign(:activities, activities)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(:refresh_triage, socket) do
    triage_results =
      case SupportDeck.AI.list_triage_for_ticket(socket.assigns.ticket.id) do
        {:ok, t} -> t
        _ -> socket.assigns.triage_results
      end

    {:noreply, assign(socket, :triage_results, triage_results)}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-6 py-6">
      <div class="mb-4">
        <.link
          navigate={@back_path}
          class="text-sm text-base-content/50 hover:text-base-content inline-flex items-center gap-1"
        >
          <.icon name="hero-arrow-left" class="size-3.5" /> {@back_label}
        </.link>
      </div>

      <div class="flex items-start justify-between mb-6">
        <div>
          <div class="flex items-center gap-2.5 mb-1">
            <h1 class="text-xl font-semibold text-base-content">{@ticket.subject}</h1>
            <.state_pill state={@ticket.state} />
            <.severity_pill severity={@ticket.severity} />
          </div>
          <p class="text-sm text-base-content/50">
            {@ticket.customer_email || "No email"} · {@ticket.source} · {@ticket.subscription_tier} tier · {relative_time(
              @ticket.inserted_at
            )}
          </p>
        </div>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div class="lg:col-span-2 space-y-4">
          <div :if={@ticket.body} class="bg-base-100 rounded-lg border border-base-300 p-4">
            <p class="text-sm text-base-content/80 whitespace-pre-wrap">{@ticket.body}</p>
          </div>

          <div class="bg-base-100 rounded-lg border border-base-300 p-4">
            <h3 class="text-sm font-semibold text-base-content mb-3">Activity</h3>
            <div :if={@activities == []} class="text-sm text-base-content/40">No activity yet.</div>
            <div class="space-y-3">
              <div :for={activity <- @activities} class="flex gap-3">
                <div class="flex flex-col items-center">
                  <div class="w-2 h-2 rounded-full bg-primary mt-1.5" />
                  <div class="w-px flex-1 bg-base-300" />
                </div>
                <div class="pb-3">
                  <p class="text-sm text-base-content/80">
                    <span class="font-medium text-base-content">{activity.actor}</span>
                    {activity.action}
                    <span :if={activity.to_value} class="font-medium text-base-content">
                      {activity.to_value}
                    </span>
                  </p>
                  <p class="text-xs text-base-content/40 mt-0.5">
                    {Calendar.strftime(activity.inserted_at, "%b %d, %Y at %H:%M")}
                  </p>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div class="space-y-4">
          <div class="bg-base-100 rounded-lg border border-base-300 p-4">
            <h3 class="text-sm font-semibold text-base-content mb-3">Transitions</h3>
            <div class="space-y-1.5">
              <button
                :for={action <- available_transitions(@ticket.state)}
                phx-click="transition"
                phx-value-action={action}
                phx-disable-with="..."
                data-confirm={if action in ["close", "resolve"], do: "#{humanize_action(action)} this ticket?"}
                class="w-full px-3 py-1.5 text-sm text-left rounded-md border border-base-300 hover:bg-base-200 transition-colors"
              >
                {humanize_action(action)}
              </button>
            </div>
            <div :if={available_transitions(@ticket.state) == []} class="text-sm text-base-content/40">
              No transitions available.
            </div>
          </div>

          <div class="bg-base-100 rounded-lg border border-base-300 p-4">
            <h3 class="text-sm font-semibold text-base-content mb-3">AI Triage</h3>
            <button
              phx-click="trigger_triage"
              phx-disable-with="Queuing..."
              class="w-full px-3 py-1.5 text-sm bg-secondary text-secondary-content rounded-lg hover:bg-secondary/90 inline-flex items-center justify-center gap-1.5"
            >
              <.icon name="hero-sparkles" class="size-3.5" /> Run Triage
            </button>
            <div
              :for={result <- @triage_results}
              class="mt-3 p-2.5 bg-base-200 rounded text-xs space-y-1"
            >
              <div class="flex justify-between">
                <span class="text-base-content/50">Category</span>
                <span>{result.predicted_category || "—"}</span>
              </div>
              <div class="flex justify-between">
                <span class="text-base-content/50">Severity</span>
                <span>{result.predicted_severity || "—"}</span>
              </div>
              <div class="flex justify-between">
                <span class="text-base-content/50">Confidence</span>
                <span>
                  {if result.confidence, do: "#{Float.round(result.confidence * 100, 1)}%", else: "—"}
                </span>
              </div>
            </div>
          </div>

          <div class="bg-base-100 rounded-lg border border-base-300 p-4">
            <h3 class="text-sm font-semibold text-base-content mb-3">Details</h3>
            <dl class="space-y-2 text-xs">
              <div class="flex justify-between">
                <dt class="text-base-content/50">Assignee</dt>
                <dd class="font-medium text-base-content">{@ticket.assignee || "Unassigned"}</dd>
              </div>
              <div class="flex justify-between">
                <dt class="text-base-content/50">SLA Deadline</dt>
                <dd class="font-medium text-base-content">{format_deadline(@ticket.sla_deadline)}</dd>
              </div>
              <div class="flex justify-between">
                <dt class="text-base-content/50">Product Area</dt>
                <dd class="font-medium text-base-content">{@ticket.product_area || "—"}</dd>
              </div>
            </dl>
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
