# frozen_string_literal: true

require "open3"

RSpec.describe "data:shift rake tasks (railtie)" do
  let(:dummy_root) { File.expand_path("../..", __dir__) }

  let(:env) do
    {
      "BUNDLE_GEMFILE" => File.join(dummy_root, "Gemfile"),
      "RAILS_ENV" => "test",
      "RACK_ENV" => "test",
    }
  end

  def rake(task_name)
    Open3.capture3(
      env,
      "bundle", "exec", "rake", task_name,
      chdir: dummy_root,
    )
  end

  describe "data:shift:rake_spec_runtime_fail" do
    it "exits 1, prints the error on stdout (summary), and does not warn duplicate on stderr" do
      stdout, stderr, status = rake("data:shift:rake_spec_runtime_fail")

      expect(status.exitstatus).to eq(1)
      expect(stdout).to include("RAKE_SPEC_RUNTIME_BOOM")
      expect(stderr).not_to include("RAKE_SPEC_RUNTIME_BOOM")
    end
  end

  describe "data:shift:rake_spec_load_fail" do
    it "exits 1 and prints a concise load failure report on stderr" do
      stdout, stderr, status = rake("data:shift:rake_spec_load_fail")

      expect(status.exitstatus).to eq(1)
      expect(stdout).to be_blank
      expect(stderr).to include("DATA SHIFT SETUP FAILED")
      expect(stderr).to include("data:shift:rake_spec_load_fail")
      expect(stderr).to include("lib/data_shifts/00000002_rake_spec_load_fail.rb")
      expect(stderr).to include("RuntimeError: RAKE_SPEC_LOAD_BOOM")
      expect(stderr).to include("Backtrace:")
      expect(stderr.lines.count { |l| l.include?("rake-") }).to eq(0)
    end
  end
end
