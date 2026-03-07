defmodule SupportDeckWeb.TicketQueueLive do
  use SupportDeckWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(SupportDeck.PubSub, "tickets:updates")
    end

    {:ok,
     socket
     |> assign(:page_title, "Tickets")
     |> assign(:current_path, ~p"/tickets")
     |> assign(:search, "")
     |> assign(:status_filter, nil)
     |> load_tickets()}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, socket |> assign(:search, search) |> load_tickets()}
  end

  def handle_event("filter_status", %{"status" => ""}, socket) do
    {:noreply, socket |> assign(:status_filter, nil) |> load_tickets()}
  end

  def handle_event("filter_status", %{"status" => status}, socket) do
    {:noreply, socket |> assign(:status_filter, String.to_existing_atom(status)) |> load_tickets()}
  end

  @impl true
  def handle_info({:ticket_created, _}, socket), do: {:noreply, load_tickets(socket)}
  def handle_info({:ticket_updated, _}, socket), do: {:noreply, load_tickets(socket)}
  def handle_info({:ticket_escalated, _}, socket), do: {:noreply, load_tickets(socket)}
  def handle_info(_, socket), do: {:noreply, socket}

  defp load_tickets(socket) do
    tickets = case socket.assigns[:status_filter] do
      nil ->
        case SupportDeck.Tickets.list_open_tickets() do
          {:ok, t} -> t
          _ -> []
        end
      status ->
        case SupportDeck.Tickets.list_by_status(status) do
          {:ok, t} -> t
          _ -> []
        end
    end

    filtered = case socket.assigns[:search] do
      "" -> tickets
      search ->
        term = String.downcase(search)
        Enum.filter(tickets, fn t ->
          String.contains?(String.downcase(t.subject || ""), term) ||
          String.contains?(String.downcase(t.customer_email || ""), term)
        end)
    end

    assign(socket, :tickets, filtered)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto px-6 py-6">
      <.tech_banner patterns={["AshStateMachine", "PubSub real-time", "Ash read actions", "Named filters"]} />

      <div class="flex items-center justify-between mb-6">
        <h1 class="text-2xl font-bold text-gray-900">Tickets</h1>
        <a href={~p"/simulator"} class="px-3 py-2 text-sm bg-indigo-600 text-white rounded-lg hover:bg-indigo-700">
          + New Ticket
        </a>
      </div>

      <div class="flex gap-4 mb-4">
        <form phx-change="search" class="flex-1">
          <input type="text" name="search" value={@search} placeholder="Search tickets..." class="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm" phx-debounce="300" />
        </form>
        <form phx-change="filter_status">
          <select name="status" class="px-3 py-2 border border-gray-300 rounded-lg text-sm">
            <option value="">All Open</option>
            <option value="new">New</option>
            <option value="triaging">Triaging</option>
            <option value="assigned">Assigned</option>
            <option value="waiting_on_customer">Waiting</option>
            <option value="escalated">Escalated</option>
            <option value="resolved">Resolved</option>
            <option value="closed">Closed</option>
          </select>
        </form>
      </div>

      <div :if={@tickets == []} class="text-center py-12 bg-white rounded-lg border border-gray-200">
        <p class="text-gray-500">No tickets found.</p>
        <a href={~p"/simulator"} class="text-indigo-600 hover:text-indigo-700 text-sm mt-2 inline-block">
          Create your first ticket in the Simulator →
        </a>
      </div>

      <div :if={@tickets != []} class="bg-white rounded-lg border border-gray-200 overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Subject</th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Status</th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Severity</th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Source</th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Assignee</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-200">
            <tr :for={ticket <- @tickets} class="hover:bg-gray-50">
              <td class="px-4 py-3">
                <a href={~p"/tickets/#{ticket.id}"} class="text-indigo-600 hover:text-indigo-700 font-medium text-sm">
                  {ticket.subject}
                </a>
              </td>
              <td class="px-4 py-3">
                <.status_badge status={ticket.state} />
              </td>
              <td class="px-4 py-3">
                <.severity_badge severity={ticket.severity} />
              </td>
              <td class="px-4 py-3 text-sm text-gray-500">{ticket.source}</td>
              <td class="px-4 py-3 text-sm text-gray-500">{ticket.assignee || "—"}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp status_badge(assigns) do
    colors = %{
      new: "bg-blue-100 text-blue-700",
      triaging: "bg-yellow-100 text-yellow-700",
      assigned: "bg-green-100 text-green-700",
      waiting_on_customer: "bg-orange-100 text-orange-700",
      escalated: "bg-red-100 text-red-700",
      resolved: "bg-gray-100 text-gray-700",
      closed: "bg-gray-100 text-gray-500"
    }
    assigns = assign(assigns, :color, Map.get(colors, assigns.status, "bg-gray-100 text-gray-500"))

    ~H"""
    <span class={"px-2 py-1 text-xs rounded-full #{@color}"}>{@status}</span>
    """
  end

  defp severity_badge(assigns) do
    colors = %{
      critical: "bg-red-100 text-red-700",
      high: "bg-orange-100 text-orange-700",
      medium: "bg-yellow-100 text-yellow-700",
      low: "bg-gray-100 text-gray-600"
    }
    assigns = assign(assigns, :color, Map.get(colors, assigns.severity, "bg-gray-100 text-gray-500"))

    ~H"""
    <span class={"px-2 py-1 text-xs rounded-full #{@color}"}>{@severity}</span>
    """
  end
end
