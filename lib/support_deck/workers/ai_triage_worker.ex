defmodule SupportDeck.Workers.AITriageWorker do
  use Oban.Worker, queue: :ai_triage, max_attempts: 3

  alias SupportDeck.{Tickets, AI}

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"ticket_id" => ticket_id}}) do
    start = System.monotonic_time(:millisecond)

    with {:ok, ticket} <- Tickets.get_ticket(ticket_id) do
      Logger.info("ai.triage.started", ticket_id: ticket_id)

      classification = classify(ticket)
      elapsed = System.monotonic_time(:millisecond) - start
      draft = maybe_generate_draft(ticket, classification)

      Tickets.apply_ai_results(ticket, %{
        ai_classification: classification,
        ai_draft_response: draft,
        ai_confidence: classification["confidence"],
        product_area: parse_area(classification),
        severity: parse_severity(classification)
      })

      AI.record_triage(ticket_id, %{
        predicted_category: classification["product_area"],
        predicted_severity: classification["severity"],
        confidence: classification["confidence"],
        is_repetitive: classification["is_repetitive"] || false,
        draft_response: draft,
        processing_time_ms: elapsed
      })

      if classification["is_repetitive"] && classification["confidence"] > 0.85 do
        Tickets.begin_triage(ticket)
      end

      Logger.info("ai.triage.completed",
        ticket_id: ticket_id,
        category: classification["product_area"],
        confidence: classification["confidence"],
        elapsed_ms: elapsed
      )

      :ok
    end
  end

  defp classify(ticket) do
    # Placeholder classification until ash_ai is integrated.
    # Returns a mock result based on simple keyword heuristics.
    body = ticket.body || ""
    subject = ticket.subject || ""
    text = String.downcase(subject <> " " <> body)

    product_area = cond do
      String.contains?(text, "auth") or String.contains?(text, "login") -> "auth"
      String.contains?(text, "database") or String.contains?(text, "postgres") -> "database"
      String.contains?(text, "storage") or String.contains?(text, "bucket") -> "storage"
      String.contains?(text, "function") or String.contains?(text, "edge function") -> "functions"
      String.contains?(text, "realtime") or String.contains?(text, "websocket") -> "realtime"
      String.contains?(text, "dashboard") -> "dashboard"
      String.contains?(text, "billing") or String.contains?(text, "invoice") -> "billing"
      true -> "general"
    end

    severity = cond do
      String.contains?(text, "down") or String.contains?(text, "outage") or String.contains?(text, "data loss") -> "critical"
      String.contains?(text, "broken") or String.contains?(text, "error") or String.contains?(text, "fail") -> "high"
      String.contains?(text, "issue") or String.contains?(text, "problem") -> "medium"
      true -> "low"
    end

    %{
      "product_area" => product_area,
      "severity" => severity,
      "is_repetitive" => false,
      "confidence" => 0.6,
      "reasoning" => "Placeholder classification based on keyword matching"
    }
  end

  defp maybe_generate_draft(ticket, classification) do
    if classification["is_repetitive"] && classification["confidence"] > 0.7 do
      area = classification["product_area"]

      "Thank you for reaching out about your #{area} issue. " <>
        "We're looking into \"#{ticket.subject}\" and will get back to you shortly. " <>
        "In the meantime, please check our documentation at https://supabase.com/docs/guides/#{area}."
    end
  end

  defp parse_area(%{"product_area" => area}) when is_binary(area) do
    String.to_existing_atom(area)
  rescue
    _ -> nil
  end
  defp parse_area(_), do: nil

  defp parse_severity(%{"severity" => s}) when is_binary(s) do
    String.to_existing_atom(s)
  rescue
    _ -> nil
  end
  defp parse_severity(_), do: nil
end
