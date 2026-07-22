# frozen_string_literal: true

require "spec_helper"

RSpec.describe AppStoreServerApi::Client do
  # A throwaway EC key so the client instantiates; the HTTP layer is stubbed so
  # no token is actually minted in these examples.
  let(:private_key) { OpenSSL::PKey::EC.generate("prime256v1").to_pem }

  let(:client) do
    described_class.new(
      private_key: private_key,
      key_id: "KEYID",
      issuer_id: "issuer",
      bundle_id: "com.example",
      environment: :sandbox,
      max_retries: 3,
      retry_base_delay: 0
    )
  end

  # Minimal stand-in for a Net::HTTPResponse (only `code`/`body` are read).
  fake_response = Struct.new(:code, :body)

  before do
    # Never actually sleep between retries in specs.
    allow(client).to receive(:sleep)
  end

  def stub_request(*responses)
    allow(client).to receive(:perform_request).and_return(*responses)
  end

  describe "successful requests" do
    it "parses a 2xx JSON body" do
      stub_request(fake_response.new("200", '{"signedTransactionInfo":"abc"}'))

      expect(client.get_transaction_info("txn")).to eq("signedTransactionInfo" => "abc")
    end

    it "returns an empty hash for an empty 2xx body" do
      stub_request(fake_response.new("200", ""))

      expect(client.request_a_test_notification).to eq({})
    end
  end

  describe "typed error mapping" do
    it "raises TransactionIdNotFoundError for a 404 with Apple's not-found errorCode" do
      stub_request(fake_response.new("404", '{"errorCode":4040010,"errorMessage":"Transaction id not found."}'))

      expect { client.get_transaction_info("bad") }
        .to raise_error(AppStoreServerApi::TransactionIdNotFoundError) { |e|
          expect(e.http_status).to eq(404)
          expect(e.api_error_code).to eq(4040010)
        }
    end

    it "raises a generic ClientError for other 4xx responses" do
      stub_request(fake_response.new("400", '{"errorCode":4000006,"errorMessage":"Invalid transaction id."}'))

      expect { client.get_transaction_info("bad") }.to raise_error(AppStoreServerApi::ClientError) { |e|
        expect(e).not_to be_a(AppStoreServerApi::TransactionIdNotFoundError)
        expect(e.http_status).to eq(400)
      }
    end

    it "raises RateLimitExceededError for a 429" do
      # 429 is retried up to max_retries, then surfaces.
      stub_request(fake_response.new("429", '{"errorCode":4290000}'))

      expect { client.get_transaction_info("txn") }.to raise_error(AppStoreServerApi::RateLimitExceededError)
    end

    it "raises ServerError for a 5xx" do
      stub_request(fake_response.new("500", ""))

      expect { client.get_transaction_info("txn") }.to raise_error(AppStoreServerApi::ServerError) { |e|
        expect(e.http_status).to eq(500)
      }
    end

    it "tolerates a non-JSON error body" do
      stub_request(fake_response.new("503", "<html>Service Unavailable</html>"))

      expect { client.get_transaction_info("txn") }.to raise_error(AppStoreServerApi::ServerError) { |e|
        expect(e.api_error_code).to be_nil
        expect(e.response_body).to include("Service Unavailable")
      }
    end
  end

  describe "retry / backoff" do
    it "retries a 503 and returns once Apple recovers" do
      stub_request(
        fake_response.new("503", ""),
        fake_response.new("503", ""),
        fake_response.new("200", '{"ok":true}')
      )

      expect(client.get_transaction_info("txn")).to eq("ok" => true)
      expect(client).to have_received(:perform_request).exactly(3).times
    end

    it "retries a network error and then succeeds" do
      call = 0
      allow(client).to receive(:perform_request) do
        call += 1
        raise AppStoreServerApi::NetworkError, "boom" if call == 1

        fake_response.new("200", '{"ok":true}')
      end

      expect(client.get_transaction_info("txn")).to eq("ok" => true)
      expect(call).to eq(2)
    end

    it "gives up after max_retries and raises the last error" do
      stub_request(
        fake_response.new("503", ""),
        fake_response.new("503", ""),
        fake_response.new("503", ""),
        fake_response.new("503", "")
      )

      expect { client.get_transaction_info("txn") }.to raise_error(AppStoreServerApi::ServerError)
      # initial attempt + 3 retries
      expect(client).to have_received(:perform_request).exactly(4).times
    end

    it "does not retry a non-retryable client error" do
      stub_request(fake_response.new("404", '{"errorCode":4040010}'))

      expect { client.get_transaction_info("txn") }.to raise_error(AppStoreServerApi::TransactionIdNotFoundError)
      expect(client).to have_received(:perform_request).once
    end
  end

  describe "#get_verified_transaction_info" do
    it "fetches, verifies, and returns the decoded transaction" do
      allow(client).to receive(:get_transaction_info)
        .with("txn").and_return("signedTransactionInfo" => "SIGNED_JWS")
      allow(AppStoreServerApi::Utils::Decoder).to receive(:decode_transaction)
        .and_return("originalTransactionId" => "orig-1")

      result = client.get_verified_transaction_info("txn")

      expect(result).to eq("originalTransactionId" => "orig-1")
      expect(AppStoreServerApi::Utils::Decoder).to have_received(:decode_transaction)
        .with(signed_transaction: "SIGNED_JWS", bundle_id: "com.example", environment: nil)
    end
  end

  describe "#get_verified_subscription_statuses" do
    it "fetches and unpacks the response into decoded structs" do
      response = {"data" => []}
      allow(client).to receive(:get_all_subscription_statuses).with("orig", params: nil).and_return(response)
      allow(AppStoreServerApi::Utils::Decoder).to receive(:decode_subscription_statuses).and_return([:decoded])

      result = client.get_verified_subscription_statuses("orig")

      expect(result).to eq([:decoded])
      expect(AppStoreServerApi::Utils::Decoder).to have_received(:decode_subscription_statuses).with(response)
    end
  end
end
