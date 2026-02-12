# frozen_string_literal: true

module DataShifter
  module Internal
    # Progress bar creation utility.
    # All methods are stateless module functions.
    module ProgressBar
      module_function

      # Create a progress bar for iteration.
      # Returns nil if progress is disabled or total is too small.
      #
      # @param total [Integer] total number of items
      # @param dry_run [Boolean] whether running in dry run mode
      # @param enabled [Boolean] whether progress bar is enabled
      # @return [ProgressBar::Base, nil] the progress bar or nil
      def create(total:, dry_run:, enabled:)
        return unless enabled && total >= 5

        require "ruby-progressbar"
        ::ProgressBar.create(
          total:,
          format: "%t: |%B| %c/%C (%P%%) %e",
          title: dry_run ? "Dry run" : "Processing",
        )
      end
    end
  end
end
