# frozen_string_literal: true

module DataShifter
  module Internal
    # Environment variable parsing utilities.
    # All methods are stateless module functions.
    module Env
      module_function

      TRUTHY = %w[1 true t yes y on].freeze
      FALSEY = %w[0 false f no n off].freeze

      # COMMIT=<truthy> means commit. Otherwise DRY_RUN decides, defaulting to a dry run.
      def dry_run?
        return !boolean!("COMMIT") if ENV["COMMIT"].present?
        return true if ENV["DRY_RUN"].blank?

        boolean!("DRY_RUN")
      end

      # Raises on anything unrecognized rather than picking a side. The old `DRY_RUN == "true"`
      # compare silently read `DRY_RUN=1` as "not dry" and committed the shift — a value that is
      # truthy in every other tool has to mean dry run here or it means data loss.
      def boolean!(var)
        raw = ENV.fetch(var, nil)
        case raw.to_s.strip.downcase
        when *TRUTHY then true
        when *FALSEY then false
        else
          raise ArgumentError, "#{var}=#{raw.inspect} is not a boolean — use one of: #{(TRUTHY + FALSEY).join(", ")}"
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
    end
  end
end
