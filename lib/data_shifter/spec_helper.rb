# frozen_string_literal: true

module DataShifter
  # Test helpers for RSpec. Include this module in your spec_helper or rails_helper:
  #
  #   require "data_shifter/spec_helper"
  #
  #   RSpec.configure do |config|
  #     config.include DataShifter::SpecHelper, type: :data_shift
  #   end
  #
  # Or include it in individual specs:
  #
  #   RSpec.describe DataShifts::BackfillFoo do
  #     include DataShifter::SpecHelper
  #     ...
  #   end
  #
  module SpecHelper
    # Run a data shift class with the given options.
    # Returns the Axn::Result.
    #
    # @param shift_class [Class] the DataShifter::Shift subclass
    # @param dry_run [Boolean] whether to run in dry_run mode (default: true)
    # @param commit [Boolean] shorthand for dry_run: false (default: false)
    # @return [Axn::Result]
    #
    # @example
    #   result = run_data_shift(DataShifts::BackfillFoo)
    #   expect(result).to be_ok
    #
    # @example with commit
    #   result = run_data_shift(DataShifts::BackfillFoo, commit: true)
    #   expect(record.reload.foo).to eq("bar")
    #
    def run_data_shift(shift_class, dry_run: true, commit: false)
      effective_dry_run = commit ? false : dry_run
      shift_class.call(dry_run: effective_dry_run)
    end

    # Suppress STDOUT output during a block (useful for cleaner test output).
    #
    # @example
    #   silence_data_shift_output do
    #     run_data_shift(DataShifts::BackfillFoo, commit: true)
    #   end
    #
    def silence_data_shift_output
      original_stdout = $stdout
      $stdout = StringIO.new
      yield
    ensure
      $stdout = original_stdout
    end

    # Run a shift and capture its output.
    # Returns [Axn::Result, String] tuple.
    #
    # @example
    #   result, output = capture_data_shift_output do
    #     run_data_shift(DataShifts::BackfillFoo)
    #   end
    #   expect(output).to include("DRY RUN")
    #
    def capture_data_shift_output
      original_stdout = $stdout
      $stdout = StringIO.new
      result = yield
      output = $stdout.string
      [result, output]
    ensure
      $stdout = original_stdout
    end
  end
end
