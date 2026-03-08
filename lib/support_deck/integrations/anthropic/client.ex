defmodule SupportDeck.Integrations.Anthropic.Client do
  alias SupportDeck.Settings.Resolver

  @base_url "https://api.anthropic.com/v1"
  @model "claude-haiku-4-5-20251001"

  def classify(subject, body) do
    api_key = Resolver.get(:anthropic, :api_key)

    if is_nil(api_key) do
      {:error, :not_configured}
    else
      prompt = build_classification_prompt(subject, body)
      call_api(api_key, prompt)
    end
  end

  defp build_classification_prompt(subject, body) do
    """
    Classify this support ticket. Return ONLY valid JSON with these fields:
    - product_area: one of "auth", "database", "storage", "functions", "realtime", "dashboard", "billing", "general"
    - severity: one of "critical", "high", "medium", "low"
    - is_repetitive: boolean (true if this seems like a commonly reported issue)
    - confidence: float between 0.0 and 1.0
    - reasoning: brief explanation of classification

    Subject: #{subject}
    Body: #{body}
    """
  end

  defp call_api(api_key, prompt) do
    case Req.post("#{@base_url}/messages",
           json: %{
             model: @model,
             max_tokens: 256,
             messages: [%{role: "user", content: prompt}]
           },
           headers: [
             {"x-api-key", api_key},
             {"anthropic-version", "2023-06-01"},
             {"content-type", "application/json"}
           ],
           receive_timeout: 15_000
         ) do
      {:ok, %{status: 200, body: %{"content" => [%{"text" => text} | _]}}} ->
        parse_classification(text)

      {:ok, %{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp parse_classification(text) do
    json_text =
      case Regex.run(~r/\{[^{}]*\}/s, text) do
        [match] -> match
        _ -> text
      end

    case Jason.decode(json_text) do
      {:ok, parsed} ->
        {:ok,
         %{
           "product_area" => parsed["product_area"] || "general",
           "severity" => parsed["severity"] || "medium",
           "is_repetitive" => parsed["is_repetitive"] || false,
           "confidence" => parsed["confidence"] || 0.8,
           "reasoning" => parsed["reasoning"] || "AI classification"
         }}

      {:error, _} ->
        {:error, :invalid_json}
    end
  end
end
