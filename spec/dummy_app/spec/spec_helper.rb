# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"
ENV["RACK_ENV"] ||= "test"

require "webmock/rspec"
require "sidekiq/testing"

require File.expand_path("../config/environment", __dir__)

Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
  config.include FactoryBot::Syntax::Methods
end
