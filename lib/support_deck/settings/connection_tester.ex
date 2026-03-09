defmodule SupportDeck.Settings.ConnectionTester do
  alias SupportDeck.Settings.Resolver

  def test(:front) do
    with_credential(:front, :api_token, "Front API token", fn token ->
      case Req.get(
             url: "https://api2.frontapp.com/me",
             headers: [{"authorization", "Bearer #{token}"}]
           ) do
        {:ok, %{status: 200, body: %{"email" => email, "first_name" => name}}} ->
          {:ok, "Connected as #{name} (#{email})"}

        {:ok, %{status: 401}} ->
          {:error, "Invalid API token — got 401 Unauthenticated"}

        {:ok, %{status: s, body: b}} ->
          {:error, "Unexpected status #{s}: #{inspect(b)}"}

        {:error, reason} ->
          {:error, "Connection failed: #{inspect(reason)}"}
      end
    end)
  end

  def test(:slack) do
    with_credential(:slack, :bot_token, "Slack bot token", fn token ->
      case Req.post(
             url: "https://slack.com/api/auth.test",
             headers: [
               {"authorization", "Bearer #{token}"},
               {"content-type", "application/json; charset=utf-8"}
             ],
             json: %{}
           ) do
        {:ok, %{status: 200, body: %{"ok" => true, "team" => team, "user" => user}}} ->
          {:ok, "Connected to #{team} as #{user}"}

        {:ok, %{status: 200, body: %{"ok" => false, "error" => error}}} ->
          {:error, "Slack API error: #{error}"}

        {:error, reason} ->
          {:error, "Connection failed: #{inspect(reason)}"}
      end
    end)
  end

  def test(:linear) do
    with_credential(:linear, :api_key, "Linear API key", fn api_key ->
      case Req.post(
             url: "https://api.linear.app/graphql",
             headers: [
               {"authorization", api_key},
               {"content-type", "application/json"}
             ],
             json: %{query: "{ viewer { id name email } }"}
           ) do
        {:ok, %{status: 200, body: %{"data" => %{"viewer" => %{"name" => name, "email" => email}}}}} ->
          {:ok, "Connected as #{name} (#{email})"}

        {:ok, %{status: 200, body: %{"errors" => [%{"message" => msg} | _]}}} ->
          {:error, "GraphQL error: #{msg}"}

        {:ok, %{status: 401}} ->
          {:error, "Invalid API key — got 401"}

        {:error, reason} ->
          {:error, "Connection failed: #{inspect(reason)}"}
      end
    end)
  end

  def test(:openai) do
    with_credential(:openai, :api_key, "OpenAI API key", fn api_key ->
      case Req.get(
             url: "https://api.openai.com/v1/models/gpt-4o-mini",
             headers: [{"authorization", "Bearer #{api_key}"}]
           ) do
        {:ok, %{status: 200, body: %{"id" => model_id}}} ->
          {:ok, "Connected — verified access to #{model_id}"}

        {:ok, %{status: 401}} ->
          {:error, "Invalid API key — got 401"}

        {:ok, %{status: 404}} ->
          {:ok, "Connected — API key valid (model gpt-4o-mini not available on this plan)"}

        {:error, reason} ->
          {:error, "Connection failed: #{inspect(reason)}"}
      end
    end)
  end

  defp with_credential(integration, key, label, fun) do
    case Resolver.get(integration, key) do
      nil -> {:error, "#{label} not configured"}
      value -> fun.(value)
    end
  end
end
