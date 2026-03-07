defmodule SupportDeckWeb.WebhookController do
  use SupportDeckWeb, :controller

  alias SupportDeckWeb.Plugs.WebhookSignature

  def front(conn, _params) do
    with :ok <- WebhookSignature.verify_front(conn),
         {:ok, payload} <- Jason.decode(conn.assigns[:raw_body]),
         event_id = payload["id"] || Ecto.UUID.generate(),
         {:ok, _} <- store_event(:front, event_id, payload["type"], payload) do
      enqueue(SupportDeck.Workers.FrontWebhookWorker, :front, event_id, payload)
      json(conn, %{status: "accepted"})
    else
      {:error, :invalid_signature} -> conn |> put_status(401) |> json(%{error: "invalid_signature"})
      {:error, :duplicate_event} -> json(conn, %{status: "already_processed"})
      {:error, reason} -> conn |> put_status(400) |> json(%{error: inspect(reason)})
    end
  end

  def slack(conn, params) do
    with :ok <- WebhookSignature.verify_slack(conn) do
      if params["type"] == "url_verification" do
        json(conn, %{challenge: params["challenge"]})
      else
        event = params["event"] || %{}

        if event["bot_id"] do
          json(conn, %{status: "ignored_bot"})
        else
          event_id = params["event_id"] || Ecto.UUID.generate()
          event_type = event["type"] || params["type"]

          case store_event(:slack, event_id, event_type, params) do
            {:ok, _} -> enqueue(SupportDeck.Workers.SlackWebhookWorker, :slack, event_id, params)
            {:error, :duplicate_event} -> :ok
          end

          json(conn, %{status: "accepted"})
        end
      end
    else
      {:error, :invalid_signature} -> conn |> put_status(401) |> json(%{error: "invalid_signature"})
    end
  end

  def linear(conn, _params) do
    with :ok <- WebhookSignature.verify_linear(conn),
         {:ok, payload} <- Jason.decode(conn.assigns[:raw_body]),
         delivery_id = get_req_header(conn, "linear-delivery") |> List.first() || Ecto.UUID.generate(),
         event_type = get_req_header(conn, "linear-event") |> List.first() || payload["type"],
         action = payload["action"] do
      case store_event(:linear, delivery_id, "#{event_type}.#{action}", payload) do
        {:ok, _} -> enqueue(SupportDeck.Workers.LinearWebhookWorker, :linear, delivery_id, payload)
        {:error, :duplicate_event} -> :ok
      end

      json(conn, %{status: "accepted"})
    else
      {:error, :invalid_signature} -> conn |> put_status(401) |> json(%{error: "invalid_signature"})
    end
  end

  defp store_event(source, external_id, event_type, payload) do
    case SupportDeck.IntegrationsDomain.store_event(%{
      source: source,
      external_id: external_id,
      event_type: event_type || "unknown",
      payload: payload
    }) do
      {:ok, event} -> {:ok, event}
      {:error, %Ash.Error.Invalid{} = _} -> {:error, :duplicate_event}
      {:error, reason} -> {:error, reason}
    end
  end

  defp enqueue(worker, source, event_id, payload) do
    %{"source" => to_string(source), "event_id" => event_id, "payload" => payload}
    |> worker.new(unique: [keys: [:source, :event_id], period: :infinity])
    |> Oban.insert()
  end
end
