# frozen_string_literal: true

require_relative "app_store_server_api/version"

module AppStoreServerApi
  class Error < StandardError; end
end

require_relative "app_store_server_api/utils/decoder"
require_relative "app_store_server_api/client"
