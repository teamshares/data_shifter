# frozen_string_literal: true

module DataShifter
  module Internal
    # ANSI color utilities for CLI output.
    # Automatically detects TTY and respects NO_COLOR environment variable.
    module Colors
      CODES = {
        reset: "\e[0m",
        bold: "\e[1m",
        dim: "\e[2m",
        green: "\e[32m",
        yellow: "\e[33m",
        red: "\e[31m",
        cyan: "\e[36m",
      }.freeze

      module_function

      def enabled?(io = $stdout)
        return false if ENV["NO_COLOR"]
        return false unless io.respond_to?(:tty?)

        io.tty?
      end

      def wrap(text, *styles, io: $stdout)
        return text unless enabled?(io)

        codes = styles.map { |s| CODES[s] }.compact.join
        "#{codes}#{text}#{CODES[:reset]}"
      end

      def bold(text, io: $stdout)
        wrap(text, :bold, io:)
      end

      def dim(text, io: $stdout)
        wrap(text, :dim, io:)
      end

      def green(text, io: $stdout)
        wrap(text, :green, io:)
      end

      def yellow(text, io: $stdout)
        wrap(text, :yellow, io:)
      end

      def red(text, io: $stdout)
        wrap(text, :red, io:)
      end

      def cyan(text, io: $stdout)
        wrap(text, :cyan, io:)
      end

      def success(text, io: $stdout)
        wrap(text, :bold, :green, io:)
      end

      def warning(text, io: $stdout)
        wrap(text, :bold, :yellow, io:)
      end

      def error(text, io: $stdout)
        wrap(text, :bold, :red, io:)
      end
    end
  end
end
