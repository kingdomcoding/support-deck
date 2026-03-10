# SupportDeck — Demo Seed Data Audit Implementation Plan

There are **3 categories of work**: (A) seeds overhaul, (B) new AI Triage page, (C) circuit breaker seeding at boot.

---

## A. Seeds Overhaul (`priv/repo/seeds.exs`)

The current seeds are too thin: 10 tickets, 3 triage results, no webhook events, no activity logs beyond state transitions, no backdated SLA deadlines. The entire file needs a rewrite.

### A1. Expand to 15 tickets with realistic distribution

Replace the current 10 tickets with 15 that cover every state, tier, source, and product area:

```elixir
tickets_data = [
  # === NEW (3) — just arrived, not yet triaged ===
  %{
    subject: "OAuth callback returning 403 after domain migration",
    body: "We migrated our app to a new domain and now OAuth callbacks fail with 403. Redirect URIs are updated in the dashboard.",
    source: :front, severity: :high, subscription_tier: :enterprise,
    customer_email: "devops@acmecorp.com", product_area: :auth,
    external_id: "seed-1"
  },
  %{
    subject: "Realtime channel dropping connections every ~5 min",
    body: "Our Realtime subscriptions on the presence channel disconnect every 5 minutes. Heartbeat is configured correctly.",
    source: :slack, severity: :high, subscription_tier: :team,
    customer_email: "eng@chatwidget.io", product_area: :realtime,
    external_id: "seed-2"
  },
  %{
    subject: "Dashboard project list slow to load",
    body: "The project list page in the Supabase dashboard takes 15+ seconds to render when we have 40+ projects.",
    source: :front, severity: :low, subscription_tier: :pro,
    customer_email: "admin@freelancer.dev", product_area: :dashboard,
    external_id: "seed-3"
  },

  # === TRIAGING (2) — AI classification in progress ===
  %{
    subject: "Storage upload returns 413 for files under limit",
    body: "We're on the Pro plan (5GB limit) but files around 200MB fail with 413 Entity Too Large.",
    source: :front, severity: :medium, subscription_tier: :pro,
    customer_email: "media@uploadhub.co", product_area: :storage,
    external_id: "seed-4"
  },
  %{
    subject: "Edge function cold start exceeds 10s in ap-southeast-1",
    body: "Our edge functions in the Singapore region have cold starts of 10-12 seconds. Other regions are fine.",
    source: :slack, severity: :medium, subscription_tier: :team,
    customer_email: "backend@apacstartup.sg", product_area: :functions,
    external_id: "seed-5"
  },

  # === ASSIGNED (4) — assigned to support engineers ===
  %{
    subject: "RLS policy bypassed via service_role key in client bundle",
    body: "We accidentally shipped our service_role key in a client-side bundle. RLS is being bypassed. Need emergency rotation.",
    source: :front, severity: :critical, subscription_tier: :enterprise,
    customer_email: "security@vaultpay.com", product_area: :database,
    external_id: "seed-6"
  },
  # ... (3 more assigned tickets)

  # === WAITING ON CUSTOMER (2) ===
  # === ESCALATED (2) — at least one with breached SLA ===
  # === RESOLVED (2) ===
]
```

**Key change**: After creating tickets, backdate `sla_deadline` on specific tickets using raw Ecto to create visible breaches:

```elixir
# Backdate SLA deadlines to create breaches
# Enterprise critical ticket — breached 47 minutes ago
SupportDeck.Repo.query!(
  "UPDATE tickets SET sla_deadline = $1 WHERE external_id = $2",
  [DateTime.add(DateTime.utc_now(), -47, :minute), "seed-escalated-1"]
)

# Team high ticket — breaching in 3 minutes (approaching)
SupportDeck.Repo.query!(
  "UPDATE tickets SET sla_deadline = $1 WHERE external_id = $2",
  [DateTime.add(DateTime.utc_now(), 3, :minute), "seed-assigned-2"]
)
```

This ensures the SLA Dashboard always shows at least 1 red breach and 2 amber warnings on fresh seed.

### A2. Rich activity logs per ticket

Currently seeds only do state transitions, which auto-log. We need explicit activity logging to show a realistic timeline:

```elixir
# For the escalated enterprise ticket
Tickets.log_activity(ticket.id, "created", "front_webhook", "new")
Tickets.log_activity(ticket.id, "state_change", "system", "triaging")
Tickets.log_activity(ticket.id, "ai_triage", "ai_classifier",
  "classified as database/critical (confidence: 92%)")
Tickets.log_activity(ticket.id, "rule_fired", "automation",
  "Rule 'Auto-escalate critical enterprise' matched → escalating")
Tickets.log_activity(ticket.id, "state_change", "automation", "escalated")
Tickets.log_activity(ticket.id, "sla_breach", "sla_checker",
  "Response SLA breached — 10min target exceeded")
```

This makes the ticket detail view tell a story when you click into an escalated ticket.

### A3. Expand triage results to 20-30 with varied confidence

```elixir
# High confidence results (> 0.85)
high_confidence_tickets = Enum.take(created_tickets, 8)
for ticket <- high_confidence_tickets do
  AI.record_triage(ticket.id, %{
    predicted_category: to_string(ticket.product_area || "general"),
    predicted_severity: to_string(ticket.severity),
    confidence: 0.85 + :rand.uniform() * 0.14,  # 0.85-0.99
    draft_response: draft_for(ticket.product_area),
    processing_time_ms: 400 + :rand.uniform(600)
  })
end

# Low confidence results (< 0.50) — shows fallback/review state
low_confidence_tickets = Enum.slice(created_tickets, 8, 3)
for ticket <- low_confidence_tickets do
  AI.record_triage(ticket.id, %{
    predicted_category: "general",  # low confidence = generic classification
    predicted_severity: "medium",
    confidence: 0.25 + :rand.uniform() * 0.24,  # 0.25-0.49
    draft_response: nil,  # no draft when confidence is low
    processing_time_ms: 200 + :rand.uniform(300)
  })
end

# Medium confidence
# ... similar pattern, 0.50-0.84 range
```

Also record `human_accepted` feedback on some results:

```elixir
# Simulate human feedback on older triage results
for result <- Enum.take(high_confidence_results, 5) do
  AI.record_feedback(result, %{
    human_accepted: Enum.random([true, true, true, false]),  # ~75% acceptance
    response_used: Enum.random([true, false])
  })
end
```

**Note**: The `record_human_feedback` action accepts `human_accepted`, `human_override_category`, `response_used`. The domain exposes `record_feedback` — verify it delegates correctly. If not, add the delegation.

### A4. Seed webhook events (5-10)

The `WebhookEvent` resource exists but the integration health page doesn't display them. We need to **both seed events and add a "Recent Webhook Events" section to the integration health page** (see section D1).

```elixir
webhook_events = [
  %{source: :front, external_id: "evt_front_#{ts - 3600}", event_type: "inbound",
    payload: %{"conversation" => %{"id" => "cnv_abc", "subject" => "Login broken"}}},
  %{source: :front, external_id: "evt_front_#{ts - 1800}", event_type: "outbound_reply",
    payload: %{"conversation" => %{"id" => "cnv_abc"}}},
  %{source: :slack, external_id: "evt_slack_#{ts - 2700}", event_type: "message",
    payload: %{"event" => %{"type" => "message", "text" => "DB connection pool exhausted"}}},
  %{source: :slack, external_id: "evt_slack_#{ts - 900}", event_type: "reaction_added",
    payload: %{"event" => %{"type" => "reaction_added", "reaction" => "eyes"}}},
  %{source: :linear, external_id: "evt_linear_#{ts - 5400}", event_type: "issue_update",
    payload: %{"data" => %{"id" => "LIN-123", "state" => %{"name" => "In Progress"}}}},
  # ... more events
]

for event <- webhook_events do
  SupportDeck.IntegrationsDomain.store_event(event)
end
```

### A5. Update automation rules to mirror job posting language

```elixir
rules = [
  %{
    name: "Auto-escalate Enterprise tickets breaching L1 SLA",
    description: "Escalate and notify #enterprise-escalations when an Enterprise ticket is created with critical severity",
    trigger: :ticket_created,
    conditions: %{"all" => [
      %{"field" => "severity", "op" => "eq", "value" => "critical"},
      %{"field" => "subscription_tier", "op" => "eq", "value" => "enterprise"}
    ]},
    actions_list: [
      %{"type" => "escalate"},
      %{"type" => "slack_notify", "params" => %{"channel" => "#enterprise-escalations"}}
    ],
    priority: 100, enabled: true
  },
  %{
    name: "Route Auth tickets to Auth specialist queue",
    description: "Automatically assign authentication-related tickets to the Auth team",
    trigger: :ticket_created,
    conditions: %{"all" => [%{"field" => "product_area", "op" => "eq", "value" => "auth"}]},
    actions_list: [%{"type" => "assign", "params" => %{"assignee" => "auth-team@supabase.io"}}],
    priority: 80, enabled: true
  },
  %{
    name: "Create Linear issue for critical severity",
    description: "Automatically create a Linear issue for engineering when ticket severity is critical",
    trigger: :ticket_created,
    conditions: %{"all" => [%{"field" => "severity", "op" => "in", "value" => ["critical", "high"]}]},
    actions_list: [%{"type" => "linear_create", "params" => %{"team" => "Engineering"}}],
    priority: 60, enabled: true
  },
  %{
    name: "Auto-assign Realtime tickets to on-shift engineer",
    description: "Route Realtime product area tickets to the on-shift Realtime specialist",
    trigger: :ticket_created,
    conditions: %{"all" => [%{"field" => "product_area", "op" => "eq", "value" => "realtime"}]},
    actions_list: [%{"type" => "assign", "params" => %{"assignee" => "realtime-oncall@supabase.io"}}],
    priority: 40, enabled: true
  },
  %{
    name: "Alert on unresponded Enterprise ticket after 8 minutes",
    description: "Send Slack DM to support lead when any Enterprise ticket goes unresponded for 8 minutes",
    trigger: :sla_breach,
    conditions: %{"all" => [%{"field" => "subscription_tier", "op" => "eq", "value" => "enterprise"}]},
    actions_list: [%{"type" => "slack_notify", "params" => %{"channel" => "#support-leads", "mention" => "@support-lead"}}],
    priority: 90, enabled: true
  }
]
```

### A6. Seed AI draft responses that are visible on ticket detail

The ticket resource has `ai_draft_response` directly on it. Populate this for tickets that have been triaged:

```elixir
# After applying triage results, set ai_draft_response on the ticket itself
Tickets.apply_ai_results(ticket, %{
  ai_classification: %{"category" => "auth", "severity" => "high"},
  ai_draft_response: "Hi there, thanks for reporting this OAuth issue. Based on your description, this appears to be related to redirect URI validation after a domain migration. Here's what to check:\n\n1. Verify your new domain is added to the Redirect URLs in Dashboard → Authentication → URL Configuration\n2. Clear any cached OAuth state from your browser\n3. If using PKCE, ensure the code verifier is regenerated\n\nCould you confirm these steps and let us know if the issue persists?",
  ai_confidence: 0.92,
  product_area: :auth,
  severity: :high,
  subscription_tier: :enterprise
})
```

---

## B. New AI Triage Performance Page

The audit requires an "AI Performance Page" with classification metrics, acceptance rates, and confidence distributions. **This page doesn't exist — we need to build it.**

### B1. Add route and sidebar entry

**Router** (`router.ex`):
```elixir
live "/ai", AITriageLive, :index
```

**Sidebar** (`layouts.ex`) — add under the "Intelligence" section:
```elixir
<.nav_item
  path={~p"/ai"}
  current={assigns[:current_path]}
  icon="hero-sparkles"
  label="AI Triage"
/>
```

### B2. Build the LiveView (`ai_triage_live.ex`)

This page needs to compute metrics from triage_results in the database. We need a couple of new read actions on the TriageResult resource:

**New action on TriageResult** (`triage_result.ex`):
```elixir
read :all_results do
  prepare build(sort: [inserted_at: :desc])
end
```

**New domain function** (`ai_domain.ex`):
```elixir
define :list_all_triage, action: :all_results
```

**The LiveView** computes metrics from the full result set:

```elixir
defmodule SupportDeckWeb.AITriageLive do
  use SupportDeckWeb, :live_view

  def mount(_params, _session, socket) do
    results = case SupportDeck.AI.list_all_triage() do
      {:ok, r} -> r
      _ -> []
    end

    metrics = compute_metrics(results)

    {:ok,
     socket
     |> assign(:page_title, "AI Triage")
     |> assign(:current_path, ~p"/ai")
     |> assign(:results, results)
     |> assign(:metrics, metrics)}
  end

  defp compute_metrics(results) do
    total = length(results)
    with_feedback = Enum.filter(results, & &1.human_accepted != nil)
    accepted = Enum.count(with_feedback, & &1.human_accepted)

    %{
      total_triages: total,
      acceptance_rate: if(with_feedback != [], do: accepted / length(with_feedback) * 100, else: 0),
      avg_confidence: if(total > 0, do: Enum.sum(Enum.map(results, & &1.confidence)) / total, else: 0),
      avg_processing_ms: if(total > 0, do: div(Enum.sum(Enum.map(results, & (&1.processing_time_ms || 0))), total), else: 0),
      by_category: Enum.frequencies_by(results, & &1.predicted_category),
      confidence_distribution: %{
        high: Enum.count(results, & &1.confidence >= 0.85),
        medium: Enum.count(results, & &1.confidence >= 0.50 and &1.confidence < 0.85),
        low: Enum.count(results, & &1.confidence < 0.50)
      }
    }
  end
end
```

**Render**: 4 metric cards (Total Triages, Acceptance Rate, Avg Confidence, Avg Processing Time), a category breakdown bar chart (simple div-based), a confidence distribution breakdown, and a scrollable table of recent results.

### B3. Add sidebar count for AI triages

**In `sidebar_counts.ex`**, add an `ai_count` assign showing 24h triage count:

```elixir
|> assign(:ai_count, safe_count(:ai_triages))

defp safe_count(:ai_triages) do
  case SupportDeck.AI.list_recent_triage(DateTime.add(DateTime.utc_now(), -24 * 3600)) do
    {:ok, t} -> length(t)
    _ -> 0
  end
end
```

---

## C. Circuit Breaker Seeding at Boot

The audit requires Linear's circuit breaker in **half-open** state on load. Circuit breakers are ETS-only (no persistence), so we need to trip Linear's breaker during seed/boot.

### C1. Why seeds can't set circuit breaker state

Seeds run in a one-off container via `Release.seed()`. ETS is in-memory and per-process — when that container exits, the ETS state dies with it. The running app container starts with fresh ETS tables, all breakers closed. Setting state in seeds is useless.

### C2. Trip Linear breaker on app boot

Instead, trip the breaker during the **running app's boot sequence**. Add a startup task to the supervision tree in `application.ex` that runs after the `CircuitBreaker` GenServer is started:

```elixir
# In application.ex children list, after CircuitBreaker:
{Task, fn ->
  # Give CircuitBreaker GenServer time to init its ETS table
  Process.sleep(100)

  for _ <- 1..5 do
    SupportDeck.Integrations.CircuitBreaker.call(:linear, fn ->
      {:error, :simulated_failure}
    end)
  end

  Logger.info("demo: tripped Linear circuit breaker (will recover in 30s)")
end}
```

This trips the breaker every time the app starts. After 30 seconds the cooldown expires and the integration health page shows Linear as "Recovering" (half-open) — the reviewer sees a breaker that's been tripped and is in the process of recovering, which is a more interesting demo state than all-green.

**Guard it with a config flag** so it only runs in demo/prod, not during tests:

```elixir
# config/runtime.exs
config :support_deck, demo_mode: System.get_env("DEMO_MODE", "false") == "true"

# application.ex — only add the task when demo_mode is true
children = [
  # ... existing children ...
] ++ if Application.get_env(:support_deck, :demo_mode), do: [
  {Task, fn -> trip_linear_breaker() end}
], else: []
```

Alternatively, skip the config flag entirely and just trip it unconditionally — the breaker self-heals in 30 seconds, so the only effect is that Linear shows "Recovering" briefly on every boot. No harm done since Linear API calls aren't happening without credentials anyway.

---

## D. Integration Health Page Additions

### D1. Add "Recent Webhook Events" section

The integration health page needs a section showing seeded webhook events. This requires:

1. **New read action** on `WebhookEvent`:
```elixir
read :recent do
  prepare build(sort: [inserted_at: :desc], limit: 10)
end
```

2. **New domain function**:
```elixir
define :list_recent_events, action: :recent
```

3. **Load in LiveView mount**:
```elixir
|> load_recent_events()

defp load_recent_events(socket) do
  events = case SupportDeck.IntegrationsDomain.list_recent_events() do
    {:ok, e} -> e
    _ -> []
  end
  assign(socket, :recent_events, events)
end
```

4. **Render section** — between "Credentials & Health" and "Circuit Breaker Controls":
```elixir
<details open class="mt-10 open:[&_summary_svg]:rotate-90">
  <summary>Recent Webhook Events</summary>
  <table>
    <thead><tr><th>Source</th><th>Type</th><th>External ID</th><th>Status</th><th>Time</th></tr></thead>
    <tbody>
      <tr :for={event <- @recent_events}>
        <td>{event.source}</td>
        <td>{event.event_type}</td>
        <td class="font-mono text-xs">{String.slice(event.external_id, 0..12)}...</td>
        <td>{if event.processed_at, do: "Processed", else: "Pending"}</td>
        <td>{relative_time(event.inserted_at)}</td>
      </tr>
    </tbody>
  </table>
</details>
```

---

## E. Ticket Detail — Show AI Draft Response

The ticket detail page shows triage results (category, severity, confidence) but **doesn't show `ai_draft_response`** — the actual draft response text that a support engineer would review.

Add to the triage result display in `ticket_detail_live.ex`:

```elixir
<div :if={result.draft_response} class="mt-2 p-2.5 bg-info/5 rounded border border-info/20">
  <p class="text-[10px] text-info font-semibold uppercase tracking-wide mb-1">AI Draft Response</p>
  <p class="text-xs text-base-content/80 whitespace-pre-wrap">{result.draft_response}</p>
</div>
```

Also show the `ai_draft_response` from the ticket itself with **functional** approve/edit/discard buttons. This is the human-in-the-loop workflow — the core differentiator described in the README's Architecture Decisions section.

#### Template (in ticket_detail_live.ex render):

```elixir
<div :if={@ticket.ai_draft_response} class="bg-base-100 rounded-lg border border-info/30 p-4">
  <h3 class="text-sm font-semibold text-info mb-2 flex items-center gap-1.5">
    <.icon name="hero-sparkles" class="size-3.5" /> AI Draft Response
  </h3>

  <%!-- View mode --%>
  <div :if={!@editing_draft}>
    <p class="text-sm text-base-content/80 whitespace-pre-wrap">{@ticket.ai_draft_response}</p>
    <div class="flex gap-2 mt-3">
      <button
        phx-click="approve_draft"
        phx-disable-with="Sending..."
        class="px-3 py-1 text-xs bg-success/15 text-success rounded-lg border border-success/30 hover:bg-success/25"
      >
        Approve & Send
      </button>
      <button
        phx-click="edit_draft"
        class="px-3 py-1 text-xs bg-base-200 text-base-content/60 rounded-lg border border-base-300 hover:bg-base-300"
      >
        Edit
      </button>
      <button
        phx-click="discard_draft"
        data-confirm="Discard this AI-generated draft?"
        class="px-3 py-1 text-xs bg-error/15 text-error rounded-lg border border-error/30 hover:bg-error/25"
      >
        Discard
      </button>
    </div>
  </div>

  <%!-- Edit mode --%>
  <div :if={@editing_draft}>
    <form phx-submit="save_edited_draft">
      <textarea
        name="draft"
        rows="6"
        class="w-full px-3 py-2 border border-base-300 rounded-lg text-sm bg-base-100"
      >{@ticket.ai_draft_response}</textarea>
      <div class="flex gap-2 mt-2">
        <button type="submit" class="px-3 py-1 text-xs bg-success/15 text-success rounded-lg border border-success/30">
          Approve & Send
        </button>
        <button type="button" phx-click="cancel_edit_draft" class="px-3 py-1 text-xs bg-base-200 text-base-content/60 rounded-lg border border-base-300">
          Cancel
        </button>
      </div>
    </form>
  </div>
</div>
```

#### Event handlers (in ticket_detail_live.ex):

```elixir
# Add :editing_draft assign in mount
|> assign(:editing_draft, false)

def handle_event("approve_draft", _, socket) do
  ticket = socket.assigns.ticket
  # Record human acceptance on the most recent triage result
  record_draft_feedback(socket, true, true)
  # Log activity
  Tickets.log_activity(ticket.id, "draft_approved", "agent", "AI draft response approved and sent")
  # Clear the draft from the ticket (it's been "sent")
  {:ok, updated} = Tickets.apply_ai_results(ticket, %{ai_draft_response: nil})

  {:noreply,
   socket
   |> assign(:ticket, updated)
   |> put_flash(:info, "Draft approved and sent")}
end

def handle_event("edit_draft", _, socket) do
  {:noreply, assign(socket, :editing_draft, true)}
end

def handle_event("cancel_edit_draft", _, socket) do
  {:noreply, assign(socket, :editing_draft, false)}
end

def handle_event("save_edited_draft", %{"draft" => draft}, socket) do
  ticket = socket.assigns.ticket
  record_draft_feedback(socket, true, true)
  Tickets.log_activity(ticket.id, "draft_edited", "agent", "AI draft edited and sent")
  {:ok, updated} = Tickets.apply_ai_results(ticket, %{ai_draft_response: nil})

  {:noreply,
   socket
   |> assign(:ticket, updated)
   |> assign(:editing_draft, false)
   |> put_flash(:info, "Edited draft sent")}
end

def handle_event("discard_draft", _, socket) do
  ticket = socket.assigns.ticket
  record_draft_feedback(socket, false, false)
  Tickets.log_activity(ticket.id, "draft_discarded", "agent", "AI draft response discarded")
  {:ok, updated} = Tickets.apply_ai_results(ticket, %{ai_draft_response: nil})

  {:noreply,
   socket
   |> assign(:ticket, updated)
   |> put_flash(:info, "Draft discarded")}
end

defp record_draft_feedback(socket, accepted, used) do
  case socket.assigns.triage_results do
    [latest | _] ->
      SupportDeck.AI.record_feedback(latest, %{
        human_accepted: accepted,
        response_used: used
      })
    _ -> :ok
  end
end
```

#### What this gives the reviewer:

- **Approve & Send**: Marks the triage result as `human_accepted: true, response_used: true`, logs "draft approved" to the activity timeline, clears the draft from the ticket. Shows flash confirmation.
- **Edit**: Opens an editable textarea pre-filled with the AI draft. Submit sends the edited version (same flow as approve but logs "draft edited").
- **Discard**: Marks as `human_accepted: false, response_used: false`, logs "draft discarded", clears the draft. Confirms before discarding.

The activity log entries make this visible even after the action is taken — a reviewer clicking into a resolved ticket can see "AI draft response approved and sent" in the timeline, proving the human-in-the-loop workflow is real.

**Note**: `apply_ai_results` currently requires all fields (ai_classification, ai_confidence, product_area, severity, subscription_tier). We may need to add a lighter `:clear_draft` action on the Ticket resource that only updates `ai_draft_response`:

```elixir
# In ticket.ex
update :clear_draft do
  accept([:ai_draft_response])
end
```

And a corresponding domain function:

```elixir
# In tickets.ex domain
define :clear_draft, action: :clear_draft
```

This avoids having to pass all the other AI fields just to clear the draft.

---

## F. SLA Dashboard — Add "Approaching Breach" Section

Currently the SLA dashboard only shows tickets **past** their deadline. We need a section for tickets **approaching** their deadline (within 15 minutes of the target remaining).

Since Ash filter expressions for date math can be tricky, filter in Elixir:

```elixir
# In sla_dashboard_live.ex mount:
approaching =
  case SupportDeck.Tickets.list_open_tickets() do
    {:ok, tickets} ->
      now = DateTime.utc_now()
      Enum.filter(tickets, fn t ->
        t.sla_deadline != nil and
        DateTime.compare(t.sla_deadline, now) == :gt and
        DateTime.diff(t.sla_deadline, now, :minute) <= 15
      end)
    _ -> []
  end
```

Then render an amber/warning section above the red breach table.

---

## Files to Touch

| File | Change |
|---|---|
| `priv/repo/seeds.exs` | Full rewrite — 15 tickets, 25+ triage results, 8 webhook events, 5 rules, richer activities, backdated SLAs |
| `lib/support_deck/tickets/ticket.ex` | Add `:clear_draft` update action |
| `lib/support_deck/tickets.ex` | Add `clear_draft` domain function |
| `lib/support_deck/integrations/webhook_event.ex` | Add `:recent` read action |
| `lib/support_deck/integrations_domain.ex` | Add `list_recent_events` define |
| `lib/support_deck/ai/triage_result.ex` | Add `:all_results` read action |
| `lib/support_deck/ai_domain.ex` | Add `list_all_triage` define |
| `lib/support_deck/application.ex` | Add startup task to trip Linear circuit breaker |
| `lib/support_deck_web/live/ai_triage_live.ex` | **New file** — AI performance page |
| `lib/support_deck_web/live/ticket_detail_live.ex` | Show `ai_draft_response` with functional approve/edit/discard + `:editing_draft` assign |
| `lib/support_deck_web/live/sla_dashboard_live.ex` | Add "Approaching Breach" warning section |
| `lib/support_deck_web/live/integration_health_live.ex` | Add "Recent Webhook Events" section |
| `lib/support_deck_web/router.ex` | Add `/ai` route |
| `lib/support_deck_web/components/layouts.ex` | Add "AI Triage" sidebar nav item |
| `lib/support_deck_web/hooks/sidebar_counts.ex` | Add `ai_count` assign |

---

## Execution Order & Detailed TODO

### Phase 1 — Resource & Domain Layer Changes

These are the foundation. Nothing else compiles or works without these.

- [x] **1.1** Add `:all_results` read action to `lib/support_deck/ai/triage_result.ex`
- [x] **1.2** Add `list_all_triage` define to `lib/support_deck/ai_domain.ex`
- [x] **1.3** Add `:recent` read action (sorted desc, limit 10) to `lib/support_deck/integrations/webhook_event.ex`
- [x] **1.4** Add `list_recent_events` define to `lib/support_deck/integrations_domain.ex`
- [x] **1.5** Add `:clear_draft` update action (accepts only `ai_draft_response`) to `lib/support_deck/tickets/ticket.ex`
- [x] **1.6** Add `clear_draft` define to `lib/support_deck/tickets.ex`
- [x] **1.7** Verify `record_feedback` in `ai_domain.ex` correctly delegates to `record_human_feedback` action with `human_accepted`, `human_override_category`, `response_used`

### Phase 2 — Circuit Breaker Boot Task

- [x] **2.1** Read `lib/support_deck/application.ex` to understand current supervision tree
- [x] **2.2** Add a `Task` child (after `CircuitBreaker`) that calls `CircuitBreaker.call(:linear, fn -> {:error, :simulated_failure} end)` five times
- [x] **2.3** Add 100ms sleep before tripping to ensure ETS table is initialized
- [x] **2.4** Decide: config flag (`DEMO_MODE`) or unconditional trip. Implement chosen approach.
- [x] **2.5** Verify the breaker transitions from "Down" → "Recovering" within ~30s on page load

### Phase 3 — Seeds Rewrite (`priv/repo/seeds.exs`)

Full rewrite. This is the largest single task.

#### 3a — Ticket Data (15 tickets across all states)

- [x] **3a.1** Define 3 tickets in `new` state (enterprise/front, team/slack, pro/front — auth, realtime, dashboard)
- [x] **3a.2** Define 2 tickets in `triaging` state (pro/front storage, team/slack functions)
- [x] **3a.3** Define 4 tickets in `assigned` state (enterprise/front database critical, team/slack billing, pro/front general, enterprise/linear auth)
- [x] **3a.4** Define 2 tickets in `waiting_on_customer` state (team/front storage, pro/slack realtime)
- [x] **3a.5** Define 2 tickets in `escalated` state (enterprise/front database critical — will be SLA-breached, enterprise/slack auth high)
- [x] **3a.6** Define 2 tickets in `resolved` state (pro/front functions, free/manual dashboard)
- [x] **3a.7** Verify coverage: at least 1 ticket per product area (auth, database, storage, functions, realtime, dashboard, billing)
- [x] **3a.8** Verify coverage: at least 1 ticket per source (front, slack, linear/manual)
- [x] **3a.9** Verify coverage: at least 1 enterprise, 1 team, 1 pro, 1 free ticket

#### 3b — State Transitions

- [x] **3b.1** Transition 2 tickets to `triaging` via `Tickets.begin_triage/1`
- [x] **3b.2** Transition 4 tickets to `assigned` via `Tickets.assign_ticket/2` with realistic assignee emails
- [x] **3b.3** Transition 2 tickets to `waiting_on_customer` via `assign → wait_on_customer`
- [x] **3b.4** Transition 2 tickets to `escalated` via `Tickets.escalate_ticket/1`
- [x] **3b.5** Transition 2 tickets to `resolved` via `assign → resolve`

#### 3c — SLA Deadline Backdating

- [x] **3c.1** Backdate 1 escalated enterprise ticket's `sla_deadline` to ~47 minutes ago (active breach, red)
- [x] **3c.2** Backdate 1 escalated ticket's `sla_deadline` to ~12 minutes ago (second breach)
- [x] **3c.3** Set 2 assigned tickets' `sla_deadline` to 3–8 minutes from now (approaching breach, amber)
- [x] **3c.4** Use `SupportDeck.Repo.query!/2` with raw SQL for backdating (Ash won't allow past deadlines via normal actions)

#### 3d — Activity Logs

- [x] **3d.1** Add 4–6 activity entries per escalated ticket (created → triaging → ai_triage → rule_fired → escalated → sla_breach)
- [x] **3d.2** Add 3–4 activity entries per assigned ticket (created → triaging → assigned)
- [x] **3d.3** Add activity entries for resolved tickets showing full lifecycle (created → triaging → assigned → resolved)
- [x] **3d.4** Add at least 1 "draft_approved" activity on a resolved ticket (shows human-in-the-loop happened)
- [x] **3d.5** Verify `Tickets.log_activity/4` signature matches: `(ticket_id, action, actor, to_value)`

#### 3e — Triage Results (25–30 total)

- [x] **3e.1** Create 10 high-confidence results (0.85–0.99) with product-specific draft responses
- [x] **3e.2** Create 5 medium-confidence results (0.50–0.84) with generic draft responses
- [x] **3e.3** Create 4 low-confidence results (0.25–0.49) with nil draft responses
- [x] **3e.4** Write `draft_for/1` helper function mapping product_area to realistic draft response text
- [x] **3e.5** Record `human_accepted` feedback on 8–10 results (~75% accepted, ~25% rejected)
- [x] **3e.6** Record `response_used: true` on 5–6 of the accepted results
- [x] **3e.7** Apply `ai_draft_response` to 3–4 tickets still in active states (assigned/escalated) so the ticket detail page shows the draft

#### 3f — Automation Rules (5 rules)

- [x] **3f.1** "Auto-escalate Enterprise tickets breaching L1 SLA" (trigger: ticket_created, priority: 100)
- [x] **3f.2** "Route Auth tickets to Auth specialist queue" (trigger: ticket_created, priority: 80)
- [x] **3f.3** "Create Linear issue for critical severity" (trigger: ticket_created, priority: 60)
- [x] **3f.4** "Auto-assign Realtime tickets to on-shift engineer" (trigger: ticket_created, priority: 40)
- [x] **3f.5** "Alert on unresponded Enterprise ticket after 8 minutes" (trigger: sla_breach, priority: 90)

#### 3g — Webhook Events (8 events)

- [x] **3g.1** Seed 3 Front webhook events (inbound, outbound_reply, tag) with realistic payloads
- [x] **3g.2** Seed 3 Slack webhook events (message, reaction_added, app_mention)
- [x] **3g.3** Seed 2 Linear webhook events (issue_update, comment_create)
- [x] **3g.4** Mark 5–6 events as processed (set `processed_at`), leave 2–3 as pending

#### 3h — Knowledge Docs (5 docs, keep existing)

- [x] **3h.1** Review existing 5 knowledge docs — update if needed, keep content realistic

### Phase 4 — AI Triage Performance Page (New)

- [x] **4.1** Create `lib/support_deck_web/live/ai_triage_live.ex` with mount, compute_metrics, render
- [x] **4.2** Implement `compute_metrics/1`: total_triages, acceptance_rate, avg_confidence, avg_processing_ms, by_category, confidence_distribution
- [x] **4.3** Render: 4 metric cards row (Total Triages, Acceptance Rate %, Avg Confidence %, Avg Processing Time ms)
- [x] **4.4** Render: Category breakdown section — horizontal bar chart (div-based) showing distribution across product areas
- [x] **4.5** Render: Confidence distribution section — 3-segment bar (high/medium/low) with counts and percentages
- [x] **4.6** Render: Recent results table — scrollable, showing timestamp, ticket subject (if loadable), category, severity, confidence %, accepted/pending status
- [x] **4.7** Add route `live "/ai", AITriageLive, :index` to `router.ex`
- [x] **4.8** Add "AI Triage" nav item to sidebar in `layouts.ex` under "Intelligence" section, with `hero-sparkles` icon
- [x] **4.9** Add `ai_count` assign to `sidebar_counts.ex` showing 24h triage count as badge
- [x] **4.10** Subscribe to PubSub for real-time updates when new triage results come in (optional, low priority)

### Phase 5 — Ticket Detail: Functional Draft Response

- [x] **5.1** Add `:editing_draft` assign (default `false`) in mount
- [x] **5.2** Add AI Draft Response card to render — view mode with Approve/Edit/Discard buttons
- [x] **5.3** Add edit mode with textarea pre-filled with draft, Approve & Send / Cancel buttons
- [x] **5.4** Implement `handle_event("approve_draft", ...)` — record feedback, log activity, clear draft via `clear_draft`
- [x] **5.5** Implement `handle_event("edit_draft", ...)` — toggle `:editing_draft` to true
- [x] **5.6** Implement `handle_event("cancel_edit_draft", ...)` — toggle `:editing_draft` to false
- [x] **5.7** Implement `handle_event("save_edited_draft", ...)` — record feedback, log "draft edited", clear draft
- [x] **5.8** Implement `handle_event("discard_draft", ...)` — record feedback (rejected), log "draft discarded", clear draft
- [x] **5.9** Implement `record_draft_feedback/3` helper — finds latest triage result, calls `AI.record_feedback`
- [x] **5.10** Add draft_response display inside existing triage result cards (below confidence score)
- [x] **5.11** Refresh triage_results assigns after feedback recording so acceptance status updates in UI

### Phase 6 — SLA Dashboard: Approaching Breach

- [x] **6.1** Add `:approaching_tickets` assign in mount — filter open tickets where `sla_deadline` is within 15 minutes
- [x] **6.2** Render amber/warning "Approaching Breach" section above the red "Breaching Tickets" table
- [x] **6.3** Show ticket subject, severity, tier, time remaining (e.g., "3m remaining")
- [x] **6.4** Make rows clickable (navigate to ticket detail with `?from=/sla`)
- [x] **6.5** Update the stats grid — add an "Approaching" metric card between Breaching and Active Policies
- [x] **6.6** Refresh approaching tickets on PubSub events (reuse existing handle_info)

### Phase 7 — Integration Health: Recent Webhook Events

- [x] **7.1** Add `load_recent_events/1` private function to `integration_health_live.ex`
- [x] **7.2** Call `load_recent_events` in mount
- [x] **7.3** Render "Recent Webhook Events" collapsible section between "Simulate Inbound Webhooks" and "Circuit Breaker Controls"
- [x] **7.4** Table columns: Source (badge), Event Type, External ID (truncated, monospace), Status (Processed/Pending badge), Time (relative)
- [x] **7.5** Empty state: "No webhook events recorded yet. Use the simulator above to generate test events."
- [x] **7.6** Refresh events after webhook simulation succeeds (call `load_recent_events` in `send_webhook` handler)

### Phase 8 — Build, Reseed, Verify

- [x] **8.1** Run `mix compile` — fix any compilation errors
- [x] **8.2** Run `mix test` — fix any test failures caused by new actions/schema changes
- [x] **8.3** Stop running app: `docker compose stop app`
- [x] **8.4** Reseed: `docker compose run --rm -e PHX_SERVER=false app bin/support_deck eval "SupportDeck.Release.seed()"`
- [x] **8.5** Start app: `docker compose start app`
- [x] **8.6** Open live demo in incognito window

### Phase 9 — Audit Checklist Verification

Walk through every item from the original audit checklist:

#### Dashboard (first 30 seconds)
- [x] **9.1** Dashboard shows tickets in multiple states (open count > 0)
- [x] **9.2** SLA Breaches metric card shows red count > 0
- [x] **9.3** Active Rules metric shows 5
- [x] **9.4** AI Triages (24h) shows count > 0
- [x] **9.5** Recent Tickets table is populated with 5 tickets
- [x] **9.6** System Health shows Linear as "Recovering" (half-open), others as "Healthy"

#### Ticket Queue
- [x] **9.7** Tickets exist in all required states (new, triaging, assigned, waiting, escalated, resolved)
- [x] **9.8** At least 1 Enterprise and 1 Team tier ticket visible
- [x] **9.9** Multiple product areas represented
- [x] **9.10** Multiple sources represented (front, slack icons)

#### Ticket Detail
- [x] **9.11** Click an escalated ticket — SLA breach visible, activity log shows full lifecycle
- [x] **9.12** At least 1 ticket has AI draft response with functional Approve/Edit/Discard buttons
- [x] **9.13** At least 1 ticket shows high confidence (>85%) triage result
- [x] **9.14** At least 1 ticket shows low confidence (<50%) triage result
- [x] **9.15** Activity log shows rule_fired and sla_breach entries

#### SLA Monitor
- [x] **9.16** At least 1 active breach (red)
- [x] **9.17** At least 2 approaching breach (amber)
- [x] **9.18** Breaching ticket rows are clickable → navigate to ticket detail

#### AI Triage Page
- [x] **9.19** Total triages shows 25+
- [x] **9.20** Acceptance rate shows ~70–80%
- [x] **9.21** Category breakdown shows distribution across product areas
- [x] **9.22** Confidence distribution shows spread (high/medium/low all > 0)
- [x] **9.23** Recent results table populated

#### Automation Rules
- [x] **9.24** 5 rules visible and enabled
- [x] **9.25** Rule names match job posting language

#### Integration Health
- [x] **9.26** Linear circuit breaker shows "Recovering" (half-open) or "Down" (open)
- [x] **9.27** Recent Webhook Events section shows 8 events with mix of Processed/Pending
- [x] **9.28** Webhook simulator works (creates ticket, shows in queue)

#### Guided Tour
- [x] **9.29** Tour completes all 5 steps without errors
- [x] **9.30** Tour creates a ticket (step 1) — visible in queue
- [x] **9.31** Tour triggers AI triage (step 2) — queues successfully
- [x] **9.32** Tour checks rules (step 3) — shows 5 enabled
- [x] **9.33** Tour checks SLA (step 4) — shows breach count
- [x] **9.34** Tour checks integrations (step 5) — shows status

#### Things that must not happen
- [x] **9.35** No empty ticket queue
- [x] **9.36** No all-zero dashboard metrics
- [x] **9.37** No JavaScript console errors
- [x] **9.38** Not all circuit breakers showing "Healthy" (Linear should be non-closed)
- [x] **9.39** AI triage page has real metrics (not empty)
- [x] **9.40** Guided tour doesn't crash mid-flow
