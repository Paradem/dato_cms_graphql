# frozen_string_literal: true

require "rails/railtie"

module ParademCmsSite
  class Railtie < ::Rails::Railtie
    rake_tasks do
      load File.expand_path("tasks.rake", __dir__)
    end
  end
end
