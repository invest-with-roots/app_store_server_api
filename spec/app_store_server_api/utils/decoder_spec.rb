# frozen_string_literal: true

require "spec_helper"

RSpec.describe AppStoreServerApi::Utils::Decoder do
  fixtures_dir = File.expand_path("../../fixtures/apple", __dir__)
  test_root = OpenSSL::X509::Certificate.new(File.binread(File.join(fixtures_dir, "certs", "testCA.der")))

  # A JWS signed by Apple's test chain (anchored at testCA.der).
  read_jws = ->(name) { File.read(File.join(fixtures_dir, "mock_signed_data", name)).strip }

  # Decode against the vendored test root instead of the real Apple root.
  decode = ->(jws, **opts) { described_class.decode_jws!(jws, root_certificates: [test_root], **opts) }

  describe "decode_jws! with valid Apple fixtures" do
    it "verifies and decodes a signed transaction" do
      payload = decode.call(read_jws.call("transactionInfo"), bundle_id: "com.example", environment: :sandbox)

      expect(payload["bundleId"]).to eq("com.example")
      expect(payload["environment"]).to eq("Sandbox")
    end

    it "verifies and decodes renewal info" do
      payload = decode.call(read_jws.call("renewalInfo"), environment: :sandbox)

      expect(payload["environment"]).to eq("Sandbox")
    end

    it "verifies and decodes a notification, asserting bundleId and environment" do
      payload = decode.call(read_jws.call("testNotification"), bundle_id: "com.example", environment: :sandbox)

      expect(payload["notificationType"]).to eq("TEST")
    end
  end

  describe "signature verification" do
    it "rejects a JWS whose signature has been tampered with" do
      jws = read_jws.call("transactionInfo")
      header, payload, signature = jws.split(".")
      # Flip the last character of the signature segment.
      tampered_char = (signature[-1] == "A") ? "B" : "A"
      tampered = [header, payload, signature[0..-2] + tampered_char].join(".")

      expect { decode.call(tampered) }.to raise_error(described_class::VerificationError)
    end

    it "rejects a JWS whose payload has been tampered with" do
      jws = read_jws.call("transactionInfo")
      header, _payload, signature = jws.split(".")
      forged_payload = Base64.urlsafe_encode64('{"bundleId":"com.attacker"}', padding: false)
      forged = [header, forged_payload, signature].join(".")

      expect { decode.call(forged) }.to raise_error(described_class::VerificationError)
    end
  end

  describe "x5c header requirements" do
    it "rejects a JWS with no x5c header" do
      expect { decode.call(read_jws.call("missingX5CHeaderClaim")) }
        .to raise_error(described_class::VerificationError, /x5c/)
    end

    it "rejects a chain that is not exactly three certificates" do
      short_chain = [AppleTestCertificates::LEAF, AppleTestCertificates::INTERMEDIATE_CA]

      expect { described_class.extract_certificates("x5c" => short_chain) }
        .to raise_error(described_class::VerificationError, /chain length/)
    end
  end

  describe "bundleId assertion" do
    it "rejects a payload whose bundleId does not match" do
      expect { decode.call(read_jws.call("wrongBundleId"), bundle_id: "com.example") }
        .to raise_error(described_class::VerificationError, /bundleId/)
    end

    it "accepts a payload whose bundleId matches" do
      expect { decode.call(read_jws.call("transactionInfo"), bundle_id: "com.example") }.not_to raise_error
    end
  end

  describe "environment assertion" do
    it "rejects a payload whose environment does not match" do
      expect { decode.call(read_jws.call("testNotification"), environment: :production) }
        .to raise_error(described_class::VerificationError, /environment/i)
    end

    it "accepts a payload whose environment matches (case-insensitively)" do
      expect { decode.call(read_jws.call("testNotification"), environment: "SANDBOX") }.not_to raise_error
    end
  end

  describe "certificate chain verification (Apple x509 test vectors)" do
    let(:root) { AppleTestCertificates.root_certificate }
    let(:valid_chain) do
      [AppleTestCertificates::LEAF, AppleTestCertificates::INTERMEDIATE_CA, AppleTestCertificates::ROOT_CA]
        .map { |b| AppleTestCertificates.certificate(b) }
    end

    def verify(chain, root:, effective_date: AppleTestCertificates::EFFECTIVE_DATE)
      described_class.verify_certificate_chain!(chain, effective_date: effective_date, root_certificates: [root])
    end

    it "accepts a well-formed chain that anchors to the trusted root" do
      expect { verify(valid_chain, root: root) }.not_to raise_error
    end

    it "rejects a leaf missing the Apple leaf marker OID" do
      chain = [
        AppleTestCertificates::LEAF_INVALID_OID,
        AppleTestCertificates::INTERMEDIATE_CA,
        AppleTestCertificates::ROOT_CA
      ].map { |b| AppleTestCertificates.certificate(b) }

      expect { verify(chain, root: root) }
        .to raise_error(described_class::VerificationError, /Leaf certificate is missing marker OID/)
    end

    it "rejects an intermediate missing the Apple WWDR marker OID" do
      chain = [
        AppleTestCertificates::LEAF_FOR_INTERMEDIATE_CA_INVALID_OID,
        AppleTestCertificates::INTERMEDIATE_CA_INVALID_OID,
        AppleTestCertificates::ROOT_CA
      ].map { |b| AppleTestCertificates.certificate(b) }

      expect { verify(chain, root: root) }
        .to raise_error(described_class::VerificationError, /Intermediate certificate is missing marker OID/)
    end

    it "rejects a chain that is expired at the signedDate" do
      expect { verify(valid_chain, root: root, effective_date: AppleTestCertificates::EXPIRED_DATE) }
        .to raise_error(described_class::VerificationError, /chain verification failed/)
    end

    it "rejects a chain that anchors to a different root" do
      expect { verify(valid_chain, root: AppleTestCertificates.real_apple_root_certificate) }
        .to raise_error(described_class::VerificationError, /chain verification failed/)
    end
  end

  describe ".apple_root_cas" do
    it "returns only self-signed Apple roots (no bundled intermediates)" do
      roots = described_class.apple_root_cas

      expect(roots).not_to be_empty
      expect(roots).to all(satisfy { |cert| cert.issuer == cert.subject })
    end
  end
end
