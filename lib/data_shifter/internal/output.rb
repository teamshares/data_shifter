# frozen_string_literal: true

module DataShifter
  module Internal
    # Output formatting utilities for data shift runs.
    # All methods are stateless module functions that accept IO and context parameters.
    module Output
      TRANSACTION_MODE_LABELS = {
        single: "single (all-or-nothing)",
        per_record: "per-record",
        none: "none",
      }.freeze

      module_function

      def print_header(io:, shift_class:, total:, label:, dry_run:, transaction_mode:, status_interval:)
        io.puts ""
        io.puts "=" * 60
        io.puts shift_class.name || "DataShifter::Shift (anonymous)"
        io.puts "\"#{shift_class.description}\"" if shift_class.description.present?
        io.puts "-" * 60
        io.puts "Mode:        #{dry_run ? "DRY RUN (no changes will be persisted)" : "LIVE"}"
        io.puts "Records:     #{total} #{label}"
        io.puts "Transaction: #{TRANSACTION_MODE_LABELS[transaction_mode]}"

        status_line = build_status_line(status_interval)
        io.puts "Status:      #{status_line} for live progress (no abort)" if status_line

        io.puts "=" * 60
        io.puts ""
      end

      def print_summary(io:, stats:, errors:, start_time:, dry_run:, transaction_mode:, interrupted:, task_name:, last_successful_id:)
        return unless start_time

        elapsed = (Time.current - start_time).round(1)
        io.puts ""
        io.puts "=" * 60
        io.puts summary_title(dry_run:, interrupted:)
        io.puts "-" * 60
        io.puts "Duration:    #{elapsed}s"
        io.puts "Processed:   #{stats[:processed]}"
        io.puts "Succeeded:   #{stats[:succeeded]}"
        io.puts "Failed:      #{stats[:failed]}"
        io.puts "Skipped:     #{stats[:skipped]}"

        print_errors(io:, errors:) if errors.any?
        print_interrupt_warning(io:, transaction_mode:, dry_run:) if interrupted
        print_dry_run_instructions(io:, task_name:) if dry_run && !interrupted
        print_continue_from_hint(io:, task_name:, last_successful_id:, dry_run:, transaction_mode:, errors:)

        io.puts "=" * 60
      end

      def print_progress(io:, stats:, errors:, start_time:, status_interval:)
        return unless start_time

        elapsed = (Time.current - start_time).round(1)
        io.puts ""
        io.puts "=" * 60

        trigger = if status_interval
                    "every #{status_interval}s (STATUS_INTERVAL)"
                  elsif Signal.list.key?("INFO")
                    "Ctrl+T"
                  else
                    "SIGUSR1"
                  end

        io.puts "STATUS (still running) — triggered by #{trigger}"
        io.puts "-" * 60
        io.puts "Duration:    #{elapsed}s"
        io.puts "Processed:   #{stats[:processed]}"
        io.puts "Succeeded:   #{stats[:succeeded]}"
        io.puts "Failed:      #{stats[:failed]}"
        io.puts "Skipped:     #{stats[:skipped]}"

        print_errors(io:, errors:) if errors.any?

        io.puts "=" * 60
        io.puts ""
      end

      def print_errors(io:, errors:)
        io.puts ""
        io.puts "ERRORS:"
        errors.each do |err|
          io.puts "  #{err[:record]}: #{err[:error]}"
          err[:backtrace]&.each { |line| io.puts "    #{line}" }
        end
      end

      def summary_title(dry_run:, interrupted:)
        base = dry_run ? "SUMMARY (DRY RUN)" : "SUMMARY"
        interrupted ? "#{base} - INTERRUPTED" : base
      end

      def print_interrupt_warning(io:, transaction_mode:, dry_run:)
        io.puts ""
        if transaction_mode == :none
          io.puts "[!] INTERRUPTED: `transaction false` mode was active."
          io.puts "    Some DB changes may have been applied before interruption."
          io.puts "    Non-DB side effects (API calls, emails, etc.) are not rolled back."
          io.puts "    Review the database state before re-running."
        elsif dry_run
          io.puts "[!] INTERRUPTED: All DB changes have been rolled back (dry run)."
          io.puts "    Non-DB side effects (API calls, emails, etc.) are not rolled back."
        else
          io.puts "[!] INTERRUPTED: DB transaction has been rolled back."
          io.puts "    No DB changes were persisted."
          io.puts "    Non-DB side effects (API calls, emails, etc.) are not rolled back."
        end
      end

      def print_dry_run_instructions(io:, task_name:)
        io.puts ""
        io.puts "[!] No changes were saved."
        return unless task_name.present?

        io.puts "To apply these changes, run:"
        io.puts "    COMMIT=1 rake data:shift:#{task_name}"
      end

      def print_continue_from_hint(io:, task_name:, last_successful_id:, dry_run:, transaction_mode:, errors:)
        return if dry_run
        return unless transaction_mode == :none
        return if errors.empty?
        return unless last_successful_id
        return unless task_name.present?

        io.puts ""
        io.puts "To resume from the last successful record:"
        io.puts "    CONTINUE_FROM=#{last_successful_id} COMMIT=1 rake data:shift:#{task_name}"
      end

      def build_status_line(status_interval)
        status_tips = []
        status_tips << "Ctrl+T" if Signal.list.key?("INFO")
        status_tips << "kill -USR1 #{Process.pid}" if Signal.list.key?("USR1")

        if status_interval
          interval_msg = "STATUS_INTERVAL is set to #{status_interval}s."
          status_tips.any? ? "#{interval_msg} Or: #{status_tips.join(", ")}" : interval_msg
        elsif status_tips.any?
          status_tips.join(" or ")
        end
      end
    end
  end
end
