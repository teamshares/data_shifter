# frozen_string_literal: true

RSpec.describe DataShifter::Internal::Env do
  describe ".status_interval_seconds" do
    around do |example|
      original_env = ENV["STATUS_INTERVAL"]
      original_config = DataShifter.config.status_interval_seconds
      example.run
      ENV["STATUS_INTERVAL"] = original_env
      DataShifter.config.status_interval_seconds = original_config
    end

    context "when ENV STATUS_INTERVAL is set" do
      before { ENV["STATUS_INTERVAL"] = "60" }

      it "returns the ENV value" do
        expect(described_class.status_interval_seconds).to eq(60)
      end

      it "ignores config value" do
        DataShifter.config.status_interval_seconds = 30
        expect(described_class.status_interval_seconds).to eq(60)
      end
    end

    context "when ENV STATUS_INTERVAL is not set" do
      before { ENV.delete("STATUS_INTERVAL") }

      it "returns config value when set" do
        DataShifter.config.status_interval_seconds = 45
        expect(described_class.status_interval_seconds).to eq(45)
      end

      it "returns nil when config is nil" do
        DataShifter.config.status_interval_seconds = nil
        expect(described_class.status_interval_seconds).to be_nil
      end
    end

    context "when ENV STATUS_INTERVAL is invalid" do
      before { ENV["STATUS_INTERVAL"] = "not_a_number" }

      it "returns config value as fallback" do
        DataShifter.config.status_interval_seconds = 20
        expect(described_class.status_interval_seconds).to eq(20)
      end
    end
  end
end
