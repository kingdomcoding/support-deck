defmodule SupportDeckWeb.Plugs.CacheRawBody do
  @moduledoc """
  Reads the raw body from the cache set by the custom body reader
  and stores it in conn.assigns[:raw_body].

  Requires Plug.Parsers to use `body_reader: {__MODULE__, :read_body, []}`.
  """

  def init(opts), do: opts

  def call(conn, _opts) do
    raw = conn.private[:raw_body] || ""
    Plug.Conn.assign(conn, :raw_body, raw)
  end

  @doc """
  Custom body reader that caches the raw body in conn.private[:raw_body].
  Used as the body_reader option for Plug.Parsers.
  """
  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        conn = Plug.Conn.put_private(conn, :raw_body, body)
        {:ok, body, conn}

      {:more, body, conn} ->
        conn = Plug.Conn.put_private(conn, :raw_body, body)
        {:more, body, conn}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
