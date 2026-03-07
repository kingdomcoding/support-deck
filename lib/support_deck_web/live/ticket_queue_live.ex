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
    {:noreply,
     socket |> assign(:status_filter, String.to_existing_atom(status)) |> load_tickets()}
  end

  @impl true
  def handle_info({:ticket_created, _}, socket), do: {:noreply, load_tickets(socket)}
  def handle_info({:ticket_updated, _}, socket), do: {:noreply, load_tickets(socket)}
  def handle_info({:ticket_escalated, _}, socket), do: {:noreply, load_tickets(socket)}
  def handle_info(_, socket), do: {:noreply, socket}

  defp load_tickets(socket) do
    tickets =
      case socket.assigns[:status_filter] do
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

    filtered =
      case socket.assigns[:search] do
        "" ->
          tickets

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
      <.page_header
        title="Tickets"
        description="Active support tickets with real-time state machine transitions and search."
        patterns={["AshStateMachine", "PubSub", "Named read actions"]}
      >
        <:actions>
          <a
            href={~p"/simulator"}
            class="px-3 py-1.5 text-sm bg-primary text-primary-content rounded-lg hover:bg-primary/90"
          >
            + New Ticket
          </a>
        </:actions>
      </.page_header>

      <div class="flex gap-4 mb-4">
        <form phx-change="search" class="flex-1">
          <input
            type="text"
            name="search"
            value={@search}
            placeholder="Search tickets..."
            class="w-full px-3 py-2 border border-base-300 rounded-lg text-sm bg-base-100 text-base-content"
            phx-debounce="300"
          />
        </form>
        <form phx-change="filter_status">
          <select
            name="status"
            class="px-3 py-2 border border-base-300 rounded-lg text-sm bg-base-100 text-base-content"
          >
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

      <div
        :if={@tickets == []}
        class="text-center py-12 bg-base-100 rounded-lg border border-base-300"
      >
        <p class="text-base-content/60">No tickets found.</p>
        <a
          href={~p"/simulator"}
          class="text-primary hover:text-primary/80 text-sm mt-2 inline-block"
        >
          Create your first ticket in the Simulator
        </a>
      </div>

      <div
        :if={@tickets != []}
        class="bg-base-100 rounded-lg border border-base-300 overflow-hidden"
      >
        <table class="min-w-full divide-y divide-base-300">
          <thead class="bg-base-200">
            <tr>
              <th class="px-4 py-3 text-left text-xs font-medium text-base-content/60 uppercase">
                Subject
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-base-content/60 uppercase">
                Status
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-base-content/60 uppercase">
                Severity
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-base-content/60 uppercase">
                Source
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-base-content/60 uppercase">
                Assignee
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-base-300">
            <tr :for={ticket <- @tickets} class="hover:bg-base-200">
              <td class="px-4 py-3">
                <a
                  href={~p"/tickets/#{ticket.id}"}
                  class="text-primary hover:text-primary/80 font-medium text-sm"
                >
                  {ticket.subject}
                </a>
              </td>
              <td class="px-4 py-3">
                <.status_badge status={ticket.state} />
              </td>
              <td class="px-4 py-3">
                <.severity_badge severity={ticket.severity} />
              </td>
              <td class="px-4 py-3 text-sm text-base-content/60">{ticket.source}</td>
              <td class="px-4 py-3 text-sm text-base-content/60">{ticket.assignee || "—"}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp status_badge(assigns) do
    color =
      case assigns.status do
        :new -> "bg-info/15 text-info"
        :triaging -> "bg-warning/15 text-warning"
        :assigned -> "bg-success/15 text-success"
        :waiting_on_customer -> "bg-warning/15 text-warning"
        :escalated -> "bg-error/15 text-error"
        :resolved -> "bg-base-content/10 text-base-content/60"
        :closed -> "bg-base-content/5 text-base-content/40"
        _ -> "bg-base-content/5 text-base-content/40"
      end

    assigns = assign(assigns, :color, color)

    ~H"""
    <span class={["px-2 py-1 text-xs rounded-full", @color]}>{@status}</span>
    """
  end

  defp severity_badge(assigns) do
    color =
      case assigns.severity do
        :critical -> "bg-error/15 text-error"
        :high -> "bg-warning/15 text-warning"
        :medium -> "bg-info/15 text-info"
        :low -> "bg-base-content/10 text-base-content/60"
        _ -> "bg-base-content/5 text-base-content/40"
      end

    assigns = assign(assigns, :color, color)

    ~H"""
    <span class={["px-2 py-1 text-xs rounded-full", @color]}>{@severity}</span>
    """
  end
end
