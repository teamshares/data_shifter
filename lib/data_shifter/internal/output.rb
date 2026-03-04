# frozen_string_literal: true

require_relative "colors"

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

      SKIP_REASONS_DISPLAY_LIMIT = 10
      DIVIDER = "=" * 60
      SEPARATOR = "-" * 60

      module_function

      # --- Public header methods ---

      def print_header(io:, shift_class:, total:, label:, dry_run:, transaction_mode:, status_interval:)
        print_header_top(io:, shift_class:, dry_run:)
        io.puts "Records:     #{total} #{label}"
        io.puts "Transaction: #{TRANSACTION_MODE_LABELS[transaction_mode]}"
        print_header_bottom(io:, status_interval:)
      end

      def print_task_header(io:, shift_class:, block_count:, dry_run:, transaction_mode:, status_interval:)
        print_header_top(io:, shift_class:, dry_run:)
        io.puts "Tasks:       #{block_count}" if block_count >= 2
        io.puts "Transaction: #{task_transaction_label(transaction_mode)}"
        print_header_bottom(io:, status_interval:)
      end

      # --- Public summary/progress methods ---

      def print_summary(io:, stats:, errors:, start_time:, dry_run:, transaction_mode:, interrupted:, task_name:, last_successful_id:, skip_reasons: {})
        return unless start_time

        has_failures = stats[:failed].positive? || interrupted

        io.puts ""
        io.puts summary_divider(has_failures:, io:)
        io.puts summary_title(dry_run:, interrupted:, has_failures:, io:)
        io.puts Colors.dim(SEPARATOR, io:)
        print_stats(io:, stats:, start_time:, skip_reasons:)

        print_errors(io:, errors:) if errors.any?
        print_interrupt_warning(io:, transaction_mode:, dry_run:) if interrupted
        print_dry_run_instructions(io:, task_name:) if dry_run && !interrupted
        print_continue_from_hint(io:, task_name:, last_successful_id:, dry_run:, transaction_mode:, errors:)

        io.puts summary_divider(has_failures:, io:)
      end

      def print_progress(io:, stats:, errors:, start_time:, status_interval:, skip_reasons: {})
        return unless start_time

        io.puts ""
        io.puts Colors.cyan(DIVIDER, io:)
        io.puts "#{Colors.cyan("STATUS (still running)", io:)} — triggered by #{status_trigger(status_interval)}"
        io.puts Colors.dim(SEPARATOR, io:)
        print_stats(io:, stats:, start_time:, skip_reasons:)

        print_errors(io:, errors:) if errors.any?

        io.puts Colors.cyan(DIVIDER, io:)
        io.puts ""
      end

      def print_errors(io:, errors:)
        io.puts ""
        io.puts Colors.error("ERRORS:", io:)
        errors.each { |err| print_single_error(io:, err:) }
      end

      # --- Private helpers ---

      def print_header_top(io:, shift_class:, dry_run:)
        io.puts ""
        io.puts Colors.dim(DIVIDER, io:)
        io.puts Colors.bold(shift_class.name || "DataShifter::Shift (anonymous)", io:)
        io.puts Colors.dim("\"#{shift_class.description}\"", io:) if shift_class.description.present?
        io.puts Colors.dim(SEPARATOR, io:)
        io.puts "Mode:        #{mode_label(dry_run:, io:)}"
      end

      def print_header_bottom(io:, status_interval:)
        status_line = build_status_line(status_interval)
        io.puts Colors.dim("Status:      #{status_line} for live progress (no abort)", io:) if status_line
        io.puts Colors.dim(DIVIDER, io:)
        io.puts ""
      end

      def print_stats(io:, stats:, start_time:, skip_reasons:)
        elapsed = (Time.current - start_time).round(1)
        io.puts "Duration:    #{elapsed}s"
        io.puts "Processed:   #{stats[:processed]}"
        io.puts "Succeeded:   #{Colors.green(stats[:succeeded].to_s, io:)}"
        io.puts "Failed:      #{Colors.red(stats[:failed].to_s, io:)}" if stats[:failed].positive?
        io.puts "Skipped:     #{Colors.yellow(stats[:skipped].to_s, io:)}" if stats[:skipped].positive?
        print_skip_reasons(io:, skip_reasons:) if skip_reasons.any?
      end

      def print_single_error(io:, err:)
        lines = err[:error].to_s.split("\n")
        io.puts "  #{Colors.red(err[:record].to_s, io:)}: #{lines.first}"
        lines.drop(1).each { |line| io.puts "    #{line}" }
        err[:backtrace]&.each { |line| io.puts Colors.dim("    #{line}", io:) }
      end

      def mode_label(dry_run:, io:)
        if dry_run
          "#{Colors.cyan("DRY RUN", io:)} (no changes will be persisted)"
        else
          Colors.warning("LIVE", io:)
        end
      end

      def task_transaction_label(mode)
        mode == :per_record ? "per-task" : TRANSACTION_MODE_LABELS[mode]
      end

      def summary_divider(has_failures:, io:)
        has_failures ? Colors.red(DIVIDER, io:) : Colors.green(DIVIDER, io:)
      end

      def summary_title(dry_run:, interrupted:, has_failures: false, io: $stdout)
        base = dry_run ? "SUMMARY (DRY RUN)" : "SUMMARY"
        title = interrupted ? "#{base} - INTERRUPTED" : base
        has_failures ? Colors.error(title, io:) : Colors.success(title, io:)
      end

      def status_trigger(status_interval)
        if status_interval
          "every #{status_interval}s (STATUS_INTERVAL)"
        elsif Signal.list.key?("INFO")
          "Ctrl+T"
        else
          "SIGUSR1"
        end
      end

      def print_interrupt_warning(io:, transaction_mode:, dry_run:)
        msg = if transaction_mode == :none
                "`transaction false` mode was active. Some DB changes may have been applied."
              elsif dry_run
                "All DB changes have been rolled back (dry run)."
              else
                "DB transaction has been rolled back. No DB changes were persisted."
              end
        io.puts ""
        io.puts "#{Colors.warning("[!] INTERRUPTED:", io:)} #{msg}"
        io.puts "    Non-DB side effects (API calls, emails, etc.) are not rolled back."
      end

      def print_dry_run_instructions(io:, task_name:)
        io.puts ""
        io.puts Colors.cyan("[!] No changes were saved.", io:)
        return unless task_name.present?

        io.puts "To apply these changes, run:"
        io.puts "    #{Colors.bold("COMMIT=1 rake data:shift:#{task_name}", io:)}"
      end

      def print_continue_from_hint(io:, task_name:, last_successful_id:, dry_run:, transaction_mode:, errors:)
        return if dry_run || transaction_mode != :none || errors.empty? || !last_successful_id || !task_name.present?

        io.puts ""
        io.puts "To resume from the last successful record:"
        io.puts "    #{Colors.bold("CONTINUE_FROM=#{last_successful_id} COMMIT=1 rake data:shift:#{task_name}", io:)}"
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

      def print_skip_reasons(io:, skip_reasons:)
        return if skip_reasons.empty?

        top = skip_reasons.sort_by { |_reason, count| -count }.first(SKIP_REASONS_DISPLAY_LIMIT)
        formatted = top.map { |reason, count| "\"#{reason}\" (#{count})" }.join(", ")
        io.puts "             #{formatted}"
      end
    end
  end
end
