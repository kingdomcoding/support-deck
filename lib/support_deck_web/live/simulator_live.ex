defmodule SupportDeckWeb.SimulatorLive do
  use SupportDeckWeb, :live_view
  alias SupportDeckWeb.ErrorHelpers

  @impl true
  def mount(_params, _session, socket) do
    tickets =
      case SupportDeck.Tickets.list_open_tickets() do
        {:ok, t} -> t
        _ -> []
      end

    {:ok,
     socket
     |> assign(:page_title, "Simulator")
     |> assign(:current_path, ~p"/simulator")
     |> assign(:tickets, tickets)
     |> assign(:ticket_form, default_ticket_form())
     |> assign(:webhook_form, %{"source" => "front", "payload" => "{\n  \n}"})
     |> assign(:triage_ticket_id, nil)
     |> assign(:result, nil)}
  end

  defp default_ticket_form do
    %{
      "subject" => "",
      "body" => "",
      "source" => "manual",
      "severity" => "medium",
      "subscription_tier" => "pro",
      "customer_email" => "",
      "external_id" => "sim-#{System.unique_integer([:positive])}"
    }
  end

  @impl true
  def handle_event("create_ticket", params, socket) do
    attrs = %{
      external_id: params["external_id"],
      source: String.to_existing_atom(params["source"]),
      body: params["body"],
      severity: String.to_existing_atom(params["severity"]),
      subscription_tier: String.to_existing_atom(params["subscription_tier"]),
      customer_email: if(params["customer_email"] != "", do: params["customer_email"])
    }

    case SupportDeck.Tickets.open_ticket(params["subject"], attrs) do
      {:ok, ticket} ->
        tickets = [ticket | socket.assigns.tickets]

        {:noreply,
         socket
         |> assign(:tickets, tickets)
         |> assign(:ticket_form, default_ticket_form())
         |> assign(:result, {:ok, "Ticket created: #{ticket.subject} (#{ticket.id})"})}

      {:error, err} ->
        {:noreply,
         assign(socket, :result, {:error, "Create failed: #{ErrorHelpers.format_error(err)}"})}
    end
  end

  def handle_event("send_webhook", params, socket) do
    source = params["source"]
    payload = params["payload"]

    case Jason.decode(payload) do
      {:ok, decoded} ->
        port =
          Application.get_env(:support_deck, SupportDeckWeb.Endpoint)[:http][:port] || 4500

        url = "http://localhost:#{port}/webhooks/#{source}"

        case Req.post(url, json: decoded) do
          {:ok, %{status: status}} ->
            {:noreply,
             assign(
               socket,
               :result,
               {:ok, "Webhook sent to /webhooks/#{source} — HTTP #{status}"}
             )}

          {:error, err} ->
            {:noreply, assign(socket, :result, {:error, "Webhook failed: #{inspect(err)}"})}
        end

      {:error, %Jason.DecodeError{} = err} ->
        {:noreply, assign(socket, :result, {:error, "Invalid JSON: #{Exception.message(err)}"})}
    end
  end

  def handle_event("trigger_triage", %{"ticket_id" => ""}, socket) do
    {:noreply, assign(socket, :result, {:error, "Select a ticket first"})}
  end

  def handle_event("trigger_triage", %{"ticket_id" => ticket_id}, socket) do
    case Oban.insert(SupportDeck.Workers.AITriageWorker.new(%{ticket_id: ticket_id})) do
      {:ok, _} ->
        {:noreply,
         assign(
           socket,
           :result,
           {:ok, "AI triage job queued for ticket #{String.slice(ticket_id, 0..7)}..."}
         )}

      {:error, err} ->
        {:noreply,
         assign(socket, :result, {:error, "Queue failed: #{ErrorHelpers.format_error(err)}"})}
    end
  end

  def handle_event("check_sla", _, socket) do
    case SupportDeck.Tickets.list_breaching_sla() do
      {:ok, tickets} ->
        {:noreply,
         assign(
           socket,
           :result,
           {:ok, "SLA check complete: #{length(tickets)} ticket(s) breaching"}
         )}

      {:error, err} ->
        {:noreply,
         assign(socket, :result, {:error, "SLA check failed: #{ErrorHelpers.format_error(err)}"})}
    end
  end

  def handle_event("trip_breaker", %{"integration" => integration}, socket) do
    name = String.to_existing_atom(integration)

    Enum.each(1..5, fn _ ->
      SupportDeck.Integrations.CircuitBreaker.call(name, fn -> {:error, :simulated_failure} end)
    end)

    status = SupportDeck.Integrations.CircuitBreaker.get_status(name)

    {:noreply,
     assign(
       socket,
       :result,
       {:ok, "#{integration} breaker state: #{status.state} (failures: #{status.failures})"}
     )}
  end

  def handle_event("reset_breaker", %{"integration" => integration}, socket) do
    name = String.to_existing_atom(integration)
    SupportDeck.Integrations.CircuitBreaker.reset(name)
    {:noreply, assign(socket, :result, {:ok, "#{integration} breaker reset to closed"})}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto px-6 py-6">
      <.page_header
        title="Simulator"
        description="Test the entire pipeline — create tickets, fire webhooks, run AI triage, and trip circuit breakers."
        patterns={["Dev tooling", "Webhook pipeline", "Oban workers"]}
      />

      <div
        :if={@result}
        class={[
          "mb-6 p-4 rounded-lg border",
          elem(@result, 0) == :ok && "bg-success/10 border-success/30",
          elem(@result, 0) != :ok && "bg-error/10 border-error/30"
        ]}
      >
        <p class={[
          "text-sm",
          elem(@result, 0) == :ok && "text-success",
          elem(@result, 0) != :ok && "text-error"
        ]}>
          {elem(@result, 1)}
        </p>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div class="bg-base-100 rounded-lg border border-base-300 p-6">
          <h2 class="text-lg font-semibold text-base-content mb-4">Create Ticket</h2>
          <form phx-submit="create_ticket" class="space-y-3">
            <div>
              <label class="block text-sm font-medium text-base-content/80 mb-1">Subject</label>
              <input
                type="text"
                name="subject"
                value={@ticket_form["subject"]}
                required
                class="w-full px-3 py-2 border border-base-300 rounded-lg text-sm bg-base-100"
              />
            </div>
            <div>
              <label class="block text-sm font-medium text-base-content/80 mb-1">Body</label>
              <textarea
                name="body"
                rows="3"
                class="w-full px-3 py-2 border border-base-300 rounded-lg text-sm bg-base-100"
              >{@ticket_form["body"]}</textarea>
            </div>
            <div class="grid grid-cols-2 gap-3">
              <div>
                <label class="block text-sm font-medium text-base-content/80 mb-1">Source</label>
                <select
                  name="source"
                  class="w-full px-3 py-2 border border-base-300 rounded-lg text-sm bg-base-100"
                >
                  <option :for={s <- [:manual, :front, :slack]} value={s}>{s}</option>
                </select>
              </div>
              <div>
                <label class="block text-sm font-medium text-base-content/80 mb-1">Severity</label>
                <select
                  name="severity"
                  class="w-full px-3 py-2 border border-base-300 rounded-lg text-sm bg-base-100"
                >
                  <option
                    :for={s <- [:low, :medium, :high, :critical]}
                    value={s}
                    selected={to_string(s) == @ticket_form["severity"]}
                  >
                    {s}
                  </option>
                </select>
              </div>
            </div>
            <div class="grid grid-cols-2 gap-3">
              <div>
                <label class="block text-sm font-medium text-base-content/80 mb-1">Tier</label>
                <select
                  name="subscription_tier"
                  class="w-full px-3 py-2 border border-base-300 rounded-lg text-sm bg-base-100"
                >
                  <option
                    :for={t <- [:free, :pro, :team, :enterprise]}
                    value={t}
                    selected={to_string(t) == @ticket_form["subscription_tier"]}
                  >
                    {t}
                  </option>
                </select>
              </div>
              <div>
                <label class="block text-sm font-medium text-base-content/80 mb-1">
                  Customer Email
                </label>
                <input
                  type="email"
                  name="customer_email"
                  value={@ticket_form["customer_email"]}
                  class="w-full px-3 py-2 border border-base-300 rounded-lg text-sm bg-base-100"
                />
              </div>
            </div>
            <div>
              <label class="block text-sm font-medium text-base-content/80 mb-1">External ID</label>
              <input
                type="text"
                name="external_id"
                value={@ticket_form["external_id"]}
                required
                class="w-full px-3 py-2 border border-base-300 rounded-lg text-sm bg-base-100"
              />
            </div>
            <button
              type="submit"
              class="w-full px-4 py-2 text-sm bg-primary text-primary-content rounded-lg hover:bg-primary/90"
              phx-disable-with="Creating..."
            >
              Create Ticket
            </button>
          </form>
        </div>

        <div class="space-y-6">
          <div class="bg-base-100 rounded-lg border border-base-300 p-6">
            <h2 class="text-lg font-semibold text-base-content mb-4">Webhook Simulation</h2>
            <form phx-submit="send_webhook" class="space-y-3">
              <div>
                <label class="block text-sm font-medium text-base-content/80 mb-1">Source</label>
                <select
                  name="source"
                  class="w-full px-3 py-2 border border-base-300 rounded-lg text-sm bg-base-100"
                >
                  <option :for={s <- [:front, :slack, :linear]} value={s}>{s}</option>
                </select>
              </div>
              <div>
                <label class="block text-sm font-medium text-base-content/80 mb-1">
                  Payload (JSON)
                </label>
                <textarea
                  name="payload"
                  rows="4"
                  class="w-full px-3 py-2 border border-base-300 rounded-lg text-sm font-mono bg-base-100"
                >{@webhook_form["payload"]}</textarea>
              </div>
              <button
                type="submit"
                class="w-full px-4 py-2 text-sm bg-primary text-primary-content rounded-lg hover:bg-primary/90"
                phx-disable-with="Sending..."
              >
                Send Webhook
              </button>
            </form>
          </div>

          <div class="bg-base-100 rounded-lg border border-base-300 p-6">
            <h2 class="text-lg font-semibold text-base-content mb-4">AI Triage</h2>
            <form phx-submit="trigger_triage" class="space-y-3">
              <div>
                <label class="block text-sm font-medium text-base-content/80 mb-1">
                  Select Ticket
                </label>
                <select
                  name="ticket_id"
                  class="w-full px-3 py-2 border border-base-300 rounded-lg text-sm bg-base-100"
                >
                  <option value="">Choose a ticket...</option>
                  <option :for={t <- @tickets} value={t.id}>{t.subject}</option>
                </select>
              </div>
              <button
                type="submit"
                class="w-full px-4 py-2 text-sm bg-secondary text-secondary-content rounded-lg hover:bg-secondary/90"
                phx-disable-with="Queuing..."
              >
                Run AI Triage
              </button>
            </form>
          </div>

          <div class="bg-base-100 rounded-lg border border-base-300 p-6">
            <h2 class="text-lg font-semibold text-base-content mb-4">SLA Check</h2>
            <button
              phx-click="check_sla"
              phx-disable-with="Checking..."
              class="w-full px-4 py-2 text-sm bg-warning text-warning-content rounded-lg hover:bg-warning/90"
            >
              Run SLA Check
            </button>
          </div>

          <div class="bg-base-100 rounded-lg border border-base-300 p-6">
            <h2 class="text-lg font-semibold text-base-content mb-4">Circuit Breakers</h2>
            <div class="space-y-2">
              <div
                :for={integration <- [:front, :slack, :linear]}
                class="flex items-center justify-between"
              >
                <span class="text-sm font-medium text-base-content/80 capitalize">
                  {integration}
                </span>
                <div class="flex gap-2">
                  <button
                    phx-click="trip_breaker"
                    phx-value-integration={integration}
                    data-confirm="Trip this circuit breaker?"
                    class="px-3 py-1 text-xs bg-error/15 text-error rounded hover:bg-error/25"
                  >
                    Trip
                  </button>
                  <button
                    phx-click="reset_breaker"
                    phx-value-integration={integration}
                    class="px-3 py-1 text-xs bg-success/15 text-success rounded hover:bg-success/25"
                  >
                    Reset
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
