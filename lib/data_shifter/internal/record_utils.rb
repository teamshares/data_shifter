# frozen_string_literal: true

module DataShifter
  module Internal
    # Record-related utility functions.
    # All methods are stateless module functions.
    module RecordUtils
      module_function

      # Generate a human-readable identifier for a record.
      #
      # @param record [Object] the record to identify
      # @return [String] identifier string
      def identifier(record)
        return "#{record.class.name}##{record.id}" if record.respond_to?(:id)

        record.inspect.truncate(80)
      end

      # Derive a default label from an array of items.
      #
      # @param items [Array] collection of items
      # @return [String] pluralized model name or "records"
      def default_label(items)
        sample = items.first
        sample.respond_to?(:model_name) ? sample.model_name.human.pluralize : "records"
      end

      # Derive a default label from an ActiveRecord::Relation.
      #
      # @param relation [ActiveRecord::Relation] the relation
      # @return [String] pluralized model name or "records"
      def default_label_for_relation(relation)
        relation.respond_to?(:model) ? relation.model.model_name.human.pluralize : "records"
      end
    end
  end
end
