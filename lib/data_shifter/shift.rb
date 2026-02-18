# frozen_string_literal: true

require "axn"
require "active_support/isolated_execution_state"
require_relative "internal/env"
require_relative "internal/output"
require_relative "internal/signal_handler"
require_relative "internal/record_utils"
require_relative "internal/progress_bar"

# Base class for data shifts. Dry-run by default, progress bars, transaction modes, consistent summaries.
#
# Usage:
#
#   # lib/data_shifts/20260201120000_backfill_foo.rb
#   module DataShifts
#     class BackfillFoo < DataShifter::Shift
#       description "Backfill foo on bars"
#
#       def collection
#         Bar.where(foo: nil)
#       end
#
#       def process_record(bar)
#         bar.update!(foo: computed_value(bar))
#       end
#     end
#   end
#
# Running:
#   - `rake data:shift:backfill_foo` (dry run by default)
#   - `COMMIT=1 rake data:shift:backfill_foo` (apply changes)
#   - Or call directly: `MyShift.call(dry_run: false)` (Axn semantics) - but note default location not auto-loaded
#
# Transaction modes (set at class level with `transaction`):
#   - `transaction :single` (default): one transaction for the whole run (all-or-nothing).
#   - `transaction :per_record`: each record in its own transaction.
#   - `transaction false`: no automatic transactions; guard writes with `return if dry_run?`.
#
# Dry run: In `:single` and `:per_record`, dry_run rolls back DB changes automatically.
# Non-DB side effects are not rolled back; guard with `return if dry_run?` / `return unless dry_run?`.
#
# Fixed list of IDs (fail fast): Use find_exactly!(Model, [id1, id2, ...]) in `collection`.
# Large collections: Return an ActiveRecord::Relation and iteration uses `find_each`.
#
module DataShifter
  class Shift
    include Axn

    expects :dry_run, type: :boolean, default: true

    log_calls false if respond_to?(:log_calls)

    around :_with_transaction_for_dry_run
    before :_reset_tracking
    on_success :_print_summary
    on_error :_print_summary

    class_attribute :_transaction_mode, default: :single
    class_attribute :_progress_enabled, default: true
    class_attribute :_description, default: nil
    class_attribute :_task_name, default: nil
    class_attribute :_throttle_interval, default: nil

    class << self
      def description(text = nil)
        if text.nil?
          _description
        else
          self._description = text.to_s.presence
        end
      end

      def task_name(value = nil)
        if value.nil?
          _task_name
        else
          self._task_name = value.to_s.presence
        end
      end

      def transaction(mode)
        case mode
        when :per_record
          self._transaction_mode = :per_record
        when :none, false
          self._transaction_mode = :none
        when :single, true
          self._transaction_mode = :single
        else
          raise ArgumentError, "Invalid transaction mode: #{mode.inspect}. Expected :single, :per_record, :none, true, or false."
        end
      end

      def progress(enabled = nil)
        if enabled.nil?
          _progress_enabled
        else
          self._progress_enabled = !!enabled
        end
      end

      def throttle(interval)
        self._throttle_interval = interval
      end

      def run!
        dry_run = Internal::Env.dry_run?
        result = call(dry_run:)
        raise result.exception if result.exception
        raise StandardError, result.error unless result.ok?
      end
    end

    # --- Public API (intentionally exposed to subclasses) ---

    def call
      _for_each_record_in(collection) { |record| process_record(record) }
    end

    def find_exactly!(model, ids)
      ids = Array(ids).compact.uniq
      return model.none if ids.empty?

      records_by_id = model.where(id: ids).index_by(&:id)
      missing = ids.reject { |id| records_by_id.key?(id) }
      raise "Expected #{model.name} with ids #{ids.inspect}, but missing: #{missing.inspect}" if missing.any?

      ids.map { |id| records_by_id[id] }
    end

    def dry_run? = dry_run

    def skip!(reason = nil)
      @stats[:skipped] += 1
      @stats[:succeeded] -= 1
      log "  SKIP: #{reason}" if reason
    end

    def log(message)
      puts message
    end

    private

    # --- Axn lifecycle hooks ---

    def _with_transaction_for_dry_run(chain)
      if _transaction_mode == :none
        chain.call
        return
      end

      if _transaction_mode == :single
        ActiveRecord::Base.transaction do
          chain.call
          raise ActiveRecord::Rollback if dry_run?
        end
        return
      end

      if dry_run?
        ActiveRecord::Base.transaction do
          chain.call
          raise ActiveRecord::Rollback
        end
      else
        chain.call
      end
    end

    def _reset_tracking
      @stats = { processed: 0, succeeded: 0, failed: 0, skipped: 0 }
      @errors = []
      @start_time = Time.current
      @last_status_print = @start_time
      @_data_shift_interrupted = false
      @_last_successful_id = nil
    end

    def _print_summary
      Internal::Output.print_summary(
        io: $stdout,
        stats: @stats,
        errors: @errors,
        start_time: @start_time,
        dry_run: dry_run?,
        transaction_mode: _transaction_mode,
        interrupted: @_data_shift_interrupted,
        task_name: self.class.task_name,
        last_successful_id: @_last_successful_id,
      )
    end

    # --- Override points ---

    def collection
      raise NotImplementedError, "#{self.class.name}: override `collection`"
    end

    def process_record(_record)
      raise NotImplementedError, "#{self.class.name}: override `process_record`"
    end

    # --- Record iteration ---

    def _print_progress
      Internal::Output.print_progress(
        io: $stdout,
        stats: @stats,
        errors: @errors,
        start_time: @start_time,
        status_interval: Internal::Env.status_interval_seconds,
      )
    end

    def _for_each_record_in(records, label: nil, &)
      _reset_tracking
      ActiveSupport::IsolatedExecutionState[:_data_shifter_current_run] = self
      status_proc = proc { ActiveSupport::IsolatedExecutionState[:_data_shifter_current_run]&.send(:_print_progress) }
      prev_handlers = Internal::SignalHandler.install_status_traps(status_proc)
      begin
        _each_record_impl(records, label:, &)
      rescue Interrupt
        _handle_interrupt
      ensure
        ActiveSupport::IsolatedExecutionState.delete(:_data_shifter_current_run)
        Internal::SignalHandler.restore_status_traps(prev_handlers)
      end
    end

    def _each_record_impl(records, label: nil, &)
      records = _apply_continue_from(records)

      if records.respond_to?(:find_each)
        total = records.count
        @label = label || Internal::RecordUtils.default_label_for_relation(records)
        _print_header(total)
        enum = records
      else
        items = records.respond_to?(:to_a) ? records.to_a : Array(records)
        total = items.size
        @label = label || Internal::RecordUtils.default_label(items)
        _print_header(total)
        enum = items
      end

      case _transaction_mode
      when :single
        _run_in_single_transaction(enum, total, &)
      when :per_record
        _run_per_record(enum, total, &)
      when :none
        _run_without_transaction(enum, total, &)
      end

      fail! "#{@stats[:failed]} record(s) failed" if @errors.any?
    end

    def _apply_continue_from(records)
      continue_from = Internal::Env.continue_from_id
      return records if continue_from.nil?

      unless records.respond_to?(:find_each)
        raise ArgumentError,
              "CONTINUE_FROM is only supported for ActiveRecord::Relation collections. " \
              "Array-based collections (e.g. from find_exactly!) cannot be resumed."
      end

      primary_key = records.model.primary_key
      log "[CONTINUE_FROM] Resuming from #{primary_key} > #{continue_from}"
      records.where("#{records.model.quoted_table_name}.#{primary_key} > ?", continue_from)
    end

    # --- Transaction execution strategies ---

    def _run_in_single_transaction(enum, total, &block)
      ActiveRecord::Base.transaction do
        _iterate(enum, total, &block)
        if dry_run?
          log "\nDry run complete — rolling back all changes."
          raise ActiveRecord::Rollback
        end
      end
    rescue StandardError => e
      return if @errors.any?

      @stats[:failed] += 1
      @errors << { record: "transaction", error: e.message, backtrace: e.backtrace&.first(3) }
    end

    def _run_per_record(enum, total, &)
      _iterate(enum, total) do |record|
        if dry_run?
          yield record
        else
          ActiveRecord::Base.transaction { yield record }
        end
      end
    end

    def _run_without_transaction(enum, total, &)
      _iterate(enum, total, &)
    end

    def _iterate(enum, total)
      bar = Internal::ProgressBar.create(total:, dry_run: dry_run?, enabled: _progress_enabled)
      if enum.respond_to?(:find_each)
        enum.find_each do |record|
          _process_one(record) { yield record }
          bar&.increment
          sleep(_throttle_interval) if _throttle_interval
        end
      else
        enum.each do |record|
          _process_one(record) { yield record }
          bar&.increment
          sleep(_throttle_interval) if _throttle_interval
        end
      end
    end

    def _process_one(record)
      @stats[:processed] += 1
      yield
      @stats[:succeeded] += 1
      @_last_successful_id = record.id if record.respond_to?(:id)
    rescue StandardError => e
      @stats[:failed] += 1
      identifier = Internal::RecordUtils.identifier(record)
      @errors << { record: identifier, error: e.message, backtrace: e.backtrace&.first(3) }
      log "ERROR #{identifier}: #{e.message}"

      raise if _transaction_mode == :single
    ensure
      _maybe_print_interval_status
    end

    def _maybe_print_interval_status
      interval = Internal::Env.status_interval_seconds
      return unless interval&.positive?
      return unless @start_time && (Time.current - @last_status_print) >= interval

      @last_status_print = Time.current
      _print_progress
    end

    # --- Output helpers ---

    def _print_header(total)
      Internal::Output.print_header(
        io: $stdout,
        shift_class: self.class,
        total:,
        label: @label,
        dry_run: dry_run?,
        transaction_mode: _transaction_mode,
        status_interval: Internal::Env.status_interval_seconds,
      )
    end

    def _handle_interrupt
      @_data_shift_interrupted = true
      log "\n\n*** Interrupted by user (Ctrl+C) ***"

      # Print summary now since on_error may not fire for Interrupt (SignalException)
      _print_summary

      # Re-raise to trigger transaction rollback in the wrapping transaction block
      raise Interrupt
    end
  end
end
