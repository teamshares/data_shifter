# frozen_string_literal: true

module DataShifter
  module Internal
    # Environment variable parsing utilities.
    # All methods are stateless module functions.
    module Env
      module_function

      # Determine dry_run mode from environment variables.
      # COMMIT=1 or COMMIT=true means dry_run=false
      # DRY_RUN=false means dry_run=false; default is true
      def dry_run?
        if ENV["COMMIT"].present?
          !%w[1 true].include?(ENV["COMMIT"].to_s.downcase)
        else
          ENV.fetch("DRY_RUN", "true") == "true"
        end
      end

      # Parse STATUS_INTERVAL environment variable, falling back to config.
      # Returns nil if not set/invalid and config is nil.
      def status_interval_seconds
        if ENV["STATUS_INTERVAL"].present?
          Integer(ENV.fetch("STATUS_INTERVAL", nil), 10)
        else
          DataShifter.config.status_interval_seconds
        end
      rescue ArgumentError
        DataShifter.config.status_interval_seconds
      end

      # Get CONTINUE_FROM environment variable value.
      # Returns nil if not set or empty.
      def continue_from_id
        ENV.fetch("CONTINUE_FROM", nil).presence
      end

      # Get countdown seconds for no-transaction warning.
      # DATA_SHIFTER_NO_TX_COUNTDOWN=0 skips the wait (still prints warning).
      # Returns 5 by default.
      def no_transaction_countdown_seconds
        value = ENV.fetch("DATA_SHIFTER_NO_TX_COUNTDOWN", nil)
        return 5 if value.blank?

        Integer(value, 10)
      rescue ArgumentError
        5
      end
    end
  end
end
