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
     |> assign(:sort_by, :inserted_at)
     |> assign(:sort_dir, :desc)
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

  def handle_event("sort", %{"field" => field}, socket) do
    field = String.to_existing_atom(field)

    {sort_by, sort_dir} =
      if socket.assigns.sort_by == field,
        do: {field, toggle_dir(socket.assigns.sort_dir)},
        else: {field, :asc}

    {:noreply,
     socket
     |> assign(:sort_by, sort_by)
     |> assign(:sort_dir, sort_dir)
     |> load_tickets()}
  end

  def handle_event("new_ticket", _, socket) do
    {:noreply, assign(socket, :show_create, true)}
  end

  def handle_event("close_create", _, socket) do
    {:noreply, assign(socket, :show_create, false)}
  end

  def handle_event("triage_all", _, socket) do
    new_tickets = Enum.filter(socket.assigns.tickets, &(&1.state == :new))

    enqueued =
      Enum.count(new_tickets, fn ticket ->
        match?({:ok, _}, SupportDeck.Workers.AITriageWorker.new(%{ticket_id: ticket.id}) |> Oban.insert())
      end)

    {:noreply, put_flash(socket, :info, "AI triage queued for #{enqueued} ticket(s)")}
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

    sorted =
      Enum.sort_by(filtered, &sort_key(&1, socket.assigns[:sort_by] || :inserted_at), socket.assigns[:sort_dir] || :desc)

    assign(socket, :tickets, sorted)
  end

  defp sort_key(ticket, :subject), do: String.downcase(ticket.subject || "")
  defp sort_key(ticket, :state), do: to_string(ticket.state)
  defp sort_key(ticket, :severity), do: severity_order(ticket.severity)
  defp sort_key(ticket, :source), do: to_string(ticket.source)
  defp sort_key(ticket, :assignee), do: ticket.assignee || ""
  defp sort_key(ticket, :inserted_at), do: ticket.inserted_at
  defp sort_key(ticket, _), do: ticket.inserted_at

  defp severity_order(:critical), do: 0
  defp severity_order(:high), do: 1
  defp severity_order(:medium), do: 2
  defp severity_order(:low), do: 3
  defp severity_order(_), do: 4

  defp toggle_dir(:asc), do: :desc
  defp toggle_dir(:desc), do: :asc

  attr :field, :atom, required: true
  attr :label, :string, required: true
  attr :sort_by, :atom, required: true
  attr :sort_dir, :atom, required: true

  defp sort_header(assigns) do
    ~H"""
    <th
      class="px-4 py-2.5 text-left font-medium cursor-pointer hover:text-base-content select-none"
      phx-click="sort"
      phx-value-field={@field}
    >
      <span class="inline-flex items-center gap-1">
        {@label}
        <.icon
          :if={@sort_by == @field}
          name={if @sort_dir == :asc, do: "hero-chevron-up", else: "hero-chevron-down"}
          class="size-3 text-primary"
        />
      </span>
    </th>
    """
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
            phx-click="triage_all"
            phx-disable-with="Triaging..."
            class="px-3 py-1.5 text-sm border border-base-300 rounded-lg hover:bg-base-200 inline-flex items-center gap-1.5"
          >
            <.icon name="hero-sparkles" class="size-3.5" /> Triage All
          </button>
          <button
            data-tour="create-ticket-btn"
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
            <option value="" selected={@status_filter == nil}>All Open</option>
            <option value="new" selected={@status_filter == :new}>New</option>
            <option value="triaging" selected={@status_filter == :triaging}>Triaging</option>
            <option value="assigned" selected={@status_filter == :assigned}>Assigned</option>
            <option value="waiting_on_customer" selected={@status_filter == :waiting_on_customer}>Waiting</option>
            <option value="escalated" selected={@status_filter == :escalated}>Escalated</option>
            <option value="resolved" selected={@status_filter == :resolved}>Resolved</option>
            <option value="closed" selected={@status_filter == :closed}>Closed</option>
          </select>
        </form>
      </div>

      <div data-tour="ticket-table" class="bg-base-100 rounded-lg border border-base-300 overflow-hidden">
        <div
          :if={@tickets == []}
          class="text-center py-12"
        >
          <p class="text-base-content/60">No tickets found.</p>
          <button
            phx-click="new_ticket"
            class="text-primary hover:text-primary/80 text-sm mt-2 inline-block"
          >
            Create your first ticket
          </button>
        </div>
        <table :if={@tickets != []} class="w-full text-sm">
          <thead>
            <tr class="border-b border-base-300 text-base-content/50 text-xs uppercase">
              <.sort_header field={:subject} label="Subject" sort_by={@sort_by} sort_dir={@sort_dir} />
              <.sort_header field={:state} label="State" sort_by={@sort_by} sort_dir={@sort_dir} />
              <.sort_header field={:severity} label="Severity" sort_by={@sort_by} sort_dir={@sort_dir} />
              <.sort_header field={:source} label="Source" sort_by={@sort_by} sort_dir={@sort_dir} />
              <.sort_header field={:assignee} label="Assignee" sort_by={@sort_by} sort_dir={@sort_dir} />
              <.sort_header field={:inserted_at} label="Created" sort_by={@sort_by} sort_dir={@sort_dir} />
            </tr>
          </thead>
          <tbody>
            <tr
              :for={ticket <- @tickets}
              class="border-b border-base-300/50 last:border-0 hover:bg-base-200/50 transition-colors cursor-pointer"
              phx-click={JS.navigate(~p"/tickets/#{ticket.id}")}
            >
              <td class="px-4 py-2.5">
                <span class="text-primary font-medium">{ticket.subject}</span>
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
        phx-window-keydown="close_create"
        phx-key="Escape"
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
