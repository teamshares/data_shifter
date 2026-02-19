# frozen_string_literal: true

require_relative "data_shifter/version"
require_relative "data_shifter/shift"
require_relative "data_shifter/railtie"

module DataShifter
  # Hosts or regexes allowed for HTTP during dry run (combined with per-shift allow_net_connect).
  # Set in an initializer: DataShifter.dry_run_allow_net_connect = ["api.readonly.example.com"]
  class << self
    attr_accessor :dry_run_allow_net_connect
  end
  self.dry_run_allow_net_connect = []
end
