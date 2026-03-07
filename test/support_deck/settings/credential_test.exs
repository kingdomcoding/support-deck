defmodule SupportDeck.Settings.CredentialTest do
  use SupportDeck.DataCase, async: true

  test "stores and retrieves a credential" do
    {:ok, cred} = SupportDeck.Settings.store_credential(%{
      integration: :front,
      key_name: :api_token,
      plaintext_value: "test-token-12345"
    })
    assert cred.integration == :front
    assert cred.key_name == :api_token
    assert cred.value_hint =~ "2345"
    assert cred.encrypted_value != "test-token-12345"
  end

  test "upserts credential on same integration/key_name" do
    {:ok, _} = SupportDeck.Settings.store_credential(%{
      integration: :slack,
      key_name: :bot_token,
      plaintext_value: "old-token"
    })
    {:ok, cred} = SupportDeck.Settings.store_credential(%{
      integration: :slack,
      key_name: :bot_token,
      plaintext_value: "new-token-5678"
    })
    assert cred.value_hint =~ "5678"
  end
end
