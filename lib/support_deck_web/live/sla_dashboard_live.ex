defmodule SupportDeckWeb.SLADashboardLive do
  use SupportDeckWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    breaching = case SupportDeck.Tickets.list_breaching_sla() do
      {:ok, tickets} -> tickets
      _ -> []
    end

    policies = case SupportDeck.SLADomain.list_all_policies() do
      {:ok, p} -> p
      _ -> []
    end

    {:ok,
     socket
     |> assign(:page_title, "SLA Dashboard")
     |> assign(:current_path, ~p"/sla")
     |> assign(:breaching_tickets, breaching)
     |> assign(:policies, policies)}
  end

  @impl true
  def handle_event("refresh", _, socket) do
    breaching = case SupportDeck.Tickets.list_breaching_sla() do
      {:ok, tickets} -> tickets
      _ -> []
    end

    {:noreply, assign(socket, :breaching_tickets, breaching)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto px-6 py-6">
      <.tech_banner patterns={["AshOban triggers", "SLA Buddy pattern", "Named read actions"]} />

      <div class="flex items-center justify-between mb-6">
        <h1 class="text-2xl font-bold text-gray-900">SLA Dashboard</h1>
        <div class="flex gap-3">
          <button phx-click="refresh" class="px-3 py-2 text-sm border border-gray-300 rounded-lg hover:bg-gray-50">
            Refresh
          </button>
          <a href={~p"/sla/policies"} class="px-3 py-2 text-sm bg-indigo-600 text-white rounded-lg hover:bg-indigo-700">
            Manage Policies
          </a>
        </div>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-8">
        <div class="bg-white rounded-lg border border-gray-200 p-4">
          <p class="text-sm text-gray-500">Breaching Tickets</p>
          <p class="text-2xl font-bold text-red-600">{length(@breaching_tickets)}</p>
        </div>
        <div class="bg-white rounded-lg border border-gray-200 p-4">
          <p class="text-sm text-gray-500">Active Policies</p>
          <p class="text-2xl font-bold text-blue-600">{length(Enum.filter(@policies, & &1.enabled))}</p>
        </div>
        <div class="bg-white rounded-lg border border-gray-200 p-4">
          <p class="text-sm text-gray-500">Total Policies</p>
          <p class="text-2xl font-bold text-gray-600">{length(@policies)}</p>
        </div>
      </div>

      <h2 class="text-xl font-semibold text-gray-900 mb-4">Breaching Tickets</h2>

      <div :if={@breaching_tickets == []} class="text-center py-12 bg-white rounded-lg border border-gray-200">
        <p class="text-gray-500">No SLA breaches. All clear.</p>
      </div>

      <div :if={@breaching_tickets != []} class="bg-white rounded-lg border border-gray-200 overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Subject</th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Severity</th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Tier</th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Status</th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Time Since Breach</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-200">
            <tr :for={ticket <- @breaching_tickets} class="hover:bg-gray-50">
              <td class="px-4 py-3">
                <a href={~p"/tickets/#{ticket.id}"} class="text-indigo-600 hover:text-indigo-700 font-medium text-sm">
                  {ticket.subject}
                </a>
              </td>
              <td class="px-4 py-3 text-sm text-gray-500">{ticket.severity}</td>
              <td class="px-4 py-3 text-sm text-gray-500">{ticket.subscription_tier}</td>
              <td class="px-4 py-3 text-sm text-gray-500">{ticket.state}</td>
              <td class="px-4 py-3 text-sm text-red-600 font-medium">{time_since_breach(ticket)}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp time_since_breach(ticket) do
    case ticket.sla_deadline do
      nil -> "N/A"
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
