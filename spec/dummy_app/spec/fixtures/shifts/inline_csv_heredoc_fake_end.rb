# frozen_string_literal: true

module DataShifts
  # Fixture: a heredoc contains a line that reads exactly __END__ at column 0,
  # before the real __END__ marker. A naive text-based split (rather than a
  # real Ruby tokenizer) would incorrectly split at the heredoc-embedded line.
  class InlineCsvHeredocFakeEnd < DataShifter::Shift
    EXAMPLE_DOC = <<~DOC.freeze
      Example shift file:
__END__
      id,name
      1,Alice
    DOC
  end
end

__END__
id,name
1,Real
