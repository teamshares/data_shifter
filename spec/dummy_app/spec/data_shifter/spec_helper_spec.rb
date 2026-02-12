# frozen_string_literal: true

require "data_shifter/spec_helper"

RSpec.describe DataShifter::SpecHelper do
  include described_class

  before { allow($stdout).to receive(:puts) }

  let(:shift_class) do
    Class.new(DataShifter::Shift) do
      define_method(:collection) { [] }
      define_method(:process_record) { |_record| nil }
    end
  end

  describe "#run_data_shift" do
    it "runs with dry_run: true by default" do
      expect(shift_class).to receive(:call).with(dry_run: true).and_call_original
      run_data_shift(shift_class)
    end

    it "runs with dry_run: false when commit: true" do
      expect(shift_class).to receive(:call).with(dry_run: false).and_call_original
      run_data_shift(shift_class, commit: true)
    end

    it "respects explicit dry_run: false" do
      expect(shift_class).to receive(:call).with(dry_run: false).and_call_original
      run_data_shift(shift_class, dry_run: false)
    end

    it "returns the Axn::Result" do
      result = run_data_shift(shift_class)
      expect(result).to be_ok
    end
  end

  describe "#silence_data_shift_output" do
    let(:noisy_shift_class) do
      Class.new(DataShifter::Shift) do
        define_method(:collection) { [] }
        define_method(:process_record) { |_record| nil }
      end
    end

    it "suppresses stdout" do
      output = capture_stdout do
        silence_data_shift_output do
          noisy_shift_class.call(dry_run: true)
        end
      end
      expect(output).to be_empty
    end

    def capture_stdout
      original = $stdout
      $stdout = StringIO.new
      yield
      $stdout.string
    ensure
      $stdout = original
    end
  end

  describe "#capture_data_shift_output" do
    let(:noisy_shift_class) do
      Class.new(DataShifter::Shift) do
        define_method(:collection) { [] }
        define_method(:process_record) { |_record| nil }
      end
    end

    it "returns result and captured output" do
      # Need to allow real puts for capture_data_shift_output to work
      allow($stdout).to receive(:puts).and_call_original

        result, output = capture_data_shift_output do
        noisy_shift_class.call(dry_run: true)
      end

      expect(result).to be_ok
      expect(output).to include("DRY RUN")
    end
  end
end
