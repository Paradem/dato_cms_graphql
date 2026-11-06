# frozen_string_literal: true

require_relative "paradem_cms_site/version"

module ParademCmsSite
  class ConfigurationError < ArgumentError; end
end

require_relative "paradem_cms_site/plain_data"
require_relative "paradem_cms_site/manifest"
require_relative "paradem_cms_site/doctor"
require_relative "paradem_cms_site/railtie" if defined?(::Rails::Railtie)
