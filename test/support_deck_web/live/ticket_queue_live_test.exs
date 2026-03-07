defmodule SupportDeckWeb.TicketQueueLiveTest do
  use SupportDeckWeb.ConnCase
  import Phoenix.LiveViewTest
  import SupportDeck.Factory

  test "renders ticket queue page", %{conn: conn} do
    create_ticket!(%{subject: "Test ticket for queue"})
    {:ok, _view, html} = live(conn, ~p"/tickets")
    assert html =~ "Tickets"
  end
end
