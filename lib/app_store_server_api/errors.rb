# frozen_string_literal: true

module AppStoreServerApi
  # Mixed into the error classes that represent a transient failure worth
  # retrying (rate limiting, Apple-side outages, network hiccups). Callers can
  # rescue AppStoreServerApi::RetryableError to treat "Apple is down" uniformly.
  module RetryableError; end

  # Raised when the request never produced an HTTP response — a connection
  # timeout, read timeout, or socket-level failure. Retryable.
  class NetworkError < Error
    include RetryableError
  end

  # Base class for any non-2xx response from the App Store Server API. Carries
  # the HTTP status, Apple's numeric errorCode (when the body includes one), and
  # the raw response body so callers can branch on a specific failure.
  #
  # See https://developer.apple.com/documentation/appstoreserverapi/error_codes
  class APIError < Error
    attr_reader :http_status, :api_error_code, :response_body

    def initialize(message = nil, http_status:, api_error_code: nil, response_body: nil)
      @http_status = http_status
      @api_error_code = api_error_code
      @response_body = response_body
      super(message || "App Store Server API request failed with HTTP #{http_status}")
    end
  end

  # A 4xx response caused by the request itself (bad transaction id, malformed
  # request). Not retryable — retrying with the same input fails the same way.
  class ClientError < APIError; end

  # The transaction id (or its account) is unknown to Apple. Apple returns this
  # as HTTP 404 with errorCode 4040010. Lets the claim path answer "bad
  # transaction id from the client" distinctly from "Apple is down".
  class TransactionIdNotFoundError < ClientError; end

  # HTTP 429 — the request was rate limited. Retryable after backoff.
  class RateLimitExceededError < ClientError
    include RetryableError
  end

  # A 5xx response — Apple is unavailable or erroring. Retryable.
  class ServerError < APIError
    include RetryableError
  end
end
