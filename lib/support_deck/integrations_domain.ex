defmodule SupportDeck.IntegrationsDomain do
  use Ash.Domain

  resources do
    resource SupportDeck.Integrations.WebhookEvent do
      define(:store_event, action: :store)
      define(:mark_event_processed, action: :mark_processed)
    end
  end
end
