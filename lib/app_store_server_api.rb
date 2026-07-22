# frozen_string_literal: true

require_relative "app_store_server_api/version"

module AppStoreServerApi
  class Error < StandardError; end
end

require_relative "app_store_server_api/errors"
require_relative "app_store_server_api/notification_type_v2"
require_relative "app_store_server_api/subtype"
require_relative "app_store_server_api/status"
require_relative "app_store_server_api/models"
require_relative "app_store_server_api/utils/decoder"
require_relative "app_store_server_api/client"
