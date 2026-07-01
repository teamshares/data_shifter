# frozen_string_literal: true

require "axn"

# Global configuration for DataShifter, declared via the Axn::Configurable DSL.
#
# Configure via:
#   DataShifter.configure do |config|
#     config.allow_external_requests = ["api.readonly.example.com"]
#     config.suppress_repeated_logs = false
#   end
#
# Or access directly:
#   DataShifter.config.progress_enabled = false
#
# This supplies DataShifter.config / .configure / .reset_config! plus per-setting
# accessors and predicates. `progress_enabled` and `suppress_repeated_logs` are
# `overridable: true`, so individual shifts can override them per-class (see Shift).
#
# Required from both data_shifter.rb and shift.rb (idempotent, like any require)
# so `include DataShifter.overrides` in Shift works whichever is required first.
module DataShifter
  extend Axn::Configurable

  # Hosts or regexes allowed for HTTP during dry run only (combined with per-shift allow_external_requests).
  # Has no effect in commit mode — HTTP is unrestricted when dry_run is false.
  setting :allow_external_requests, default: []

  # Whether to allow loopback HTTP (127.0.0.1, ::1, localhost) during dry runs. Default: true.
  # Loopback is rarely "external" and is needed for tracing/metrics sidecars (Datadog agent on
  # 8126, statsd on 8125, OTLP collector, etc.). Set to false if you want strict net blocking.
  setting :allow_loopback_requests, default: true

  # Whether to suppress repeated log messages during a shift run. Default: true.
  # Can be overridden per shift with `suppress_repeated_logs true/false`.
  setting :suppress_repeated_logs, default: true, overridable: true

  # Maximum unique log messages to track for deduplication. Default: 1000.
  # When exceeded, entries with count == 1 are cleared first; repeated entries are kept.
  setting :repeated_log_cap, default: 1000

  # Global default for progress bar visibility. Default: true.
  # Per-shift `progress true/false` overrides this.
  setting :progress_enabled, default: true, overridable: true

  # Default status print interval in seconds when ENV STATUS_INTERVAL is not set. Default: nil.
  setting :status_interval_seconds, default: nil
end
