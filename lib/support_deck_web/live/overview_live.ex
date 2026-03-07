defmodule SupportDeckWeb.OverviewLive do
  use SupportDeckWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(SupportDeck.PubSub, "tickets:updates")
    end

    stats = load_stats()

    {:ok,
     socket
     |> assign(:page_title, "Overview")
     |> assign(:current_path, ~p"/")
     |> assign(:stats, stats)}
  end

  @impl true
  def handle_info({:ticket_created, _}, socket) do
    {:noreply, assign(socket, :stats, load_stats())}
  end

  def handle_info({:ticket_updated, _}, socket) do
    {:noreply, assign(socket, :stats, load_stats())}
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

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto px-6 py-6">
      <.tech_banner
        patterns={["Phoenix LiveView", "PubSub real-time", "Ash Domain queries"]}
        description="Landing page with live system metrics"
      />

      <div class="mb-8">
        <h1 class="text-3xl font-bold text-base-content">SupportDeck</h1>
        <p class="mt-2 text-base-content/60">Internal support tooling platform built with Ash Framework</p>
      </div>

      <div class="mb-6">
        <a
          href={~p"/tour"}
          class="inline-flex items-center gap-2 px-4 py-2 bg-primary text-primary-content rounded-lg hover:bg-primary/90"
        >
          <.icon name="hero-map" class="size-5" /> Take the Guided Tour
        </a>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-8">
        <.stat_card label="Open Tickets" value={@stats.open_tickets} color="blue" />
        <.stat_card label="SLA Breaches" value={@stats.sla_breaches} color="red" />
        <.stat_card label="Active Rules" value={@stats.active_rules} color="green" />
        <.stat_card label="AI Triages (24h)" value={@stats.ai_triages_24h} color="purple" />
      </div>

      <h2 class="text-xl font-semibold text-base-content mb-4">Feature Map</h2>
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
        <.feature_card
          title="Ticket Queue"
          href={~p"/tickets"}
          description="Real-time ticket management with state machine"
          patterns={["AshStateMachine", "PubSub"]}
        />
        <.feature_card
          title="SLA Dashboard"
          href={~p"/sla"}
          description="SLA breach tracking with countdown timers"
          patterns={["AshOban triggers", "SLA Buddy"]}
        />
        <.feature_card
          title="AI Triage"
          href={~p"/ai"}
          description="Automated classification and response drafting"
          patterns={["Prompt-backed actions"]}
        />
        <.feature_card
          title="Rules Engine"
          href={~p"/rules"}
          description="Configurable automation rules"
          patterns={["Condition matching", "Oban workers"]}
        />
        <.feature_card
          title="Knowledge Base"
          href={~p"/knowledge"}
          description="Searchable support documentation"
          patterns={["Ash resources"]}
        />
        <.feature_card
          title="Integrations"
          href={~p"/integrations"}
          description="Front, Slack, Linear with circuit breakers"
          patterns={["Circuit breaker", "Req"]}
        />
        <.feature_card
          title="Settings"
          href={~p"/settings"}
          description="Credential vault with AES-256-GCM encryption"
          patterns={["GenServer", "ETS cache"]}
        />
        <.feature_card
          title="Simulator"
          href={~p"/simulator"}
          description="Test webhooks, AI triage, and SLA checks"
          patterns={["Dev tooling"]}
        />
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :color, :string, required: true

  defp stat_card(assigns) do
    color_classes = %{
      "blue" => "text-info",
      "red" => "text-error",
      "green" => "text-success",
      "purple" => "text-secondary"
    }

    assigns =
      assign(assigns, :color_class, Map.get(color_classes, assigns.color, "text-base-content/60"))

    ~H"""
    <div class="bg-base-100 rounded-lg border border-base-300 p-4">
      <p class="text-sm text-base-content/60">{@label}</p>
      <p class={["text-2xl font-bold", @color_class]}>{@value}</p>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :href, :string, required: true
  attr :description, :string, required: true
  attr :patterns, :list, required: true

  defp feature_card(assigns) do
    ~H"""
    <a
      href={@href}
      class="block bg-base-100 rounded-lg border border-base-300 p-4 hover:border-primary/30 hover:shadow-sm transition"
    >
      <h3 class="font-medium text-base-content">{@title}</h3>
      <p class="text-sm text-base-content/60 mt-1">{@description}</p>
      <div class="flex flex-wrap gap-1 mt-2">
        <span
          :for={p <- @patterns}
          class="px-2 py-0.5 text-[11px] rounded-full bg-primary/10 text-primary border border-primary/20"
        >
          {p}
        </span>
      </div>
    </a>
    """
  end
end
