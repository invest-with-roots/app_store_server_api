## [Unreleased]

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
