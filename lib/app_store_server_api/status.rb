# frozen_string_literal: true

module AppStoreServerApi
  # The `status` integers Apple returns for each auto-renewable subscription in
  # the Get All Subscription Statuses response. Mirrors Apple's official
  # `Status` enum (ported from the MIT-licensed
  # apple/app-store-server-library-python).
  #
  # https://developer.apple.com/documentation/appstoreserverapi/status
  module Status
    # The auto-renewable subscription is active.
    ACTIVE = 1
    # The auto-renewable subscription is expired.
    EXPIRED = 2
    # The auto-renewable subscription is in a billing retry period.
    BILLING_RETRY = 3
    # The auto-renewable subscription is in a Billing Grace Period.
    BILLING_GRACE_PERIOD = 4
    # The auto-renewable subscription is revoked. The App Store refunded the
    # transaction or revoked it from Family Sharing.
    REVOKED = 5

    ALL = [ACTIVE, EXPIRED, BILLING_RETRY, BILLING_GRACE_PERIOD, REVOKED].freeze

    # Stable, snake_case symbol name for each status integer. Consumers can map
    # these to their own vocabulary; the mapping to any app's own column lives
    # in that app, not here.
    NAMES = {
      ACTIVE => :active,
      EXPIRED => :expired,
      BILLING_RETRY => :billing_retry,
      BILLING_GRACE_PERIOD => :billing_grace_period,
      REVOKED => :revoked
    }.freeze

    module_function

    # The symbol name for a status integer, or nil for an unknown code.
    def name_for(code)
      NAMES[code]
    end
  end
end
