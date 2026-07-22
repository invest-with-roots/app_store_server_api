# Apple test fixtures

These files are copied verbatim from Apple's MIT-licensed official library
[`apple/app-store-server-library-python`](https://github.com/apple/app-store-server-library-python)
(`tests/resources/`), used here purely to exercise JWS verification.

- `certs/testCA.der` — the test root CA that anchors the signed data below.
- `mock_signed_data/*` — pre-signed JWS payloads produced by Apple's test suite:
  - `transactionInfo`, `renewalInfo`, `testNotification` — valid, Sandbox.
  - `wrongBundleId` — a valid chain whose payload carries a different bundleId.
  - `missingX5CHeaderClaim` — a JWS without an `x5c` header.

Copyright (c) 2023 Apple Inc. Licensed under the MIT License. No code from
these libraries is copied into the gem's runtime — only these test vectors.

The certificate constants used for the certificate-chain edge cases
(`spec/support/apple_test_certificates.rb`) come from the same repository's
`tests/test_x509_verifiction.py`.
