defmodule SupportDeckWeb.Hooks.SidebarCounts do
  import Phoenix.LiveView
  import Phoenix.Component

  def on_mount(:default, _params, _session, socket) do
    socket =
      socket
      |> assign(:ticket_count, 0)
      |> assign(:breach_count, 0)
      |> assign(:rule_count, 0)
      |> assign(:ai_count, 0)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(SupportDeck.PubSub, "tickets:updates")
      Phoenix.PubSub.subscribe(SupportDeck.PubSub, "sla:updates")
      Phoenix.PubSub.subscribe(SupportDeck.PubSub, "rules:updates")

      socket =
        socket
        |> assign(:ticket_count, safe_count(:tickets))
        |> assign(:breach_count, safe_count(:breaching))
        |> assign(:rule_count, safe_count(:rules))
        |> assign(:ai_count, safe_count(:ai_triages))
        |> attach_hook(:sidebar_counts, :handle_info, &handle_sidebar_info/2)

      {:cont, socket}
    else
      {:cont, socket}
    end
  end

  defp handle_sidebar_info({:ticket_created, _}, socket) do
    {:cont, assign(socket, :ticket_count, safe_count(:tickets))}
  end

  defp handle_sidebar_info({:ticket_updated, _}, socket) do
    {:cont,
     socket
     |> assign(:ticket_count, safe_count(:tickets))
     |> assign(:breach_count, safe_count(:breaching))}
  end

  defp handle_sidebar_info({:ticket_escalated, _}, socket) do
    {:cont,
     socket
     |> assign(:ticket_count, safe_count(:tickets))
     |> assign(:breach_count, safe_count(:breaching))}
  end

  defp handle_sidebar_info({:rule_updated, _}, socket) do
    {:cont, assign(socket, :rule_count, safe_count(:rules))}
  end

  defp handle_sidebar_info(_, socket), do: {:cont, socket}

  defp safe_count(:tickets) do
    case SupportDeck.Tickets.list_open_tickets() do
      {:ok, tickets} -> length(tickets)
      _ -> 0
    end
  end

  defp safe_count(:breaching) do
    case SupportDeck.Tickets.list_breaching_sla() do
      {:ok, tickets} -> length(tickets)
      _ -> 0
    end
  end

  defp safe_count(:rules) do
    case SupportDeck.Tickets.list_all_rules() do
      {:ok, rules} -> length(Enum.filter(rules, & &1.enabled))
      _ -> 0
    end
  end

  defp safe_count(:ai_triages) do
    case SupportDeck.AI.list_recent_triage(DateTime.add(DateTime.utc_now(), -24 * 3600)) do
      {:ok, t} -> length(t)
      _ -> 0
    end
  end
end
