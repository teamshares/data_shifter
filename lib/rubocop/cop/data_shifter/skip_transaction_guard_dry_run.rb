# frozen_string_literal: true

module RuboCop
  module Cop
    module DataShifter
      # In data shift files, `transaction false` disables automatic transaction
      # and rollback. DB writes (and side effects) are not rolled back on dry run, so
      # the shift must guard them with `return if dry_run?` or `return unless dry_run?`.
      #
      # @example
      #   # bad
      #   class BackfillUsers < DataShifter::Shift
      #     transaction false
      #     def process_record(record)
      #       record.update!(foo: 1)
      #     end
      #   end
      #
      #   # good
      #   class BackfillUsers < DataShifter::Shift
      #     transaction false
      #     def process_record(record)
      #       return if dry_run?
      #       record.update!(foo: 1)
      #     end
      #   end
      class SkipTransactionGuardDryRun < Base
        MSG = "Data shifts using `transaction false` must guard writes/side effects with " \
              "`return if dry_run?` or `return unless dry_run?`."

        def_node_matcher :skip_transaction_call?, <<~PATTERN
          (send _ :transaction {(sym :none) (false)})
        PATTERN

        def on_send(node)
          return unless skip_transaction_call?(node)
          return if file_contains_dry_run_guard?

          add_offense(node, message: MSG)
        end

        private

        def file_contains_dry_run_guard?
          return true unless processed_source.ast

          processed_source.ast.each_node(:send) do |send_node|
            return true if send_node.method?(:dry_run?)
          end
          false
        end
      end
    end
  end
end
