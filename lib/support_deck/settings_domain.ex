defmodule SupportDeck.Settings do
  use Ash.Domain

  resources do
    resource SupportDeck.Settings.Credential do
      define :store_credential, action: :store
      define :delete_credential, action: :destroy
      define :record_test_result, action: :record_test_result
      define :list_for_integration, action: :for_integration, args: [:integration]
      define :list_all_credentials, action: :all_credentials
    end
  end
end
