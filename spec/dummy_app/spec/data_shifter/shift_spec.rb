# frozen_string_literal: true

RSpec.describe DataShifter::Shift do
  before { allow($stdout).to receive(:puts) }

  describe ".description" do
    it "stores and returns the description" do
      klass = Class.new(described_class) do
        description "Backfill foo on bars"
        define_method(:collection) { [] }
        define_method(:process_record) { |_record| nil }
      end
      expect(klass.description).to eq("Backfill foo on bars")
    end
  end

  let(:dry_run) { true }
  let(:records) { [record_a, record_b, record_c] }
  let(:record_a) { create(:user) }
  let(:record_b) { create(:user) }
  let(:record_c) { create(:user) }

  describe "collection-based migration" do
    subject(:result) { migration_class.call(dry_run:) }

    let(:migration_class) do
      recs = records
      Class.new(described_class) do
        define_method(:collection) { recs }
        define_method(:process_record) do |record|
          record.update!(time_zone: "Pacific Time (US & Canada)")
        end
      end
    end

    context "when dry_run is true (default)" do
      let(:dry_run) { true }

      it { is_expected.to be_ok }

      it "does not apply changes" do
        result
        expect(records.map { |r| r.reload.time_zone }).to all(eq("Eastern Time (US & Canada)"))
      end
    end

    context "when dry_run is false" do
      let(:dry_run) { false }

      it { is_expected.to be_ok }

      it "applies changes to all records" do
        result
        expect(records.map { |r| r.reload.time_zone }).to all(eq("Pacific Time (US & Canada)"))
      end
    end

    context "when collection is empty" do
      let(:migration_class) do
        Class.new(described_class) do
          define_method(:collection) { [] }
          define_method(:process_record) { |_record| nil }
        end
      end

      it { is_expected.to be_ok }
    end
  end

  describe "single transaction mode (default)" do
    subject(:result) { migration_class.call(dry_run: false) }

    context "when one record fails" do
      let(:migration_class) do
        recs = records
        bad_id = record_b.id
        Class.new(described_class) do
          define_method(:collection) { recs }
          define_method(:process_record) do |record|
            raise "boom" if record.id == bad_id

            record.update!(time_zone: "Pacific Time (US & Canada)")
          end
        end
      end

      it "rolls back all changes" do
        result
        expect(records.map { |r| r.reload.time_zone }).to all(eq("Eastern Time (US & Canada)"))
      end

      it "reports the failure" do
        expect(result).not_to be_ok
        expect(result.error).to include("failed")
      end
    end
  end

  describe "transaction :per_record mode" do
    context "when one record fails" do
      subject(:result) { migration_class.call(dry_run: false) }

      let(:migration_class) do
        recs = records
        bad_id = record_b.id
        Class.new(described_class) do
          transaction :per_record

          define_method(:collection) { recs }
          define_method(:process_record) do |record|
            raise "boom" if record.id == bad_id

            record.update!(time_zone: "Pacific Time (US & Canada)")
          end
        end
      end

      it "keeps changes for records that succeeded" do
        result
        expect(record_a.reload.time_zone).to eq("Pacific Time (US & Canada)")
        expect(record_c.reload.time_zone).to eq("Pacific Time (US & Canada)")
      end

      it "does not apply changes to the failed record" do
        result
        expect(record_b.reload.time_zone).to eq("Eastern Time (US & Canada)")
      end

      it "reports the failure" do
        expect(result).not_to be_ok
        expect(result.error).to include("1 record(s) failed")
      end
    end

    context "when dry_run is true" do
      let(:migration_class) do
        recs = records
        Class.new(described_class) do
          transaction :per_record

          define_method(:collection) { recs }
          define_method(:process_record) do |record|
            record.update!(time_zone: "Pacific Time (US & Canada)")
          end
        end
      end

      it "rolls back all changes (outer transaction)" do
        migration_class.call(dry_run: true)
        expect(records.map { |r| r.reload.time_zone }).to all(eq("Eastern Time (US & Canada)"))
      end
    end

    context "when multiple records fail" do
      subject(:result) { migration_class.call(dry_run: false) }

      let(:migration_class) do
        recs = records
        bad_ids = [record_a.id, record_c.id]
        Class.new(described_class) do
          transaction :per_record

          define_method(:collection) { recs }
          define_method(:process_record) do |record|
            raise "boom" if bad_ids.include?(record.id)

            record.update!(time_zone: "Pacific Time (US & Canada)")
          end
        end
      end

      it "keeps changes for the successful record only" do
        result
        expect(record_a.reload.time_zone).to eq("Eastern Time (US & Canada)")
        expect(record_b.reload.time_zone).to eq("Pacific Time (US & Canada)")
        expect(record_c.reload.time_zone).to eq("Eastern Time (US & Canada)")
      end

      it "reports both failures" do
        expect(result).not_to be_ok
        expect(result.error).to include("2 record(s) failed")
      end
    end
  end

  describe "transaction false mode" do
    subject(:result) { migration_class.call(dry_run: false) }

    let(:migration_class) do
      recs = records
      Class.new(described_class) do
        transaction false

        define_method(:collection) { recs }
        define_method(:process_record) do |record|
          record.update!(time_zone: "Pacific Time (US & Canada)")
        end
      end
    end

    it { is_expected.to be_ok }

    it "applies changes" do
      result
      expect(records.map { |r| r.reload.time_zone }).to all(eq("Pacific Time (US & Canada)"))
    end

    context "when one record raises" do
      let(:migration_class) do
        recs = records
        bad_id = record_b.id
        Class.new(described_class) do
          transaction false

          define_method(:collection) { recs }
          define_method(:process_record) do |record|
            raise "boom" if record.id == bad_id

            record.update!(time_zone: "Pacific Time (US & Canada)")
          end
        end
      end

      it "continues processing other records" do
        result
        expect(record_a.reload.time_zone).to eq("Pacific Time (US & Canada)")
        expect(record_c.reload.time_zone).to eq("Pacific Time (US & Canada)")
      end

      it "does not apply changes to the failed record" do
        result
        expect(record_b.reload.time_zone).to eq("Eastern Time (US & Canada)")
      end

      it "reports the failure" do
        expect(result).not_to be_ok
        expect(result.error).to include("1 record(s) failed")
      end
    end

    context "when dry_run is true and migration does not guard writes" do
      let(:migration_class) do
        recs = records
        Class.new(described_class) do
          transaction false

          define_method(:collection) { recs }
          define_method(:process_record) do |record|
            record.update!(time_zone: "Pacific Time (US & Canada)")
          end
        end
      end

      it "still rolls back (dry run always wrapped in transaction)" do
        migration_class.call(dry_run: true)
        expect(records.map { |r| r.reload.time_zone }).to all(eq("Eastern Time (US & Canada)"))
      end
    end

  end

  describe "skip! helper" do
    subject(:result) { migration_class.call(dry_run: false) }

    let(:migration_class) do
      recs = records
      skip_id = record_b.id
      Class.new(described_class) do
        transaction false

        define_method(:collection) { recs }
        define_method(:process_record) do |record|
          if record.id == skip_id
            skip!("not eligible")
            return
          end

          record.update!(time_zone: "Pacific Time (US & Canada)")
        end
      end
    end

    it { is_expected.to be_ok }

    it "skips the record and processes others" do
      result
      expect(record_a.reload.time_zone).to eq("Pacific Time (US & Canada)")
      expect(record_b.reload.time_zone).to eq("Eastern Time (US & Canada)")
      expect(record_c.reload.time_zone).to eq("Pacific Time (US & Canada)")
    end
  end

  describe "custom call override (non-collection)" do
    context "with transaction false (no wrapping)" do
      subject(:result) { migration_class.call(dry_run: false) }

      let(:migration_class) do
        rec = record_a
        Class.new(described_class) do
          transaction false

          define_method(:call) do
            return if dry_run?

            rec.update!(time_zone: "Pacific Time (US & Canada)")
          end
        end
      end

      it { is_expected.to be_ok }

      it "applies the change" do
        result
        expect(record_a.reload.time_zone).to eq("Pacific Time (US & Canada)")
      end
    end

    context "with default single transaction and dry_run" do
      let(:migration_class) do
        rec = record_a
        Class.new(described_class) do
          define_method(:call) do
            rec.update!(time_zone: "Pacific Time (US & Canada)")
          end
        end
      end

      it "rolls back when dry_run is true" do
        migration_class.call(dry_run: true)
        expect(record_a.reload.time_zone).to eq("Eastern Time (US & Canada)")
      end

      it "persists when dry_run is false" do
        migration_class.call(dry_run: false)
        expect(record_a.reload.time_zone).to eq("Pacific Time (US & Canada)")
      end
    end

    context "with default single transaction when call raises" do
      let(:migration_class) do
        rec = record_a
        Class.new(described_class) do
          define_method(:call) do
            rec.update!(time_zone: "Pacific Time (US & Canada)")
            raise "boom"
          end
        end
      end

      it "rolls back and reports the failure" do
        result = migration_class.call(dry_run: false)
        expect(record_a.reload.time_zone).to eq("Eastern Time (US & Canada)")
        expect(result).not_to be_ok
        expect(result.exception.message).to eq("boom")
      end
    end
  end

  describe "#find_exactly!" do
    let(:migration_instance) { Class.new(described_class).new(dry_run: true) }

    it "returns records in the order of the given ids" do
      result = migration_instance.find_exactly!(User, [record_b.id, record_a.id, record_c.id])
      expect(result.map(&:id)).to eq([record_b.id, record_a.id, record_c.id])
    end

    it "raises if any id is missing" do
      missing_id = 999_999_999
      expect do
        migration_instance.find_exactly!(User, [record_a.id, missing_id, record_b.id])
      end.to raise_error(/Expected User with ids.*but missing:.*999999999/)
    end

    it "returns model.none for empty ids" do
      result = migration_instance.find_exactly!(User, [])
      expect(result).to eq(User.none)
    end
  end

  describe ".run!" do
    let(:migration_class) do
      recs = records
      Class.new(described_class) do
        define_method(:collection) { recs }
        define_method(:process_record) { |_record| nil }
      end
    end

    it "parses DRY_RUN=true from ENV when COMMIT is not set" do
      allow(ENV).to receive(:[]).with("COMMIT").and_return(nil)
      allow(ENV).to receive(:fetch).with("DRY_RUN", "true").and_return("true")
      expect(migration_class).to receive(:call).with(dry_run: true).and_return(Axn::Result.ok("done"))
      migration_class.run!
    end

    it "parses DRY_RUN=false from ENV when COMMIT is not set" do
      allow(ENV).to receive(:[]).with("COMMIT").and_return(nil)
      allow(ENV).to receive(:fetch).with("DRY_RUN", "true").and_return("false")
      expect(migration_class).to receive(:call).with(dry_run: false).and_return(Axn::Result.ok("done"))
      migration_class.run!
    end

    it "parses COMMIT=1 from ENV and calls with dry_run: false" do
      allow(ENV).to receive(:[]).with("COMMIT").and_return("1")
      expect(migration_class).to receive(:call).with(dry_run: false).and_return(Axn::Result.ok("done"))
      migration_class.run!
    end

    it "parses COMMIT=true from ENV and calls with dry_run: false" do
      allow(ENV).to receive(:[]).with("COMMIT").and_return("true")
      expect(migration_class).to receive(:call).with(dry_run: false).and_return(Axn::Result.ok("done"))
      migration_class.run!
    end

    it "raises when the shift fails (Rake will exit non-zero)" do
      allow(ENV).to receive(:[]).with("COMMIT").and_return(nil)
      allow(ENV).to receive(:fetch).with("DRY_RUN", "true").and_return("true")
      allow(migration_class).to receive(:call).with(dry_run: true).and_return(Axn::Result.error("something broke"))
      expect { migration_class.run! }.to raise_error(StandardError, "something broke")
    end
  end

  describe "find_each for relation collections" do
    it "uses find_each when collection is a relation" do
      relation = User.where(id: [record_a.id, record_b.id])
      allow(relation).to receive(:find_each).and_call_original

      migration_class = Class.new(described_class) do
        define_method(:collection) { relation }
        define_method(:process_record) { |_record| nil }
      end
      migration_class.call(dry_run: true)
      expect(relation).to have_received(:find_each)
    end
  end

  describe "interrupt handling (Ctrl+C)" do
    let(:migration_class) do
      recs = records
      interrupt_at = record_b.id
      Class.new(described_class) do
        define_method(:collection) { recs }
        define_method(:process_record) do |record|
          raise Interrupt if record.id == interrupt_at

          record.update!(time_zone: "Pacific Time (US & Canada)")
        end
      end
    end

    context "with single transaction mode (default)" do
      it "rolls back all changes on interrupt" do
        expect { migration_class.call(dry_run: false) }.to raise_error(Interrupt)
        expect(record_a.reload.time_zone).to eq("Eastern Time (US & Canada)")
      end

      it "prints interrupted summary" do
        expect($stdout).to receive(:puts).with(/Interrupted by user/).at_least(:once)
        expect { migration_class.call(dry_run: false) }.to raise_error(Interrupt)
      end
    end

    context "with transaction :per_record mode" do
      let(:migration_class) do
        recs = records
        interrupt_at = record_b.id
        Class.new(described_class) do
          transaction :per_record

          define_method(:collection) { recs }
          define_method(:process_record) do |record|
            raise Interrupt if record.id == interrupt_at

            record.update!(time_zone: "Pacific Time (US & Canada)")
          end
        end
      end

      it "rolls back all changes on interrupt (outer dry_run transaction)" do
        expect { migration_class.call(dry_run: true) }.to raise_error(Interrupt)
        expect(record_a.reload.time_zone).to eq("Eastern Time (US & Canada)")
      end
    end

    context "with transaction false mode" do
      let(:migration_class) do
        recs = records
        interrupt_at = record_c.id
        Class.new(described_class) do
          transaction false

          define_method(:collection) { recs }
          define_method(:process_record) do |record|
            record.update!(time_zone: "Pacific Time (US & Canada)")
            raise Interrupt if record.id == interrupt_at
          end
        end
      end

      it "leaves partial changes applied (no transaction to roll back)" do
        expect { migration_class.call(dry_run: false) }.to raise_error(Interrupt)
        # record_a and record_b were processed before interrupt on record_c
        expect(record_a.reload.time_zone).to eq("Pacific Time (US & Canada)")
        expect(record_b.reload.time_zone).to eq("Pacific Time (US & Canada)")
        # record_c was updated then interrupted
        expect(record_c.reload.time_zone).to eq("Pacific Time (US & Canada)")
      end

      it "prints warning about partial changes" do
        expect($stdout).to receive(:puts).with(/`transaction false` mode was active/).at_least(:once)
        expect { migration_class.call(dry_run: false) }.to raise_error(Interrupt)
      end
    end
  end

  describe ".progress" do
    it "stores and returns progress enabled state" do
      klass = Class.new(described_class) do
        define_method(:collection) { [] }
        define_method(:process_record) { |_record| nil }
      end

      expect(klass.progress).to be_nil

      klass.progress false
      expect(klass.progress).to be false

      klass.progress true
      expect(klass.progress).to be true
    end
  end

  describe "throttle DSL" do
    let(:migration_class) do
      recs = records
      Class.new(described_class) do
        throttle 0.01

        define_method(:collection) { recs }
        define_method(:process_record) { |_record| nil }
      end
    end

    it "sleeps between records" do
      expect_any_instance_of(migration_class).to receive(:sleep).with(0.01).exactly(3).times
      migration_class.call(dry_run: true)
    end

    it "stores the throttle interval as a class attribute" do
      expect(migration_class._throttle_interval).to eq(0.01)
    end
  end

  describe "CONTINUE_FROM checkpointing" do
    around do |example|
      original_value = ENV["CONTINUE_FROM"]
      example.run
    ensure
      ENV["CONTINUE_FROM"] = original_value
    end

    context "with an ActiveRecord::Relation collection" do
      let(:migration_class) do
        Class.new(described_class) do
          define_method(:collection) { User.order(:id) }
          define_method(:process_record) { |record| record.update!(time_zone: "Pacific Time (US & Canada)") }
        end
      end

      it "skips records with id <= CONTINUE_FROM value" do
        # Force records to be created in order
        ordered_records = [record_a, record_b, record_c].sort_by(&:id)
        first_record = ordered_records.first

        ENV["CONTINUE_FROM"] = first_record.id.to_s
        migration_class.call(dry_run: false)

        expect(first_record.reload.time_zone).to eq("Eastern Time (US & Canada)")
        ordered_records[1..].each do |record|
          expect(record.reload.time_zone).to eq("Pacific Time (US & Canada)")
        end
      end

      it "logs a message about resuming" do
        ENV["CONTINUE_FROM"] = record_a.id.to_s
        expect($stdout).to receive(:puts).with(/CONTINUE_FROM.*Resuming from id > #{record_a.id}/).at_least(:once)
        migration_class.call(dry_run: true)
      end
    end

    context "with an Array collection (e.g. find_exactly!)" do
      let(:migration_class) do
        recs = records
        Class.new(described_class) do
          define_method(:collection) { recs }
          define_method(:process_record) { |_record| nil }
        end
      end

      it "raises an error" do
        ENV["CONTINUE_FROM"] = "123"
        result = migration_class.call(dry_run: true)
        # Axn wraps exceptions in the result, so check the exception
        expect(result.exception).to be_a(ArgumentError)
        expect(result.exception.message).to match(/CONTINUE_FROM is only supported for ActiveRecord::Relation/)
      end
    end

    context "when CONTINUE_FROM is not set" do
      let(:migration_class) do
        recs = records
        Class.new(described_class) do
          define_method(:collection) { recs }
          define_method(:process_record) { |_record| nil }
        end
      end

      it "processes all records" do
        ENV["CONTINUE_FROM"] = nil
        result = migration_class.call(dry_run: true)
        expect(result).to be_ok
      end
    end
  end

  describe "CONTINUE_FROM hint in summary" do
    let(:ordered_records) { [record_a, record_b, record_c].sort_by(&:id) }
    let(:first_record) { ordered_records[0] }
    let(:second_record) { ordered_records[1] }
    let(:third_record) { ordered_records[2] }

    context "with transaction false mode and failures" do
      let(:migration_class) do
        bad_id = second_record.id
        Class.new(described_class) do
          transaction false
          task_name "test_shift"

          define_method(:collection) { User.order(:id) }
          define_method(:process_record) do |record|
            raise "boom" if record.id == bad_id

            record.update!(time_zone: "Pacific Time (US & Canada)")
          end
        end
      end

      it "prints CONTINUE_FROM hint with last successful ID" do
        output = StringIO.new
        allow($stdout).to receive(:puts) { |msg| output.puts(msg) }

        migration_class.call(dry_run: false)

        # first succeeds, second fails, third succeeds => last successful is third
        expect(output.string).to include("To resume from the last successful record")
        expect(output.string).to include("CONTINUE_FROM=#{third_record.id}")
      end

      it "does not print hint in dry run mode" do
        output = StringIO.new
        allow($stdout).to receive(:puts) { |msg| output.puts(msg) }

        migration_class.call(dry_run: true)

        expect(output.string).not_to include("CONTINUE_FROM")
      end
    end

    context "with transaction :per_record mode and failures" do
      let(:migration_class) do
        bad_id = second_record.id
        Class.new(described_class) do
          transaction :per_record
          task_name "test_shift"

          define_method(:collection) { User.order(:id) }
          define_method(:process_record) do |record|
            raise "boom" if record.id == bad_id

            record.update!(time_zone: "Pacific Time (US & Canada)")
          end
        end
      end

      it "does not print CONTINUE_FROM hint (per-record transactions handle rollback)" do
        expect($stdout).not_to receive(:puts).with(/CONTINUE_FROM/)
        migration_class.call(dry_run: false)
      end
    end

    context "with single transaction mode (default) and failures" do
      let(:migration_class) do
        bad_id = second_record.id
        Class.new(described_class) do
          task_name "test_shift"

          define_method(:collection) { User.order(:id) }
          define_method(:process_record) do |record|
            raise "boom" if record.id == bad_id

            record.update!(time_zone: "Pacific Time (US & Canada)")
          end
        end
      end

      it "does not print CONTINUE_FROM hint (everything rolls back)" do
        expect($stdout).not_to receive(:puts).with(/CONTINUE_FROM/)
        migration_class.call(dry_run: false)
      end
    end

    context "without task_name set" do
      let(:migration_class) do
        bad_id = second_record.id
        Class.new(described_class) do
          transaction false
          # No task_name set

          define_method(:collection) { User.order(:id) }
          define_method(:process_record) do |record|
            raise "boom" if record.id == bad_id

            record.update!(time_zone: "Pacific Time (US & Canada)")
          end
        end
      end

      it "does not print CONTINUE_FROM hint (no rake task to reference)" do
        expect($stdout).not_to receive(:puts).with(/CONTINUE_FROM/)
        migration_class.call(dry_run: false)
      end
    end
  end

  describe "side-effect guards (dry run)" do
    it "blocks HTTP to disallowed hosts during dry run" do
      # Guard applies WebMock.disable_net_connect!; we translate to ExternalRequestNotAllowedError
      expect do
        DataShifter::Internal::SideEffectGuards.with_guards(
          shift_class: Class.new(described_class)
        ) { Net::HTTP.get(URI("http://external.example.com/")) }
      end.to raise_error(DataShifter::ExternalRequestNotAllowedError) do |e|
        expect(e.attempted_host).to eq("external.example.com")
        expect(e.message).to include('allow_external_requests ["external.example.com"]')
        expect(e.message).to include("DataShifter.config.allow_external_requests")
        expect(e.message).not_to include("WebMock")
        expect(e.cause).to be_a(WebMock::NetConnectNotAllowedError)
      end
    end

    it "blocks HTTP when running a shift in dry run (integration)" do
      record_a # ensure at least one user exists
      migration_class = Class.new(described_class) do
        define_method(:collection) { User.limit(1) }
        define_method(:process_record) { |_record| Net::HTTP.get(URI("http://external.example.com/")) }
      end
      result = migration_class.call(dry_run: true)
      expect(result).not_to be_ok
      expect(result.exception).to be_a(DataShifter::ExternalRequestNotAllowedError)
      expect(result.exception.attempted_host).to eq("external.example.com")
      expect(result.exception.message).not_to include("WebMock")
    end

    it "allows HTTP to hosts listed in allow_external_requests during dry run" do
      record_a # ensure at least one user exists
      stub_request(:get, "http://allowed.example.com/").to_return(status: 200, body: "ok")
      migration_class = Class.new(described_class) do
        allow_external_requests ["allowed.example.com"]

        define_method(:collection) { User.limit(1) }
        define_method(:process_record) { |_record| Net::HTTP.get(URI("http://allowed.example.com/")) }
      end
      result = migration_class.call(dry_run: true)
      expect(result).to be_ok
    end

    it "does not block HTTP when commit (dry_run: false)" do
      stub_request(:get, "http://example.com/").to_return(status: 200)
      migration_class = Class.new(described_class) do
        define_method(:collection) { User.limit(1) }
        define_method(:process_record) { |_record| Net::HTTP.get(URI("http://example.com/")) }
      end
      result = migration_class.call(dry_run: false)
      expect(result).to be_ok
    end

    it "restores WebMock after dry run to previous state (e.g. enabled in specs)" do
      migration_class = Class.new(described_class) do
        define_method(:collection) { [] }
        define_method(:process_record) { |_record| nil }
      end
      migration_class.call(dry_run: true)
      # Restored to enabled (spec env), so stubs apply again
      stub_request(:get, "http://after.example.com/").to_return(status: 200)
      expect { Net::HTTP.get(URI("http://after.example.com/")) }.not_to raise_error
    end

    context "ActionMailer guard" do
      it "sets perform_deliveries to false during dry run and restores after" do
        original = ActionMailer::Base.perform_deliveries
        value_during_block = nil
        DataShifter::Internal::SideEffectGuards.with_guards(shift_class: Class.new(described_class)) do
          value_during_block = ActionMailer::Base.perform_deliveries
        end
        expect(value_during_block).to eq(false)
        expect(ActionMailer::Base.perform_deliveries).to eq(original)
      end
    end

    context "ActiveJob guard" do
      it "uses test queue adapter during dry run and restores after" do
        original_adapter = ActiveJob::Base.queue_adapter
        adapter_during_block = nil
        DataShifter::Internal::SideEffectGuards.with_guards(shift_class: Class.new(described_class)) do
          adapter_during_block = ActiveJob::Base.queue_adapter
        end
        expect(adapter_during_block).to be_a(ActiveJob::QueueAdapters::TestAdapter)
        expect(ActiveJob::Base.queue_adapter).to eq(original_adapter)
      end
    end

    context "Sidekiq guard" do
      it "calls fake! during dry run and disable! on restore" do
        expect(Sidekiq::Testing).to receive(:fake!).and_call_original
        expect(Sidekiq::Testing).to receive(:disable!).and_call_original
        DataShifter::Internal::SideEffectGuards.with_guards(shift_class: Class.new(described_class)) do
          expect(Sidekiq::Testing.fake?).to be true
        end
      end
    end
  end

  describe ".allow_external_requests" do
    it "stores allowed hosts for dry run" do
      klass = Class.new(described_class) do
        allow_external_requests ["api.example.com", %r{\.readonly\.local\z}]
      end
      expect(klass._allow_external_requests).to eq(["api.example.com", %r{\.readonly\.local\z}])
    end
  end

  describe ".suppress_repeated_logs" do
    it "stores boolean for per-shift override" do
      klass = Class.new(described_class) do
        suppress_repeated_logs false
      end
      expect(klass._suppress_repeated_logs).to be false
    end

    it "defaults to nil (use config)" do
      klass = Class.new(described_class)
      expect(klass._suppress_repeated_logs).to be_nil
    end
  end

  describe "progress from config" do
    let(:original_progress_enabled) { DataShifter.config.progress_enabled }

    before { original_progress_enabled }

    after { DataShifter.config.progress_enabled = original_progress_enabled }

    it "uses config.progress_enabled when _progress_enabled is nil" do
      DataShifter.config.progress_enabled = false
      items = [Struct.new(:id).new(1), Struct.new(:id).new(2)]
      klass = Class.new(described_class) do
        define_singleton_method(:items) { items }
        define_method(:collection) { self.class.items }
        define_method(:process_record) { |_| nil }
      end
      expect(klass._progress_enabled).to be_nil

      expect(DataShifter::Internal::ProgressBar).to receive(:create).with(hash_including(enabled: false)).and_call_original
      klass.call(dry_run: true)
    end

    it "uses per-shift progress setting when explicitly set" do
      DataShifter.config.progress_enabled = true
      items = [Struct.new(:id).new(1), Struct.new(:id).new(2)]
      klass = Class.new(described_class) do
        progress false
        define_singleton_method(:items) { items }
        define_method(:collection) { self.class.items }
        define_method(:process_record) { |_| nil }
      end

      expect(DataShifter::Internal::ProgressBar).to receive(:create).with(hash_including(enabled: false)).and_call_original
      result = klass.call(dry_run: true)
      expect(result).to be_ok
    end
  end

  describe "transaction DSL" do
    let(:migration_class) { Class.new(described_class) }

    it "sets mode to :per_record" do
      migration_class.transaction(:per_record)
      expect(migration_class._transaction_mode).to eq(:per_record)
    end

    it "sets mode to :none with false" do
      migration_class.transaction(false)
      expect(migration_class._transaction_mode).to eq(:none)
    end

    it "sets mode to :none with :none" do
      migration_class.transaction(:none)
      expect(migration_class._transaction_mode).to eq(:none)
    end

    it "sets mode to :single with true" do
      migration_class.transaction(true)
      expect(migration_class._transaction_mode).to eq(:single)
    end

    it "sets mode to :single with :single" do
      migration_class.transaction(:single)
      expect(migration_class._transaction_mode).to eq(:single)
    end

    it "raises on invalid mode" do
      expect { migration_class.transaction(:invalid) }.to raise_error(ArgumentError)
    end
  end
end
