# frozen_string_literal: true

require "uri"

module DataShifter
  module Internal
    # Applies and restores side-effect guards during dry runs so that HTTP, mail,
    # and job enqueues are blocked (or faked) unless explicitly allowed.
    #
    # Production impact:
    # - WebMock: required only when apply_webmock runs (i.e. during a dry run), so commit-only
    #   production runs never load WebMock. On restore we revert to the previous state (enable!
    #   or disable!) so e.g. specs that had WebMock enabled are not left with it disabled.
    # - ActionMailer / ActiveJob / Sidekiq: no extra loading; we only toggle existing config
    #   for the duration of the block and restore in ensure, so impact is scoped to the run.
    module SideEffectGuards
      class << self
        # Applies side-effect guards, yields, then restores. Call only when running in dry run.
        def with_guards(shift_class:, &block)
          saved = {}
          apply_guards(shift_class, saved)
          block.call
        rescue webmock_net_connect_error => e
          host = extract_host_from_webmock_message(e.message)
          raise DataShifter::ExternalRequestNotAllowedError.new(attempted_host: host), cause: e
        ensure
          restore_guards(saved) if saved.any?
        end

        private

        def apply_guards(shift_class, saved)
          apply_webmock(shift_class, saved)
          # rubocop:disable Style/CombinableDefined -- parent must be checked first to avoid NameError when constant not loaded
          apply_action_mailer(saved) if defined?(ActionMailer) && defined?(ActionMailer::Base)
          apply_active_job(saved) if defined?(ActiveJob) && defined?(ActiveJob::Base)
          apply_sidekiq(saved) if defined?(Sidekiq) && defined?(Sidekiq::Testing)
          # rubocop:enable Style/CombinableDefined
        end

        def apply_webmock(shift_class, saved)
          if defined?(WebMock)
            # WebMock already loaded (e.g. in specs); capture so we can restore
            saved[:webmock_was_enabled] = net_http_webmock_enabled?
          else
            require "webmock"
            saved[:webmock_was_enabled] = false
          end
          WebMock.enable!
          allowed = allowed_net_hosts(shift_class)
          opts = allowed.any? ? { allow: allowed } : {}
          WebMock.disable_net_connect!(**opts)
          saved[:webmock] = true
        end

        def net_http_webmock_enabled?
          Net::HTTP.socket_type.to_s.include?("StubSocket")
        rescue StandardError
          false
        end

        def allowed_net_hosts(shift_class)
          per_shift = shift_class.respond_to?(:_allow_external_requests) ? shift_class._allow_external_requests : []
          global = DataShifter.config.allow_external_requests
          Array(per_shift) + Array(global)
        end

        def webmock_net_connect_error
          return WebMock::NetConnectNotAllowedError if defined?(WebMock::NetConnectNotAllowedError)

          Class.new(StandardError) # never matched when WebMock not loaded
        end

        def extract_host_from_webmock_message(message)
          return nil unless message.is_a?(String)

          # WebMock format: "Unregistered request: GET https://host/path with headers ..."
          m = message.match(%r{Unregistered request: \w+ (https?://[^\s]+)})
          return nil unless m

          uri = URI.parse(m[1])
          uri.host
        rescue URI::InvalidURIError, ArgumentError
          nil
        end

        def apply_action_mailer(saved)
          saved[:action_mailer_perform_deliveries] = ActionMailer::Base.perform_deliveries
          ActionMailer::Base.perform_deliveries = false
        end

        def apply_active_job(saved)
          saved[:active_job_adapter] = ActiveJob::Base.queue_adapter
          ActiveJob::Base.queue_adapter = :test
        end

        def apply_sidekiq(saved)
          return unless Sidekiq::Testing.respond_to?(:fake!)

          Sidekiq::Testing.fake!
          saved[:sidekiq] = true
        end

        def restore_guards(saved)
          if saved.delete(:webmock)
            (saved.delete(:webmock_was_enabled) ? WebMock.enable! : WebMock.disable!)
          end

          ActionMailer::Base.perform_deliveries = saved.delete(:action_mailer_perform_deliveries) if saved.key?(:action_mailer_perform_deliveries)

          ActiveJob::Base.queue_adapter = saved.delete(:active_job_adapter) if saved.key?(:active_job_adapter)

          return unless saved.delete(:sidekiq)

          Sidekiq::Testing.disable!
        end
      end
    end
  end
end
