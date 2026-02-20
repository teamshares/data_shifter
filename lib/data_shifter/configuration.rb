# frozen_string_literal: true

module DataShifter
  # Global configuration for DataShifter.
  #
  # Configure via:
  #   DataShifter.configure do |config|
  #     config.allow_external_requests = ["api.readonly.example.com"]
  #     config.suppress_repeated_logs = true
  #   end
  #
  # Or access directly:
  #   DataShifter.config.progress_enabled = false
  class Configuration
    # Hosts or regexes allowed for HTTP during dry run only (combined with per-shift allow_external_requests).
    # Has no effect in commit mode — HTTP is unrestricted when dry_run is false.
    attr_accessor :allow_external_requests

    # Whether to suppress repeated log messages during a shift run. Default: true.
    # Can be overridden per shift with `suppress_repeated_logs true/false`.
    attr_accessor :suppress_repeated_logs

    # Maximum unique log messages to track for deduplication. Default: 1000.
    # When exceeded, entries with count == 1 are cleared first; repeated entries are kept.
    attr_accessor :repeated_log_cap

    # Global default for progress bar visibility. Default: true.
    # Per-shift `progress true/false` overrides this.
    attr_accessor :progress_enabled

    # Default status print interval in seconds when ENV STATUS_INTERVAL is not set. Default: nil.
    attr_accessor :status_interval_seconds

    def initialize
      @allow_external_requests = []
      @suppress_repeated_logs = true
      @repeated_log_cap = 1000
      @progress_enabled = true
      @status_interval_seconds = nil
    end
  end
end
