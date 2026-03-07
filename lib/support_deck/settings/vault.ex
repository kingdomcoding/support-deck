defmodule SupportDeck.Settings.Vault do
  @moduledoc """
  AES-256-GCM encryption for credential storage.

  Derives a 32-byte encryption key from SECRET_KEY_BASE using HKDF.
  Each value is encrypted with a unique IV. Format: iv <> ciphertext <> tag,
  Base64-encoded for DB storage.
  """

  @aad "SupportDeck.Settings.Vault"

  def encrypt!(plaintext) when is_binary(plaintext) do
    key = derive_key()
    iv = :crypto.strong_rand_bytes(12)
    {ciphertext, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, plaintext, @aad, true)
    Base.encode64(iv <> ciphertext <> tag)
  end

  def decrypt!(encoded) when is_binary(encoded) do
    key = derive_key()
    raw = Base.decode64!(encoded)
    <<iv::binary-12, rest::binary>> = raw
    ct_size = byte_size(rest) - 16
    <<ciphertext::binary-size(^ct_size), tag::binary-16>> = rest
    :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, ciphertext, @aad, tag, false)
  end

  defp derive_key do
    secret =
      Application.get_env(:support_deck, SupportDeckWeb.Endpoint)[:secret_key_base] ||
        raise "SECRET_KEY_BASE not configured"

    <<key::binary-32, _::binary>> = :crypto.hash(:sha256, "credential_vault:" <> secret)
    key
  end
end
