# frozen_string_literal: true

RSpec.describe "DataShifter configuration" do
  around do |example|
    DataShifter.reset_config!
    example.run
    DataShifter.reset_config!
  end

  describe "defaults" do
    subject(:config) { DataShifter.config }

    it { expect(config.allow_external_requests).to eq([]) }
    it { expect(config.allow_loopback_requests).to be true }
    it { expect(config.suppress_repeated_logs).to be true }
    it { expect(config.repeated_log_cap).to eq(1000) }
    it { expect(config.progress_enabled).to be true }
    it { expect(config.status_interval_seconds).to be_nil }
  end

  describe "DataShifter.config" do
    it "returns the same instance" do
      expect(DataShifter.config).to be(DataShifter.config)
    end
  end

  describe "predicates" do
    it "exposes a boolean predicate for any setting" do
      expect(DataShifter.config.progress_enabled?).to be true
      DataShifter.config.progress_enabled = false
      expect(DataShifter.config.progress_enabled?).to be false
    end
  end

  describe "DataShifter.configure" do
    it "yields the config for block configuration" do
      DataShifter.configure do |config|
        config.allow_external_requests = ["example.com"]
        config.allow_loopback_requests = false
        config.suppress_repeated_logs = false
        config.repeated_log_cap = 500
        config.progress_enabled = false
        config.status_interval_seconds = 30
      end

      expect(DataShifter.config.allow_external_requests).to eq(["example.com"])
      expect(DataShifter.config.allow_loopback_requests).to be false
      expect(DataShifter.config.suppress_repeated_logs).to be false
      expect(DataShifter.config.repeated_log_cap).to eq(500)
      expect(DataShifter.config.progress_enabled).to be false
      expect(DataShifter.config.status_interval_seconds).to eq(30)
    end
  end

  describe "DataShifter.reset_config!" do
    it "discards assigned values" do
      DataShifter.config.progress_enabled = false
      expect(DataShifter.config.progress_enabled).to be false

      DataShifter.reset_config!
      expect(DataShifter.config.progress_enabled).to be true
    end
  end
end
