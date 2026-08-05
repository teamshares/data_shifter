# frozen_string_literal: true

RSpec.describe DataShifter::Internal::Env do
  describe ".dry_run?" do
    around do |example|
      original = ENV.slice("COMMIT", "DRY_RUN")
      ENV.delete("COMMIT")
      ENV.delete("DRY_RUN")
      example.run
      ENV.delete("COMMIT")
      ENV.delete("DRY_RUN")
      ENV.update(original)
    end

    it "defaults to a dry run when nothing is set" do
      expect(described_class.dry_run?).to be true
    end

    it "treats DRY_RUN=1 as a dry run (truthy = dry, not commit)" do
      ENV["DRY_RUN"] = "1"
      expect(described_class.dry_run?).to be true
    end

    it "treats DRY_RUN=true as a dry run" do
      ENV["DRY_RUN"] = "true"
      expect(described_class.dry_run?).to be true
    end

    it "treats DRY_RUN=false as a commit" do
      ENV["DRY_RUN"] = "false"
      expect(described_class.dry_run?).to be false
    end

    it "treats DRY_RUN=0 as a commit" do
      ENV["DRY_RUN"] = "0"
      expect(described_class.dry_run?).to be false
    end

    it "treats blank DRY_RUN as a dry run" do
      ENV["DRY_RUN"] = ""
      expect(described_class.dry_run?).to be true
    end

    it "commits on COMMIT=1" do
      ENV["COMMIT"] = "1"
      expect(described_class.dry_run?).to be false
    end

    it "dry-runs on COMMIT=false" do
      ENV["COMMIT"] = "false"
      expect(described_class.dry_run?).to be true
    end

    it "lets COMMIT win over DRY_RUN" do
      ENV["COMMIT"] = "1"
      ENV["DRY_RUN"] = "true"
      expect(described_class.dry_run?).to be false
    end

    it "raises on an unrecognized COMMIT rather than silently dry-running" do
      ENV["COMMIT"] = "garbage"
      expect { described_class.dry_run? }.to raise_error(ArgumentError, /COMMIT="garbage" is not a boolean/)
    end

    it "raises on an unrecognized DRY_RUN" do
      ENV["DRY_RUN"] = "maybe"
      expect { described_class.dry_run? }.to raise_error(ArgumentError, /DRY_RUN="maybe" is not a boolean/)
    end

    it "is case- and whitespace-insensitive" do
      ENV["DRY_RUN"] = "  FALSE  "
      expect(described_class.dry_run?).to be false
    end
  end

  describe ".boolean!" do
    around do |example|
      original = ENV.slice("PROBE")
      example.run
      ENV.delete("PROBE")
      ENV.update(original)
    end

    %w[1 true t yes y on TRUE On  YES].each do |v|
      it "reads #{v.inspect} as true" do
        ENV["PROBE"] = v
        expect(described_class.boolean!("PROBE")).to be true
      end
    end

    %w[0 false f no n off FALSE Off  NO].each do |v|
      it "reads #{v.inspect} as false" do
        ENV["PROBE"] = v
        expect(described_class.boolean!("PROBE")).to be false
      end
    end

    it "raises with a helpful list on anything unrecognized" do
      ENV["PROBE"] = "nope"
      expect { described_class.boolean!("PROBE") }
        .to raise_error(ArgumentError, /PROBE="nope" is not a boolean — use one of: 1, true/)
    end
  end

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
