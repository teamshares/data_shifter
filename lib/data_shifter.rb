# frozen_string_literal: true

require_relative "data_shifter/version"
require_relative "data_shifter/configuration"
require_relative "data_shifter/errors"
require_relative "data_shifter/shift"
require_relative "data_shifter/railtie"

module DataShifter
  class << self
    # Returns the global configuration instance.
    def config
      @config ||= Configuration.new
    end

    # Yields the configuration for block-style setup.
    #
    #   DataShifter.configure do |c|
    #     c.allow_external_requests = ["api.readonly.example.com"]
    #     c.suppress_repeated_logs = false
    #   end
    def configure
      yield config
    end
  end
end
