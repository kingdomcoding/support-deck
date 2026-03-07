defmodule SupportDeckWeb.Plugs.WebhookSignature do
  import Plug.Conn

  @max_timestamp_age_seconds 300

  def verify_front(conn) do
    secret = SupportDeck.Settings.Resolver.get(:front, :webhook_secret)
    signature = get_req_header(conn, "x-front-signature") |> List.first()

    case {secret, signature} do
      {nil, _} ->
        skip_in_dev()

      {_, nil} ->
        {:error, :invalid_signature}

      {s, sig} ->
        expected = :crypto.mac(:hmac, :sha, s, conn.assigns[:raw_body]) |> Base.encode64()
        if Plug.Crypto.secure_compare(expected, sig), do: :ok, else: {:error, :invalid_signature}
    end
  end

  def verify_slack(conn) do
    secret = SupportDeck.Settings.Resolver.get(:slack, :signing_secret)
    timestamp = get_req_header(conn, "x-slack-request-timestamp") |> List.first()
    signature = get_req_header(conn, "x-slack-signature") |> List.first()

    with :ok <- check_timestamp_freshness(timestamp),
         base_string = "v0:#{timestamp}:#{conn.assigns[:raw_body]}",
         expected =
           "v0=" <>
             (:crypto.mac(:hmac, :sha256, secret, base_string) |> Base.encode16(case: :lower)),
         true <- Plug.Crypto.secure_compare(expected, signature || "") do
      :ok
    else
      _ -> {:error, :invalid_signature}
    end
  end

  def verify_linear(conn) do
    secret = SupportDeck.Settings.Resolver.get(:linear, :webhook_secret)
    signature = get_req_header(conn, "linear-signature") |> List.first()

    case {secret, signature} do
      {nil, _} ->
        skip_in_dev()

      {_, nil} ->
        {:error, :invalid_signature}

      {s, sig} ->
        expected =
          :crypto.mac(:hmac, :sha256, s, conn.assigns[:raw_body]) |> Base.encode16(case: :lower)

        if Plug.Crypto.secure_compare(expected, sig), do: :ok, else: {:error, :invalid_signature}
    end
  end

  defp check_timestamp_freshness(nil), do: {:error, :missing_timestamp}

  defp check_timestamp_freshness(timestamp_str) do
    ts = String.to_integer(timestamp_str)
    now = System.system_time(:second)

    if abs(now - ts) <= @max_timestamp_age_seconds,
      do: :ok,
      else: {:error, :timestamp_expired}
  end

  defp skip_in_dev do
    if Application.get_env(:support_deck, :env) == :prod,
      do: {:error, :invalid_signature},
      else: :ok
  end
end
