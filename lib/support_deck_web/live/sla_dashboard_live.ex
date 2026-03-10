defmodule SupportDeckWeb.SLADashboardLive do
  use SupportDeckWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(SupportDeck.PubSub, "tickets:updates")
    end

    breaching =
      case SupportDeck.Tickets.list_breaching_sla() do
        {:ok, tickets} -> tickets
        _ -> []
      end

    approaching =
      case SupportDeck.Tickets.list_approaching_sla() do
        {:ok, tickets} -> tickets
        _ -> []
      end

    policies =
      case SupportDeck.SLADomain.list_all_policies() do
        {:ok, p} -> p
        _ -> []
      end

    {:ok,
     socket
     |> assign(:page_title, "SLA Dashboard")
     |> assign(:current_path, ~p"/sla")
     |> assign(:breaching_tickets, breaching)
     |> assign(:approaching_tickets, approaching)
     |> assign(:policies, policies)}
  end

  @impl true
  def handle_info({event, _}, socket) when event in [:ticket_created, :ticket_updated, :ticket_escalated] do
    breaching =
      case SupportDeck.Tickets.list_breaching_sla() do
        {:ok, tickets} -> tickets
        _ -> []
      end

    approaching =
      case SupportDeck.Tickets.list_approaching_sla() do
        {:ok, tickets} -> tickets
        _ -> []
      end

    {:noreply, socket |> assign(:breaching_tickets, breaching) |> assign(:approaching_tickets, approaching)}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto px-6 py-6">
      <.page_header
        title="SLA Monitor"
        description="Track response and resolution deadlines. Overdue tickets are auto-escalated."
      >
        <:actions>
          <.link
            navigate={~p"/sla/policies"}
            class="px-3 py-1.5 text-sm bg-primary text-primary-content rounded-lg hover:bg-primary/90"
          >
            Policies
          </.link>
        </:actions>
      </.page_header>

      <div data-tour="sla-stats" class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-8">
        <div class="bg-base-100 rounded-lg border border-base-300 p-4">
          <p class="text-sm text-base-content/60">Breaching Tickets</p>
          <p class="text-2xl font-bold text-error">{length(@breaching_tickets)}</p>
        </div>
        <div class="bg-base-100 rounded-lg border border-base-300 p-4">
          <p class="text-sm text-base-content/60">Approaching Breach</p>
          <p class="text-2xl font-bold text-warning">{length(@approaching_tickets)}</p>
        </div>
        <div class="bg-base-100 rounded-lg border border-base-300 p-4">
          <p class="text-sm text-base-content/60">Active Policies</p>
          <p class="text-2xl font-bold text-info">
            {length(Enum.filter(@policies, & &1.enabled))}
          </p>
        </div>
        <div class="bg-base-100 rounded-lg border border-base-300 p-4">
          <p class="text-sm text-base-content/60">Total Policies</p>
          <p class="text-2xl font-bold text-base-content/60">{length(@policies)}</p>
        </div>
      </div>

      <div :if={@approaching_tickets != []} class="mb-8">
        <h2 class="text-xl font-semibold text-warning mb-4">Approaching Breach</h2>
        <div class="bg-base-100 rounded-lg border border-warning/30 overflow-hidden">
          <table class="min-w-full divide-y divide-base-300">
            <thead class="bg-warning/10">
              <tr>
                <th class="px-4 py-3 text-left text-xs font-medium text-base-content/60 uppercase">
                  Subject
                </th>
                <th class="px-4 py-3 text-left text-xs font-medium text-base-content/60 uppercase">
                  Severity
                </th>
                <th class="px-4 py-3 text-left text-xs font-medium text-base-content/60 uppercase">
                  Tier
                </th>
                <th class="px-4 py-3 text-left text-xs font-medium text-base-content/60 uppercase">
                  Status
                </th>
                <th class="px-4 py-3 text-left text-xs font-medium text-base-content/60 uppercase">
                  Time Until Breach
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-base-300">
              <tr
                :for={ticket <- @approaching_tickets}
                class="hover:bg-base-200 cursor-pointer"
                phx-click={JS.navigate(~p"/tickets/#{ticket.id}?from=/sla")}
              >
                <td class="px-4 py-3">
                  <span class="text-primary font-medium text-sm">{ticket.subject}</span>
                </td>
                <td class="px-4 py-3 text-sm text-base-content/60">{ticket.severity}</td>
                <td class="px-4 py-3 text-sm text-base-content/60">{ticket.subscription_tier}</td>
                <td class="px-4 py-3 text-sm text-base-content/60">{ticket.state}</td>
                <td class="px-4 py-3 text-sm text-warning font-medium">{time_until_breach(ticket)}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <h2 class="text-xl font-semibold text-base-content mb-4">Breaching Tickets</h2>

      <div
        :if={@breaching_tickets == []}
        class="text-center py-12 bg-base-100 rounded-lg border border-base-300"
      >
        <p class="text-base-content/60">No SLA breaches. All clear.</p>
      </div>

      <div
        :if={@breaching_tickets != []}
        class="bg-base-100 rounded-lg border border-base-300 overflow-hidden"
      >
        <table class="min-w-full divide-y divide-base-300">
          <thead class="bg-base-200">
            <tr>
              <th class="px-4 py-3 text-left text-xs font-medium text-base-content/60 uppercase">
                Subject
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-base-content/60 uppercase">
                Severity
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-base-content/60 uppercase">
                Tier
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-base-content/60 uppercase">
                Status
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-base-content/60 uppercase">
                Time Since Breach
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-base-300">
            <tr
              :for={ticket <- @breaching_tickets}
              class="hover:bg-base-200 cursor-pointer"
              phx-click={JS.navigate(~p"/tickets/#{ticket.id}?from=/sla")}
            >
              <td class="px-4 py-3">
                <span class="text-primary font-medium text-sm">{ticket.subject}</span>
              </td>
              <td class="px-4 py-3 text-sm text-base-content/60">{ticket.severity}</td>
              <td class="px-4 py-3 text-sm text-base-content/60">{ticket.subscription_tier}</td>
              <td class="px-4 py-3 text-sm text-base-content/60">{ticket.state}</td>
              <td class="px-4 py-3 text-sm text-error font-medium">{time_since_breach(ticket)}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp time_until_breach(ticket) do
    case ticket.sla_deadline do
      nil ->
        "N/A"

      deadline ->
        diff = DateTime.diff(deadline, DateTime.utc_now(), :minute)

        cond do
          diff <= 0 -> "Imminent"
          diff < 60 -> "#{diff}m"
          true -> "#{div(diff, 60)}h #{rem(diff, 60)}m"
        end
    end
  end

  defp time_since_breach(ticket) do
    case ticket.sla_deadline do
      nil ->
        "N/A"

      deadline ->
        diff = DateTime.diff(DateTime.utc_now(), deadline, :minute)

        cond do
          diff < 60 -> "#{diff}m ago"
          diff < 1440 -> "#{div(diff, 60)}h #{rem(diff, 60)}m ago"
          true -> "#{div(diff, 1440)}d #{div(rem(diff, 1440), 60)}h ago"
        end
    end
  end
end
