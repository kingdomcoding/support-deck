defmodule SupportDeck.Integrations.Linear.ClientBehaviour do
  @callback create_issue(map()) :: {:ok, map()} | {:error, term()}
  @callback get_issue(String.t()) :: {:ok, map()} | {:error, term()}
  @callback create_attachment(String.t(), map()) :: :ok | {:error, term()}
  @callback create_comment(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
end
