# frozen_string_literal: true

require "digest"
require "logger"

module DataShifter
  module Internal
    # A proxy logger that suppresses repeated log messages during a shift run.
    # Uses a hash of the message as the key for memory efficiency.
    # First occurrence is forwarded; subsequent occurrences are counted but not forwarded.
    # At the end, prints a summary of suppressed messages via puts.
    class LogDeduplicator
      attr_reader :real_logger, :cap, :seen

      def initialize(real_logger, cap:)
        @real_logger = real_logger
        @cap = cap
        @seen = {}
      end

      def add(severity, message = nil, progname = nil, &block)
        msg = block ? block.call : message
        key = message_key(severity, progname, msg)

        if @seen.key?(key)
          @seen[key][:count] += 1
          nil
        else
          enforce_cap
          @seen[key] = { count: 1, message: truncate_message(msg || progname), severity: }
          @real_logger.add(severity, message, progname, &block)
        end
      end

      def debug(message = nil, progname = nil, &)
        add(Logger::DEBUG, message, progname, &)
      end

      def info(message = nil, progname = nil, &)
        add(Logger::INFO, message, progname, &)
      end

      def warn(message = nil, progname = nil, &)
        add(Logger::WARN, message, progname, &)
      end

      def error(message = nil, progname = nil, &)
        add(Logger::ERROR, message, progname, &)
      end

      def fatal(message = nil, progname = nil, &)
        add(Logger::FATAL, message, progname, &)
      end

      def unknown(message = nil, progname = nil, &)
        add(Logger::UNKNOWN, message, progname, &)
      end

      def <<(msg)
        key = message_key(Logger::INFO, nil, msg)
        if @seen.key?(key)
          @seen[key][:count] += 1
        else
          enforce_cap
          @seen[key] = { count: 1, message: truncate_message(msg), severity: Logger::INFO }
          @real_logger << msg
        end
      end

      def level
        @real_logger.level
      end

      def level=(val)
        @real_logger.level = val
      end

      def formatter
        @real_logger.formatter
      end

      def formatter=(val)
        @real_logger.formatter = val
      end

      def close
        @real_logger.close
      end

      def suppressed_messages
        @seen.select { |_k, v| v[:count] > 1 }
      end

      def print_summary
        suppressed = suppressed_messages
        return if suppressed.empty?

        puts "\n[DataShifter] Suppressed repeated log messages:"
        suppressed.each_value do |entry|
          count = entry[:count] - 1
          snippet = entry[:message].to_s[0, 100]
          snippet = "#{snippet}..." if entry[:message].to_s.length > 100
          puts "  #{count}x suppressed: #{snippet.inspect}"
        end
      end

      def method_missing(method, ...)
        @real_logger.send(method, ...)
      end

      def respond_to_missing?(method, include_private = false)
        @real_logger.respond_to?(method, include_private) || super
      end

      class << self
        def with_deduplicating_logger(real_logger, cap:)
          proxy = new(real_logger, cap:)
          yield proxy
        ensure
          proxy&.print_summary
        end
      end

      private

      def message_key(severity, progname, message)
        normalized = "#{severity}:#{progname}:#{message}"
        Digest::SHA256.hexdigest(normalized)
      end

      def truncate_message(msg)
        str = msg.to_s
        str.length > 200 ? "#{str[0, 200]}..." : str
      end

      def enforce_cap
        return if @seen.size < @cap

        singles = @seen.select { |_k, v| v[:count] == 1 }
        singles.each_key { |k| @seen.delete(k) } if singles.any?

        return unless @seen.size >= @cap

        oldest_key = @seen.keys.first
        @seen.delete(oldest_key)
      end
    end
  end
end
