# app-store-server-api
A Ruby client for the [App Store Server API](https://developer.apple.com/documentation/appstoreserverapi), offering:
- Transaction history, transaction info, and subscription status endpoints
- Test notification and notification history endpoints
- Automatic ES256 JWT authentication with token refresh
- Helpers for decoding and verifying JWS payloads
- Built-in trust chain validation against Apple Root CAs

[![Gem Version](https://badge.fury.io/rb/app_store_server_api.svg)](https://badge.fury.io/rb/app_store_server_api)

> **Fork notice.** This is the `invest-with-roots` maintained fork of the
> MIT-licensed [`mnyify/app_store_server_api`](https://github.com/mnyify/app_store_server_api),
> forked from base commit
> [`5c4cb97c9ac9445a308e726652220aa0a61fae83`](https://github.com/mnyify/app_store_server_api/commit/5c4cb97c9ac9445a308e726652220aa0a61fae83).
> The upstream MIT license and attribution are preserved in `LICENSE.txt`. JWS
> verification has been hardened to match Apple's official verifier — see
> [JWS verification](#jws-verification).

## Features
* Transaction history, transaction info, and subscription status endpoints
* Test notification and notification history endpoints
* Automatic ES256 JWT authentication with token refresh
* Helpers for decoding and verifying JWS payloads
* Built-in trust chain validation against Apple Root CAs

## Requirements
- Ruby 3.0 or higher

## Installation

### RubyGems
```bash
gem install app_store_server_api
```

### Bundler
Add to your `Gemfile`:
```ruby
gem 'app_store_server_api'
```
Run:
```bash
bundle install
```

## Usage

### Prerequisites
To get started, you must obtain the following:
- An [API key](https://developer.apple.com/documentation/appstoreserverapi/creating_api_keys_to_use_with_the_app_store_server_api)
- The ID of the key
- Your [issuer ID](https://developer.apple.com/documentation/appstoreserverapi/generating_tokens_for_api_requests)

### Configure

**In your Rails application, create a client configure**

```ruby
# my_app/config/app_store_server.yml
default: &default
  private_key: |
    -----BEGIN PRIVATE KEY-----
  key_id: S4AZ693A4A
  issuer_id: fd02853a-1290-4854-875e-918c86459b3e
  bundle_id: com.myapp.app
  environment: sandbox

development:
  <<: *default

test:
  <<: *default

production:
  <<: *default
```

**Load the configure**

```ruby
# my_app/config/application.rb

config.app_store_server = config_for :app_store_server
```

**Create a global client**

```ruby
# my_app/config/initializers/app_store_server_api.rb

AppStoreServerApiClient = AppStoreServerApi::Client.new(**Rails.configuration.app_store_server)
```

### API

**Get Transaction History**

```ruby
data = client.get_transaction_history(transaction_id,
  params: {
    sort: "DESCENDING"
  })

transactions = AppStoreServerApi::Utils::Decoder.decode_transactions signed_transactions: data["signedTransactions"]
```

**Get Transaction Info**

```ruby
client.get_transaction_info transaction_id
```

**Get All Subscription Statuses**
```ruby
response = client.get_all_subscription_statuses transaction_id

signed = response["data"].first["lastTransactions"].first["signedTransactionInfo"]

transaction = AppStoreServerApi::Utils::Decoder.decode_transaction signed_transaction: signed
```

**Request a Test Notification**

```ruby
client.request_a_test_notification
```


**Utils**

- AppStoreServerApi::Utils::Decoder.decode_transaction
- AppStoreServerApi::Utils::Decoder.decode_transactions
- AppStoreServerApi::Utils::Decoder.decode_notification
- AppStoreServerApi::Utils::Decoder.decode_jws!

## JWS verification

`Utils::Decoder` verifies the JWS payloads returned by the App Store Server API
and App Store Server Notifications using the same semantics as Apple's official
libraries (ported from the MIT-licensed
[`apple/app-store-server-library-python`](https://github.com/apple/app-store-server-library-python)
/ [`-node`](https://github.com/apple/app-store-server-library-node)). A payload
is trusted only when:

1. Its `x5c` header carries a chain of exactly three certificates.
2. That chain builds and validates up to a bundled, trusted Apple root CA, with
   each certificate's validity window evaluated at the payload's `signedDate`.
3. The leaf carries Apple's leaf marker OID (`1.2.840.113635.100.6.11.1`) and
   the intermediate carries the WWDR marker OID (`1.2.840.113635.100.6.2.1`).
4. The signature verifies against the leaf's public key using ES256.

For App Store Server Notifications you should also assert the app identity so
cross-app or cross-environment payloads are rejected:

```ruby
payload = AppStoreServerApi::Utils::Decoder.decode_notification(
  signed_payload: signed_payload,
  bundle_id: "com.myapp.app",
  environment: :sandbox
)
```

`bundle_id:` and `environment:` are also accepted by `decode_transaction`,
`decode_transactions`, and `decode_jws!`, and are optional (verification of the
signing chain always runs). A `AppStoreServerApi::Utils::Decoder::VerificationError`
is raised when any check fails.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the AppStoreServerApi project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/mnyify/app_store_server_api/blob/main/CODE_OF_CONDUCT.md).
