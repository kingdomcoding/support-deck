defmodule SupportDeck.Settings.VaultTest do
  use ExUnit.Case, async: true

  test "encrypts and decrypts a value" do
    plaintext = "my-secret-api-key"
    encrypted = SupportDeck.Settings.Vault.encrypt!(plaintext)
    assert encrypted != plaintext
    decrypted = SupportDeck.Settings.Vault.decrypt!(encrypted)
    assert decrypted == plaintext
  end

  test "different plaintexts produce different ciphertexts" do
    a = SupportDeck.Settings.Vault.encrypt!("key-a")
    b = SupportDeck.Settings.Vault.encrypt!("key-b")
    assert a != b
  end
end
