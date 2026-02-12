# frozen_string_literal: true

require "rails/railtie"

module DataShifter
  class Railtie < Rails::Railtie
    # Extract description DSL from shift file without loading it.
    # Supports: description "text", description 'text', description %(text), description <<~HEREDOC
    def self.extract_description(file_path)
      content = File.read(file_path)

      # Single/double quoted strings: description "text" or description 'text'
      if (match = content.match(/^\s*description\s+["'](.+?)["']/))
        return match[1]
      end

      # Percent strings: description %(text) or description %Q(text)
      if (match = content.match(/^\s*description\s+%Q?\((.+?)\)/m))
        return match[1].gsub(/\s+/, " ").strip
      end

      # Heredoc: description <<~HEREDOC or <<-HEREDOC or <<HEREDOC
      if (match = content.match(/^\s*description\s+<<[~-]?(\w+)\s*\n(.*?)\n\s*\1/m))
        return match[2].gsub(/\s+/, " ").strip
      end

      nil
    end

    generators do
      require "generators/data_shift_generator"
    end

    # Zeitwerk infers constants from filenames. Timestamped shift files
    # (e.g. 20260211_backfill_users.rb) would map to an invalid constant
    # starting with a digit. Tell Zeitwerk to ignore the shifts directory
    # so we can load them manually with require.
    initializer "data_shifter.ignore_shifts_dir" do
      shifts_dir = Rails.root.join("lib/data_shifts")
      Rails.autoloaders.main.ignore(shifts_dir) if shifts_dir.exist?
    end

    rake_tasks do
      namespace :data do
        namespace :shift do
          shifts_dir = Rails.root.join("lib/data_shifts")
          next unless shifts_dir.exist?

          Dir.glob(shifts_dir.join("*.rb")).each do |file_path|
            # Infer task name from filename: "20260211_backfill_users.rb" -> "backfill_users"
            filename = File.basename(file_path, ".rb")
            task_name = filename.sub(/\A\d+_/, "")
            class_name = task_name.camelize

            # Extract description from file without loading it (for rake -T)
            task_desc = Railtie.extract_description(file_path) || "Run data shift: #{class_name}"

            # Define the rake task lazily (only loads class when task runs)
            desc task_desc
            task task_name => :environment do
              require file_path

              # Resolve the constant inside the DataShifts namespace
              klass = "DataShifts::#{class_name}".constantize
              klass.task_name(task_name)
              klass.run!
            rescue Interrupt
              exit(130)
            rescue StandardError
              exit(1)
            end
          end
        end
      end
    end
  end
end
