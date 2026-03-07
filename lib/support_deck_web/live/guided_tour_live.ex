defmodule SupportDeckWeb.GuidedTourLive do
  use SupportDeckWeb, :live_view
  alias SupportDeckWeb.ErrorHelpers

  @steps [
    %{
      title: "Create a Ticket",
      description: "Create a support ticket manually to see the Ash resource in action.",
      patterns: ["Ash.Resource", "AshStateMachine", "create action"]
    },
    %{
      title: "AI Triage",
      description: "Trigger AI classification on a ticket to see prompt-backed actions.",
      patterns: ["AshAI", "Oban worker", "prompt-backed action"]
    },
    %{
      title: "Rule Evaluation",
      description: "Watch the rule engine evaluate conditions and dispatch actions.",
      patterns: ["Rule engine", "Condition matching", "Oban"]
    },
    %{
      title: "SLA Tracking",
      description: "See SLA deadlines, breach detection, and escalation in action.",
      patterns: ["AshOban triggers", "SLA Buddy pattern"]
    },
    %{
      title: "Webhook Simulation",
      description: "Send a simulated webhook payload and watch it process.",
      patterns: ["Plug pipeline", "Signature verification", "Oban"]
    },
    %{
      title: "Knowledge Search",
      description: "Search the knowledge base to see Ash read actions.",
      patterns: ["Ash read actions", "Filtering"]
    },
    %{
      title: "Circuit Breaker",
      description: "Trip and reset a circuit breaker to see fault tolerance.",
      patterns: ["GenServer", "ETS", "Circuit breaker pattern"]
    }
  ]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(SupportDeck.PubSub, "tickets:updates")
    end

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
             body: "Created during guided tour"
           }
         ) do
      {:ok, ticket} -> "Ticket created: #{ticket.subject} (#{ticket.id})"
      {:error, err} -> "Error: #{ErrorHelpers.format_error(err)}"
    end
  end

  defp execute_step(1), do: "AI triage would classify the ticket (requires AI API keys)"

  defp execute_step(2) do
    case SupportDeck.Tickets.list_all_rules() do
      {:ok, rules} ->
        "Found #{length(rules)} rules (#{length(Enum.filter(rules, & &1.enabled))} enabled)"

      _ ->
        "No rules configured yet"
    end
  end

  defp execute_step(3) do
    case SupportDeck.Tickets.list_breaching_sla() do
      {:ok, tickets} -> "#{length(tickets)} tickets currently breaching SLA"
      _ -> "No SLA breaches"
    end
  end

  defp execute_step(4), do: "Webhook simulation available in the Simulator page"

  defp execute_step(5) do
    case SupportDeck.AI.list_all_knowledge_docs() do
      {:ok, docs} -> "Knowledge base has #{length(docs)} documents"
      _ -> "Knowledge base is empty"
    end
  end

  defp execute_step(6) do
    status = SupportDeck.Integrations.CircuitBreaker.get_status(:front)
    "Front circuit breaker state: #{inspect(status.state)}"
  end

  @impl true
  def render(assigns) do
    step = Enum.at(assigns.steps, assigns.current_step)
    assigns = assign(assigns, :step, step)

    ~H"""
    <div class="max-w-4xl mx-auto px-6 py-6">
      <.tech_banner patterns={["Interactive walkthrough", "PubSub events", "Domain API calls"]} />

      <h1 class="text-2xl font-bold text-base-content mb-6">Guided Tour</h1>

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
        <div class="flex items-center gap-2 mb-2">
          <span class="text-sm font-medium text-primary">
            Step {@current_step + 1} of {length(@steps)}
          </span>
        </div>
        <h2 class="text-xl font-semibold text-base-content mb-2">{@step.title}</h2>
        <p class="text-base-content/60 mb-4">{@step.description}</p>

        <div class="flex flex-wrap gap-1.5 mb-4">
          <span
            :for={p <- @step.patterns}
            class="px-2 py-0.5 text-[11px] font-medium rounded-full bg-primary/10 text-primary border border-primary/20"
          >
            {p}
          </span>
        </div>

        <button
          phx-click="run_step"
          class="px-4 py-2 bg-primary text-primary-content rounded-lg hover:bg-primary/90"
        >
          Run This Step
        </button>

        <div :if={@result} class="mt-4 p-3 bg-base-200 rounded-lg border border-base-300">
          <p class="text-sm text-base-content/80 font-mono">{@result}</p>
        </div>
      </div>

      <div class="flex justify-between">
        <button
          :if={@current_step > 0}
          phx-click="prev"
          class="px-4 py-2 text-base-content/60 border border-base-300 rounded-lg hover:bg-base-200"
        >
          &larr; Previous
        </button>
        <div :if={@current_step == 0} />
        <button
          :if={@current_step < length(@steps) - 1}
          phx-click="next"
          class="px-4 py-2 bg-primary text-primary-content rounded-lg hover:bg-primary/90"
        >
          Next &rarr;
        </button>
      </div>
    </div>
    """
  end
end
