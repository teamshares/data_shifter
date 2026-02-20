# frozen_string_literal: true

RSpec.describe DataShifter::Configuration do
  describe "defaults" do
    subject(:config) { described_class.new }

    it { expect(config.allow_external_requests).to eq([]) }
    it { expect(config.suppress_repeated_logs).to be true }
    it { expect(config.repeated_log_cap).to eq(1000) }
    it { expect(config.progress_enabled).to be true }
    it { expect(config.status_interval_seconds).to be_nil }
  end

  describe "DataShifter.config" do
    it "returns the same instance" do
      expect(DataShifter.config).to be(DataShifter.config)
    end

    it "returns a Configuration instance" do
      expect(DataShifter.config).to be_a(described_class)
    end
  end

  describe "DataShifter.configure" do
    around do |example|
      original_config = DataShifter.instance_variable_get(:@config)
      DataShifter.instance_variable_set(:@config, nil)
      example.run
      DataShifter.instance_variable_set(:@config, original_config)
    end

    it "yields the config for block configuration" do
      DataShifter.configure do |config|
        config.allow_external_requests = ["example.com"]
        config.suppress_repeated_logs = false
        config.repeated_log_cap = 500
        config.progress_enabled = false
        config.status_interval_seconds = 30
      end

      expect(DataShifter.config.allow_external_requests).to eq(["example.com"])
      expect(DataShifter.config.suppress_repeated_logs).to be false
      expect(DataShifter.config.repeated_log_cap).to eq(500)
      expect(DataShifter.config.progress_enabled).to be false
      expect(DataShifter.config.status_interval_seconds).to eq(30)
    end
  end
end
