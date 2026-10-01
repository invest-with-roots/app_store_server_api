# frozen_string_literal: true

require "spec_helper"
require "jwt"

# StoreKit Testing in Xcode signs each transaction with one self-signed
# ES256 certificate (header x5c of length 1, environment "Xcode"). A
# development server opts into those payloads by passing that exported
# certificate as `test_certificates:`; everything else keeps the Apple chain.
RSpec.describe AppStoreServerApi::Utils::Decoder, "trusted test certificates" do
  def self_signed(name:, not_before: Time.now - 3600, not_after: Time.now + 365 * 24 * 3600)
    key = OpenSSL::PKey::EC.generate("prime256v1")
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = cert.issuer = OpenSSL::X509::Name.parse("/CN=#{name}/O=#{name}")
    cert.public_key = key
    cert.not_before = not_before
    cert.not_after = not_after
    cert.sign(key, OpenSSL::Digest.new("SHA256"))
    [key, cert]
  end

  let(:signed_at) { Time.now }
  let(:payload) do
    {
      "transactionId" => "0", "originalTransactionId" => "0", "bundleId" => "com.example.app",
      "productId" => "sub_monthly", "environment" => "Xcode", "signedDate" => (signed_at.to_f * 1000).to_i,
      "offerType" => 1, "offerDiscountType" => "FREE_TRIAL"
    }
  end
  let(:xcode) { self_signed(name: "StoreKit Testing in Xcode") }
  let(:jws) do
    JWT.encode(payload, xcode[0], "ES256", { "x5c" => [Base64.strict_encode64(xcode[1].to_der)], "kid" => "Apple_Xcode_Key" })
  end

  it "verifies a single-certificate payload against a trusted test certificate" do
    decoded = described_class.decode_transaction(signed_transaction: jws, bundle_id: "com.example.app", environment: "Xcode", test_certificates: [xcode[1]])

    expect(decoded["productId"]).to eq("sub_monthly")
    expect(decoded["environment"]).to eq("Xcode")
  end

  it "keeps rejecting that payload when no test certificates are configured" do
    expect { described_class.decode_transaction(signed_transaction: jws) }
      .to raise_error(described_class::VerificationError, /chain length/)
    expect { described_class.decode_transaction(signed_transaction: jws, test_certificates: []) }
      .to raise_error(described_class::VerificationError, /chain length/)
  end

  it "rejects a single-certificate payload signed by a certificate that is not the trusted one" do
    _, other = self_signed(name: "StoreKit Testing in Xcode")

    expect { described_class.decode_transaction(signed_transaction: jws, test_certificates: [other]) }
      .to raise_error(described_class::VerificationError, /chain length/)
  end

  it "rejects a payload whose signature does not match the trusted certificate's key" do
    other_key, = self_signed(name: "StoreKit Testing in Xcode")
    forged = JWT.encode(payload, other_key, "ES256", { "x5c" => [Base64.strict_encode64(xcode[1].to_der)] })

    expect { described_class.decode_transaction(signed_transaction: forged, test_certificates: [xcode[1]]) }
      .to raise_error(described_class::VerificationError, /JWS verification failed/)
  end

  it "rejects a payload signed outside the trusted certificate's validity window" do
    expired_key, expired = self_signed(name: "StoreKit Testing in Xcode", not_before: Time.now - 2 * 365 * 24 * 3600, not_after: Time.now - 24 * 3600)
    stale = JWT.encode(payload, expired_key, "ES256", { "x5c" => [Base64.strict_encode64(expired.to_der)] })

    expect { described_class.decode_transaction(signed_transaction: stale, test_certificates: [expired]) }
      .to raise_error(described_class::VerificationError, /chain length/)
  end

  it "still asserts bundleId and environment on a trusted test payload" do
    expect { described_class.decode_transaction(signed_transaction: jws, bundle_id: "com.other.app", test_certificates: [xcode[1]]) }
      .to raise_error(described_class::VerificationError, /bundleId/)
    expect { described_class.decode_transaction(signed_transaction: jws, environment: "Sandbox", test_certificates: [xcode[1]]) }
      .to raise_error(described_class::VerificationError, /environment/)
  end

  it "leaves Apple-chain payloads on the chain path even when test certificates are configured" do
    fixtures_dir = File.expand_path("../../fixtures/apple", __dir__)
    test_root = OpenSSL::X509::Certificate.new(File.binread(File.join(fixtures_dir, "certs", "testCA.der")))
    apple_jws = File.read(File.join(fixtures_dir, "mock_signed_data", "transactionInfo")).strip

    decoded = described_class.decode_jws!(apple_jws, root_certificates: [test_root], test_certificates: [xcode[1]])
    expect(decoded["environment"]).not_to eq("Xcode")
  end
end
