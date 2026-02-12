# frozen_string_literal: true

module DataShifter
  module Internal
    # Signal trap management for status reporting during data shift runs.
    # All methods are stateless module functions.
    module SignalHandler
      module_function

      # Install signal traps for status reporting (SIGUSR1, SIGINFO).
      # Returns a hash of previous handlers to restore later.
      #
      # @param status_proc [Proc] the proc to call when signal is received
      # @return [Hash] previous signal handlers keyed by signal name
      def install_status_traps(status_proc)
        handlers = {}

        %w[USR1 INFO].each do |sig|
          next unless Signal.list.key?(sig)

          handlers[sig] = Signal.trap(sig, status_proc)
        end

        handlers
      end

      # Restore previous signal handlers.
      #
      # @param handlers [Hash] previous handlers from install_status_traps
      def restore_status_traps(handlers)
        handlers.each do |sig, prev|
          Signal.trap(sig, prev) if prev && Signal.list.key?(sig)
        end
      end
    end
  end
end
