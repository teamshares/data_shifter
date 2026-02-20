# frozen_string_literal: true

module DataShifter
  # Raised when a dry run attempts an outbound HTTP request to a host that is
  # not allowed via allow_external_requests (per-shift or global config).
  class ExternalRequestNotAllowedError < StandardError
    def initialize(attempted_host: nil)
      @attempted_host = attempted_host
      super(build_message)
    end

    attr_reader :attempted_host

    private

    def build_message
      intro = if @attempted_host && !@attempted_host.to_s.strip.empty?
                "Dry run blocked an outbound HTTP request to #{@attempted_host}."
              else
                "Dry run blocked an outbound HTTP request."
              end

      if @attempted_host && !@attempted_host.to_s.strip.empty?
        <<~MSG.strip
          #{intro}

          To allow this host during dry run, add to your shift class:

            allow_external_requests ["#{@attempted_host}"]

          Or set DataShifter.config.allow_external_requests in an initializer.
        MSG
      else
        <<~MSG.strip
          #{intro}

          To allow specific hosts during dry run, add to your shift class:

            allow_external_requests ["host.example.com"]  # or use a regex

          Or set DataShifter.config.allow_external_requests in an initializer.
        MSG
      end
    end
  end
end
