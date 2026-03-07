defmodule SupportDeckWeb.PageController do
  use SupportDeckWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
