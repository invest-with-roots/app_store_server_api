## [Unreleased]

## [0.3.0] - 2026-07-22

### Added
- Protocol constants mirroring Apple's official enums so consumers branch on
  named values instead of magic strings/ints:
  - `AppStoreServerApi::NotificationTypeV2` and `AppStoreServerApi::Subtype`
    (App Store Server Notifications V2 `notificationType` / `subtype`).
  - `AppStoreServerApi::Status` (subscription status integers 1–5) with
    `Status.name_for` returning a symbol (`:active`, `:expired`,
    `:billing_retry`, `:billing_grace_period`, `:revoked`).
- Composed, verified helpers that return decoded structs — no raw JWS crosses
  the gem boundary:
  - `Client#get_verified_transaction_info` — Get Transaction Info, then verify
    and decode the returned `signedTransactionInfo`.
  - `Utils::Decoder.verify_and_decode_notification` — verify a notification
    envelope AND its nested `data.signedTransactionInfo` /
    `data.signedRenewalInfo`, returning an `AppStoreServerApi::DecodedNotification`.
  - `Utils::Decoder.decode_subscription_statuses` (and
    `Client#get_verified_subscription_statuses`) — unpack a Get All Subscription
    Statuses response's nested `lastTransactions` JWS arrays into verified
    `AppStoreServerApi::SubscriptionStatus` structs with named statuses.
- Typed, actionable client errors replacing generic string exceptions:
  `APIError` (with `http_status`, `api_error_code`, `response_body`),
  `ClientError`, `TransactionIdNotFoundError`, `RateLimitExceededError`,
  `ServerError`, and `NetworkError`. `RetryableError` marks the transient ones.
- Automatic retry with exponential backoff on rate-limit (429), 5xx, and
  network failures, configurable via `max_retries:` / `retry_base_delay:`.
- Specs covering the new helpers, constants, error mapping, and retry behavior.

## [0.2.0] - 2026-07-22

Fork of [`mnyify/app_store_server_api`](https://github.com/mnyify/app_store_server_api)
maintained under `invest-with-roots`, base commit
`5c4cb97c9ac9445a308e726652220aa0a61fae83`.

### Changed
- Hardened `Utils::Decoder` JWS verification to match Apple's official
  verifier (ported from Apple's MIT-licensed `app-store-server-library`):
  - Enforce an x5c chain of exactly three certificates.
  - Build and validate the chain to a trusted Apple root CA (only self-signed
    bundled roots are trusted as anchors).
  - Require the Apple leaf marker OID (`1.2.840.113635.100.6.11.1`) and the
    WWDR intermediate marker OID (`1.2.840.113635.100.6.2.1`).
  - Evaluate certificate validity dates at the payload's `signedDate`.
  - Reject non-ES256 algorithms.

### Added
- Optional `bundle_id:` and `environment:` assertions on the decode helpers to
  reject cross-app / cross-environment payloads (App Store Server Notifications).
- `Utils::Decoder.decode_notification` and an injectable `root_certificates:`
  option (used by the test suite).
- Specs covering verification against Apple's published test JWS fixtures.

## [0.1.0] - 2024-05-12

- Initial release
