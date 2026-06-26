# frozen_string_literal: true

module DataShifts
  # Fixture: no __END__ data section, to exercise the error path.
  class InlineCsvNoEnd < DataShifter::Shift
  end
end
