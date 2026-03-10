# SupportDeck

A real-time support operations platform built with Elixir, Phoenix LiveView, and Ash Framework.

**[Live Demo →](https://supportdeck.josboxoffice.com)**

## What It Does

- **Ticket Management** — Ingest tickets from Front, Slack, and Linear webhooks. Track them through a full lifecycle from creation to resolution.
- **AI Triage** — Automatically classify incoming tickets by category, severity, and suggested response using OpenAI, with keyword fallback when the AI service is unavailable.
- **SLA Monitoring** — Define response and resolution targets per plan tier and severity. Overdue tickets are flagged and auto-escalated.
- **Automation Rules** — Route, assign, escalate, or notify based on configurable conditions. Rules execute asynchronously in the background.
- **Integration Hub** — Encrypted credential vault, per-service health monitoring with circuit breakers, and webhook simulation tools for testing.
- **Real-time UI** — 11 LiveView pages with instant updates via PubSub. No page reloads, no polling.

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

## Architecture

SupportDeck is organized into five Ash domains, each owning its resources and business logic. LiveView pages call domain APIs directly. Background work — webhook processing, AI triage, rule execution, SLA checks — runs through Oban workers with dedicated queues. External API calls are protected by per-service circuit breakers.

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

## Technical Highlights

### Declarative State Machine

Ticket lifecycle (new → triaging → assigned → waiting → escalated → resolved → closed) is defined declaratively via AshStateMachine. Invalid transitions are rejected at the resource level — no defensive coding needed in controllers or LiveViews.

### Circuit Breaker Pattern

Each external integration (Front, Slack, Linear) has an ETS-backed GenServer circuit breaker. After 5 consecutive failures, the breaker trips and blocks calls for 30 seconds. Recovery is automatic — the next call after cooldown tests the connection.

### Encrypted Credential Vault

API keys are AES-256-GCM encrypted at rest. A GenServer loads and decrypts credentials into an ETS table on boot for fast reads. The UI lets you save, test, and delete credentials with the cache staying in sync.

### Idempotent Webhook Processing

Every inbound webhook is stored with a unique constraint (source + external_id) before processing. Duplicate deliveries are safely rejected. Each source (Front, Slack, Linear) has its own HMAC signature verification.

### Background Job Architecture

Six Oban queues with dedicated concurrency limits handle webhook processing, AI classification, rule execution, SLA monitoring, integration sync, and maintenance. Two AshOban scheduled triggers run directly on the Ticket resource: SLA breach checks (every minute) and auto-close of resolved tickets (hourly).

### Automation Rules Engine

A configurable rule engine evaluates conditions against ticket fields (severity, tier, product area, source) and dispatches actions (assign, escalate, notify via Slack, create Linear issues, reply via Front). Rules are stored as JSON and executed asynchronously through Oban.

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
├── support_deck_web/
│   ├── live/              # 11 LiveView pages
│   ├── controllers/       # Webhook ingestion, health check
│   ├── plugs/             # Raw body cache, signature verification
│   └── components/        # Shared UI components, sidebar layout
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

## Environment Variables

| Variable | Purpose |
|---|---|
| `SECRET_KEY_BASE` | Phoenix session encryption |
| `DATABASE_URL` | PostgreSQL connection string |
| `PHX_HOST` | Public hostname |
| `CREDENTIAL_VAULT_KEY` | Optional separate vault key (defaults to SECRET_KEY_BASE) |

Integration credentials (Front, Slack, Linear, OpenAI) are managed through the in-app credential vault on the Integrations page — no environment variables needed.

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
