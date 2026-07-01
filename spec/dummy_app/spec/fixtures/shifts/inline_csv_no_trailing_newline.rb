# frozen_string_literal: true

module DataShifts
  # Fixture: __END__ is the literal last bytes of the file, no trailing
  # newline and no data after it.
  class InlineCsvNoTrailingNewline < DataShifter::Shift
  end
end

__END__