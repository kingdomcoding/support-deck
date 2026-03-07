defmodule SupportDeckWeb.WebhookControllerTest do
  use SupportDeckWeb.ConnCase

  test "rejects requests without valid signature", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/webhooks/front", Jason.encode!(%{type: "inbound"}))

    assert conn.status in [400, 401]
  end
end
