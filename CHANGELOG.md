# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Loud warning and 5-second countdown when running with `transaction false` / `:none`, reminding that dry run only applies if writes are guarded with `dry_run?`. Use `DATA_SHIFTER_NO_TX_COUNTDOWN=0` to skip the countdown in CI/scripts.
- **Automatic side-effect guards in dry run**: When a shift runs in dry run mode, HTTP (via WebMock), ActionMailer, ActiveJob, and Sidekiq (if loaded) are now automatically blocked or faked so that unguarded external calls do not run. Restore happens in an `ensure` so state is reverted after the run.
  - **HTTP**: All outbound requests are blocked unless allowed with the per-shift `allow_external_requests` DSL or global `DataShifter.config.allow_external_requests`.
  - **ActionMailer**: `perform_deliveries = false` for the duration of the dry run.
  - **ActiveJob**: Queue adapter set to `:test` for the duration of the dry run.
  - **Sidekiq**: `Sidekiq::Testing.fake!` for the duration of the dry run (only if `Sidekiq::Testing` is already loaded).
- Dependency on `webmock` (>= 3.18) for dry-run HTTP blocking.

## [0.1.0] - Initial release
