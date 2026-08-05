# frozen_string_literal: true

module DataShifts
  # Fixture: exercises inline_csv as a collection source. Defined in a real
  # file so Object.const_source_location can resolve the __END__ data.
  class InlineCsvBasic < DataShifter::Shift
    def self.seen
      @seen ||= []
    end

    def self.reset!
      @seen = []
    end

    def collection
      inline_csv
    end

    def process_record(row)
      self.class.seen << row.to_h
    end
  end
end

__END__
id,name
1,Alice
2,Bob
