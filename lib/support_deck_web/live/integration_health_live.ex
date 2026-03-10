defmodule SupportDeckWeb.IntegrationHealthLive do
  use SupportDeckWeb, :live_view
  alias SupportDeckWeb.ErrorHelpers
  alias SupportDeck.Integrations.CircuitBreaker
  alias SupportDeck.Settings.Resolver

  @integrations [
    {:front, "Ticket ingestion via webhooks",
     [api_token: "API Token", webhook_secret: "Webhook Secret"]},
    {:slack, "Notifications and escalations",
     [bot_token: "Bot Token", signing_secret: "Signing Secret"]},
    {:linear, "Issue sync and escalation",
     [api_key: "API Key", webhook_secret: "Webhook Secret"]},
    {:openai, "AI triage and draft responses", [api_key: "API Key"]}
  ]

  @breaker_integrations [:front, :slack, :linear]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: schedule_refresh(socket)

    {:ok,
     socket
     |> assign(:page_title, "Integrations")
     |> assign(:current_path, ~p"/integrations")
     |> assign(:integrations, @integrations)
     |> assign(:breaker_integrations, @breaker_integrations)
     |> assign(:testing, nil)
     |> assign(:test_results, %{})
     |> assign(:webhook_results, %{})
     |> assign(:breaker_results, %{})
     |> load_credentials()
     |> load_statuses()
     |> load_rules_and_linear_ticket()
     |> load_webhook_events()
     |> compute_breaker_display()}
  end

  # Credential events

  @impl true
  def handle_event("save_credentials", %{"integration" => integration} = params, socket) do
    name = String.to_existing_atom(integration)
    credentials = params["credentials"] || %{}

    non_empty =
      Enum.filter(credentials, fn {_key, value} -> value != "" end)

    if non_empty == [] do
      {:noreply, put_flash(socket, :error, "Enter at least one credential value")}
    else
      results =
        Enum.map(non_empty, fn {key_name, value} ->
          key_atom = String.to_existing_atom(key_name)

          result =
            SupportDeck.Settings.store_credential(%{
              integration: name,
              key_name: key_atom,
              plaintext_value: value
            })

          if match?({:ok, _}, result), do: Resolver.reload_credential(name, key_atom)
          result
        end)

      case Enum.find(results, fn r -> match?({:error, _}, r) end) do
        nil ->
          {:noreply,
           socket
           |> put_flash(:info, "Credentials saved")
           |> load_credentials()
           |> load_statuses()
           |> compute_breaker_display()}

        {:error, err} ->
          {:noreply,
           put_flash(socket, :error, "Save failed: #{ErrorHelpers.format_error(err)}")}
      end
    end
  end

  def handle_event("test_connection", %{"integration" => integration}, socket) do
    name = String.to_existing_atom(integration)
    socket = assign(socket, :testing, name)

    result =
      case SupportDeck.Settings.ConnectionTester.test(name) do
        {:ok, message} ->
          update_test_results(name, :ok, message)
          {:ok, message}

        {:error, message} ->
          update_test_results(name, :error, message)
          {:error, message}
      end

    {:noreply,
     socket
     |> assign(:testing, nil)
     |> update(:test_results, &Map.put(&1, name, result))
     |> load_credentials()}
  end

  def handle_event("delete_credential", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.credentials, &(&1.id == id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "Credential not found")}

      credential ->
        case SupportDeck.Settings.delete_credential(credential) do
          :ok ->
            Resolver.invalidate_credential(credential.integration, credential.key_name)

            {:noreply,
             socket
             |> put_flash(:info, "Credential deleted")
             |> load_credentials()
             |> load_statuses()
             |> compute_breaker_display()}

          {:error, err} ->
            {:noreply,
             put_flash(socket, :error, "Delete failed: #{ErrorHelpers.format_error(err)}")}
        end
    end
  end

  # Circuit breaker events

  def handle_event("reset_breaker", %{"name" => name}, socket) do
    integration = String.to_existing_atom(name)
    CircuitBreaker.reset(integration)

    {:noreply,
     socket
     |> update(:breaker_results, &Map.put(&1, integration,
       {:reset, System.monotonic_time(:millisecond)}))
     |> load_statuses()
     |> compute_breaker_display()}
  end

  def handle_event("trip_breaker", %{"name" => name}, socket) do
    integration = String.to_existing_atom(name)

    for _ <- 1..5 do
      CircuitBreaker.call(integration, fn -> {:error, :simulated_failure} end)
    end

    {:noreply,
     socket
     |> update(:breaker_results, &Map.put(&1, integration,
       {:tripped, System.monotonic_time(:millisecond)}))
     |> load_statuses()
     |> compute_breaker_display()}
  end

  # Webhook test

  def handle_event("send_webhook", %{"source" => source, "payload" => payload}, socket) do
    source_atom = String.to_existing_atom(source)

    result =
      case Jason.decode(payload) do
        {:ok, decoded} ->
          url = "#{SupportDeckWeb.Endpoint.url()}/webhooks/#{source}"

          case Req.post(url, json: decoded) do
            {:ok, %{status: status, body: body}} when is_map(body) ->
              categorize_response(status, body)

            {:ok, %{status: status}} ->
              {:ok, "Webhook delivered — HTTP #{status}"}

            {:error, err} ->
              {:error, "Request failed: #{inspect(err)}"}
          end

        {:error, _} ->
          {:error, "Invalid JSON payload"}
      end

    socket =
      socket
      |> update(:webhook_results, &Map.put(&1, source_atom, result))
      |> load_rules_and_linear_ticket()
      |> load_webhook_events()

    socket =
      case result do
        {:ok, _} -> push_event(socket, "tour:action_complete", %{action: "webhook_sent"})
        _ -> socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info(:refresh, socket) do
    socket =
      socket
      |> expire_breaker_results()
      |> load_statuses()
      |> compute_breaker_display()

    schedule_refresh(socket)
    {:noreply, socket}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  defp schedule_refresh(socket) do
    interval = if has_active_breaker_events?(socket), do: 1_000, else: 5_000
    Process.send_after(self(), :refresh, interval)
  end

  defp has_active_breaker_events?(socket) do
    breaker_results = socket.assigns[:breaker_results] || %{}

    Enum.any?(breaker_results, fn {_, {kind, _}} -> kind == :tripped end) or
      Enum.any?(socket.assigns[:statuses] || [], fn {_, s} -> s.state != :closed end)
  end

  defp expire_breaker_results(socket) do
    now = System.monotonic_time(:millisecond)

    updated =
      socket.assigns.breaker_results
      |> Enum.reject(fn {_, {kind, at}} ->
        kind == :reset and now - at > 8_000
      end)
      |> Map.new()

    assign(socket, :breaker_results, updated)
  end

  defp categorize_response(status, body) when status in 200..299 do
    case body do
      %{"error" => err} -> {:error, "Rejected — #{err}"}
      %{"status" => "already_processed"} -> {:warning, "Duplicate event — already processed. Each send generates a fresh ID, so this is unexpected."}
      %{"status" => "ignored_bot"} -> {:warning, "Ignored — detected as bot message"}
      %{"status" => "accepted"} -> {:ok, "Webhook accepted — ticket is being created"}
      _ -> {:ok, "Webhook delivered — HTTP #{status}"}
    end
  end

  defp categorize_response(status, %{"error" => err}), do: {:error, "HTTP #{status} — #{err}"}
  defp categorize_response(status, _), do: {:error, "HTTP #{status}"}

  defp build_platform_tools(linked_ticket) do
    ts = System.os_time(:millisecond)

    linear_issue_id =
      if linked_ticket, do: linked_ticket.linear_issue_id, else: "no-linked-ticket"

    [
      {:front,
       "Simulates Front sending us a new conversation. Creates a ticket and triggers matching rules.",
       %{
         "type" => "inbound",
         "conversation" => %{
           "id" => "cnv_test_#{ts}",
           "subject" => "Login broken after password reset",
           "tags" => []
         },
         "target" => %{
           "data" => %{
             "body" =>
               "I changed my password and now I can't log in. Getting 401 errors on every request.",
             "author" => %{"email" => "test@example.com"}
           }
         }
       }},
      {:slack,
       "Simulates a Slack message arriving. Creates a ticket and triggers matching rules.",
       %{
         "type" => "event_callback",
         "event_id" => "evt_test_slack_#{ts}",
         "event" => %{
           "type" => "message",
           "text" => "Database connection pool exhausted on project abc123",
           "user" => "U0TEST",
           "channel" => "C0SUPPORT",
           "ts" => "#{div(ts, 1000)}.000001"
         }
       }},
      {:linear,
       if(linked_ticket,
         do:
           "Simulates Linear marking issue #{linear_issue_id} as completed. Will resolve the linked ticket.",
         else:
           "No tickets are currently linked to a Linear issue. Create one first via a rule with linear_create action."
       ),
       %{
         "type" => "Issue",
         "action" => "update",
         "data" => %{
           "id" => linear_issue_id,
           "identifier" => "SUP-999",
           "state" => %{"name" => "Done", "type" => "completed"}
         }
       }}
    ]
  end

  defp update_test_results(integration, status, message) do
    case SupportDeck.Settings.list_for_integration(integration) do
      {:ok, creds} ->
        Enum.each(creds, fn cred ->
          SupportDeck.Settings.record_test_result(cred, %{status: status, message: message})
        end)

      _ ->
        :ok
    end
  end

  defp load_rules_and_linear_ticket(socket) do
    has_rules =
      case SupportDeck.Tickets.list_all_rules() do
        {:ok, rules} -> rules != []
        _ -> false
      end

    linked_ticket =
      case SupportDeck.Tickets.list_open_tickets() do
        {:ok, tickets} -> Enum.find(tickets, & &1.linear_issue_id)
        _ -> nil
      end

    socket
    |> assign(:has_rules, has_rules)
    |> assign(:linked_linear_ticket, linked_ticket)
    |> assign(:platform_tools, build_platform_tools(linked_ticket))
  end

  defp load_webhook_events(socket) do
    events =
      case SupportDeck.IntegrationsDomain.list_recent_events() do
        {:ok, e} -> e
        _ -> []
      end

    assign(socket, :webhook_events, events)
  end

  defp load_credentials(socket) do
    credentials =
      case SupportDeck.Settings.list_all_credentials() do
        {:ok, c} -> c
        _ -> []
      end

    assign(socket, :credentials, credentials)
  end

  defp load_statuses(socket) do
    statuses =
      Enum.map(@breaker_integrations, fn name ->
        {name, CircuitBreaker.get_status(name)}
      end)

    assign(socket, :statuses, statuses)
  end

  # Pre-computes all time-dependent breaker values as assigns so LiveView's
  # diff engine sees actual value changes (countdown decrementing, state transitions).
  # Without this, assign/3's value comparison sees identical ETS data and skips re-render.
  defp compute_breaker_display(socket) do
    statuses = socket.assigns.statuses
    breaker_results = socket.assigns.breaker_results
    credentials = socket.assigns.credentials

    breaker_display =
      Enum.map(@breaker_integrations, fn platform ->
        breaker = find_breaker_status(statuses, platform)
        display_state = display_breaker_state(breaker)
        breaker_result = breaker_results[platform]
        msg = breaker_result && breaker_result_message(platform, breaker_result, breaker)

        cred_status = Resolver.integration_status(platform)

        {platform,
         %{
           display_state: display_state,
           state_label: friendly_state(display_state),
           state_class: breaker_state_class(display_state),
           failures: breaker && breaker.failures,
           last_failure: breaker && format_last_failure(breaker.last_failure_at),
           message: msg,
           message_kind: breaker_result && elem(breaker_result, 0),
           credentials_configured: cred_status == :configured
         }}
      end)
      |> Map.new()

    integration_statuses =
      Enum.map(@integrations, fn {name, _, _} ->
        {name, compute_integration_status(name, credentials, statuses)}
      end)
      |> Map.new()

    socket
    |> assign(:breaker_display, breaker_display)
    |> assign(:integration_statuses, integration_statuses)
  end

  defp compute_integration_status(name, _credentials, statuses) do
    config = Resolver.integration_status(name)
    breaker = find_breaker_status(statuses, name)
    display_state = display_breaker_state(breaker)

    status =
      case {config, display_state} do
        {:not_configured, _} -> :not_configured
        {:partial, _} -> :partial
        {_, :open} -> :down
        {_, :half_open} -> :degraded
        {:configured, _} -> :healthy
      end

    %{
      status: status,
      label: status_badge_label(status),
      class: status_badge_class(status),
      failures: breaker && breaker.failures,
      last_failure: breaker && format_last_failure(breaker.last_failure_at)
    }
  end

  defp find_credential(credentials, integration, key_name) do
    Enum.find(credentials, fn c -> c.integration == integration and c.key_name == key_name end)
  end

  defp find_breaker_status(statuses, name) do
    case Enum.find(statuses, fn {n, _} -> n == name end) do
      {_, status} -> status
      nil -> nil
    end
  end

  # Returns the effective display state, accounting for cooldown expiry.
  # ETS state stays :open until a call triggers the transition, but visually
  # we show :half_open once the cooldown period has elapsed.
  defp display_breaker_state(nil), do: nil

  defp display_breaker_state(%{state: :open, last_failure_at: last_at, cooldown_ms: cooldown})
       when last_at != nil do
    elapsed = System.monotonic_time(:millisecond) - last_at
    if elapsed >= cooldown, do: :half_open, else: :open
  end

  defp display_breaker_state(%{state: state}), do: state

  defp status_badge_class(:healthy), do: "bg-success/15 text-success"
  defp status_badge_class(:down), do: "bg-error/15 text-error"
  defp status_badge_class(:degraded), do: "bg-warning/15 text-warning"
  defp status_badge_class(:partial), do: "bg-warning/15 text-warning"
  defp status_badge_class(:not_configured), do: "bg-base-content/10 text-base-content/50"

  defp status_badge_label(:healthy), do: "Healthy"
  defp status_badge_label(:down), do: "Down"
  defp status_badge_label(:degraded), do: "Recovering"
  defp status_badge_label(:partial), do: "Partial Config"
  defp status_badge_label(:not_configured), do: "Not Configured"

  defp credential_status_class(:ok), do: "bg-success/15 text-success"
  defp credential_status_class(:error), do: "bg-error/15 text-error"
  defp credential_status_class(_), do: "bg-base-content/10 text-base-content/60"

  defp friendly_state(:closed), do: "Healthy"
  defp friendly_state(:open), do: "Down"
  defp friendly_state(:half_open), do: "Recovering"
  defp friendly_state(_), do: "Unknown"

  defp breaker_state_class(:closed), do: "bg-success/15 text-success"
  defp breaker_state_class(:open), do: "bg-error/15 text-error"
  defp breaker_state_class(:half_open), do: "bg-warning/15 text-warning"
  defp breaker_state_class(_), do: "bg-base-content/10 text-base-content/50"

  defp format_last_failure(nil), do: "Never"

  defp format_last_failure(mono_time) do
    elapsed_ms = System.monotonic_time(:millisecond) - mono_time
    elapsed_s = div(elapsed_ms, 1000)

    cond do
      elapsed_s < 60 -> "#{elapsed_s}s ago"
      elapsed_s < 3600 -> "#{div(elapsed_s, 60)}m ago"
      true -> "#{div(elapsed_s, 3600)}h ago"
    end
  end

  defp breaker_countdown_remaining(breaker) do
    case breaker do
      %{state: :open, last_failure_at: last_at, cooldown_ms: cooldown} when last_at != nil ->
        elapsed = System.monotonic_time(:millisecond) - last_at
        max(div(cooldown - elapsed, 1000), 0)

      _ ->
        0
    end
  end

  defp breaker_result_message(platform, {kind, at}, breaker) do
    now = System.monotonic_time(:millisecond)
    elapsed_s = div(now - at, 1000)

    case kind do
      :tripped ->
        remaining = breaker_countdown_remaining(breaker)

        if remaining > 0 do
          "Circuit breaker tripped — #{platform} API calls are blocked. Recovers in #{remaining}s."
        else
          "Cooldown expired — next #{platform} API call will test the connection."
        end

      :reset ->
        if elapsed_s < 8 do
          "Circuit breaker reset — #{platform} API calls are flowing normally."
        else
          nil
        end
    end
  end

  defp breaker_protects(:front), do: "Outbound Front API calls (replies and tagging from rules)"
  defp breaker_protects(:slack), do: "Slack notifications from rules and SLA alerts"
  defp breaker_protects(:linear), do: "Linear issue creation from rules"

  defp webhook_result_class(:ok), do: "bg-success/10 border-success/30 text-success"
  defp webhook_result_class(:warning), do: "bg-warning/10 border-warning/30 text-warning"
  defp webhook_result_class(:error), do: "bg-error/10 border-error/30 text-error"
  defp webhook_result_class(_), do: "bg-base-content/10 border-base-300 text-base-content/60"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-6 py-6">
      <.page_header
        title="Integrations"
        description="Manage credentials, monitor connection health, and test webhooks."
      />

      <details open data-tour="breaker-cards" class="open:[&_summary_svg]:rotate-90">
        <summary class="text-sm font-semibold text-base-content/60 uppercase tracking-widest mb-4 cursor-pointer select-none list-none flex items-center gap-2 hover:text-base-content/80">
          <svg class="w-3.5 h-3.5 transition-transform" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5"><path d="M9 5l7 7-7 7" /></svg>
          Credentials & Health
        </summary>
        <div class="space-y-6">
        <div
          :for={{name, description, keys} <- @integrations}
          class="bg-base-100 rounded-lg border border-base-300 p-6"
        >
          <% int_status = @integration_statuses[name] %>
          <% configured = Resolver.integration_status(name) == :configured %>
          <div class="flex items-center justify-between mb-1">
            <h3 class="text-lg font-semibold text-base-content capitalize">{name}</h3>
            <div class="flex items-center gap-3">
              <div :if={int_status.failures} class="flex items-center gap-3 text-xs text-base-content/50">
                <span>
                  <span class="text-base-content/40">Failures:</span>
                  <span class="font-medium text-base-content/70">{int_status.failures}</span>
                </span>
                <span>
                  <span class="text-base-content/40">Last:</span>
                  <span class="font-medium text-base-content/70">{int_status.last_failure}</span>
                </span>
              </div>
              <span class={["px-2.5 py-0.5 text-xs rounded-full font-medium", int_status.class]}>
                {int_status.label}
              </span>
            </div>
          </div>
          <p class="text-sm text-base-content/50 mb-4">{description}</p>

          <form phx-submit="save_credentials" data-tour="credential-vault" class="space-y-3">
            <input type="hidden" name="integration" value={name} />
            <div :for={{key_name, label} <- keys}>
              <% existing = find_credential(@credentials, name, key_name) %>
              <div>
                <label class="block text-sm font-medium text-base-content/80 mb-1">{label}</label>
                <div :if={existing} class="flex items-center gap-2 mb-1">
                  <span class="text-xs text-base-content/40">{existing.value_hint}</span>
                  <span class={[
                    "inline-flex items-center gap-1 text-[10px]",
                    credential_status_class(existing.last_test_status)
                  ]}>
                    <span class={[
                      "w-1.5 h-1.5 rounded-full",
                      existing.last_test_status == :ok && "bg-success",
                      existing.last_test_status == :error && "bg-error",
                      existing.last_test_status not in [:ok, :error] && "bg-base-content/40"
                    ]} />
                    {existing.last_test_status}
                  </span>
                  <button
                    type="button"
                    phx-click="delete_credential"
                    phx-value-id={existing.id}
                    data-confirm="Delete this credential?"
                    class="px-1.5 py-0.5 text-[10px] text-error border border-error/30 rounded hover:bg-error/10"
                  >
                    Delete
                  </button>
                </div>
                <input
                  type="password"
                  name={"credentials[#{key_name}]"}
                  placeholder={if existing, do: "Update value...", else: "Enter value..."}
                  class="w-full px-3 py-2 border border-base-300 rounded-lg text-sm bg-base-100"
                />
              </div>
            </div>

            <% test_result = @test_results[name] %>
            <div
              :if={test_result}
              class={[
                "p-3 rounded-lg border text-sm",
                elem(test_result, 0) == :ok && "bg-success/10 border-success/30 text-success",
                elem(test_result, 0) != :ok && "bg-error/10 border-error/30 text-error"
              ]}
            >
              {elem(test_result, 1)}
            </div>

            <div class="flex items-center gap-2 flex-wrap">
              <button
                type="submit"
                class="px-3 py-1.5 text-sm bg-primary text-primary-content rounded-lg hover:bg-primary/90"
                phx-disable-with="Saving..."
              >
                Save
              </button>
              <button
                type="button"
                phx-click="test_connection"
                phx-value-integration={name}
                disabled={@testing == name || !configured}
                class={[
                  "px-3 py-1.5 text-sm rounded-lg transition-colors",
                  configured && "border border-primary bg-primary/10 text-primary font-medium hover:bg-primary/20",
                  !configured && "border border-base-300 text-base-content/40 cursor-not-allowed"
                ]}
              >
                {if @testing == name, do: "Testing...", else: "Test Connection"}
              </button>
              <span :if={!configured} class="text-xs text-base-content/40">
                Configure all credentials to enable testing
              </span>
            </div>
          </form>
        </div>
        </div>
      </details>

      <%!-- Simulate Inbound Webhooks --%>
      <details open class="mt-10 open:[&_summary_svg]:rotate-90" data-tour="webhook-test">
        <summary class="text-sm font-semibold text-base-content/60 uppercase tracking-widest mb-4 cursor-pointer select-none list-none flex items-center gap-2 hover:text-base-content/80">
          <svg class="w-3.5 h-3.5 transition-transform" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5"><path d="M9 5l7 7-7 7" /></svg>
          Simulate Inbound Webhooks
        </summary>
        <p class="text-xs text-base-content/50 mb-4">
          Send test payloads to your webhook endpoints. These simulate external services sending data to SupportDeck — creating tickets, triggering rules, and syncing state.
        </p>
        <div :if={!@has_rules} class="mb-4 p-3 rounded-lg border border-warning/30 bg-warning/10 text-warning text-sm">
          No automation rules found. Webhooks will create tickets but no rules will fire.
          Seed your database or create rules to see the full pipeline in action.
        </div>
        <div class="space-y-4">
          <div
            :for={{platform, description, default} <- @platform_tools}
            class="bg-base-100 rounded-lg border border-base-300 p-4"
          >
            <h3 class="text-sm font-semibold text-base-content capitalize mb-1">{platform}</h3>
            <p class="text-xs text-base-content/50 mb-3">{description}</p>

            <% result = @webhook_results[platform] %>
            <div
              :if={result}
              class={["mb-3 p-3 rounded-lg border text-sm space-y-1", webhook_result_class(elem(result, 0))]}
            >
              <p>{elem(result, 1)}</p>
              <.link
                :if={elem(result, 0) == :ok}
                navigate={~p"/tickets"}
                class="inline-flex items-center gap-1 text-xs font-medium underline hover:no-underline"
              >
                View tickets &rarr;
              </.link>
            </div>

            <form phx-submit="send_webhook" class="space-y-2">
              <input type="hidden" name="source" value={platform} />
              <div>
                <label class="block text-[10px] text-base-content/40 mb-1">
                  Payload <span class="text-base-content/30">— edit fields to customize</span>
                </label>
                <textarea
                  name="payload"
                  rows="4"
                  class="w-full px-3 py-2 border border-base-300 rounded-lg text-xs font-mono bg-base-100 text-base-content"
                >{Jason.encode!(default, pretty: true)}</textarea>
              </div>
              <button
                type="submit"
                phx-disable-with="Sending..."
                disabled={platform == :linear && !@linked_linear_ticket}
                class={[
                  "px-3 py-1.5 text-sm rounded-lg",
                  (platform == :linear && !@linked_linear_ticket) && "bg-base-300 text-base-content/40 cursor-not-allowed",
                  !(platform == :linear && !@linked_linear_ticket) && "bg-primary text-primary-content hover:bg-primary/90"
                ]}
              >
                Simulate {platform |> to_string() |> String.capitalize()} Webhook
              </button>
            </form>
          </div>
        </div>
      </details>

      <%!-- Recent Webhook Events --%>
      <details open class="mt-10 open:[&_summary_svg]:rotate-90">
        <summary class="text-sm font-semibold text-base-content/60 uppercase tracking-widest mb-4 cursor-pointer select-none list-none flex items-center gap-2 hover:text-base-content/80">
          <svg class="w-3.5 h-3.5 transition-transform" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5"><path d="M9 5l7 7-7 7" /></svg>
          Recent Webhook Events
        </summary>
        <div :if={@webhook_events == []} class="text-center py-8 bg-base-100 rounded-lg border border-base-300">
          <p class="text-base-content/60 text-sm">No webhook events recorded yet.</p>
        </div>
        <div :if={@webhook_events != []} class="bg-base-100 rounded-lg border border-base-300 overflow-hidden">
          <table class="min-w-full divide-y divide-base-300">
            <thead class="bg-base-200">
              <tr>
                <th class="px-4 py-3 text-left text-xs font-medium text-base-content/60 uppercase">Source</th>
                <th class="px-4 py-3 text-left text-xs font-medium text-base-content/60 uppercase">Event Type</th>
                <th class="px-4 py-3 text-left text-xs font-medium text-base-content/60 uppercase">Status</th>
                <th class="px-4 py-3 text-left text-xs font-medium text-base-content/60 uppercase">Time</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-base-300">
              <tr :for={event <- @webhook_events} class="hover:bg-base-200">
                <td class="px-4 py-3 text-sm font-medium text-base-content capitalize">{event.source}</td>
                <td class="px-4 py-3 text-sm text-base-content/60">{event.event_type}</td>
                <td class="px-4 py-3">
                  <span class={[
                    "px-2 py-0.5 text-xs rounded-full font-medium",
                    if(event.processed_at, do: "bg-success/15 text-success", else: "bg-warning/15 text-warning")
                  ]}>
                    {if event.processed_at, do: "Processed", else: "Pending"}
                  </span>
                </td>
                <td class="px-4 py-3 text-sm text-base-content/50">
                  {Calendar.strftime(event.inserted_at, "%b %d, %H:%M")}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </details>

      <%!-- Circuit Breaker Controls --%>
      <details open class="mt-10 open:[&_summary_svg]:rotate-90">
        <summary class="text-sm font-semibold text-base-content/60 uppercase tracking-widest mb-4 cursor-pointer select-none list-none flex items-center gap-2 hover:text-base-content/80">
          <svg class="w-3.5 h-3.5 transition-transform" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5"><path d="M9 5l7 7-7 7" /></svg>
          Circuit Breaker Controls
        </summary>
        <div class="bg-base-100 rounded-lg border border-base-300 p-4">
          <p class="text-xs text-base-content/50 mb-4">
            Circuit breakers protect <span class="font-medium text-base-content/70">outbound</span> API calls.
            When a service fails repeatedly, its breaker trips to prevent cascading failures.
            After a 30-second cooldown, the next call tests the connection — if it succeeds, the breaker resets automatically.
          </p>
          <div class="divide-y divide-base-300">
            <div
              :for={{platform, bd} <- @breaker_display}
              class="py-3 first:pt-0 last:pb-0"
            >
              <div class="flex items-center justify-between">
                <div class="flex items-center gap-3 min-w-0">
                  <h4 class="text-sm font-semibold text-base-content capitalize shrink-0">{platform}</h4>
                  <span class={["px-2 py-0.5 text-[10px] rounded-full font-medium shrink-0", bd.state_class]}>
                    {bd.state_label}
                  </span>
                  <span :if={!bd.credentials_configured} class="px-1.5 py-0.5 text-[10px] rounded-full bg-base-content/10 text-base-content/40">
                    No credentials
                  </span>
                  <span class="text-xs text-base-content/40 truncate hidden sm:inline">
                    {breaker_protects(platform)}
                  </span>
                </div>
                <div class="flex items-center gap-2 shrink-0">
                  <div :if={bd.failures} class="flex items-center gap-3 text-[10px] text-base-content/40 mr-2 hidden sm:flex">
                    <span>
                      <span class="text-base-content/30">Fails:</span>
                      <span class="font-medium text-base-content/60">{bd.failures}</span>
                    </span>
                    <span>
                      <span class="text-base-content/30">Last:</span>
                      <span class="font-medium text-base-content/60">{bd.last_failure}</span>
                    </span>
                  </div>
                  <button
                    phx-click="trip_breaker"
                    phx-value-name={platform}
                    data-confirm="This will simulate 5 consecutive failures and trip the circuit breaker. Continue?"
                    class="px-2.5 py-1 text-xs text-warning border border-warning/30 rounded-lg hover:bg-warning/10"
                  >
                    Simulate Failure
                  </button>
                  <button
                    :if={bd.display_state != :closed}
                    phx-click="reset_breaker"
                    phx-value-name={platform}
                    class="px-2.5 py-1 text-xs text-success border border-success/30 rounded-lg hover:bg-success/10"
                  >
                    Reset
                  </button>
                </div>
              </div>
              <p class="text-xs text-base-content/40 mt-1 sm:hidden">{breaker_protects(platform)}</p>
              <div
                :if={bd.message}
                class={[
                  "mt-2 p-2.5 rounded-lg border text-xs",
                  bd.message_kind == :tripped && "bg-error/10 border-error/30 text-error",
                  bd.message_kind == :reset && "bg-success/10 border-success/30 text-success"
                ]}
              >
                {bd.message}
              </div>
            </div>
          </div>
        </div>
      </details>
    </div>
    """
  end
end
