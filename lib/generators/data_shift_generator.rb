# frozen_string_literal: true

# Generator for data shifts.
#
# Usage:
#   rails g data_shift backfill_users
#   rails g data_shift backfill_users --model=User
#
class DataShiftGenerator < Rails::Generators::NamedBase
  class_option :model,
               type: :string,
               default: nil,
               desc: "Model to operate on (e.g. User). Pre-fills the collection method."

  class_option :spec,
               type: :boolean,
               default: false,
               desc: "Generate RSpec file"

  def check_for_naming_conflict
    underscored_name = name.underscore

    # Use destination_root if available (for testing), otherwise Rails.root
    root = respond_to?(:destination_root) ? Pathname.new(destination_root) : Rails.root
    shifts_dir = root.join("lib/data_shifts")
    return unless shifts_dir.exist?

    # Look for any existing file that would create the same rake task name
    conflicting_file = Dir.glob(shifts_dir.join("*_#{underscored_name}.rb")).first
    return unless conflicting_file

    raise Thor::Error, <<~ERROR
      A data shift with task name '#{underscored_name}' already exists:
        #{conflicting_file}

      Rake task names must be unique. Please choose a different name.
    ERROR
  end

  def create_shift_file
    underscored_name = name.underscore
    @timestamp = Time.current.strftime("%Y%m%d%H%M%S")
    @class_name = underscored_name.camelize
    model_name_raw = options[:model].to_s.strip
    @model_name = model_name_raw.present? ? model_name_raw.underscore.singularize.camelize : nil

    collection_body = if @model_name.present?
                        "#{@model_name}.all"
                      else
                        "# Model.where(foo: nil)"
                      end

    record_arg = @model_name.present? ? @model_name.underscore : "record"

    create_file "lib/data_shifts/#{@timestamp}_#{underscored_name}.rb", <<~RUBY
      # frozen_string_literal: true

      #   rake data:shift:#{underscored_name}          # Dry run (default)
      #   COMMIT=1 rake data:shift:#{underscored_name} # Apply changes

      module DataShifts
        class #{@class_name} < DataShifter::Shift
          description "TODO: Describe this shift"

          transaction true # or false or :per_record

          def collection
            #{collection_body}
          end

          def process_record(#{record_arg})
            # #{record_arg}.update!(...)
          end
        end
      end
    RUBY
  end

  def create_spec_file
    return unless options[:spec]
    return unless rspec_enabled?

    underscored_name = name.underscore
    record_arg = @model_name.present? ? @model_name.underscore : "record"

    model_for_change = @model_name.present? ? @model_name : "Model"
    create_file "spec/lib/data_shifts/#{underscored_name}_spec.rb", <<~RUBY
      # frozen_string_literal: true

      require "rails_helper"
      require "data_shifter/spec_helper"

      RSpec.describe DataShifts::#{@class_name} do
        include DataShifter::SpecHelper

        before { allow($stdout).to receive(:puts) }

        # Set up test records as needed
        # let(:#{record_arg}) { create(:#{record_arg}) }

        describe "dry run" do
          it "does not persist changes" do
            expect do
              result = run_data_shift(described_class, dry_run: true)
              expect(result).to be_ok
            end.not_to change(#{model_for_change}, :count)
          end
        end

        describe "commit" do
          it "applies changes" do
            expect do
              result = run_data_shift(described_class, commit: true)
              expect(result).to be_ok
            end.to change(#{model_for_change}, :count)
          end
        end
      end
    RUBY
  end

  private

  def rspec_enabled?
    # Check if rspec-rails is available and configured as the test framework
    return false unless defined?(Rails)

    # Check Rails generator configuration
    test_framework = Rails.configuration.generators.options.dig(:rails, :test_framework)
    return test_framework == :rspec if test_framework

    # Fall back to checking if rspec-rails is loaded
    defined?(RSpec::Rails)
  end
end
