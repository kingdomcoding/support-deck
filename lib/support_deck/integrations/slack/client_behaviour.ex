defmodule SupportDeck.Integrations.Slack.ClientBehaviour do
  @callback post_message(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback add_reaction(String.t(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  @callback get_channel_history(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
end
