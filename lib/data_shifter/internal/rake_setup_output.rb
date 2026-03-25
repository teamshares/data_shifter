# frozen_string_literal: true

require "pathname"

require_relative "colors"

module DataShifter
  module Internal
    # Formatted stderr output when a rake data:shift task fails before the shift summary (load, constantize, etc.).
    module RakeSetupOutput
      extend self

      BACKTRACE_LIMIT = 12
      DIVIDER = "=" * 60
      SEPARATOR = "-" * 60

      def print_failure(io:, exception:, file_path:, task_name:)
        lines = filtered_backtrace(exception, file_path)
        display = relative_display_path(file_path)

        io.puts ""
        io.puts Colors.red(DIVIDER, io:)
        io.puts Colors.error("DATA SHIFT SETUP FAILED", io:)
        io.puts Colors.dim(SEPARATOR, io:)
        io.puts "Rake task:   data:shift:#{task_name}"
        io.puts "File:        #{display}"
        io.puts Colors.dim(SEPARATOR, io:)
        io.puts Colors.error("#{exception.class}: #{exception.message}", io:)
        if lines.any?
          io.puts ""
          io.puts Colors.dim("Backtrace:", io:)
          lines.each { |line| io.puts Colors.dim("  #{line}", io:) }
        end
        io.puts Colors.red(DIVIDER, io:)
        io.puts ""
      end

      private

      def relative_display_path(file_path)
        if defined?(Rails) && Rails.root
          Pathname(file_path).relative_path_from(Rails.root).to_s
        else
          file_path.to_s
        end
      rescue ArgumentError
        file_path.to_s
      end

      def filtered_backtrace(exception, file_path)
        raw = exception.backtrace || []
        cleaned =
          if defined?(Rails) && Rails.respond_to?(:backtrace_cleaner) && Rails.backtrace_cleaner
            Rails.backtrace_cleaner.clean(raw)
          else
            raw
          end
        lines = cleaned.map(&:to_s).reject(&:empty?).first(BACKTRACE_LIMIT)
        return lines if lines.any?

        needle = file_path.to_s
        lines = raw.select { |ln| ln.start_with?(needle) || ln.include?("/data_shifts/") }.first(BACKTRACE_LIMIT)
        return lines if lines.any?

        raw.first(BACKTRACE_LIMIT)
      end
    end
  end
end
