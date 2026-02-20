# Changelog

## [Unreleased]

* N/A

## [0.2.0]

### Added

- **Configuration object**: New `DataShifter.configure` block for global settings.
- **Dry-run rollback for `transaction false`**: Shifts using `transaction false` (or `:none`) now roll back DB changes in dry-run mode, matching the behavior of other transaction modes.
- **Automatic side-effect guards in dry run**: When a shift runs in dry run mode, HTTP (via WebMock), ActionMailer, ActiveJob, and Sidekiq (if loaded) are now automatically blocked or faked so that unguarded external calls do not run. Restore happens in an `ensure` so state is reverted after the run.
  - **HTTP**: All outbound requests are blocked unless allowed with the per-shift `allow_external_requests [...]` DSL or global `DataShifter.config.allow_external_requests`.
  - **ActionMailer**: `perform_deliveries = false` for the duration of the dry run.
  - **ActiveJob**: Queue adapter set to `:test` for the duration of the dry run.
  - **Sidekiq**: `Sidekiq::Testing.fake!` for the duration of the dry run (only if `Sidekiq::Testing` is already loaded).
- Dependency on `webmock` (>= 3.18) for dry-run HTTP blocking.
- **Log deduplication**: Repeated log messages are now suppressed during shift runs (default: on). First occurrence logs normally; subsequent occurrences are counted and a summary is printed at the end. Configure globally with `config.suppress_repeated_logs` and `config.repeated_log_cap` (default 1000). Override per-shift with `suppress_repeated_logs false`.
- **Global progress bar default**: `config.progress_enabled` (default `true`) sets the default for all shifts. Per-shift `progress true/false` still overrides.
- **Global status interval**: `config.status_interval_seconds` (default `nil`) provides a fallback when `STATUS_INTERVAL` env var is not set.
- **skip! abort behavior**: `skip!` now terminates the current `process_record` (no `return` needed after calling it).
- **Grouped skip reasons**: Skip reasons are grouped and the top 10 (by count) are shown in the summary and status output instead of logging each skip inline.

## [0.1.0] - Initial release
