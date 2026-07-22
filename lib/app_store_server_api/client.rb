require "jwt"

require "net/http"
require "uri"
require "json"
require "openssl"

require_relative "errors"
require_relative "models"
require_relative "utils/decoder"

module AppStoreServerApi
  class Client
    # Apple's errorCode for an unknown transaction id (returned as HTTP 404).
    # https://developer.apple.com/documentation/appstoreserverapi/transactionidnotfounderror
    TRANSACTION_ID_NOT_FOUND_CODE = 4040010

    def initialize(
      private_key:, # p8 key
      key_id:,      # Your private key ID from App Store Connect (Ex: 2X9R4HXF34)
      issuer_id:,   # Your issuer ID from the Keys page in App Store Connect
      bundle_id:,   # Your app’s bundle ID (Ex: “com.example.testbundleid”)
      environment: :production,
      max_retries: 3,       # retries for rate-limit / 5xx / network failures
      retry_base_delay: 0.5 # seconds; exponential backoff base
    )
      @private_key = private_key
      @key_id = key_id
      @issuer_id = issuer_id
      @bundle_id = bundle_id
      @environment = environment.to_sym
      @base_url = app_store_base_url @environment
      @max_retries = max_retries
      @retry_base_delay = retry_base_delay
    end

    def get_transaction_history(transaction_id, params: nil)
      request_uri("#{@base_url}/inApps/v1/history/#{transaction_id}", params: params)
    end

    def get_transaction_info(transaction_id, params: nil)
      request_uri("#{@base_url}/inApps/v1/transactions/#{transaction_id}", params: params)
    end

    # status
    #
    # 1, The auto-renewable subscription is active.
    # 2, The auto-renewable subscription is expired.
    # 3, The auto-renewable subscription is in a billing retry period.
    # 4, The auto-renewable subscription is in a Billing Grace Period.
    # 5, The auto-renewable subscription is revoked. The App Store refunded the transaction or revoked it from Family Sharing
    def get_all_subscription_statuses(transaction_id, params: nil)
      request_uri("#{@base_url}/inApps/v1/subscriptions/#{transaction_id}", params: params)
    end

    def request_a_test_notification
      request_uri "#{@base_url}/inApps/v1/notifications/test", http_method: :post
    end

    # Fetch Get Transaction Info for a transaction id and return the verified,
    # decoded transaction in one call. The returned `signedTransactionInfo` JWS
    # is verified against Apple's signing chain (and this app's bundleId) and
    # decoded — the raw JWS never leaves the gem.
    #
    # @return [Hash] the decoded, verified transaction (incl. `originalTransactionId`).
    # @raise [TransactionIdNotFoundError] when Apple does not recognise the id.
    # @raise [Utils::Decoder::VerificationError] when the payload fails verification.
    def get_verified_transaction_info(transaction_id, bundle_id: @bundle_id, environment: nil)
      response = get_transaction_info(transaction_id)

      Utils::Decoder.decode_transaction(
        signed_transaction: response["signedTransactionInfo"],
        bundle_id: bundle_id,
        environment: environment
      )
    end

    # Fetch Get All Subscription Statuses for a transaction id and unpack the
    # nested `lastTransactions` JWS arrays into verified, decoded
    # {SubscriptionStatus} structs (with named statuses) in one call.
    #
    # @return [Array<AppStoreServerApi::SubscriptionStatus>]
    def get_verified_subscription_statuses(transaction_id, params: nil)
      response = get_all_subscription_statuses(transaction_id, params: params)

      Utils::Decoder.decode_subscription_statuses(response)
    end

    private

    def request_uri(uri, http_method: :get, headers: nil, params: nil, timeout: 5)
      attempt = 0

      begin
        response = perform_request(uri, http_method: http_method, headers: headers, params: params, timeout: timeout)
        handle_response(response)
      rescue RetryableError
        attempt += 1
        raise if attempt > @max_retries

        sleep backoff_delay(attempt)
        retry
      end
    end

    def perform_request(uri, http_method:, headers:, params:, timeout:)
      uri = URI(uri)
      uri.query = URI.encode_www_form(params) if params && http_method == :get

      http = Net::HTTP.new(uri.host, 443)
      http.open_timeout = timeout
      http.read_timeout = timeout
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER

      request = (http_method == :get) ? Net::HTTP::Get.new(uri.request_uri) : Net::HTTP::Post.new(uri.request_uri)
      request.initialize_http_header headers || request_headers
      request.body = params.to_json if http_method == :post

      http.request request
    rescue Net::OpenTimeout
      raise NetworkError, "Timeout while opening the connection"
    rescue Net::ReadTimeout
      raise NetworkError, "Timeout while reading data"
    rescue IOError, SocketError, SystemCallError => e
      raise NetworkError, "Network error: #{e.message}"
    end

    # Map an HTTP response to parsed JSON (2xx) or a typed error, so callers can
    # branch on transaction-not-found vs rate-limited vs server error.
    def handle_response(response)
      status = response.code.to_i
      return parse_body(response.body) if status.between?(200, 299)

      body = response.body
      parsed = safe_json(body)
      code = parsed && parsed["errorCode"]
      message = (parsed && parsed["errorMessage"]) || "HTTP #{status}"

      raise error_class_for(status, code).new(
        message,
        http_status: status,
        api_error_code: code,
        response_body: body
      )
    end

    def error_class_for(status, code)
      return TransactionIdNotFoundError if code == TRANSACTION_ID_NOT_FOUND_CODE
      return RateLimitExceededError if status == 429
      return ServerError if (500..599).cover?(status)
      return ClientError if (400..499).cover?(status)

      APIError
    end

    def parse_body(body)
      return {} if body.nil? || body.empty?

      JSON.parse body
    end

    def safe_json(body)
      return nil if body.nil? || body.empty?

      JSON.parse body
    rescue JSON::ParserError
      nil
    end

    def backoff_delay(attempt)
      @retry_base_delay * (2**(attempt - 1))
    end

    def bearer_token
      if @bearer_token
        begin
          JWT.decode @bearer_token, OpenSSL::PKey::EC.new(@private_key), true, {algorithm: "ES256"}
          return @bearer_token
        rescue JWT::ExpiredSignature
        end
      end

      @bearer_token = generate_bearer_token(
        key_id: @key_id,
        issuer_id: @issuer_id,
        private_key: @private_key,
        bundle_id: @bundle_id
      )
    end

    def request_headers
      {
        "Content-Type" => "application/json",
        "Authorization" => "Bearer #{bearer_token}"
      }
    end

    def generate_bearer_token(
      key_id:,
      issuer_id:,
      bundle_id:,
      private_key:,
      audience: "appstoreconnect-v1", # appstoreconnect-v1,
      issued_at: Time.now.to_i, # The time at which you issue the token, in UNIX time, in seconds (Ex: 1623085200)
      expired_in: 3600,
      alg: "ES256",
      typ: "JWT"
    )
      payload = {
        iss: issuer_id,
        iat: issued_at,
        exp: expired_in + issued_at,
        aud: audience,
        bid: bundle_id
      }

      JWT.encode payload, OpenSSL::PKey::EC.new(private_key), alg, {typ: typ, kid: key_id}
    end

    def app_store_base_url environment
      if environment == :production
        "https://api.storekit.itunes.apple.com"
      else
        "https://api.storekit-sandbox.itunes.apple.com"
      end
    end
  end
end
