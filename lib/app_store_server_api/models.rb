# frozen_string_literal: true

require_relative "status"

module AppStoreServerApi
  # A fully verified App Store Server Notification V2. The envelope signature is
  # verified and the nested `signedTransactionInfo` / `signedRenewalInfo` JWS
  # strings are verified and decoded into `transaction_info` / `renewal_info`.
  #
  # The raw JWS strings are intentionally NOT exposed here — consumers receive
  # only decoded, verified data.
  DecodedNotification = Struct.new(
    :notification_type,
    :subtype,
    :notification_uuid,
    :version,
    :environment,
    :app_apple_id,
    :bundle_id,
    :transaction_info,
    :renewal_info,
    :summary,
    keyword_init: true
  )

  # One verified subscription status entry from Get All Subscription Statuses.
  # `status` is the raw Apple integer and `status_name` its symbol (see
  # {Status}); `transaction_info` / `renewal_info` are the verified, decoded
  # payloads of the entry's nested JWS strings.
  SubscriptionStatus = Struct.new(
    :original_transaction_id,
    :status,
    :status_name,
    :subscription_group_identifier,
    :transaction_info,
    :renewal_info,
    keyword_init: true
  ) do
    def active?
      status == Status::ACTIVE
    end

    def expired?
      status == Status::EXPIRED
    end

    def billing_retry?
      status == Status::BILLING_RETRY
    end

    def billing_grace_period?
      status == Status::BILLING_GRACE_PERIOD
    end

    def revoked?
      status == Status::REVOKED
    end
  end
end
