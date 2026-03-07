defmodule SupportDeck.Integrations.Front.ClientBehaviour do
  @callback list_conversations(keyword()) :: {:ok, map()} | {:error, term()}
  @callback get_conversation(String.t()) :: {:ok, map()} | {:error, term()}
  @callback get_conversation_messages(String.t()) :: {:ok, map()} | {:error, term()}
  @callback reply_to_conversation(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback add_comment(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  @callback tag_conversation(String.t(), list(String.t())) :: {:ok, map()} | {:error, term()}
  @callback assign_conversation(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
end
