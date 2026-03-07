# SupportDeck

A production-grade support engineering platform built with **Ash Framework**, **Phoenix LiveView**, and **Oban** — demonstrating how declarative resource modeling, real-time UI, and robust background processing combine to create sophisticated internal tooling.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Phoenix LiveView (Real-time Dashboard)                     │
│  ┌──────────┬──────────┬──────────┬──────────┬───────────┐  │
│  │ Tickets  │   SLA    │    AI    │  Rules   │ Settings  │  │
│  │  Queue   │Dashboard │Dashboard │  Engine  │  & Vault  │  │
│  └──────────┴──────────┴──────────┴──────────┴───────────┘  │
├─────────────────────────────────────────────────────────────┤
│  Ash Domains (Business Logic)                               │
│  ┌──────────┬──────────┬──────────┬──────────┬───────────┐  │
│  │ Tickets  │   SLA    │   AI     │Integra-  │ Settings  │  │
│  │          │          │          │  tions   │           │  │
│  └──────────┴──────────┴──────────┴──────────┴───────────┘  │
├─────────────────────────────────────────────────────────────┤
│  Oban Workers (Background Processing)                       │
│  ┌──────────┬──────────┬──────────┬──────────┬───────────┐  │
│  │ Webhook  │   SLA    │    AI    │  Rule    │  Sync     │  │
│  │Processors│ Notifier │  Triage  │ Actions  │           │  │
│  └──────────┴──────────┴──────────┴──────────┴───────────┘  │
├─────────────────────────────────────────────────────────────┤
│  PostgreSQL (AshPostgres) + Oban Jobs                       │
└─────────────────────────────────────────────────────────────┘
```

## Tech Stack

| Layer | Technology |
|---|---|
| Framework | Phoenix 1.8 + LiveView 1.1 |
| Resource Modeling | Ash 3.x + AshPostgres + AshStateMachine + AshOban |
| Background Jobs | Oban (webhooks, SLA, AI triage, rules, sync queues) |
| Database | PostgreSQL 16 |
| HTTP Client | Req |
| Integrations | Front, Slack, Linear (with circuit breakers) |
| Security | AES-256-GCM credential vault, HMAC webhook signatures |

## Key Features

**Ticket Lifecycle** — Declarative state machine (new → triaging → assigned → waiting → escalated → resolved → closed) with automatic SLA tracking and escalation.

**SLA Engine** — Tier×severity SLA policies with real-time countdown, automatic escalation via AshOban scheduled triggers, and breach alerting.

**AI Triage** — Automatic ticket classification (severity, product area, draft response) via pluggable AI pipeline with confidence scoring.

**Automation Rules** — Configurable condition/action rules evaluated on ticket events, with Oban-backed action execution (assign, notify, escalate, create Linear issues).

**Integration Hub** — Front, Slack, and Linear integrations with ETS-backed circuit breakers, idempotent webhook processing, and encrypted credential storage.

**Real-time Dashboard** — 12 LiveView pages with PubSub-driven updates, sidebar badge counts, and a guided tour for reviewers.

## Quick Start

### With Docker

```bash
cp .env.example .env
docker compose up -d
# App available at http://localhost:4500
```

### Local Development

```bash
# Prerequisites: Elixir 1.17+, PostgreSQL 16+
mix setup
mix phx.server
# Visit http://localhost:4500
```

### Running Tests

```bash
mix test
mix test --cover
```

## Project Structure

```
lib/
├── support_deck/
│   ├── tickets/          # Ticket, TicketActivity, Rule resources + RuleEngine
│   ├── sla/              # SLA Policy resource + defaults
│   ├── ai/               # TriageResult, KnowledgeDoc, Classification
│   ├── integrations/     # CircuitBreaker, Front/Slack/Linear clients
│   ├── settings/         # Credential resource, Vault, Resolver
│   ├── workers/          # Oban workers (webhooks, SLA, AI, rules)
│   ├── tickets.ex        # Tickets domain
│   ├── sla_domain.ex     # SLA domain
│   ├── ai_domain.ex      # AI domain
│   ├── integrations_domain.ex
│   └── settings_domain.ex
├── support_deck_web/
│   ├── live/             # 12 LiveView pages
│   ├── controllers/      # Webhook + Health controllers
│   ├── plugs/            # Raw body caching, signature verification
│   └── components/       # Layouts with sidebar navigation
```

## Design Decisions

- **Ash as the core** — All business logic lives in declarative Ash resources and domains, providing a consistent API layer with built-in validation, authorization hooks, and code generation.
- **AshStateMachine for ticket lifecycle** — State transitions are declarative and enforced at the resource level, making invalid state changes impossible.
- **AshOban for scheduled work** — SLA checks and auto-close are defined directly on the Ticket resource, keeping scheduling logic co-located with the resource it operates on.
- **ETS-backed circuit breakers** — External API calls go through a GenServer-based circuit breaker to prevent cascade failures, with per-integration isolation.
- **Encrypted credential vault** — Integration credentials are AES-256-GCM encrypted at rest with an ETS-cached resolver for fast lookups.
- **Idempotent webhook processing** — Every webhook event is stored with a unique constraint before processing, preventing duplicate handling.
