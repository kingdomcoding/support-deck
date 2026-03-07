defmodule SupportDeckWeb.TicketQueueLive do
  use SupportDeckWeb, :live_view

  alias SupportDeckWeb.ErrorHelpers

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
     |> assign(:show_create, false)
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

  def handle_event("new_ticket", _, socket) do
    {:noreply, assign(socket, :show_create, true)}
  end

  def handle_event("close_create", _, socket) do
    {:noreply, assign(socket, :show_create, false)}
  end

  def handle_event("create_ticket", params, socket) do
    attrs = %{
      external_id: "ui-#{System.unique_integer([:positive])}",
      source: :manual,
      body: params["body"],
      severity: String.to_existing_atom(params["severity"]),
      subscription_tier: String.to_existing_atom(params["tier"]),
      customer_email: if(params["customer_email"] != "", do: params["customer_email"])
    }

    case SupportDeck.Tickets.open_ticket(params["subject"], attrs) do
      {:ok, _ticket} ->
        {:noreply,
         socket
         |> assign(:show_create, false)
         |> put_flash(:info, "Ticket created")
         |> load_tickets()}

      {:error, err} ->
        {:noreply, put_flash(socket, :error, ErrorHelpers.format_error(err))}
    end
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
          <button
            phx-click="new_ticket"
            class="px-3 py-1.5 text-sm bg-primary text-primary-content rounded-lg hover:bg-primary/90"
          >
            + New Ticket
          </button>
        </:actions>
      </.page_header>

      <div class="flex gap-4 mb-4">
        <form phx-change="search" phx-submit="search" class="flex-1">
          <input
            type="text"
            name="search"
            value={@search}
            placeholder="Search by subject or email..."
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
        <button
          phx-click="new_ticket"
          class="text-primary hover:text-primary/80 text-sm mt-2 inline-block"
        >
          Create your first ticket
        </button>
      </div>

      <div
        :if={@tickets != []}
        class="bg-base-100 rounded-lg border border-base-300 overflow-hidden"
      >
        <table class="w-full text-sm">
          <thead>
            <tr class="border-b border-base-300 text-base-content/50 text-xs uppercase">
              <th class="px-4 py-2.5 text-left font-medium">Subject</th>
              <th class="px-4 py-2.5 text-left font-medium">State</th>
              <th class="px-4 py-2.5 text-left font-medium">Severity</th>
              <th class="px-4 py-2.5 text-left font-medium">Source</th>
              <th class="px-4 py-2.5 text-left font-medium">Assignee</th>
              <th class="px-4 py-2.5 text-left font-medium">Created</th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={ticket <- @tickets}
              class="border-b border-base-300/50 last:border-0 hover:bg-base-200/50 transition-colors"
            >
              <td class="px-4 py-2.5">
                <.link
                  navigate={~p"/tickets/#{ticket.id}"}
                  class="text-primary hover:underline font-medium"
                >
                  {ticket.subject}
                </.link>
              </td>
              <td class="px-4 py-2.5">
                <.state_pill state={ticket.state} />
              </td>
              <td class="px-4 py-2.5">
                <.severity_pill severity={ticket.severity} />
              </td>
              <td class="px-4 py-2.5 text-base-content/60">{ticket.source}</td>
              <td class="px-4 py-2.5 text-base-content/60">{ticket.assignee || "Unassigned"}</td>
              <td class="px-4 py-2.5 text-base-content/40 text-xs">
                {relative_time(ticket.inserted_at)}
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div
        :if={@show_create}
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
      >
        <div
          class="bg-base-100 rounded-xl shadow-xl w-full max-w-lg mx-4 p-6"
          phx-click-away="close_create"
        >
          <div class="flex items-center justify-between mb-4">
            <h2 class="text-lg font-semibold text-base-content">New Ticket</h2>
            <button phx-click="close_create" class="text-base-content/40 hover:text-base-content">
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>
          <form phx-submit="create_ticket" class="space-y-3">
            <div>
              <label class="text-xs font-medium text-base-content/60 mb-1 block">Subject</label>
              <input
                type="text"
                name="subject"
                required
                class="w-full px-3 py-2 border border-base-300 rounded-lg text-sm bg-base-100"
                placeholder="Brief description of the issue"
              />
            </div>
            <div>
              <label class="text-xs font-medium text-base-content/60 mb-1 block">Description</label>
              <textarea
                name="body"
                rows="3"
                class="w-full px-3 py-2 border border-base-300 rounded-lg text-sm bg-base-100"
                placeholder="Detailed description..."
              ></textarea>
            </div>
            <div class="grid grid-cols-2 gap-3">
              <div>
                <label class="text-xs font-medium text-base-content/60 mb-1 block">Severity</label>
                <select
                  name="severity"
                  class="w-full px-3 py-2 border border-base-300 rounded-lg text-sm bg-base-100"
                >
                  <option :for={s <- [:low, :medium, :high, :critical]} value={s}>{s}</option>
                </select>
              </div>
              <div>
                <label class="text-xs font-medium text-base-content/60 mb-1 block">Tier</label>
                <select
                  name="tier"
                  class="w-full px-3 py-2 border border-base-300 rounded-lg text-sm bg-base-100"
                >
                  <option :for={t <- [:free, :pro, :team, :enterprise]} value={t}>{t}</option>
                </select>
              </div>
            </div>
            <div>
              <label class="text-xs font-medium text-base-content/60 mb-1 block">
                Customer Email
              </label>
              <input
                type="email"
                name="customer_email"
                class="w-full px-3 py-2 border border-base-300 rounded-lg text-sm bg-base-100"
                placeholder="customer@example.com"
              />
            </div>
            <div class="flex justify-end gap-2 pt-2">
              <button
                type="button"
                phx-click="close_create"
                class="px-3 py-1.5 text-sm border border-base-300 rounded-lg hover:bg-base-200"
              >
                Cancel
              </button>
              <button
                type="submit"
                class="px-3 py-1.5 text-sm bg-primary text-primary-content rounded-lg hover:bg-primary/90"
                phx-disable-with="Creating..."
              >
                Create Ticket
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end
end
