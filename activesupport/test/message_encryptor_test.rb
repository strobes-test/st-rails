# frozen_string_literal: true

require_relative "abstract_unit"
require "openssl"
require "active_support/time"
require "active_support/json"

class MessageEncryptorTest < ActiveSupport::TestCase
  class JSONSerializer
    def dump(value)
      ActiveSupport::JSON.encode(value)
    end

    def load(value)
      ActiveSupport::JSON.decode(value)
    end
  end

  def setup
    @secret    = SecureRandom.random_bytes(32)
    @verifier  = ActiveSupport::MessageVerifier.new(@secret, serializer: ActiveSupport::MessageEncryptor::NullSerializer)
    @encryptor = ActiveSupport::MessageEncryptor.new(@secret)
    @data = { some: "data", now: Time.local(2010) }
  end

  def test_encrypting_twice_yields_differing_cipher_text
    first_message = @encryptor.encrypt_and_sign(@data).split("--").first
    second_message = @encryptor.encrypt_and_sign(@data).split("--").first
    assert_not_equal first_message, second_message
  end

  def test_messing_with_either_encrypted_values_causes_failure
    text, iv = @verifier.verify(@encryptor.encrypt_and_sign(@data)).split("--")
    assert_not_decrypted([iv, text] * "--")
    assert_not_decrypted([text, munge(iv)] * "--")
    assert_not_decrypted([munge(text), iv] * "--")
    assert_not_decrypted([munge(text), munge(iv)] * "--")
  end

  def test_messing_with_verified_values_causes_failures
    text, iv = @encryptor.encrypt_and_sign(@data).split("--")
    assert_not_verified([iv, text] * "--")
    assert_not_verified([text, munge(iv)] * "--")
    assert_not_verified([munge(text), iv] * "--")
    assert_not_verified([munge(text), munge(iv)] * "--")
  end

  def test_signed_round_tripping
    message = @encryptor.encrypt_and_sign(@data)
    assert_equal @data, @encryptor.decrypt_and_verify(message)
  end

  def test_backwards_compat_for_64_bytes_key
    # 64 bit key
    secret = ["3942b1bf81e622559ed509e3ff274a780784fe9e75b065866bd270438c74da822219de3156473cc27df1fd590e4baf68c95eeb537b6e4d4c5a10f41635b5597e"].pack("H*")
    # Encryptor with 32 bit key, 64 bit secret for verifier
    encryptor = ActiveSupport::MessageEncryptor.new(secret[0..31], secret)
    # Message generated with 64 bit key
    message = "eHdGeExnZEwvMSt3U3dKaFl1WFo0TjVvYzA0eGpjbm5WSkt5MXlsNzhpZ0ZnbWhBWFlQZTRwaXE1bVJCS2oxMDZhYVp2dVN3V0lNZUlWQ3c2eVhQbnhnVjFmeVVubmhRKzF3WnZyWHVNMDg9LS1HSisyakJVSFlPb05ISzRMaXRzcFdBPT0=--831a1d54a3cda8a0658dc668a03dedcbce13b5ca"
    assert_equal "data", encryptor.decrypt_and_verify(message)[:some]
  end

  def test_alternative_serialization_method
    prev = ActiveSupport.use_standard_json_time_format
    ActiveSupport.use_standard_json_time_format = true
    encryptor = ActiveSupport::MessageEncryptor.new(SecureRandom.random_bytes(32), SecureRandom.random_bytes(128), serializer: JSONSerializer.new)
    message = encryptor.encrypt_and_sign({ :foo => 123, "bar" => Time.utc(2010) })
    exp = { "foo" => 123, "bar" => "2010-01-01T00:00:00.000Z" }
    assert_equal exp, encryptor.decrypt_and_verify(message)
  ensure
    ActiveSupport.use_standard_json_time_format = prev
  end

  def test_message_obeys_strict_encoding
    bad_encoding_characters = "\n!@#"
    message, iv = @encryptor.encrypt_and_sign("This is a very \n\nhumble string" + bad_encoding_characters)

    assert_not_decrypted("#{::Base64.encode64 message.to_s}--#{::Base64.encode64 iv.to_s}")
    assert_not_verified("#{::Base64.encode64 message.to_s}--#{::Base64.encode64 iv.to_s}")

    assert_not_decrypted([iv,  message] * bad_encoding_characters)
    assert_not_verified([iv,  message] * bad_encoding_characters)
  end

  test "supports URL-safe encoding when using authenticated encryption" do
    encryptor = ActiveSupport::MessageEncryptor.new(@secret, url_safe: true, cipher: "aes-256-gcm")

    # Because encrypted data appears random, we cannot control whether it will
    # contain bytes that _would_ be encoded as non-URL-safe characters (i.e. "+"
    # or "/") if `url_safe: true` were broken.  Therefore, to make our test
    # falsifiable, we use a large string so that the encrypted data will almost
    # certainly contain such bytes.
    data = "x" * 10001
    message = encryptor.encrypt_and_sign(data)

    assert_equal data, encryptor.decrypt_and_verify(message)
    assert_equal message, URI.encode_www_form_component(message)
  end

  test "supports URL-safe encoding when using unauthenticated encryption" do
    encryptor = ActiveSupport::MessageEncryptor.new(@secret, url_safe: true, cipher: "aes-256-cbc")

    # When using unauthenticated encryption, messages are double encoded: once
    # when encrypting and once again when signing with a MessageVerifier.  The
    # 1st encode eliminates the possibility of a 6-bit aligned occurrence of
    # `0b111110` or `0b111111`, which the 2nd encode _would_ map to a
    # non-URL-safe character (i.e. "+" or "/") if `url_safe: true` were broken.
    # Therefore, to ensure our test is falsifiable, we also assert that the
    # message payload _would_ have padding characters (i.e. "=") if
    # `url_safe: true` were broken.
    data = 1
    message = encryptor.encrypt_and_sign(data)

    assert_equal data, encryptor.decrypt_and_verify(message)
    assert_equal message, URI.encode_www_form_component(message)
    assert_not_equal 0, message.rpartition("--").first.length % 4,
      "Unable to assert that the message payload is unpadded, because it does not require padding"
  end

  def test_aead_mode_encryption
    encryptor = ActiveSupport::MessageEncryptor.new(@secret, cipher: "aes-256-gcm")
    message = encryptor.encrypt_and_sign(@data)
    assert_equal @data, encryptor.decrypt_and_verify(message)
  end

  def test_aead_mode_with_hmac_cbc_cipher_text
    encryptor = ActiveSupport::MessageEncryptor.new(@secret, cipher: "aes-256-gcm")

    assert_aead_not_decrypted(encryptor, "eHdGeExnZEwvMSt3U3dKaFl1WFo0TjVvYzA0eGpjbm5WSkt5MXlsNzhpZ0ZnbWhBWFlQZTRwaXE1bVJCS2oxMDZhYVp2dVN3V0lNZUlWQ3c2eVhQbnhnVjFmeVVubmhRKzF3WnZyWHVNMDg9LS1HSisyakJVSFlPb05ISzRMaXRzcFdBPT0=--831a1d54a3cda8a0658dc668a03dedcbce13b5ca")
  end

  def test_messing_with_aead_values_causes_failures
    encryptor = ActiveSupport::MessageEncryptor.new(@secret, cipher: "aes-256-gcm")
    text, iv, auth_tag = encryptor.encrypt_and_sign(@data).split("--")
    assert_aead_not_decrypted(encryptor, [iv, text, auth_tag] * "--")
    assert_aead_not_decrypted(encryptor, [munge(text), iv, auth_tag] * "--")
    assert_aead_not_decrypted(encryptor, [text, munge(iv), auth_tag] * "--")
    assert_aead_not_decrypted(encryptor, [text, iv, munge(auth_tag)] * "--")
    assert_aead_not_decrypted(encryptor, [munge(text), munge(iv), munge(auth_tag)] * "--")
    assert_aead_not_decrypted(encryptor, [text, iv] * "--")
    assert_aead_not_decrypted(encryptor, [text, iv, auth_tag[0..-2]] * "--")
  end

  def test_backwards_compatibility_decrypt_previously_encrypted_messages_without_metadata
    secret = "\xB7\xF0\xBCW\xB1\x18`\xAB\xF0\x81\x10\xA4$\xF44\xEC\xA1\xDC\xC1\xDDD\xAF\xA9\xB8\x14\xCD\x18\x9A\x99 \x80)"
    encryptor = ActiveSupport::MessageEncryptor.new(secret, cipher: "aes-256-gcm")
    encrypted_message = "9cVnFs2O3lL9SPvIJuxBOLS51nDiBMw=--YNI5HAfHEmZ7VDpl--ddFJ6tXA0iH+XGcCgMINYQ=="

    assert_equal "Ruby on Rails", encryptor.decrypt_and_verify(encrypted_message)
  end


  private
    def assert_aead_not_decrypted(encryptor, value)
      assert_raise(ActiveSupport::MessageEncryptor::InvalidMessage) do
        encryptor.decrypt_and_verify(value)
      end
    end

    def assert_not_decrypted(value)
      assert_raise(ActiveSupport::MessageEncryptor::InvalidMessage) do
        @encryptor.decrypt_and_verify(@verifier.generate(value))
      end
    end

    def assert_not_verified(value)
      assert_raise(ActiveSupport::MessageEncryptor::InvalidMessage) do
        @encryptor.decrypt_and_verify(value)
      end
    end

    def secrets
      @secrets ||= Hash.new { |h, k| h[k] = SecureRandom.random_bytes(32) }
    end

    def munge(base64_string)
      bits = ::Base64.strict_decode64(base64_string)
      bits.reverse!
      ::Base64.strict_encode64(bits)
    end
end

class MessageEncryptorWithHybridSerializerAndMarshalDumpTest < MessageEncryptorTest
  def setup
    @secret    = SecureRandom.random_bytes(32)
    @verifier  = ActiveSupport::MessageVerifier.new(@secret, serializer: ActiveSupport::MessageEncryptor::NullSerializer)
    @data      = { some: "data", now: Time.local(2010) }
    @encryptor = ActiveSupport::MessageEncryptor.new(@secret)
    @default_message_encryptor_serializer        = ActiveSupport::MessageEncryptor.default_message_encryptor_serializer
    @default_fallback_to_marshal_deserialization = ActiveSupport::JsonWithMarshalFallback.fallback_to_marshal_deserialization
    ActiveSupport::MessageEncryptor.default_message_encryptor_serializer = :hybrid
  end

  def teardown
    ActiveSupport::MessageEncryptor.default_message_encryptor_serializer       = @default_message_encryptor_serializer
    ActiveSupport::JsonWithMarshalFallback.fallback_to_marshal_deserialization = @default_fallback_to_marshal_deserialization
    super
  end

  def test_backwards_compatibility_decrypt_previously_marshal_serialized_messages_when_fallback_to_marshal_deserialization_is_true
    secret = "\xB7\xF0\xBCW\xB1\x18`\xAB\xF0\x81\x10\xA4$\xF44\xEC\xA1\xDC\xC1\xDDD\xAF\xA9\xB8\x14\xCD\x18\x9A\x99 \x80)"
    data = "this_is_data"
    marshal_message = ActiveSupport::MessageEncryptor.new(secret, cipher: "aes-256-gcm", serializer: Marshal).encrypt_and_sign(data)
    assert_equal data, ActiveSupport::MessageEncryptor.new(secret, cipher: "aes-256-gcm").decrypt_and_verify(marshal_message)
  end

  def test_failure_to_decrypt_marshal_serialized_messages_when_fallback_to_marshal_deserialization_is_false
    ActiveSupport::JsonWithMarshalFallback.fallback_to_marshal_deserialization = false
    secret = "\xB7\xF0\xBCW\xB1\x18`\xAB\xF0\x81\x10\xA4$\xF44\xEC\xA1\xDC\xC1\xDDD\xAF\xA9\xB8\x14\xCD\x18\x9A\x99 \x80)"
    data = "this_is_data"
    marshal_message = ActiveSupport::MessageEncryptor.new(secret, cipher: "aes-256-gcm", serializer: Marshal).encrypt_and_sign(data)
    assert_raise(ActiveSupport::MessageEncryptor::InvalidMessage) do
      ActiveSupport::MessageEncryptor.new(secret, cipher: "aes-256-gcm").decrypt_and_verify(marshal_message)
    end
  end
end

class MessageEncryptorWithJsonSerializerTest < MessageEncryptorTest
  def setup
    @secret    = SecureRandom.random_bytes(32)
    @verifier  = ActiveSupport::MessageVerifier.new(@secret, serializer: ActiveSupport::MessageEncryptor::NullSerializer)
    @data      = { "some" => "data", "now" => Time.local(2010) }
    @encryptor = ActiveSupport::MessageEncryptor.new(@secret)
    @default_message_encryptor_serializer = ActiveSupport::MessageEncryptor.default_message_encryptor_serializer
    ActiveSupport::MessageEncryptor.default_message_encryptor_serializer = :json
  end

  def teardown
    ActiveSupport::MessageEncryptor.default_message_encryptor_serializer = @default_message_encryptor_serializer
    super
  end

  def test_backwards_compat_for_64_bytes_key
    # 64 bit key
    secret = ["3942b1bf81e622559ed509e3ff274a780784fe9e75b065866bd270438c74da822219de3156473cc27df1fd590e4baf68c95eeb537b6e4d4c5a10f41635b5597e"].pack("H*")
    # Encryptor with 32 bit key, 64 bit secret for verifier
    encryptor = ActiveSupport::MessageEncryptor.new(secret[0..31], secret)
    # Message generated with 64 bit key using the JSON serializer
    message = "YWZPOVBzcS8ycGZpVWpjWWU5NXZoanRtRGkzTVRjZk16UUpuRE9wa0pNNGI0dGxMRU5RdC94ZVhiQzUwYktFL2NEUjBnUm1QSlRDQ1RrMGlvakVZcGc9PS0tbXROMVdDUnNxWlRxMXA4dEtjWi9oZz09--3489b03e85aa14d8ed8cdd455507246f2e2884ae"
    assert_equal "data", encryptor.decrypt_and_verify(message)["some"]
  end

  def test_backwards_compatibility_decrypt_previously_encrypted_messages_without_metadata
    secret = "\xB7\xF0\xBCW\xB1\x18`\xAB\xF0\x81\x10\xA4$\xF44\xEC\xA1\xDC\xC1\xDDD\xAF\xA9\xB8\x14\xCD\x18\x9A\x99 \x80)"
    encryptor = ActiveSupport::MessageEncryptor.new(secret, cipher: "aes-256-gcm")
    # Message generated with MessageEncryptor given JSON as the serializer.
    encrypted_message = "NIevxlF4gFUETmYTm3GJ--SIlwA5xxwpqNtiiv--woA9eLuVMbmapIDGDj7HQQ=="

    assert_equal "Ruby on Rails", encryptor.decrypt_and_verify(encrypted_message)
  end
end

class MessageEncryptorWithHybridSerializerAndWithoutMarshalDumpTest < MessageEncryptorWithJsonSerializerTest
  def setup
    @secret    = SecureRandom.random_bytes(32)
    @verifier  = ActiveSupport::MessageVerifier.new(@secret, serializer: ActiveSupport::MessageEncryptor::NullSerializer)
    @data      = { "some" => "data", "now" => Time.local(2010) }
    @encryptor = ActiveSupport::MessageEncryptor.new(@secret)
    @default_message_encryptor_serializer = ActiveSupport::MessageEncryptor.default_message_encryptor_serializer
    @default_use_marshal_serialization    = ActiveSupport::JsonWithMarshalFallback.use_marshal_serialization
    ActiveSupport::MessageEncryptor.default_message_encryptor_serializer = :hybrid
    ActiveSupport::JsonWithMarshalFallback.use_marshal_serialization     = false
  end

  def teardown
    ActiveSupport::MessageEncryptor.default_message_encryptor_serializer = @default_message_encryptor_serializer
    ActiveSupport::JsonWithMarshalFallback.use_marshal_serialization     = @default_use_marshal_serialization
    super
  end
end
