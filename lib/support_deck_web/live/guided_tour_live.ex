defmodule SupportDeckWeb.GuidedTourLive do
  use SupportDeckWeb, :live_view
  alias SupportDeckWeb.ErrorHelpers

  @steps [
    %{
      title: "1. Create a Support Ticket",
      description:
        "Watch how Ash resources, AshStateMachine, and PubSub work together. A ticket is created with a state machine lifecycle that tracks it from 'new' through 'resolved'.",
      action_label: "Create Ticket",
      result_link: "/tickets",
      result_link_label: "View in Queue",
      patterns: ["Ash.Resource", "AshStateMachine", "create action", "PubSub broadcast"]
    },
    %{
      title: "2. Trigger AI Triage",
      description:
        "An Oban worker picks up the ticket, calls the AI provider (or simulates classification), and records a triage result with predicted category, severity, and confidence score.",
      action_label: "Run AI Triage",
      result_link: "/tickets",
      result_link_label: "View Tickets",
      patterns: ["Oban worker", "Prompt-backed action", "AI classification"]
    },
    %{
      title: "3. Evaluate Automation Rules",
      description:
        "The rule engine checks all enabled rules against the ticket. Matching rules dispatch Oban jobs to execute actions like auto-assign, escalate, or notify.",
      action_label: "Check Rules",
      result_link: "/rules",
      result_link_label: "View Rules",
      patterns: ["Rule engine", "Condition matching", "Oban dispatch"]
    },
    %{
      title: "4. SLA Deadline Tracking",
      description:
        "AshOban scheduled triggers periodically check for tickets approaching or past their SLA deadlines. Breaching tickets are flagged and can trigger escalation rules.",
      action_label: "Check SLA Status",
      result_link: "/sla",
      result_link_label: "View SLA Dashboard",
      patterns: ["AshOban triggers", "SLA Buddy pattern", "Scheduled workers"]
    },
    %{
      title: "5. Circuit Breaker Fault Tolerance",
      description:
        "Each integration (Front, Slack, Linear) has a GenServer-backed circuit breaker. After consecutive failures it 'trips', stopping requests. It auto-recovers with a half-open probe.",
      action_label: "Trip Front Breaker",
      result_link: "/integrations",
      result_link_label: "View Health",
      patterns: ["GenServer", "ETS state", "Circuit breaker pattern"]
    },
    %{
      title: "6. Encrypted Credential Vault",
      description:
        "API keys are encrypted with AES-256-GCM before storage. A GenServer resolver decrypts on demand and caches in ETS for performance.",
      action_label: "View Vault",
      result_link: "/settings",
      result_link_label: "View Settings",
      patterns: ["AES-256-GCM", "GenServer", "ETS cache"]
    }
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Guided Tour")
     |> assign(:current_path, ~p"/tour")
     |> assign(:current_step, 0)
     |> assign(:steps, @steps)
     |> assign(:result, nil)}
  end

  @impl true
  def handle_event("go_to", %{"step" => step}, socket) do
    {:noreply, socket |> assign(:current_step, String.to_integer(step)) |> assign(:result, nil)}
  end

  def handle_event("prev", _, socket) do
    {:noreply,
     socket
     |> assign(:current_step, max(0, socket.assigns.current_step - 1))
     |> assign(:result, nil)}
  end

  def handle_event("next", _, socket) do
    {:noreply,
     socket
     |> assign(:current_step, min(length(@steps) - 1, socket.assigns.current_step + 1))
     |> assign(:result, nil)}
  end

  def handle_event("run_step", _, socket) do
    result = execute_step(socket.assigns.current_step)
    {:noreply, assign(socket, :result, result)}
  end

  @impl true
  def handle_info(_, socket), do: {:noreply, socket}

  defp execute_step(0) do
    case SupportDeck.Tickets.open_ticket(
           "Tour Test Ticket",
           %{
             external_id: "tour-#{System.unique_integer([:positive])}",
             source: :manual,
             body: "Created during guided tour",
             severity: :medium,
             subscription_tier: :pro
           }
         ) do
      {:ok, ticket} -> "Ticket created: #{ticket.subject} (state: #{ticket.state})"
      {:error, err} -> "Error: #{ErrorHelpers.format_error(err)}"
    end
  end

  defp execute_step(1) do
    case SupportDeck.Tickets.list_open_tickets() do
      {:ok, [ticket | _]} ->
        SupportDeck.Workers.AITriageWorker.new(%{ticket_id: ticket.id}) |> Oban.insert()
        "AI triage queued for ticket: #{ticket.subject}"

      _ ->
        "No tickets available — create one first (step 1)"
    end
  end

  defp execute_step(2) do
    case SupportDeck.Tickets.list_all_rules() do
      {:ok, rules} ->
        enabled = Enum.filter(rules, & &1.enabled)
        "Found #{length(rules)} rules (#{length(enabled)} enabled)"

      _ ->
        "No rules configured yet"
    end
  end

  defp execute_step(3) do
    case SupportDeck.Tickets.list_breaching_sla() do
      {:ok, tickets} -> "#{length(tickets)} tickets currently breaching SLA"
      _ -> "SLA check complete — no breaches found"
    end
  end

  defp execute_step(4) do
    Enum.each(1..5, fn _ ->
      SupportDeck.Integrations.CircuitBreaker.call(:front, fn -> {:error, :simulated_failure} end)
    end)

    status = SupportDeck.Integrations.CircuitBreaker.get_status(:front)
    "Front circuit breaker state: #{status.state} (tripped after simulated failures)"
  end

  defp execute_step(5) do
    "Credential vault uses AES-256-GCM encryption — visit Settings to manage API keys"
  end

  @impl true
  def render(assigns) do
    step = Enum.at(assigns.steps, assigns.current_step)
    assigns = assign(assigns, :step, step)

    ~H"""
    <div class="max-w-4xl mx-auto px-6 py-6">
      <.page_header
        title="Guided Tour"
        description="Interactive walkthrough of SupportDeck's key features and Ash patterns."
        patterns={["Interactive walkthrough", "Domain API calls"]}
      />

      <div class="flex gap-2 mb-6">
        <button
          :for={{_s, i} <- Enum.with_index(@steps)}
          phx-click="go_to"
          phx-value-step={i}
          class={[
            "flex-1 h-2 rounded-full transition",
            i == @current_step && "bg-primary",
            i < @current_step && "bg-primary/40",
            i > @current_step && "bg-base-300"
          ]}
        />
      </div>

      <div class="bg-base-100 rounded-lg border border-base-300 p-6 mb-6">
        <div class="flex items-center gap-3 mb-3">
          <div class="w-8 h-8 rounded-full bg-primary/15 text-primary flex items-center justify-center text-sm font-bold">
            {@current_step + 1}
          </div>
          <h2 class="text-lg font-semibold text-base-content">{@step.title}</h2>
        </div>
        <p class="text-sm text-base-content/70 mb-4 leading-relaxed">{@step.description}</p>

        <div class="flex flex-wrap gap-1 mb-4">
          <span
            :for={p <- @step.patterns}
            class="px-1.5 py-0.5 text-[10px] font-medium rounded bg-base-content/5 text-base-content/40"
          >
            {p}
          </span>
        </div>

        <div class="flex items-center gap-3">
          <button
            phx-click="run_step"
            phx-disable-with="Running..."
            class="px-4 py-2 bg-primary text-primary-content rounded-lg hover:bg-primary/90 inline-flex items-center gap-1.5 text-sm"
          >
            <.icon name="hero-play" class="size-3.5" /> {@step.action_label}
          </button>
          <.link
            :if={@result}
            navigate={@step.result_link}
            class="px-3 py-1.5 text-sm text-primary hover:text-primary/80 inline-flex items-center gap-1.5"
          >
            {@step.result_link_label} <.icon name="hero-arrow-right" class="size-3.5" />
          </.link>
        </div>

        <div :if={@result} class="mt-4 p-3 bg-success/10 rounded-lg border border-success/20">
          <p class="text-sm text-success font-medium">{@result}</p>
        </div>
      </div>

      <div class="flex justify-between">
        <button
          :if={@current_step > 0}
          phx-click="prev"
          class="px-4 py-2 text-sm text-base-content/60 border border-base-300 rounded-lg hover:bg-base-200"
        >
          &larr; Previous
        </button>
        <div :if={@current_step == 0} />
        <button
          :if={@current_step < length(@steps) - 1}
          phx-click="next"
          class="px-4 py-2 text-sm bg-primary text-primary-content rounded-lg hover:bg-primary/90"
        >
          Next &rarr;
        </button>
      </div>
    </div>
    """
  end
end
