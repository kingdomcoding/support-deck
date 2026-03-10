# SupportDeck

A production-patterned support operations platform built in Elixir/Phoenix, demonstrating the architecture I'd bring to the [Support Tooling role at Supabase](https://jobs.ashbyhq.com/supabase/2ed5e80d-438b-47a5-9efe-12d168b8de81).

The system mirrors what's described in the job posting and Supabase's own [SLA Buddy blog post](https://supabase.com/blog/sla-buddy) — idempotent webhook processing via Oban workers, Front/Slack/Linear integrations with per-service circuit breakers, AI-assisted triage with human-in-the-loop approval, and a real-time LiveView admin dashboard. Built with Phoenix, LiveView, Ash Framework, AshOban, and PostgreSQL — the same stack powering Supabase's existing internal systems.

**[Live Demo →](https://supportdeck.josboxoffice.com)** — Start with the Guided Tour to see ticket automation, SLA breach detection, and AI triage in action without manual setup.

---

## What It Does

- **Ticket Management** — Ingest tickets from Front, Slack, and Linear webhooks. Track them through a full lifecycle (new → triaging → assigned → waiting → escalated → resolved → closed) with an explicit state machine that rejects invalid transitions at the resource level.
- **AI Triage** — Automatically classify incoming tickets by category, severity, and suggested response using OpenAI, with a keyword heuristic fallback when the AI service is unavailable. AI responses are surfaced as drafts for human approval — never auto-sent.
- **SLA Monitoring** — Define response and resolution targets per plan tier and severity. Overdue tickets are flagged in real time and auto-escalated via Oban cron triggers.
- **Automation Rules** — Route, assign, escalate, or notify based on configurable conditions. Support leads create and edit rules through the admin UI without touching code. Rules execute asynchronously through Oban.
- **Integration Hub** — AES-256-GCM encrypted credential vault, per-service circuit breakers backed by ETS, and webhook simulation tools for testing integrations without live traffic.
- **Real-Time UI** — 11 LiveView pages with instant updates via PubSub. No polling, no page reloads, no client-side state management.

---

## Architecture Decisions

These are the choices I made and why. In interviews, I'd expect to defend every one of them.

### Ash Framework for the domain layer

Ash gives you declarative resource definitions — schemas, validations, actions, state machines, and authorization policies all co-located on the resource. The tradeoff is a steeper learning curve and a layer of abstraction over Ecto. I chose it because it's how I'd approach a codebase that a small team needs to evolve quickly without accumulating implicit knowledge in controllers and context functions. AshStateMachine in particular keeps the ticket lifecycle explicit and self-documenting — invalid transitions are rejected at the resource level before any business logic runs.

For an internal tools codebase where the team is small and requirements evolve constantly, the declarative surface is worth the abstraction cost.

### Six Oban queues, not one

Webhook processing, AI classification, rule execution, SLA monitoring, integration sync, and maintenance each have their own queue with independent concurrency limits. A spike in AI triage jobs (which are slow — they make LLM API calls) cannot starve webhook processing (which must be near-real-time). A queue-per-concern also makes it easy to tune concurrency per bottleneck and to observe which part of the system is under load.

This is directly inspired by the SLA Buddy architecture — the pattern of "enqueue immediately, return 200, process asynchronously" is the right default for any webhook receiver.

### Human-in-the-loop for all AI responses

The AI triage pipeline classifies tickets and generates draft responses. Those drafts are surfaced to support engineers for review and approval. The AI never sends a reply directly.

This is a deliberate constraint, not a missing feature. Enterprise customers with 10-minute SLA targets cannot receive incorrect AI-generated answers without a human check. The value of AI here is reducing the cognitive load of the first response, not eliminating the human. The feedback loop — which responses engineers accept, edit, or discard — also creates the data needed to improve the model over time.

### Per-service circuit breakers, not global

Front, Slack, and Linear each have their own ETS-backed GenServer circuit breaker. After 5 consecutive failures, a breaker trips and blocks calls to that service for 30 seconds. Recovery is automatic.

The reason they're per-service: Front going down should not prevent Slack escalation notifications from firing. A global circuit breaker would create false coupling between independent failure domains. The integration health page shows the state of each breaker in real time, which is the first thing you'd check during an incident.

### Configurable rule engine over hardcoded automations

Automation rules — routing, assignment, escalation, notifications — are stored as JSON in Postgres and evaluated at runtime by an Oban worker. Support leads create and edit rules through the admin UI.

The alternative (hardcoding automations as Elixir functions) means every workflow change requires an engineer to write, review, and deploy code. Support team requirements evolve constantly. A configurable rule engine eliminates that bottleneck and gives the support team direct control over their own workflows — which is a better product.

### Idempotent webhook processing with unique constraints

Every inbound webhook is stored with a unique constraint on `(source, external_id)` before the processing job is enqueued. Duplicate deliveries — which happen routinely with Front, Slack, and Linear — are rejected at the database level before they reach Oban. This means the Oban workers can be written without defensive deduplication logic, because the guarantee is enforced further upstream.

---

## Technical Highlights

### Declarative State Machine

Ticket lifecycle is defined declaratively via AshStateMachine. States: `new → triaging → assigned → waiting_on_customer → escalated → resolved → closed`. Invalid transitions are rejected at the resource level — no defensive coding scattered across controllers or LiveViews.

### Encrypted Credential Vault

API keys are AES-256-GCM encrypted at rest via a GenServer that loads and decrypts credentials into an ETS table on boot for fast reads. The vault key defaults to `SECRET_KEY_BASE` but can be rotated independently via `CREDENTIAL_VAULT_KEY`. The UI lets you save, test, and delete credentials with the in-memory cache staying in sync.

### SLA Breach Detection

Two AshOban scheduled triggers run directly on the Ticket resource: SLA breach checks every minute and auto-close of resolved tickets hourly. Breach detection uses the same tiered escalation model described in Supabase's SLA Buddy post — escalation actions are dispatched through the rule engine rather than hardcoded.

### Integration Health Monitoring

The Integrations page shows circuit breaker state (closed / open / half-open), last successful connection, and recent webhook failures for each service. This is the operational view a support engineer would reach for first during an incident.

---

## What I'd Build Next

These are the gaps I'd prioritize on the actual team:

1. **Webhook replay tooling** — Currently, failed webhook processing requires manual re-triggering via the simulator. A proper replay interface would show failed events, their error reasons, and allow selective retry with full observability.
2. **On-call rotation integration** — The SLA escalation chain currently assigns to static roles. Connecting to PagerDuty or Incident.io would route escalations to whoever is actually on shift, which is how the real SLA Buddy works.
3. **Customer health scoring** — Ticket frequency, severity trends, and SLA breach history per customer are all in the database. Surfacing a health score on the ticket detail view would help support engineers prioritize without manually cross-referencing history.
4. **Support engineer workload balancing** — Assignment today is rule-based. Real-time queue depth per engineer would enable smarter auto-assignment and help leads spot who is overloaded.
5. **Runbook automation** — Attach executable runbooks to ticket categories so common resolutions (password resets, quota increases, permission issues) can be partially or fully automated with a single click from the ticket detail view.

---

## Quick Start

### Docker (recommended)

```bash
cp .env.example .env
docker compose up -d
# → http://localhost:4500
```

### Local Development

```bash
# Requires: Elixir 1.18+, PostgreSQL 16+
mix setup          # deps, db create, migrate, seed
mix phx.server     # → http://localhost:4500
```

### Running Tests

```bash
mix test
```

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│  LiveView Pages (11)              PubSub (real-time)    │
├─────────────────────────────────────────────────────────┤
│  Ash Domains                                            │
│  Tickets · SLA · AI · Integrations · Settings           │
├─────────────────────────────────────────────────────────┤
│  Oban Workers (6 queues)          AshOban Triggers (2)  │
├─────────────────────────────────────────────────────────┤
│  PostgreSQL 16 + pgvector                               │
└─────────────────────────────────────────────────────────┘
```

SupportDeck is organized into five Ash domains, each owning its resources and business logic. LiveView pages call domain APIs directly. Background work — webhook processing, AI triage, rule execution, SLA checks — runs through Oban workers with dedicated queues. External API calls are protected by per-service circuit breakers backed by ETS GenServers.

## Project Structure

```
lib/
├── support_deck/
│   ├── tickets/           # Ticket, TicketActivity, Rule + RuleEngine
│   ├── sla/               # SLA policies and deadline defaults
│   ├── ai/                # Triage results, knowledge docs, classification
│   ├── integrations/      # Circuit breaker, Front/Slack/Linear/OpenAI clients
│   ├── settings/          # Credential vault, resolver, connection tester
│   └── workers/           # 6 Oban workers (webhooks, AI, rules, SLA)
└── support_deck_web/
    ├── live/              # 11 LiveView pages
    ├── controllers/       # Webhook ingestion, health check
    ├── plugs/             # Raw body cache, signature verification
    └── components/        # Shared UI components, sidebar layout
```

## Tech Stack

| Layer | Technology |
|---|---|
| Language | Elixir 1.18, Erlang/OTP 27 |
| Web | Phoenix 1.8, LiveView 1.1 |
| Data | Ash 3.x, AshPostgres, AshStateMachine, AshOban |
| Database | PostgreSQL 16 with pgvector |
| Jobs | Oban (6 queues, 2 scheduled triggers) |
| AI | OpenAI gpt-4o-mini with heuristic fallback |
| Integrations | Front, Slack, Linear |
| HTTP | Req |
| UI | Tailwind CSS 4, daisyUI 5 |
| Deployment | Docker multi-stage build |

## Pages

| Page | Description |
|---|---|
| Dashboard | Live overview of queue, SLA compliance, triage activity |
| Guided Tour | Interactive walkthrough that creates tickets and triggers features |
| Tickets | Searchable ticket queue with state management |
| Ticket Detail | Full ticket view with state transitions, AI triage, activity log |
| SLA Monitor | Response/resolution deadline tracking with breach alerts |
| SLA Policies | Editable policy grid by tier and severity |
| Automation Rules | Create/edit rules with condition builder and action config |
| Knowledge Base | Documentation and FAQs used for AI triage context |
| Integrations | Credential vault, circuit breaker controls, webhook simulator |

## Environment Variables

| Variable | Purpose |
|---|---|
| `SECRET_KEY_BASE` | Phoenix session encryption |
| `DATABASE_URL` | PostgreSQL connection string |
| `PHX_HOST` | Public hostname |
| `CREDENTIAL_VAULT_KEY` | Optional separate vault key (defaults to SECRET_KEY_BASE) |

Integration credentials (Front, Slack, Linear, OpenAI) are managed through the in-app credential vault on the Integrations page — no environment variables needed for third-party services.