alias SupportDeck.{Tickets, AI}

# ── SLA Policies ──────────────────────────────────────────────────────

for tier <- [:free, :pro, :team, :enterprise],
    severity <- [:low, :medium, :high, :critical] do
  minutes = SupportDeck.SLA.Defaults.deadline_minutes(tier, severity)

  if minutes do
    SupportDeck.SLADomain.create_policy(%{
      name: "#{tier}-#{severity}",
      subscription_tier: tier,
      severity: severity,
      first_response_minutes: minutes,
      resolution_minutes: minutes * 4,
      escalation_thresholds: %{"L1" => div(minutes, 2), "L2" => minutes, "L3" => minutes * 2},
      enabled: true
    })
  end
end

IO.puts("Seeded SLA policies")

# ── Tickets (15 total) ────────────────────────────────────────────────

tickets_data = [
  # NEW (3)
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

  # TRIAGING (2)
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

  # ASSIGNED (4)
  %{
    subject: "RLS policy bypassed via service_role key in client bundle",
    body: "We accidentally shipped our service_role key in a client-side bundle. RLS is being bypassed. Need emergency key rotation.",
    source: :front, severity: :critical, subscription_tier: :enterprise,
    customer_email: "security@vaultpay.com", product_area: :database,
    external_id: "seed-6"
  },
  %{
    subject: "Billing shows Team plan but features are Pro-level",
    body: "We upgraded to Team last week but the dashboard still shows Pro limits. Support chat said to file a ticket.",
    source: :front, severity: :high, subscription_tier: :team,
    customer_email: "finance@growthapp.io", product_area: :billing,
    external_id: "seed-7"
  },
  %{
    subject: "PostgREST returns 500 on nested resource embedding",
    body: "SELECT from a view with nested foreign key relationships returns 500 instead of the joined data.",
    source: :slack, severity: :medium, subscription_tier: :pro,
    customer_email: "backend@saasbuilder.dev", product_area: :database,
    external_id: "seed-8"
  },
  %{
    subject: "Auth email templates not sending custom branding",
    body: "We configured custom email templates in the dashboard but confirmation emails still show default Supabase branding.",
    source: :front, severity: :medium, subscription_tier: :enterprise,
    customer_email: "product@luxuryretail.com", product_area: :auth,
    external_id: "seed-9"
  },

  # WAITING ON CUSTOMER (2)
  %{
    subject: "Storage bucket CORS policy not applying",
    body: "We've set CORS origins on our storage bucket but cross-origin uploads still fail. Browser console shows CORS error.",
    source: :front, severity: :medium, subscription_tier: :team,
    customer_email: "frontend@mediaco.com", product_area: :storage,
    external_id: "seed-10"
  },
  %{
    subject: "Realtime presence shows stale users after disconnect",
    body: "Users who close their browser still appear in the presence state for 5+ minutes after disconnecting.",
    source: :slack, severity: :low, subscription_tier: :pro,
    customer_email: "dev@collabtools.io", product_area: :realtime,
    external_id: "seed-11"
  },

  # ESCALATED (2)
  %{
    subject: "Database connection pool exhausted under normal load",
    body: "We're hitting connection limits with only ~30 concurrent users on Enterprise plan. PgBouncer is configured but connections still exhaust.",
    source: :front, severity: :critical, subscription_tier: :enterprise,
    customer_email: "infra@megafinance.com", product_area: :database,
    external_id: "seed-12"
  },
  %{
    subject: "Auth JWT validation fails intermittently in EU region",
    body: "About 5% of requests get 401 with valid JWTs. Only happens in eu-west-1. US regions are fine.",
    source: :slack, severity: :high, subscription_tier: :enterprise,
    customer_email: "sre@eurobank.de", product_area: :auth,
    external_id: "seed-13"
  },

  # RESOLVED (2)
  %{
    subject: "Edge function deploy stuck in 'Building' state",
    body: "Deployed a new edge function 3 hours ago and it's still showing 'Building'. Previous deploys worked fine.",
    source: :front, severity: :medium, subscription_tier: :pro,
    customer_email: "dev@indiemaker.co", product_area: :functions,
    external_id: "seed-14"
  },
  %{
    subject: "Cannot delete unused project from dashboard",
    body: "Getting a 500 error when trying to delete an old test project. The delete button spins and then shows an error toast.",
    source: :manual, severity: :low, subscription_tier: :free,
    customer_email: "learner@student.edu", product_area: :dashboard,
    external_id: "seed-15"
  }
]

created_tickets =
  for data <- tickets_data do
    case Tickets.open_ticket(data.subject, Map.delete(data, :subject)) do
      {:ok, ticket} -> ticket
      {:error, err} ->
        IO.puts("Failed to create ticket: #{inspect(err)}")
        nil
    end
  end
  |> Enum.reject(&is_nil/1)

IO.puts("Seeded #{length(created_tickets)} tickets")

# ── State Transitions ─────────────────────────────────────────────────

by_id = Map.new(created_tickets, &{&1.external_id, &1})

# TRIAGING: seed-4, seed-5
for eid <- ~w(seed-4 seed-5), t = by_id[eid], t != nil do
  Tickets.begin_triage(t)
end

# ASSIGNED: seed-6, seed-7, seed-8, seed-9
assignees = %{
  "seed-6" => "maria.chen@supabase.io",
  "seed-7" => "billing-team@supabase.io",
  "seed-8" => "james.wu@supabase.io",
  "seed-9" => "auth-team@supabase.io"
}

for {eid, assignee} <- assignees, t = by_id[eid], t != nil do
  Tickets.assign_ticket(t, assignee)
end

# WAITING ON CUSTOMER: seed-10, seed-11
for eid <- ~w(seed-10 seed-11), t = by_id[eid], t != nil do
  {:ok, assigned} = Tickets.assign_ticket(t, "support-l1@supabase.io")
  Tickets.wait_on_customer(assigned)
end

# ESCALATED: seed-12, seed-13
for eid <- ~w(seed-12 seed-13), t = by_id[eid], t != nil do
  Tickets.escalate_ticket(t)
end

# RESOLVED: seed-14, seed-15
for eid <- ~w(seed-14 seed-15), t = by_id[eid], t != nil do
  {:ok, assigned} = Tickets.assign_ticket(t, "support-l1@supabase.io")
  Tickets.resolve_ticket(assigned)
end

IO.puts("Applied ticket state transitions")

# ── SLA Deadline Backdating ───────────────────────────────────────────

now = DateTime.utc_now()

# Enterprise critical — breached 47 minutes ago
SupportDeck.Repo.query!(
  "UPDATE tickets SET sla_deadline = $1 WHERE external_id = $2",
  [DateTime.add(now, -47, :minute), "seed-12"]
)

# Enterprise high — breached 12 minutes ago
SupportDeck.Repo.query!(
  "UPDATE tickets SET sla_deadline = $1 WHERE external_id = $2",
  [DateTime.add(now, -12, :minute), "seed-13"]
)

# Approaching breach — 4 minutes from now
SupportDeck.Repo.query!(
  "UPDATE tickets SET sla_deadline = $1 WHERE external_id = $2",
  [DateTime.add(now, 4, :minute), "seed-7"]
)

# Approaching breach — 8 minutes from now
SupportDeck.Repo.query!(
  "UPDATE tickets SET sla_deadline = $1 WHERE external_id = $2",
  [DateTime.add(now, 8, :minute), "seed-9"]
)

IO.puts("Backdated SLA deadlines")

# ── Activity Logs ─────────────────────────────────────────────────────

if t = by_id["seed-12"] do
  Tickets.log_activity(t.id, "ai_triage", "ai_classifier", "classified as database/critical (confidence: 94%)")
  Tickets.log_activity(t.id, "rule_fired", "automation", "Rule 'Auto-escalate Enterprise tickets breaching L1 SLA' matched")
  Tickets.log_activity(t.id, "sla_breach", "sla_checker", "Response SLA breached — 10min target exceeded by 37min")
end

if t = by_id["seed-13"] do
  Tickets.log_activity(t.id, "ai_triage", "ai_classifier", "classified as auth/high (confidence: 88%)")
  Tickets.log_activity(t.id, "rule_fired", "automation", "Rule 'Route Auth tickets to Auth specialist queue' matched")
  Tickets.log_activity(t.id, "sla_breach", "sla_checker", "Response SLA breached — 30min target exceeded by 12min")
end

if t = by_id["seed-6"] do
  Tickets.log_activity(t.id, "ai_triage", "ai_classifier", "classified as database/critical (confidence: 97%)")
  Tickets.log_activity(t.id, "rule_fired", "automation", "Rule 'Create Linear issue for critical severity' matched")
end

if t = by_id["seed-14"] do
  Tickets.log_activity(t.id, "ai_triage", "ai_classifier", "classified as functions/medium (confidence: 91%)")
  Tickets.log_activity(t.id, "draft_approved", "agent", "AI draft response approved and sent")
end

if t = by_id["seed-15"] do
  Tickets.log_activity(t.id, "ai_triage", "ai_classifier", "classified as dashboard/low (confidence: 72%)")
end

IO.puts("Seeded activity logs")

# ── AI Triage Results ─────────────────────────────────────────────────

draft_for = fn
  :auth -> "Thanks for reporting this authentication issue. Here are some steps to try:\n\n1. Verify your redirect URIs match exactly (including trailing slashes)\n2. Check that your JWT secret hasn't been rotated recently\n3. Clear browser cookies and try again\n\nCould you share your project ref so we can check the auth logs?"
  :database -> "Thank you for reaching out about this database issue. Let's investigate:\n\n1. Check your connection pool settings in the dashboard under Database > Settings\n2. Verify PgBouncer is enabled and configured for transaction mode\n3. Review the pg_stat_activity view for idle connections\n\nWhat's your current max_connections setting?"
  :storage -> "Thanks for reporting this storage issue. A few things to check:\n\n1. Verify your file size is within your plan's limits\n2. Check that your storage bucket's file size limit hasn't been set lower than the plan default\n3. Try uploading via the CLI to rule out browser-specific issues\n\nCan you share the full error response body?"
  :functions -> "Thank you for reporting this Edge Functions issue. Let's troubleshoot:\n\n1. Check the function logs in the dashboard for timeout or memory errors\n2. Verify your function doesn't exceed the memory limit for your plan\n3. Try redeploying the function\n\nCould you share the function name and region?"
  :realtime -> "Thanks for reaching out about Realtime. Here are some things to check:\n\n1. Verify your client is sending heartbeat pings every 30 seconds\n2. Check if you're hitting the concurrent connection limit for your plan\n3. Review the Realtime logs in the dashboard\n\nWhat client library version are you using?"
  :billing -> "Thank you for reaching out about this billing concern. I've flagged this for our billing team to review. In the meantime:\n\n1. Check your subscription status at supabase.com/dashboard/account/billing\n2. Verify the payment method on file is current\n\nWe'll follow up within 24 hours with a resolution."
  :dashboard -> "Thanks for reporting this dashboard issue. A few things that might help:\n\n1. Try clearing your browser cache and refreshing\n2. Check if the issue persists in an incognito window\n3. Try a different browser\n\nCould you share a screenshot of the issue?"
  _ -> "Thank you for contacting Supabase support. We've received your ticket and a team member will review it shortly."
end

# High confidence results (10)
high_conf_eids = ~w(seed-1 seed-2 seed-4 seed-6 seed-7 seed-9 seed-12 seed-13 seed-14 seed-15)

high_conf_results =
  for eid <- high_conf_eids, t = by_id[eid], t != nil do
    {:ok, result} = AI.record_triage(t.id, %{
      predicted_category: to_string(t.product_area || "general"),
      predicted_severity: to_string(t.severity),
      confidence: 0.85 + :rand.uniform() * 0.14,
      draft_response: draft_for.(t.product_area),
      processing_time_ms: 400 + :rand.uniform(800)
    })
    result
  end

# Medium confidence results (5)
med_conf_eids = ~w(seed-3 seed-5 seed-8 seed-10 seed-11)

med_conf_results =
  for eid <- med_conf_eids, t = by_id[eid], t != nil do
    {:ok, result} = AI.record_triage(t.id, %{
      predicted_category: to_string(t.product_area || "general"),
      predicted_severity: to_string(t.severity),
      confidence: 0.50 + :rand.uniform() * 0.34,
      draft_response: draft_for.(t.product_area),
      processing_time_ms: 300 + :rand.uniform(500)
    })
    result
  end

# Low confidence results (4) — simulates fallback heuristic
low_conf_eids = ~w(seed-1 seed-6 seed-12 seed-13)

for eid <- low_conf_eids, t = by_id[eid], t != nil do
  AI.record_triage(t.id, %{
    predicted_category: "general",
    predicted_severity: "medium",
    confidence: 0.25 + :rand.uniform() * 0.24,
    draft_response: nil,
    processing_time_ms: 150 + :rand.uniform(200)
  })
end

IO.puts("Seeded #{length(high_conf_results) + length(med_conf_results) + 4} triage results")

# Record human feedback (~75% acceptance on high, reject on medium)
for {result, i} <- Enum.with_index(Enum.take(high_conf_results, 8)) do
  accepted = rem(i, 4) != 3
  AI.record_feedback(result, %{
    human_accepted: accepted,
    response_used: accepted and rem(i, 2) == 0
  })
end

for result <- Enum.take(med_conf_results, 3) do
  AI.record_feedback(result, %{human_accepted: false, response_used: false})
end

IO.puts("Recorded human feedback on triage results")

# Apply AI draft responses to active tickets
for eid <- ~w(seed-6 seed-9 seed-12 seed-1), t = by_id[eid], t != nil do
  {:ok, current} = Tickets.get_ticket(t.id)
  Tickets.apply_ai_results(current, %{
    ai_classification: %{"category" => to_string(t.product_area), "severity" => to_string(t.severity)},
    ai_draft_response: draft_for.(t.product_area),
    ai_confidence: 0.85 + :rand.uniform() * 0.14,
    product_area: t.product_area,
    severity: t.severity,
    subscription_tier: t.subscription_tier
  })
end

IO.puts("Applied AI draft responses to active tickets")

# ── Automation Rules ──────────────────────────────────────────────────

rules = [
  %{
    name: "Auto-escalate Enterprise tickets breaching L1 SLA",
    description: "Escalate and notify #enterprise-escalations when an Enterprise ticket is created with critical severity",
    trigger: :ticket_created,
    conditions: %{
      "all" => [
        %{"field" => "severity", "op" => "eq", "value" => "critical"},
        %{"field" => "subscription_tier", "op" => "eq", "value" => "enterprise"}
      ]
    },
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
    description: "Automatically create a Linear issue for engineering when ticket severity is critical or high",
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
    description: "Send Slack DM to support lead when any Enterprise ticket goes unresponded",
    trigger: :sla_breach,
    conditions: %{"all" => [%{"field" => "subscription_tier", "op" => "eq", "value" => "enterprise"}]},
    actions_list: [%{"type" => "slack_notify", "params" => %{"channel" => "#support-leads", "mention" => "@support-lead"}}],
    priority: 90, enabled: true
  }
]

for rule <- rules do
  Tickets.create_rule(rule)
end

IO.puts("Seeded automation rules")

# ── Knowledge Docs ────────────────────────────────────────────────────

docs = [
  %{
    content: "To reset a user's password in Supabase Auth, use supabase.auth.admin.updateUserById() with the new password. The user will need to re-authenticate after the change.",
    content_type: :doc,
    source_url: "https://supabase.com/docs/guides/auth"
  },
  %{
    content: "Database connection limits vary by plan: Free (20), Pro (60), Team (200), Enterprise (custom). Connection pooling with PgBouncer is recommended for production workloads.",
    content_type: :doc,
    source_url: "https://supabase.com/docs/guides/database"
  },
  %{
    content: "Storage upload size limits: Free (50MB), Pro (5GB), Team (5GB), Enterprise (custom). For large files, use resumable uploads via the TUS protocol.",
    content_type: :doc,
    source_url: "https://supabase.com/docs/guides/storage"
  },
  %{
    content: "Edge Functions have a 2-second timeout on the Free plan, 60 seconds on Pro/Team, and configurable on Enterprise. Use streaming responses for long-running operations.",
    content_type: :faq
  },
  %{
    content: "RLS policies are evaluated per-row. Common issues: forgetting to enable RLS on a table, using security definer functions that bypass RLS, or misconfigured JWT claims.",
    content_type: :resolved_ticket
  }
]

for doc <- docs do
  AI.add_knowledge_doc(doc)
end

IO.puts("Seeded knowledge docs")

# ── Webhook Events ────────────────────────────────────────────────────

ts = System.os_time(:second)

webhook_events = [
  %{source: :front, external_id: "evt_front_inb_#{ts}", event_type: "inbound",
    payload: %{"type" => "inbound", "conversation" => %{"id" => "cnv_abc123", "subject" => "Login broken after password reset"},
    "target" => %{"data" => %{"body" => "I changed my password and now I can't log in.", "author" => %{"email" => "user@example.com"}}}}},
  %{source: :front, external_id: "evt_front_reply_#{ts}", event_type: "outbound_reply",
    payload: %{"type" => "outbound_reply", "conversation" => %{"id" => "cnv_abc123"}}},
  %{source: :front, external_id: "evt_front_tag_#{ts}", event_type: "tag",
    payload: %{"type" => "tag", "conversation" => %{"id" => "cnv_abc123"}, "tag" => %{"name" => "enterprise"}}},
  %{source: :slack, external_id: "evt_slack_msg_#{ts}", event_type: "message",
    payload: %{"type" => "event_callback", "event" => %{"type" => "message", "text" => "Database connection pool exhausted on project abc123", "user" => "U0ENGINEER", "channel" => "C0SUPPORT"}}},
  %{source: :slack, external_id: "evt_slack_react_#{ts}", event_type: "reaction_added",
    payload: %{"type" => "event_callback", "event" => %{"type" => "reaction_added", "reaction" => "eyes", "item" => %{"channel" => "C0SUPPORT", "ts" => "1234567890.000001"}}}},
  %{source: :slack, external_id: "evt_slack_mention_#{ts}", event_type: "app_mention",
    payload: %{"type" => "event_callback", "event" => %{"type" => "app_mention", "text" => "help with auth tokens expiring", "user" => "U0SUPPORT", "channel" => "C0ESCALATIONS"}}},
  %{source: :linear, external_id: "evt_linear_update_#{ts}", event_type: "issue_update",
    payload: %{"type" => "Issue", "action" => "update", "data" => %{"id" => "LIN-456", "identifier" => "SUP-42", "state" => %{"name" => "In Progress", "type" => "started"}}}},
  %{source: :linear, external_id: "evt_linear_comment_#{ts}", event_type: "comment_create",
    payload: %{"type" => "Comment", "action" => "create", "data" => %{"body" => "Confirmed this is a connection pooling issue. Deploying fix.", "issue" => %{"id" => "LIN-456"}, "user" => %{"name" => "Engineer"}}}}
]

stored_events =
  for event <- webhook_events do
    case SupportDeck.IntegrationsDomain.store_event(event) do
      {:ok, e} -> e
      {:error, _} -> nil
    end
  end
  |> Enum.reject(&is_nil/1)

# Mark most as processed, leave last 2 pending
for event <- Enum.take(stored_events, 6) do
  SupportDeck.IntegrationsDomain.mark_event_processed(event)
end

IO.puts("Seeded #{length(stored_events)} webhook events")

IO.puts("Seeding complete!")
