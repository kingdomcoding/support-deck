defmodule SupportDeckWeb.OverviewLive do
  use SupportDeckWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(SupportDeck.PubSub, "tickets:updates")
    end

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:current_path, ~p"/")
     |> assign(:stats, load_stats())
     |> assign(:recent_tickets, load_recent_tickets())
     |> assign(:health, load_health())}
  end

  @impl true
  def handle_info({:ticket_created, _}, socket) do
    {:noreply,
     socket
     |> assign(:stats, load_stats())
     |> assign(:recent_tickets, load_recent_tickets())}
  end

  def handle_info({:ticket_updated, _}, socket) do
    {:noreply,
     socket
     |> assign(:stats, load_stats())
     |> assign(:recent_tickets, load_recent_tickets())}
  end

  def handle_info({:ticket_escalated, _}, socket) do
    {:noreply,
     socket
     |> assign(:stats, load_stats())
     |> assign(:recent_tickets, load_recent_tickets())}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  defp load_stats do
    open =
      case SupportDeck.Tickets.list_open_tickets() do
        {:ok, t} -> length(t)
        _ -> 0
      end

    breaching =
      case SupportDeck.Tickets.list_breaching_sla() do
        {:ok, t} -> length(t)
        _ -> 0
      end

    rules =
      case SupportDeck.Tickets.list_all_rules() do
        {:ok, r} -> length(Enum.filter(r, & &1.enabled))
        _ -> 0
      end

    triage =
      case SupportDeck.AI.list_recent_triage(DateTime.add(DateTime.utc_now(), -24 * 3600)) do
        {:ok, t} -> length(t)
        _ -> 0
      end

    %{open_tickets: open, sla_breaches: breaching, active_rules: rules, ai_triages_24h: triage}
  end

  defp load_recent_tickets do
    case SupportDeck.Tickets.list_open_tickets() do
      {:ok, t} -> Enum.take(t, 5)
      _ -> []
    end
  end

  defp load_health do
    Enum.map([:front, :slack, :linear], fn name ->
      {name, SupportDeck.Integrations.CircuitBreaker.get_status(name)}
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto px-6 py-6">
      <.page_header
        title="Dashboard"
        description="Real-time overview of support operations, SLA compliance, and AI triage performance."
        patterns={["Phoenix LiveView", "PubSub real-time", "Ash Domain queries"]}
      >
        <:actions>
          <.link
            navigate={~p"/tour"}
            class="inline-flex items-center gap-2 px-3 py-1.5 text-sm bg-primary text-primary-content rounded-lg hover:bg-primary/90"
          >
            <.icon name="hero-play-circle" class="size-4" /> Guided Tour
          </.link>
        </:actions>
      </.page_header>

      <div class="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-6">
        <.metric_card
          label="Open Tickets"
          value={@stats.open_tickets}
          icon="hero-inbox-stack"
          href={~p"/tickets"}
          variant="info"
        />
        <.metric_card
          label="SLA Breaches"
          value={@stats.sla_breaches}
          icon="hero-exclamation-triangle"
          href={~p"/sla"}
          variant="error"
        />
        <.metric_card
          label="Active Rules"
          value={@stats.active_rules}
          icon="hero-bolt"
          href={~p"/rules"}
          variant="success"
        />
        <.metric_card
          label="AI Triages (24h)"
          value={@stats.ai_triages_24h}
          icon="hero-sparkles"
          href={~p"/ai"}
          variant="accent"
        />
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
        <div class="lg:col-span-2 bg-base-100 rounded-lg border border-base-300 overflow-hidden">
          <div class="px-4 py-3 border-b border-base-300 flex items-center justify-between">
            <h2 class="text-sm font-semibold text-base-content">Recent Tickets</h2>
            <.link navigate={~p"/tickets"} class="text-xs text-primary hover:underline">View all</.link>
          </div>
          <div :if={@recent_tickets == []} class="p-8 text-center text-base-content/50 text-sm">
            No tickets yet.
            <.link navigate={~p"/simulator"} class="text-primary hover:underline">
              Create one in the Simulator
            </.link>
          </div>
          <table :if={@recent_tickets != []} class="w-full text-sm">
            <tbody>
              <tr
                :for={ticket <- @recent_tickets}
                class="border-b border-base-300/50 last:border-0 hover:bg-base-200/50"
              >
                <td class="px-4 py-2.5">
                  <.link
                    navigate={~p"/tickets/#{ticket.id}?from=/"}
                    class="text-primary hover:underline font-medium"
                  >
                    {ticket.subject}
                  </.link>
                  <p class="text-xs text-base-content/40 mt-0.5">
                    {ticket.customer_email || "No email"} · {relative_time(ticket.inserted_at)}
                  </p>
                </td>
                <td class="px-4 py-2.5 text-right">
                  <.state_pill state={ticket.state} />
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div class="space-y-4">
          <div class="bg-base-100 rounded-lg border border-base-300 p-4">
            <h2 class="text-sm font-semibold text-base-content mb-3">System Health</h2>
            <div class="space-y-2">
              <.health_row :for={{name, status} <- @health} name={name} state={status.state} />
            </div>
          </div>

          <div class="bg-base-100 rounded-lg border border-base-300 p-4">
            <h2 class="text-sm font-semibold text-base-content mb-3">Quick Actions</h2>
            <div class="space-y-1.5">
              <.link
                navigate={~p"/simulator"}
                class="flex items-center gap-2 text-sm text-base-content/70 hover:text-base-content py-1"
              >
                <.icon name="hero-plus-circle" class="size-4 text-primary" /> Create Ticket
              </.link>
              <.link
                navigate={~p"/rules"}
                class="flex items-center gap-2 text-sm text-base-content/70 hover:text-base-content py-1"
              >
                <.icon name="hero-bolt" class="size-4 text-primary" /> Automation Rules
              </.link>
              <.link
                navigate={~p"/settings"}
                class="flex items-center gap-2 text-sm text-base-content/70 hover:text-base-content py-1"
              >
                <.icon name="hero-key" class="size-4 text-primary" /> Configure Credentials
              </.link>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :icon, :string, required: true
  attr :href, :string, required: true
  attr :variant, :string, required: true

  defp metric_card(assigns) do
    variant_classes = %{
      "info" => "text-info",
      "error" => "text-error",
      "success" => "text-success",
      "accent" => "text-accent"
    }

    assigns =
      assign(
        assigns,
        :variant_class,
        Map.get(variant_classes, assigns.variant, "text-base-content")
      )

    ~H"""
    <.link
      navigate={@href}
      class="bg-base-100 rounded-lg border border-base-300 p-4 hover:border-primary/30 transition group block"
    >
      <div class="flex items-center justify-between mb-1">
        <span class="text-xs text-base-content/50">{@label}</span>
        <.icon name={@icon} class={["size-4 opacity-60", @variant_class]} />
      </div>
      <p class={["text-2xl font-bold", @variant_class]}>{@value}</p>
    </.link>
    """
  end
end
