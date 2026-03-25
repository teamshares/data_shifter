# frozen_string_literal: true

module DataShifts
  class RakeSpecRuntimeFail < DataShifter::Shift
    description "Rake spec: runtime failure fixture"

    task do
      raise "RAKE_SPEC_RUNTIME_BOOM"
    end
  end
end
