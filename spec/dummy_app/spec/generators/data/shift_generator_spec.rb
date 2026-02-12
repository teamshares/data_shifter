# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "rails/generators"
require "rails/generators/testing/behavior"
require "rails/generators/testing/assertions"
require "generators/data_shift_generator"

RSpec.describe DataShiftGenerator do
  include Rails::Generators::Testing::Behavior
  include Rails::Generators::Testing::Assertions
  include FileUtils

  tests DataShiftGenerator
  destination File.expand_path("../../../tmp/generators", __dir__)

  before do
    prepare_destination
  end

  after do
    rm_rf(destination_root)
  end

  describe "basic generation" do
    before { run_generator %w[backfill_users] }

    it "creates a shift file in lib/data_shifts with timestamp prefix" do
      files = Dir.glob("#{destination_root}/lib/data_shifts/*_backfill_users.rb")
      expect(files.size).to eq(1)
      expect(File.basename(files.first)).to match(/\A\d{14}_backfill_users\.rb\z/)
    end

    it "wraps class in DataShifts module" do
      file = Dir.glob("#{destination_root}/lib/data_shifts/*_backfill_users.rb").first
      content = File.read(file)

      expect(content).to include("module DataShifts")
      expect(content).to include("end") # closing module
    end

    it "generates class inheriting from DataShifter::Shift" do
      file = Dir.glob("#{destination_root}/lib/data_shifts/*_backfill_users.rb").first
      content = File.read(file)

      expect(content).to include("class BackfillUsers < DataShifter::Shift")
    end

    it "includes description DSL placeholder" do
      file = Dir.glob("#{destination_root}/lib/data_shifts/*_backfill_users.rb").first
      content = File.read(file)

      expect(content).to include('description "TODO: Describe this shift"')
    end

    it "includes collection method stub" do
      file = Dir.glob("#{destination_root}/lib/data_shifts/*_backfill_users.rb").first
      content = File.read(file)

      expect(content).to include("def collection")
      expect(content).to include("# Model.where(foo: nil)")
    end

    it "includes process_record method stub with generic argument" do
      file = Dir.glob("#{destination_root}/lib/data_shifts/*_backfill_users.rb").first
      content = File.read(file)

      expect(content).to include("def process_record(record)")
      expect(content).to include("# record.update!(...)")
    end

    it "includes usage comments with rake commands" do
      file = Dir.glob("#{destination_root}/lib/data_shifts/*_backfill_users.rb").first
      content = File.read(file)

      expect(content).to include("rake data:shift:backfill_users")
      expect(content).to include("COMMIT=1 rake data:shift:backfill_users")
    end

    it "includes transaction DSL with inline options comment" do
      file = Dir.glob("#{destination_root}/lib/data_shifts/*_backfill_users.rb").first
      content = File.read(file)

      expect(content).to include("transaction true # or false or :per_record")
    end

    it "generates valid Ruby syntax" do
      file = Dir.glob("#{destination_root}/lib/data_shifts/*_backfill_users.rb").first
      expect { RubyVM::InstructionSequence.compile_file(file) }.not_to raise_error
    end
  end

  describe "with --model option" do
    before { run_generator %w[backfill_users --model=User] }

    it "pre-fills collection with model scope" do
      file = Dir.glob("#{destination_root}/lib/data_shifts/*_backfill_users.rb").first
      content = File.read(file)

      expect(content).to include("def collection")
      expect(content).to include("User.all")
    end

    it "uses model name as process_record argument" do
      file = Dir.glob("#{destination_root}/lib/data_shifts/*_backfill_users.rb").first
      content = File.read(file)

      expect(content).to include("def process_record(user)")
      expect(content).to include("# user.update!(...)")
    end
  end

  describe "with CamelCase name" do
    before { run_generator %w[BackfillUserEmails] }

    it "creates file with underscored name" do
      files = Dir.glob("#{destination_root}/lib/data_shifts/*_backfill_user_emails.rb")
      expect(files.size).to eq(1)
    end

    it "generates CamelCase class name" do
      file = Dir.glob("#{destination_root}/lib/data_shifts/*_backfill_user_emails.rb").first
      content = File.read(file)

      expect(content).to include("class BackfillUserEmails < DataShifter::Shift")
    end
  end

  describe "with underscored name" do
    before { run_generator %w[fix_legacy_data] }

    it "generates properly camelized class name" do
      file = Dir.glob("#{destination_root}/lib/data_shifts/*_fix_legacy_data.rb").first
      content = File.read(file)

      expect(content).to include("class FixLegacyData < DataShifter::Shift")
    end
  end

  describe "naming conflict detection" do
    it "does not create a second file when a shift with the same task name exists" do
      # Create the first shift
      run_generator %w[duplicate_name]
      first_files = Dir.glob("#{destination_root}/lib/data_shifts/*_duplicate_name.rb")
      expect(first_files.size).to eq(1)

      # Wait to ensure different timestamp
      sleep(0.01)

      # Attempt to create another with the same name should not create a new file
      run_generator %w[duplicate_name]
      after_files = Dir.glob("#{destination_root}/lib/data_shifts/*_duplicate_name.rb")

      # Should still be exactly 1 file (the original)
      expect(after_files.size).to eq(1)
      expect(after_files).to eq(first_files)
    end

    it "outputs error message with conflicting file path" do
      run_generator %w[existing_shift]

      output = capture(:stderr) { run_generator %w[existing_shift] }

      expect(output).to include("existing_shift")
      expect(output).to include("already exists")
      expect(output).to include("choose a different name")
    end

    it "allows shifts with different names" do
      run_generator %w[first_shift]

      expect { run_generator %w[second_shift] }.not_to raise_error
      expect(Dir.glob("#{destination_root}/lib/data_shifts/*_second_shift.rb").size).to eq(1)
    end
  end

  describe "spec file generation" do
    context "when rspec is enabled and --spec is passed" do
      before do
        allow_any_instance_of(DataShiftGenerator).to receive(:rspec_enabled?).and_return(true)
        run_generator %w[backfill_posts --model=Post --spec]
      end

      it "creates a spec file in spec/lib/data_shifts" do
        spec_file = "#{destination_root}/spec/lib/data_shifts/backfill_posts_spec.rb"
        expect(File.exist?(spec_file)).to be true
      end

      it "includes the correct class name in the spec" do
        spec_file = "#{destination_root}/spec/lib/data_shifts/backfill_posts_spec.rb"
        content = File.read(spec_file)

        expect(content).to include("RSpec.describe DataShifts::BackfillPosts")
      end

      it "includes DataShifter::SpecHelper" do
        spec_file = "#{destination_root}/spec/lib/data_shifts/backfill_posts_spec.rb"
        content = File.read(spec_file)

        expect(content).to include("include DataShifter::SpecHelper")
      end

      it "includes dry run and commit test stubs" do
        spec_file = "#{destination_root}/spec/lib/data_shifts/backfill_posts_spec.rb"
        content = File.read(spec_file)

        expect(content).to include('describe "dry run"')
        expect(content).to include('describe "commit"')
        expect(content).to include("run_data_shift(described_class, dry_run: true)")
        expect(content).to include("run_data_shift(described_class, commit: true)")
      end

      it "uses model name in let stub when --model is provided" do
        spec_file = "#{destination_root}/spec/lib/data_shifts/backfill_posts_spec.rb"
        content = File.read(spec_file)

        expect(content).to include("let(:post)")
      end

      it "generates valid Ruby syntax" do
        spec_file = "#{destination_root}/spec/lib/data_shifts/backfill_posts_spec.rb"
        expect { RubyVM::InstructionSequence.compile_file(spec_file) }.not_to raise_error
      end
    end

    context "when rspec is not enabled" do
      before do
        allow_any_instance_of(DataShiftGenerator).to receive(:rspec_enabled?).and_return(false)
        run_generator %w[backfill_comments --spec]
      end

      it "does not create a spec file" do
        spec_file = "#{destination_root}/spec/lib/data_shifts/backfill_comments_spec.rb"
        expect(File.exist?(spec_file)).to be false
      end
    end

    context "without --spec option" do
      before do
        allow_any_instance_of(DataShiftGenerator).to receive(:rspec_enabled?).and_return(true)
        run_generator %w[backfill_items]
      end

      it "does not create a spec file" do
        spec_file = "#{destination_root}/spec/lib/data_shifts/backfill_items_spec.rb"
        expect(File.exist?(spec_file)).to be false
      end
    end
  end
end
