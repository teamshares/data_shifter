# Changelog

## [Unreleased]

## [0.3.5]

* [Changed] `Shift#run!` now wraps its call in `Axn::Extensions::InvokedVia.with(:data_shifter)`, tagging every axn in the run (including nested sub-axns and enqueue-time job tags) with `invoked_via: :data_shifter`. Bumps the minimum `axn` to `>= 0.1.0-alpha.6`, the first release shipping `Axn::Extensions::InvokedVia`.
* [Fixed] Test suite no longer triggers Sidekiq's `require "sidekiq/testing"` deprecation warning; it now uses `Sidekiq.testing!(:fake)` on Sidekiq >= 8 and falls back to the old `require` on older versions.

## [0.3.4]

* [Changed] `COMMIT` / `DRY_RUN` are now parsed as real booleans (`1/true/t/yes/y/on` vs `0/false/f/no/n/off`, case- and whitespace-insensitive). **`DRY_RUN=1` now means a dry run** — previously the `DRY_RUN == "true"` compare read `DRY_RUN=1` as "not dry" and committed the shift, which is data loss for a value that is truthy in every other tool. Unrecognized values (e.g. `COMMIT=garbage`) now raise `ArgumentError` instead of silently dry-running. `DRY_RUN=false` / `COMMIT=1` still commit.
* [Changed] Bumped the minimum Rails (ActiveRecord, ActiveSupport, Railties) to `>= 7.2`, matching upstream `axn`. Its `on_success` now fires via `ActiveRecord.after_all_transactions_commit`, which requires ActiveRecord 7.2+.
* [Feature] `throttle` now accepts an optional `per:` keyword. When set, the sleep is inserted only after processing that many records instead of after every record (e.g. `throttle 1.second, per: 100` sleeps once per 100 records).
* [Feature] `task` now accepts an Axn class as sugar for a one-axn task: `task "label", SomeAxn, foo: 1` forwards to `SomeAxn.call!(foo: 1)`, so a helper axn's failure is never silently swallowed. Keyword args are static (evaluated at class-load); use the block form when you need runtime values. Passing both a class and a block raises.
* [Feature] `inline_csv` reads CSV colocated with the shift after a `__END__` marker, so small data sets can live alongside the code. Returns the data rows (`CSV::Row` objects by default, so `row["id"]` works); options forward to `CSV.parse`. Typically used as `def collection = inline_csv`. `csv` is required lazily (not a hard dependency) — add `gem "csv"` to your Gemfile if you're on Ruby 3.4+ and hit a load error.
* [Changed] Configuration now rides on the upstream `Axn::Configurable` DSL instead of a hand-rolled config object. The public API is unchanged — `DataShifter.configure { |c| ... }`, `DataShifter.config.x`, and the per-shift `progress`/`suppress_repeated_logs` overrides all keep working. This raises the minimum `axn` to `>= 0.1.0.alpha.5` (the first release shipping `Axn::Configurable`), now depended on from rubygems rather than a git pin.
* [Changed] Replaced the removed `log_calls false` DSL with `auto_log false` (axn renamed the method on main). The previous `respond_to?(:log_calls)` guard silently no-op'd, re-enabling axn's per-call logging that shifts intend to suppress.

## [0.3.3]

* [Bugfix] Dry-run net guard now allows loopback hosts (`127.0.0.1`, `::1`, `localhost`) by default. Previously, any tracing/metrics sidecar listening on loopback (Datadog agent on 8126, statsd on 8125, OTLP collectors, etc.) would trip `WebMock::NetConnectNotAllowedError` from a background tracer thread and abort the rake task — even when the shift itself made no HTTP calls. Opt out with `DataShifter.config.allow_loopback_requests = false` for strict net blocking.

## [0.3.2.1]

* [Bugfix] Dry-run Sidekiq guard restores the previous `Sidekiq::Testing` mode (`fake!`, `inline!`, or `disable!`) instead of always calling `disable!`, which leaked global state and could leave later specs enqueueing work to real Redis.

## [0.3.2]

* [Bugfix] Rake tasks exit quietly after a failed shift run when the shift already printed its failure summary; failures before that summary are still reported on stderr. Replaces rescuing only `Axn::Failure`, which missed most re-raised exceptions from `run!`.
* [Changed] Setup failures (load, constantize, etc.) print a short framed report on stderr with rake task, file path (relative to `Rails.root`), exception, and a Rails-cleaned backtrace (capped) instead of a full `Exception#full_message` dump.

## [0.3.1]

* [Bugfix] No longer swallowing unexpected exceptions (errors in *loading* a data shift still need to be reported). No change to handling of exceptions raised while *running* a shift.

## [0.3.0]

### Added

- **Task-based shifts**: New `task` DSL for targeted, one-off changes without the `collection`/`process_record` pattern. Define one or more `task "label" do ... end` blocks that run in sequence with shared transaction and dry-run semantics. Labels appear in output and error messages.
- **Generator `--task` option**: `rails g data_shift fix_order_1234 --task` generates a shift with a `task` block instead of `collection`/`process_record`.
- **Colorized CLI output**: Headers, summaries, and status output now use ANSI colors for better readability. Colors are automatically disabled when output is not a TTY or when `NO_COLOR` environment variable is set.
- **Cleaner summaries**: `Failed` and `Skipped` lines are now omitted from summaries when their values are zero.

### Changed

- **Improved error messages**: `NotImplementedError` messages for `collection` and `process_record` now suggest using `task` blocks as an alternative.
- **Task labels logged on execution**: When running task-based shifts, each labeled task logs its name (`>> label`) when it starts.

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
