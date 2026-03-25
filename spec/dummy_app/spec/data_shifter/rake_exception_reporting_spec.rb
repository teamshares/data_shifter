# frozen_string_literal: true

RSpec.describe DataShifter::Internal::RakeExceptionReporting do
  before do
    allow($stdout).to receive(:puts)
    described_class.clear!
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:[]).with("COMMIT").and_return(nil)
    allow(ENV).to receive(:fetch).with("DRY_RUN", "true").and_return("true")
  end

  describe "with Shift integration" do
    let(:ok_shift) do
      Class.new(DataShifter::Shift) do
        task { nil }
      end
    end

    let(:failing_shift) do
      Class.new(DataShifter::Shift) do
        task { raise "task failure for spec" }
      end
    end

    it "does not mark after a successful call" do
      result = ok_shift.call(dry_run: true)
      expect(result).to be_ok
      expect(described_class.failure_summary_reported?).to be(false)
    end

    it "marks after Axn error path (failed call)" do
      result = failing_shift.call(dry_run: true)
      expect(result).not_to be_ok
      expect(described_class.failure_summary_reported?).to be(true)
    end

    it "clears the flag at the start of a subsequent run" do
      failing_shift.call(dry_run: true)
      expect(described_class.failure_summary_reported?).to be(true)

      result = ok_shift.call(dry_run: true)
      expect(result).to be_ok
      expect(described_class.failure_summary_reported?).to be(false)
    end
  end

  describe "interrupt handling" do
    let(:records) { [create(:user), create(:user)] }
    let(:interrupt_at) { records.second.id }

    let(:interrupting_shift) do
      recs = records
      at = interrupt_at
      Class.new(DataShifter::Shift) do
        define_method(:collection) { recs }
        define_method(:process_record) do |record|
          raise Interrupt if record.id == at

          record.update!(time_zone: "Pacific Time (US & Canada)")
        end
      end
    end

    it "does not mark failure summary reported on Interrupt" do
      expect(described_class).not_to receive(:mark_failure_summary_reported!)

      expect { interrupting_shift.call(dry_run: false) }.to raise_error(Interrupt)
    end
  end
end
