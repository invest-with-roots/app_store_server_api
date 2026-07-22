# frozen_string_literal: true

module AppStoreServerApi
  # The `subtype` values that accompany certain notification types in App Store
  # Server Notifications V2. Mirrors Apple's official `Subtype` enum (ported from
  # the MIT-licensed apple/app-store-server-library-python).
  #
  # https://developer.apple.com/documentation/appstoreservernotifications/subtype
  module Subtype
    INITIAL_BUY = "INITIAL_BUY"
    RESUBSCRIBE = "RESUBSCRIBE"
    DOWNGRADE = "DOWNGRADE"
    UPGRADE = "UPGRADE"
    AUTO_RENEW_ENABLED = "AUTO_RENEW_ENABLED"
    AUTO_RENEW_DISABLED = "AUTO_RENEW_DISABLED"
    VOLUNTARY = "VOLUNTARY"
    BILLING_RETRY = "BILLING_RETRY"
    PRICE_INCREASE = "PRICE_INCREASE"
    GRACE_PERIOD = "GRACE_PERIOD"
    PENDING = "PENDING"
    ACCEPTED = "ACCEPTED"
    BILLING_RECOVERY = "BILLING_RECOVERY"
    PRODUCT_NOT_FOR_SALE = "PRODUCT_NOT_FOR_SALE"
    SUMMARY = "SUMMARY"
    FAILURE = "FAILURE"
    UNREPORTED = "UNREPORTED"

    # Every known subtype, for validation/enumeration.
    ALL = [
      INITIAL_BUY, RESUBSCRIBE, DOWNGRADE, UPGRADE, AUTO_RENEW_ENABLED,
      AUTO_RENEW_DISABLED, VOLUNTARY, BILLING_RETRY, PRICE_INCREASE,
      GRACE_PERIOD, PENDING, ACCEPTED, BILLING_RECOVERY, PRODUCT_NOT_FOR_SALE,
      SUMMARY, FAILURE, UNREPORTED
    ].freeze
  end
end
