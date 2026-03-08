alias SupportDeck.{Tickets, AI}

# SLA Policies
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

# Tickets
tickets_data = [
  %{
    subject: "Cannot connect to database",
    body: "Getting connection refused errors on our Pro plan",
    source: :front,
    severity: :critical,
    subscription_tier: :pro,
    customer_email: "alice@startup.io",
    product_area: :database,
    external_id: "seed-1"
  },
  %{
    subject: "Auth tokens expiring early",
    body: "JWT tokens are expiring 30 minutes before the configured lifetime",
    source: :front,
    severity: :high,
    subscription_tier: :enterprise,
    customer_email: "bob@bigcorp.com",
    product_area: :auth,
    external_id: "seed-2"
  },
  %{
    subject: "Storage upload fails for large files",
    body: "Files over 50MB fail to upload with a 413 error",
    source: :slack,
    severity: :medium,
    subscription_tier: :team,
    customer_email: "carol@agency.dev",
    product_area: :storage,
    external_id: "seed-3"
  },
  %{
    subject: "Realtime subscriptions dropping",
    body: "WebSocket connections are dropping every 5 minutes",
    source: :front,
    severity: :high,
    subscription_tier: :enterprise,
    customer_email: "dave@fintech.co",
    product_area: :realtime,
    external_id: "seed-4"
  },
  %{
    subject: "Dashboard loading slowly",
    body: "The project dashboard takes 15+ seconds to load",
    source: :manual,
    severity: :low,
    subscription_tier: :free,
    customer_email: "eve@personal.me",
    product_area: :dashboard,
    external_id: "seed-5"
  },
  %{
    subject: "Edge function timeout",
    body: "Edge functions timing out after 2 seconds on the free plan",
    source: :front,
    severity: :medium,
    subscription_tier: :free,
    customer_email: "frank@hobby.dev",
    product_area: :functions,
    external_id: "seed-6"
  },
  %{
    subject: "Billing discrepancy",
    body: "Charged for Team plan but only have Pro features enabled",
    source: :front,
    severity: :high,
    subscription_tier: :team,
    customer_email: "grace@saas.io",
    product_area: :billing,
    external_id: "seed-7"
  },
  %{
    subject: "Row level security not working",
    body: "RLS policies are being bypassed for authenticated users",
    source: :slack,
    severity: :critical,
    subscription_tier: :enterprise,
    customer_email: "henry@secure.co",
    product_area: :database,
    external_id: "seed-8"
  },
  %{
    subject: "Cannot delete project",
    body: "Getting a 500 error when trying to delete an unused project",
    source: :manual,
    severity: :low,
    subscription_tier: :pro,
    customer_email: "iris@dev.team",
    product_area: :dashboard,
    external_id: "seed-9"
  },
  %{
    subject: "Migration stuck in pending",
    body: "Database migration has been in pending state for 2 hours",
    source: :front,
    severity: :medium,
    subscription_tier: :team,
    customer_email: "jack@devops.co",
    product_area: :database,
    external_id: "seed-10"
  }
]

created_tickets =
  for data <- tickets_data do
    case Tickets.open_ticket(data.subject, Map.delete(data, :subject)) do
      {:ok, ticket} ->
        ticket

      {:error, err} ->
        IO.puts("Failed to create ticket: #{inspect(err)}")
        nil
    end
  end
  |> Enum.reject(&is_nil/1)

IO.puts("Seeded #{length(created_tickets)} tickets")

# Transition some tickets to different states
if length(created_tickets) >= 5 do
  [t1, t2, t3, t4 | _] = created_tickets
  Tickets.begin_triage(t1)
  Tickets.assign_ticket(t2, "support-agent-1@supabase.io")

  with {:ok, t3} <- Tickets.assign_ticket(t3, "support-agent-2@supabase.io") do
    Tickets.resolve_ticket(t3)
  end

  Tickets.escalate_ticket(t4)
end

IO.puts("Applied ticket state transitions")

# Automation Rules
rules = [
  %{
    name: "Auto-escalate critical enterprise",
    trigger: :ticket_created,
    conditions: %{
      "all" => [
        %{"field" => "severity", "op" => "eq", "value" => "critical"},
        %{"field" => "subscription_tier", "op" => "eq", "value" => "enterprise"}
      ]
    },
    actions_list: [%{"type" => "escalate"}],
    priority: 100,
    enabled: true
  },
  %{
    name: "Notify on high severity",
    trigger: :ticket_created,
    conditions: %{
      "all" => [%{"field" => "severity", "op" => "in", "value" => ["high", "critical"]}]
    },
    actions_list: [%{"type" => "slack_notify", "params" => %{"channel" => "#support-alerts"}}],
    priority: 50,
    enabled: true
  },
  %{
    name: "Auto-assign billing tickets",
    trigger: :ticket_created,
    conditions: %{"all" => [%{"field" => "product_area", "op" => "eq", "value" => "billing"}]},
    actions_list: [%{"type" => "assign", "params" => %{"assignee" => "billing-team@supabase.io"}}],
    priority: 30,
    enabled: true
  },
  %{
    name: "Create Linear for database issues",
    trigger: :ticket_created,
    conditions: %{
      "all" => [
        %{"field" => "product_area", "op" => "eq", "value" => "database"},
        %{"field" => "severity", "op" => "in", "value" => ["high", "critical"]}
      ]
    },
    actions_list: [%{"type" => "linear_create", "params" => %{"team" => "Database"}}],
    priority: 20,
    enabled: true
  },
  %{
    name: "Auto-reply to Front auth tickets",
    trigger: :ticket_created,
    conditions: %{
      "all" => [
        %{"field" => "product_area", "op" => "eq", "value" => "auth"},
        %{"field" => "source", "op" => "eq", "value" => "front"}
      ]
    },
    actions_list: [
      %{
        "type" => "front_reply",
        "params" => %{
          "body" =>
            "Thank you for reporting this auth issue. We're looking into it and will respond shortly. In the meantime, please check https://supabase.com/docs/guides/auth for troubleshooting steps."
        }
      }
    ],
    priority: 10,
    enabled: true
  }
]

for rule <- rules do
  Tickets.create_rule(rule)
end

IO.puts("Seeded automation rules")

# Knowledge Docs
docs = [
  %{
    content:
      "To reset a user's password in Supabase Auth, use supabase.auth.admin.updateUserById() with the new password. The user will need to re-authenticate after the change.",
    content_type: :doc,
    source_url: "https://supabase.com/docs/guides/auth"
  },
  %{
    content:
      "Database connection limits vary by plan: Free (20), Pro (60), Team (200), Enterprise (custom). Connection pooling with PgBouncer is recommended for production workloads.",
    content_type: :doc,
    source_url: "https://supabase.com/docs/guides/database"
  },
  %{
    content:
      "Storage upload size limits: Free (50MB), Pro (5GB), Team (5GB), Enterprise (custom). For large files, use resumable uploads via the TUS protocol.",
    content_type: :doc,
    source_url: "https://supabase.com/docs/guides/storage"
  },
  %{
    content:
      "Edge Functions have a 2-second timeout on the Free plan, 60 seconds on Pro/Team, and configurable on Enterprise. Use streaming responses for long-running operations.",
    content_type: :faq
  },
  %{
    content:
      "RLS policies are evaluated per-row. Common issues: forgetting to enable RLS on a table, using security definer functions that bypass RLS, or misconfigured JWT claims.",
    content_type: :resolved_ticket
  }
]

for doc <- docs do
  AI.add_knowledge_doc(doc)
end

IO.puts("Seeded knowledge docs")

# Triage Results for some tickets
if length(created_tickets) >= 3 do
  for ticket <- Enum.take(created_tickets, 3) do
    AI.record_triage(ticket.id, %{
      predicted_category: to_string(ticket.product_area || "general"),
      predicted_severity: to_string(ticket.severity),
      confidence: 0.85 + :rand.uniform() * 0.1,
      draft_response:
        "Thank you for reaching out. We're looking into the #{ticket.product_area} issue you reported.",
      processing_time_ms: 500 + :rand.uniform(1000)
    })
  end

  IO.puts("Seeded triage results")
end

IO.puts("Seeding complete!")
