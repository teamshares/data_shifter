# frozen_string_literal: true

require "webmock"

module DataShifter
  module Internal
    # Applies and restores side-effect guards during dry runs so that HTTP, mail,
    # and job enqueues are blocked (or faked) unless explicitly allowed.
    module SideEffectGuards
      class << self
        # Applies side-effect guards, yields, then restores. Call only when running in dry run.
        def with_guards(shift_class:, &block)
          saved = {}
          apply_guards(shift_class, saved)
          block.call
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
          WebMock.enable!
          allowed = allowed_net_hosts(shift_class)
          opts = allowed.any? ? { allow: allowed } : {}
          WebMock.disable_net_connect!(**opts)
          saved[:webmock] = true
        end

        def allowed_net_hosts(shift_class)
          per_shift = shift_class.respond_to?(:_dry_run_allow_net_connect) ? shift_class._dry_run_allow_net_connect : []
          global = DataShifter.respond_to?(:dry_run_allow_net_connect) ? DataShifter.dry_run_allow_net_connect : []
          Array(per_shift) + Array(global)
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
          WebMock.allow_net_connect! if saved.delete(:webmock)

          ActionMailer::Base.perform_deliveries = saved.delete(:action_mailer_perform_deliveries) if saved.key?(:action_mailer_perform_deliveries)

          ActiveJob::Base.queue_adapter = saved.delete(:active_job_adapter) if saved.key?(:active_job_adapter)

          return unless saved.delete(:sidekiq)

          Sidekiq::Testing.disable!
        end
      end
    end
  end
end
