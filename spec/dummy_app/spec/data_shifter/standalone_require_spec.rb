# frozen_string_literal: true

require "bundler"
require "English"

RSpec.describe "requiring data_shifter/shift standalone" do
  # Regression: Shift's `include DataShifter.overrides` depends on DataShifter
  # having been extended with Axn::Configurable (done in lib/data_shifter.rb).
  # A consumer requiring the subfile directly, without going through the
  # top-level "data_shifter" require first, must not crash.
  it "loads without requiring the top-level data_shifter file first" do
    gem_root = Gem.loaded_specs["data_shifter"].full_gem_path

    output = Bundler.with_original_env do
      Dir.chdir(gem_root) do
        `bundle exec ruby -Ilib -e 'require "data_shifter/shift"' 2>&1`
      end
    end

    expect($CHILD_STATUS).to be_success, output
  end
end
