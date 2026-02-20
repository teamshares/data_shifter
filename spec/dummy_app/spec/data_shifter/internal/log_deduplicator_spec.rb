# frozen_string_literal: true

require "logger"
require "stringio"

RSpec.describe DataShifter::Internal::LogDeduplicator do
  let(:log_output) { StringIO.new }
  let(:real_logger) { Logger.new(log_output) }
  let(:cap) { 10 }

  subject(:deduplicator) { described_class.new(real_logger, cap: cap) }

  describe "#add / severity methods" do
    it "forwards first occurrence to real logger" do
      deduplicator.info("Hello world")
      expect(log_output.string).to include("Hello world")
    end

    it "suppresses second occurrence" do
      deduplicator.info("Hello world")
      deduplicator.info("Hello world")
      expect(log_output.string.scan("Hello world").size).to eq(1)
    end

    it "increments count for repeated messages" do
      3.times { deduplicator.warn("Repeated warning") }
      expect(deduplicator.suppressed_messages.values.first[:count]).to eq(3)
    end

    it "tracks different messages separately" do
      deduplicator.info("Message A")
      deduplicator.info("Message B")
      deduplicator.info("Message A")
      expect(log_output.string).to include("Message A")
      expect(log_output.string).to include("Message B")
      expect(deduplicator.seen.size).to eq(2)
    end
  end

  describe "cap enforcement" do
    let(:cap) { 5 }

    it "clears entries with count == 1 when cap is reached" do
      5.times { |i| deduplicator.info("Unique message #{i}") }
      deduplicator.info("Message to repeat")
      deduplicator.info("Message to repeat")

      deduplicator.info("New message after cap")

      repeated = deduplicator.seen.values.select { |v| v[:count] > 1 }
      expect(repeated.size).to eq(1)
      expect(repeated.first[:message]).to include("Message to repeat")
    end

    it "keeps entries with count > 1 when clearing" do
      3.times { |i| deduplicator.info("Single #{i}") }
      2.times { deduplicator.warn("Repeated message") }

      5.times { |i| deduplicator.info("Fill up #{i}") }

      expect(deduplicator.seen.values.any? { |v| v[:message].include?("Repeated message") }).to be true
    end
  end

  describe "#suppressed_messages" do
    it "returns only messages with count > 1" do
      deduplicator.info("Once only")
      3.times { deduplicator.warn("Repeated warning") }

      suppressed = deduplicator.suppressed_messages
      expect(suppressed.size).to eq(1)
      expect(suppressed.values.first[:count]).to eq(3)
    end
  end

  describe "#print_summary" do
    it "prints nothing when no messages were suppressed" do
      deduplicator.info("Single message")
      expect { deduplicator.print_summary }.not_to output.to_stdout
    end

    it "prints summary for suppressed messages" do
      3.times { deduplicator.warn("Repeated warning") }
      expect { deduplicator.print_summary }.to output(/Suppressed repeated log messages/).to_stdout
      expect { deduplicator.print_summary }.to output(/2x suppressed/).to_stdout
    end
  end

  describe ".with_deduplicating_logger" do
    it "yields proxy and prints summary after block" do
      yielded_proxy = nil
      output = capture_stdout do
        described_class.with_deduplicating_logger(real_logger, cap: 10) do |proxy|
          yielded_proxy = proxy
          3.times { proxy.info("Test message") }
        end
      end

      expect(yielded_proxy).to be_a(described_class)
      expect(output).to include("2x suppressed")
    end

    it "prints summary even if block raises" do
      output = capture_stdout do
        expect do
          described_class.with_deduplicating_logger(real_logger, cap: 10) do |proxy|
            2.times { proxy.error("Error message") }
            raise "boom"
          end
        end.to raise_error("boom")
      end

      expect(output).to include("1x suppressed")
    end
  end

  describe "logger delegation" do
    it "delegates level to real logger" do
      real_logger.level = Logger::WARN
      expect(deduplicator.level).to eq(Logger::WARN)
    end

    it "delegates unknown methods to real logger" do
      expect(deduplicator.datetime_format).to eq(real_logger.datetime_format)
    end
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end
