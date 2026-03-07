defmodule SupportDeck.Settings.ConnectionTester do
  @moduledoc """
  Lightweight connection tests for each integration.

  Each test makes the cheapest possible API call to verify the credential
  is valid and returns identifying information about the connected account.
  """

  alias SupportDeck.Settings.Resolver

  def test(:front) do
    token = Resolver.get(:front, :api_token)

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
  end

  def test(:slack) do
    token = Resolver.get(:slack, :bot_token)

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
  end

  def test(:linear) do
    api_key = Resolver.get(:linear, :api_key)

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
  end

  def test(:openai) do
    api_key = Resolver.get(:openai, :api_key)

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
  end

  def test(:anthropic) do
    api_key = Resolver.get(:anthropic, :api_key)

    case Req.get(
           url: "https://api.anthropic.com/v1/models",
           headers: [
             {"x-api-key", api_key},
             {"anthropic-version", "2023-06-01"}
           ]
         ) do
      {:ok, %{status: 200, body: %{"data" => models}}} ->
        count = length(models)
        {:ok, "Connected — #{count} models available"}

      {:ok, %{status: 401}} ->
        {:error, "Invalid API key — got 401"}

      {:error, reason} ->
        {:error, "Connection failed: #{inspect(reason)}"}
    end
  end
end
