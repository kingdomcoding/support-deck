defmodule SupportDeck.Tickets do
  use Ash.Domain

  resources do
    resource SupportDeck.Tickets.Ticket do
      define(:open_ticket, action: :open, args: [:subject])
      define(:upsert_ticket, action: :upsert)

      define(:begin_triage, action: :begin_triage)
      define(:assign_ticket, action: :assign_to, args: [:assignee])
      define(:wait_on_customer, action: :wait_on_customer)
      define(:customer_replied, action: :customer_replied)
      define(:escalate_ticket, action: :escalate)
      define(:resolve_ticket, action: :resolve)
      define(:close_ticket, action: :close)

      define(:apply_ai_results, action: :apply_ai_results)
      define(:clear_draft, action: :clear_draft)
      define(:link_linear_issue, action: :link_linear_issue, args: [:linear_issue_id])

      define(:list_open_tickets, action: :open_tickets)
      define(:list_by_status, action: :by_status, args: [:status])
      define(:get_ticket, action: :read, get_by: [:id])

      define(:get_by_source,
        action: :by_source_and_external_id,
        args: [:source, :external_id],
        get?: true
      )

      define(:get_by_slack_thread,
        action: :by_slack_thread,
        args: [:channel_id, :thread_ts],
        get?: true
      )

      define(:get_by_linear_issue,
        action: :by_linear_issue,
        args: [:linear_issue_id],
        get?: true
      )

      define(:list_breaching_sla, action: :breaching_sla)
    end

    resource SupportDeck.Tickets.TicketActivity do
      define(:log_activity, action: :log, args: [:ticket_id, :action, :actor, {:optional, :to_value}])
      define(:list_activities_for_ticket, action: :for_ticket, args: [:ticket_id])
    end

    resource SupportDeck.Tickets.Rule do
      define(:create_rule, action: :create)
      define(:update_rule, action: :update)
      define(:delete_rule, action: :destroy)
      define(:get_rule, action: :read, get_by: [:id])
      define(:list_rules_for_trigger, action: :enabled_for_trigger, args: [:trigger])
      define(:list_all_rules, action: :all_rules)
    end
  end
end
