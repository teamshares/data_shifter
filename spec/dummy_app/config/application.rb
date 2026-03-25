# frozen_string_literal: true

require_relative "boot"

require "rails/all"

Bundler.require(*Rails.groups)

require "data_shifter"

module DummyApp
  class Application < Rails::Application
    # Nested under spec/dummy_app; avoid resolving Rails.root to the gem root when running
    # `bundle exec rspec` from the repository root.
    config.root = File.expand_path("..", __dir__)

    config.load_defaults 7.0
    config.api_only = true
  end
end
