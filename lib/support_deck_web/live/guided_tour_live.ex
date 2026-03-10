defmodule SupportDeckWeb.GuidedTourLive do
  use SupportDeckWeb, :live_view
  alias SupportDeckWeb.ErrorHelpers

  @steps [
    %{
      title: "1. Create a Support Ticket",
      description:
        "Create a new ticket and watch it appear in the queue in real time. Tickets track their full lifecycle from creation through resolution.",
      action_label: "Create Ticket",
      result_link: "/tickets",
      result_link_label: "View in Queue"
    },
    %{
      title: "2. Trigger AI Triage",
      description:
        "Run AI classification on a ticket to predict its category, severity, and confidence score. Falls back to keyword matching if the AI service is unavailable.",
      action_label: "Run AI Triage",
      result_link: "/tickets",
      result_link_label: "View Tickets"
    },
    %{
      title: "3. Evaluate Automation Rules",
      description:
        "Check all enabled rules against the ticket. Matching rules automatically execute actions like assigning, escalating, or sending notifications.",
      action_label: "Check Rules",
      result_link: "/rules",
      result_link_label: "View Rules"
    },
    %{
      title: "4. SLA Deadline Tracking",
      description:
        "Monitor response and resolution deadlines. Tickets approaching or past their SLA targets are flagged and can trigger automatic escalation.",
      action_label: "Check SLA Status",
      result_link: "/sla",
      result_link_label: "View SLA Dashboard"
    },
    %{
      title: "5. Integrations & Credentials",
      description:
        "Connect to external services like Front, Slack, and Linear. API keys are encrypted at rest. Each integration has health monitoring and automatic recovery from failures.",
      action_label: "Check Integrations",
      result_link: "/integrations",
      result_link_label: "View Integrations"
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
    statuses =
      Enum.map([:front, :slack, :linear], fn name ->
        status = SupportDeck.Integrations.CircuitBreaker.get_status(name)

        label =
          case status.state do
            :closed -> "healthy"
            :open -> "failing"
            :half_open -> "recovering"
            _ -> "unknown"
          end

        "#{name}: #{label}"
      end)

    configured =
      Enum.count([:front, :slack, :linear, :openai], fn name ->
        SupportDeck.Settings.Resolver.integration_status(name) == :configured
      end)

    "#{configured}/4 integrations configured — #{Enum.join(statuses, ", ")}"
  end

  @impl true
  def render(assigns) do
    step = Enum.at(assigns.steps, assigns.current_step)
    assigns = assign(assigns, :step, step)

    ~H"""
    <div class="max-w-4xl mx-auto px-6 py-6">
      <.page_header
        title="Guided Tour"
        description="Interactive walkthrough of SupportDeck's key features."
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
