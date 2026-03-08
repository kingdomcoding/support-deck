defmodule SupportDeck.Tickets.Ticket do
  use Ash.Resource,
    domain: SupportDeck.Tickets,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStateMachine, AshOban]

  postgres do
    table("tickets")
    repo(SupportDeck.Repo)

    custom_indexes do
      index([:source, :external_id], unique: true)
      index([:state], where: "state NOT IN ('resolved', 'closed')")

      index([:sla_deadline],
        where: "state NOT IN ('resolved', 'closed') AND sla_deadline IS NOT NULL"
      )

      index([:assignee])
      index([:product_area])
    end
  end

  state_machine do
    initial_states([:new])
    default_initial_state(:new)

    transitions do
      transition(:begin_triage, from: :new, to: :triaging)

      transition(:assign_to,
        from: [:new, :triaging, :escalated, :resolved, :closed],
        to: :assigned
      )

      transition(:wait_on_customer, from: [:assigned, :escalated], to: :waiting_on_customer)
      transition(:customer_replied, from: :waiting_on_customer, to: :assigned)

      transition(:escalate,
        from: [:new, :triaging, :assigned, :waiting_on_customer],
        to: :escalated
      )

      transition(:resolve, from: [:assigned, :escalated, :waiting_on_customer], to: :resolved)

      transition(:close,
        from: [:new, :triaging, :assigned, :waiting_on_customer, :escalated, :resolved],
        to: :closed
      )
    end
  end

  oban do
    triggers do
      trigger :check_sla do
        action(:check_and_escalate_sla)
        scheduler_cron("* * * * *")

        where(
          expr(
            state not in [:resolved, :closed] and
              not is_nil(sla_deadline) and
              sla_deadline <= now()
          )
        )

        queue(:sla)
        max_attempts(1)
        scheduler_module_name(SupportDeck.Tickets.Ticket.AshOban.CheckSlaScheduler)
        worker_module_name(SupportDeck.Tickets.Ticket.AshOban.CheckSlaWorker)
      end

      trigger :auto_close_resolved do
        action(:close)
        scheduler_cron("0 * * * *")
        where(expr(state == :resolved and updated_at <= ago(48, :hour)))
        queue(:maintenance)
        max_attempts(3)
        scheduler_module_name(SupportDeck.Tickets.Ticket.AshOban.AutoCloseScheduler)
        worker_module_name(SupportDeck.Tickets.Ticket.AshOban.AutoCloseWorker)
      end
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute(:external_id, :string, allow_nil?: false, public?: true)

    attribute :source, :atom do
      constraints(one_of: [:front, :slack, :manual])
      allow_nil?(false)
      public?(true)
    end

    attribute(:subject, :string, allow_nil?: false, public?: true)
    attribute(:body, :string, public?: true)

    attribute :severity, :atom do
      constraints(one_of: [:low, :medium, :high, :critical])
      default(:low)
      allow_nil?(false)
      public?(true)
    end

    attribute :product_area, :atom do
      constraints(
        one_of: [
          :auth,
          :database,
          :storage,
          :functions,
          :realtime,
          :dashboard,
          :billing,
          :general
        ]
      )

      public?(true)
    end

    attribute :subscription_tier, :atom do
      constraints(one_of: [:free, :pro, :team, :enterprise])
      default(:free)
      public?(true)
    end

    attribute(:customer_email, :string, public?: true)
    attribute(:customer_id, :string, public?: true)
    attribute(:assignee, :string, public?: true)

    attribute(:front_conversation_id, :string, public?: true)
    attribute(:slack_thread_ts, :string, public?: true)
    attribute(:slack_channel_id, :string, public?: true)
    attribute(:linear_issue_id, :string, public?: true)

    attribute(:sla_deadline, :utc_datetime, public?: true)
    attribute(:escalation_level, :integer, default: 0, public?: true)

    attribute(:ai_classification, :map, public?: true)
    attribute(:ai_draft_response, :string, public?: true)
    attribute(:ai_confidence, :float, public?: true)

    attribute(:metadata, :map, default: %{}, public?: true)

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    has_many :activities, SupportDeck.Tickets.TicketActivity
    has_many :triage_results, SupportDeck.AI.TriageResult
  end

  identities do
    identity(:unique_source_external, [:source, :external_id])
  end

  actions do
    defaults([:read, :destroy])

    create :open do
      accept([
        :external_id,
        :source,
        :subject,
        :body,
        :severity,
        :product_area,
        :subscription_tier,
        :customer_email,
        :customer_id,
        :front_conversation_id,
        :slack_thread_ts,
        :slack_channel_id,
        :metadata
      ])

      change(fn changeset, _ctx ->
        tier = Ash.Changeset.get_attribute(changeset, :subscription_tier) || :free
        severity = Ash.Changeset.get_attribute(changeset, :severity) || :low

        case SupportDeck.SLA.Defaults.deadline_minutes(tier, severity) do
          nil ->
            changeset

          minutes ->
            deadline = DateTime.add(DateTime.utc_now(), minutes * 60)
            Ash.Changeset.force_change_attribute(changeset, :sla_deadline, deadline)
        end
      end)

      change(
        after_action(fn changeset, ticket, _ctx ->
          broadcast({:ticket_created, ticket})
          SupportDeck.Tickets.log_activity!(ticket.id, "created", "system")
          {:ok, ticket}
        end)
      )
    end

    create :upsert do
      accept([
        :external_id,
        :source,
        :subject,
        :body,
        :severity,
        :product_area,
        :subscription_tier,
        :customer_email,
        :customer_id,
        :front_conversation_id,
        :slack_thread_ts,
        :slack_channel_id,
        :metadata
      ])

      upsert?(true)
      upsert_identity(:unique_source_external)

      upsert_fields([
        :subject,
        :body,
        :severity,
        :product_area,
        :subscription_tier,
        :customer_email,
        :metadata
      ])

      change(fn changeset, _ctx ->
        tier = Ash.Changeset.get_attribute(changeset, :subscription_tier) || :free
        severity = Ash.Changeset.get_attribute(changeset, :severity) || :low

        case SupportDeck.SLA.Defaults.deadline_minutes(tier, severity) do
          nil ->
            changeset

          minutes ->
            deadline = DateTime.add(DateTime.utc_now(), minutes * 60)
            Ash.Changeset.force_change_attribute(changeset, :sla_deadline, deadline)
        end
      end)

      change(
        after_action(fn changeset, ticket, _ctx ->
          broadcast({:ticket_created, ticket})
          SupportDeck.Tickets.log_activity!(ticket.id, "created", "system")
          {:ok, ticket}
        end)
      )
    end

    update :begin_triage do
      require_atomic?(false)
      accept([])
      change(transition_state(:triaging))

      change(
        after_action(fn _changeset, ticket, _ctx ->
          log_and_broadcast(ticket, "state_change", "system", "triaging")
          {:ok, ticket}
        end)
      )
    end

    update :assign_to do
      require_atomic?(false)
      accept([:assignee])
      change(transition_state(:assigned))

      change(
        after_action(fn _changeset, ticket, _ctx ->
          log_and_broadcast(ticket, "assignment", "system", ticket.assignee)
          {:ok, ticket}
        end)
      )
    end

    update :wait_on_customer do
      require_atomic?(false)
      accept([])
      change(transition_state(:waiting_on_customer))

      change(
        after_action(fn _changeset, ticket, _ctx ->
          log_and_broadcast(ticket, "state_change", "agent", "waiting_on_customer")
          {:ok, ticket}
        end)
      )
    end

    update :customer_replied do
      require_atomic?(false)
      accept([])
      change(transition_state(:assigned))

      change(
        after_action(fn _changeset, ticket, _ctx ->
          log_and_broadcast(ticket, "state_change", "customer", "assigned")
          {:ok, ticket}
        end)
      )
    end

    update :escalate do
      require_atomic?(false)
      accept([])
      change(transition_state(:escalated))
      change(increment(:escalation_level))

      change(
        after_action(fn _changeset, ticket, _ctx ->
          log_and_broadcast(ticket, "escalation", "sla_checker", "L#{ticket.escalation_level}")
          {:ok, ticket}
        end)
      )
    end

    update :resolve do
      require_atomic?(false)
      accept([])
      change(transition_state(:resolved))

      change(
        after_action(fn _changeset, ticket, _ctx ->
          log_and_broadcast(ticket, "state_change", "agent", "resolved")
          {:ok, ticket}
        end)
      )
    end

    update :close do
      require_atomic?(false)
      accept([])
      change(transition_state(:closed))

      change(
        after_action(fn _changeset, ticket, _ctx ->
          log_and_broadcast(ticket, "state_change", "system", "closed")
          {:ok, ticket}
        end)
      )
    end

    update :apply_ai_results do
      require_atomic?(false)
      accept([:ai_classification, :ai_draft_response, :ai_confidence, :product_area, :severity, :subscription_tier])

      change(fn changeset, _ctx ->
        Ash.Changeset.after_action(changeset, fn _changeset, ticket ->
          log_and_broadcast(ticket, "ai_triage", "system", "completed")
          {:ok, ticket}
        end)
      end)
    end

    update :link_linear_issue do
      require_atomic?(false)
      accept([:linear_issue_id])
    end

    update :set_sla_deadline do
      require_atomic?(false)
      accept([:sla_deadline])
    end

    update :check_and_escalate_sla do
      require_atomic?(false)
      accept([])
      change(transition_state(:escalated))

      change(fn changeset, _ctx ->
        lock_key = :erlang.phash2({"sla", Ash.Changeset.get_data(changeset, :id)})

        case SupportDeck.Repo.query("SELECT pg_try_advisory_xact_lock($1)", [lock_key]) do
          {:ok, %{rows: [[true]]}} ->
            changeset
            |> Ash.Changeset.force_change_attribute(
              :escalation_level,
              (Ash.Changeset.get_data(changeset, :escalation_level) || 0) + 1
            )
            |> Ash.Changeset.set_context(%{sla_lock_acquired: true})

          _ ->
            changeset
        end
      end)

      change(
        after_action(fn _changeset, ticket, _ctx ->
          if _changeset.context[:sla_lock_acquired] do
            SupportDeck.Workers.SLANotifier.enqueue(ticket)
            broadcast({:ticket_escalated, ticket})
            SupportDeck.Tickets.log_activity!(ticket.id, "escalation", "sla_checker", "SLA breached")
          end

          {:ok, ticket}
        end)
      )
    end

    read :open_tickets do
      description("All non-resolved/closed tickets, ordered by SLA urgency.")

      filter(expr(state not in [:resolved, :closed]))

      prepare(fn query, _ctx ->
        Ash.Query.sort(query, sla_deadline: :asc_nils_last, inserted_at: :desc)
      end)
    end

    read :by_status do
      argument(:status, :atom, allow_nil?: false)

      filter(expr(state == ^arg(:status)))

      prepare(fn query, _ctx ->
        Ash.Query.sort(query, inserted_at: :desc)
      end)
    end

    read :by_source_and_external_id do
      argument(:source, :atom, allow_nil?: false)
      argument(:external_id, :string, allow_nil?: false)

      filter(expr(source == ^arg(:source) and external_id == ^arg(:external_id)))
    end

    read :by_slack_thread do
      argument(:channel_id, :string, allow_nil?: false)
      argument(:thread_ts, :string, allow_nil?: false)

      filter(expr(slack_channel_id == ^arg(:channel_id) and slack_thread_ts == ^arg(:thread_ts)))
    end

    read :by_linear_issue do
      argument(:linear_issue_id, :string, allow_nil?: false)

      filter(expr(linear_issue_id == ^arg(:linear_issue_id)))
    end

    read :breaching_sla do
      description("Tickets past their SLA deadline that haven't been resolved.")

      filter(
        expr(
          state not in [:resolved, :closed] and
            not is_nil(sla_deadline) and
            sla_deadline <= now()
        )
      )
    end

    read :for_auto_close do
      description("Resolved tickets older than 48 hours.")

      filter(expr(state == :resolved and updated_at <= ago(48, :hour)))
    end
  end

  calculations do
    calculate(
      :sla_remaining_minutes,
      :integer,
      expr(fragment("EXTRACT(EPOCH FROM (? - NOW())) / 60", sla_deadline))
    )
  end

  defp broadcast(message) do
    Phoenix.PubSub.broadcast(SupportDeck.PubSub, "tickets:updates", message)
  end

  defp log_and_broadcast(ticket, action, actor, value) do
    SupportDeck.Tickets.log_activity!(ticket.id, action, actor, value)
    broadcast({:ticket_updated, ticket})
  end
end
