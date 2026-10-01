# frozen_string_literal: true

require "base64"
require "openssl"
require "jwt"

require_relative "../models"

module AppStoreServerApi
  module Utils
    # Verifies and decodes the JWS (JSON Web Signature) payloads that Apple's
    # App Store Server API and App Store Server Notifications return.
    #
    # The verification semantics are ported from Apple's own MIT-licensed
    # official libraries (apple/app-store-server-library-python and -node) so
    # that a payload is only trusted when:
    #
    #   1. The x5c header carries a chain of exactly three certificates.
    #   2. That chain builds and validates up to a trusted Apple root CA, with
    #      every certificate's validity window evaluated at the payload's
    #      signedDate (the "effective date").
    #   3. The leaf carries Apple's leaf marker OID (1.2.840.113635.100.6.11.1)
    #      and the intermediate carries the WWDR marker OID
    #      (1.2.840.113635.100.6.2.1).
    #   4. The JWS signature verifies against the leaf certificate's public key
    #      using ES256.
    #
    # Callers may additionally assert the payload's bundleId and environment,
    # which App Store Server Notifications require to reject cross-app or
    # cross-environment payloads.
    module Decoder
      module_function

      # Apple signs App Store Server payloads with a three-certificate chain:
      # [leaf, intermediate, root].
      EXPECTED_CHAIN_LENGTH = 3

      # Apple only signs these payloads with ES256; reject anything else to
      # prevent algorithm-substitution attacks.
      ALGORITHM = "ES256"

      # Custom certificate-extension OIDs Apple stamps on the signing chain.
      # The leaf carries the App Store receipt/transaction signing marker...
      LEAF_CERTIFICATE_OID = "1.2.840.113635.100.6.11.1"
      # ...and the intermediate carries the Apple WWDR marker.
      INTERMEDIATE_CERTIFICATE_OID = "1.2.840.113635.100.6.2.1"

      # Raised whenever a payload fails any verification step.
      class VerificationError < AppStoreServerApi::Error; end

      # Verify a JWS and return its decoded payload.
      #
      # @param jws [String] the compact JWS string.
      # @param bundle_id [String, nil] when set, reject payloads whose bundleId
      #   does not match.
      # @param environment [String, Symbol, nil] when set, reject payloads whose
      #   environment does not match (compared case-insensitively).
      # @param root_certificates [Array<OpenSSL::X509::Certificate>, nil] trust
      #   anchors; defaults to the bundled Apple root CA(s).
      # @return [Hash] the verified payload.
      # @raise [VerificationError] if verification fails.
      # @param test_certificates [Array<OpenSSL::X509::Certificate>, nil]
      #   certificates accepted as the sole signer of a payload: StoreKit
      #   Testing in Xcode signs every transaction with one self-signed
      #   certificate per Mac (header `x5c` of length 1, environment "Xcode"),
      #   so a development server that wants to accept simulator purchases
      #   trusts that exported certificate here. A payload whose single `x5c`
      #   certificate byte-equals one of these is verified against it and the
      #   Apple chain checks are skipped; anything else goes through the Apple
      #   chain exactly as before. Never set this in production. Mirrors
      #   Apple's App Store Server Library `Environment.XCODE`.
      def decode_jws!(jws, bundle_id: nil, environment: nil, root_certificates: nil, test_certificates: nil)
        unverified_payload, header = decode_without_verification(jws)

        assert_algorithm!(header)
        effective_date = effective_date_for(unverified_payload)
        leaf = matching_test_certificate(header, test_certificates, effective_date: effective_date) ||
          verify_certificate_chain!(
            extract_certificates(header),
            effective_date: effective_date,
            root_certificates: root_certificates || apple_root_cas
          )

        payload, = JWT.decode(jws, leaf.public_key, true, algorithm: ALGORITHM)

        assert_app_identity!(payload, bundle_id: bundle_id, environment: environment)
        payload
      rescue JWT::DecodeError => e
        # Signature / structural failures surface as a uniform verification error.
        raise VerificationError, "JWS verification failed: #{e.message}"
      end

      def decode_transaction(signed_transaction:, bundle_id: nil, environment: nil, root_certificates: nil, test_certificates: nil)
        decode_jws! signed_transaction,
          bundle_id: bundle_id,
          environment: environment,
          root_certificates: root_certificates,
          test_certificates: test_certificates
      end

      def decode_transactions(signed_transactions:, bundle_id: nil, environment: nil, root_certificates: nil, test_certificates: nil)
        signed_transactions.map do |signed_transaction|
          decode_transaction signed_transaction: signed_transaction,
            bundle_id: bundle_id,
            environment: environment,
            root_certificates: root_certificates,
            test_certificates: test_certificates
        end
      end

      # Verify an App Store Server Notification (signedPayload). The bundleId and
      # environment live under the payload's `data`/`summary` object, so callers
      # should pass the expected values to reject cross-app/cross-environment
      # notifications.
      def decode_notification(signed_payload:, bundle_id: nil, environment: nil, root_certificates: nil)
        decode_jws! signed_payload,
          bundle_id: bundle_id,
          environment: environment,
          root_certificates: root_certificates
      end

      # Verify an App Store Server Notification (signedPayload) AND its nested
      # `data.signedTransactionInfo` / `data.signedRenewalInfo` JWS strings in a
      # single call, mirroring the official libraries' `SignedDataVerifier`.
      #
      # The envelope's signature is verified (and bundleId/environment asserted
      # when supplied); each nested JWS is independently verified against Apple's
      # signing chain and decoded. The raw nested JWS strings are never returned
      # — callers receive only decoded, verified data.
      #
      # @return [AppStoreServerApi::DecodedNotification]
      def verify_and_decode_notification(signed_payload:, bundle_id: nil, environment: nil, root_certificates: nil)
        payload = decode_jws!(signed_payload,
          bundle_id: bundle_id,
          environment: environment,
          root_certificates: root_certificates)

        data = payload["data"] || {}
        summary = payload["summary"]
        identity = data.empty? ? (summary || {}) : data

        DecodedNotification.new(
          notification_type: payload["notificationType"],
          subtype: payload["subtype"],
          notification_uuid: payload["notificationUUID"],
          version: payload["version"],
          environment: identity["environment"],
          app_apple_id: identity["appAppleId"],
          bundle_id: identity["bundleId"],
          transaction_info: decode_nested(data["signedTransactionInfo"], root_certificates),
          renewal_info: decode_nested(data["signedRenewalInfo"], root_certificates),
          summary: summary
        )
      end

      # Unpack a Get All Subscription Statuses response into verified, decoded
      # structs. Each entry's nested `signedTransactionInfo` / `signedRenewalInfo`
      # is verified against Apple's signing chain and decoded; the raw JWS
      # strings are never returned.
      #
      # @param response [Hash] the parsed Get All Subscription Statuses response.
      # @return [Array<AppStoreServerApi::SubscriptionStatus>] flattened across
      #   all subscription groups.
      def decode_subscription_statuses(response, root_certificates: nil)
        groups = response.is_a?(Hash) ? (response["data"] || []) : []

        groups.flat_map do |group|
          group_id = group["subscriptionGroupIdentifier"]

          (group["lastTransactions"] || []).map do |entry|
            status = entry["status"]

            SubscriptionStatus.new(
              original_transaction_id: entry["originalTransactionId"],
              status: status,
              status_name: Status.name_for(status),
              subscription_group_identifier: group_id,
              transaction_info: decode_nested(entry["signedTransactionInfo"], root_certificates),
              renewal_info: decode_nested(entry["signedRenewalInfo"], root_certificates)
            )
          end
        end
      end

      # The Apple root certificate(s) bundled with the gem. Only self-signed
      # roots are treated as trust anchors; bundled intermediates (e.g. WWDR)
      # are ignored so they cannot act as a root.
      def apple_root_cas
        bundled_certificates.select { |cert| self_signed?(cert) }
      end

      def bundled_certificates
        Dir.glob(File.join(__dir__, "certs", "*.cer")).map do |filename|
          OpenSSL::X509::Certificate.new File.read(filename)
        end
      end

      # --- internal helpers -------------------------------------------------

      # Verify and decode a nested JWS (a transaction/renewal payload carried
      # inside a notification or statuses response). Only the signing chain is
      # verified here; the enclosing envelope already asserts app identity, and
      # renewalInfo payloads carry no bundleId to assert against.
      def decode_nested(jws, root_certificates)
        return nil if jws.nil? || jws.empty?

        decode_jws!(jws, root_certificates: root_certificates)
      end

      def decode_without_verification(jws)
        JWT.decode(jws, nil, false)
      rescue JWT::DecodeError => e
        raise VerificationError, "Malformed JWS: #{e.message}"
      end

      def assert_algorithm!(header)
        alg = header["alg"]
        return if alg == ALGORITHM

        raise VerificationError, "Unexpected JWS algorithm: #{alg.inspect} (expected #{ALGORITHM})"
      end

      # The trusted test certificate this payload is signed with, or nil when
      # the payload must take the Apple chain path: no test certificates were
      # configured, the `x5c` header is not exactly one certificate, that
      # certificate is not byte-identical to a trusted one, or the payload was
      # signed outside the certificate's validity window.
      def matching_test_certificate(header, test_certificates, effective_date:)
        return nil if test_certificates.nil? || test_certificates.empty?

        x5c = header["x5c"]
        return nil unless x5c.is_a?(Array) && x5c.length == 1

        presented = OpenSSL::X509::Certificate.new(Base64.decode64(x5c.first))
        trusted = test_certificates.find { |certificate| certificate.to_der == presented.to_der }
        return nil if trusted.nil?
        return nil unless trusted.not_before <= effective_date && effective_date <= trusted.not_after

        trusted
      rescue OpenSSL::X509::CertificateError
        nil
      end

      def extract_certificates(header)
        x5c = header["x5c"]
        raise VerificationError, "Missing x5c certificate chain" if x5c.nil? || x5c.empty?

        unless x5c.length == EXPECTED_CHAIN_LENGTH
          raise VerificationError,
            "Unexpected certificate chain length: #{x5c.length} (expected #{EXPECTED_CHAIN_LENGTH})"
        end

        x5c.map { |cert| OpenSSL::X509::Certificate.new Base64.decode64(cert) }
      rescue OpenSSL::X509::CertificateError => e
        raise VerificationError, "Invalid certificate in x5c chain: #{e.message}"
      end

      def verify_certificate_chain!(certificates, effective_date:, root_certificates:)
        raise VerificationError, "No trusted root certificates configured" if root_certificates.empty?

        leaf, intermediate, = certificates

        assert_certificate_oid! leaf, LEAF_CERTIFICATE_OID, "leaf"
        assert_certificate_oid! intermediate, INTERMEDIATE_CERTIFICATE_OID, "intermediate"

        store = OpenSSL::X509::Store.new
        root_certificates.each { |root| store.add_cert root }
        # Validity dates are checked against the payload's signedDate, matching
        # Apple's verifier (a payload signed while the cert was valid stays
        # verifiable after the cert later expires).
        store.time = effective_date

        # Anchor to the trusted store using only the leaf + intermediate as the
        # untrusted chain, exactly like Apple's libraries.
        context = OpenSSL::X509::StoreContext.new(store, leaf, [intermediate])
        unless context.verify
          raise VerificationError, "Certificate chain verification failed: #{context.error_string}"
        end

        leaf
      end

      def assert_certificate_oid!(certificate, oid, label)
        return if certificate.extensions.any? { |ext| ext.oid == oid }

        raise VerificationError, "#{label.capitalize} certificate is missing marker OID #{oid}"
      end

      def assert_app_identity!(payload, bundle_id:, environment:)
        assert_bundle_id!(payload, bundle_id) unless bundle_id.nil?
        assert_environment!(payload, environment) unless environment.nil?
      end

      def assert_bundle_id!(payload, expected)
        actual = payload_bundle_id(payload)
        return if actual == expected

        raise VerificationError, "Unexpected bundleId: #{actual.inspect} (expected #{expected.inspect})"
      end

      def assert_environment!(payload, expected)
        actual = payload_environment(payload)
        return if normalize(actual) == normalize(expected)

        raise VerificationError, "Unexpected environment: #{actual.inspect} (expected #{expected.inspect})"
      end

      # bundleId lives at the top level for transactions and under data/summary
      # for notifications.
      def payload_bundle_id(payload)
        payload["bundleId"] || payload.dig("data", "bundleId") || payload.dig("summary", "bundleId")
      end

      def payload_environment(payload)
        payload["environment"] || payload.dig("data", "environment") || payload.dig("summary", "environment")
      end

      def effective_date_for(payload)
        signed_date = payload["signedDate"] || payload.dig("data", "signedDate") || payload["receiptCreationDate"]
        return Time.now if signed_date.nil?

        # Apple expresses signedDate in milliseconds since the epoch.
        Time.at(signed_date / 1000.0)
      end

      def normalize(value)
        value.to_s.downcase
      end

      def self_signed?(certificate)
        certificate.issuer == certificate.subject && certificate.verify(certificate.public_key)
      end
    end
  end
end
