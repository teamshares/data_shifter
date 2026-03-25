# frozen_string_literal: true

require "active_support/isolated_execution_state"

module DataShifter
  module Internal
    # Tracks whether Axn's on_error path already printed failure context (summary).
    # Used by rake tasks to avoid duplicating setup failure output.
    module RakeExceptionReporting
      KEY = :data_shifter_rake_failure_summary_reported

      module_function

      def clear!
        ActiveSupport::IsolatedExecutionState.delete(KEY)
      end

      def mark_failure_summary_reported!
        ActiveSupport::IsolatedExecutionState[KEY] = true
      end

      def failure_summary_reported?
        ActiveSupport::IsolatedExecutionState[KEY] == true
      end
    end
  end
end
