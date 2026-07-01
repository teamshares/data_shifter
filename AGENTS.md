# AGENTS.md

Guidance for agents working **on** this gem (not for agents writing individual data shift files —
that's the README's audience).

## What this is

`DataShifter::Shift` (`lib/data_shifter/shift.rb`) is the base class downstream apps subclass to
write rake-backed data migrations. `Shift` `include Axn`, so this gem is itself an **Axn consumer** —
config (`DataShifter.configure`) rides on `Axn::Configurable`, and the `task "label", SomeAxn` sugar
calls into `Axn::Result`/`call!`. When working on anything that touches Axn semantics (failure
buckets, message presentation, `call` vs `call!`, the `Configurable` DSL), first read axn's own
agent guide: run `bundle show axn` and read `AGENTS-consuming.md` at that path. Don't guess at Axn
behavior — verify against that guide or the source it points to.

## Structure

- `lib/data_shifter/shift.rb` — the DSL and execution engine (collection/process_record, `task`,
  transactions, throttle, dry-run guards, `inline_csv`).
- `lib/data_shifter/internal/` — output formatting, side-effect guards (WebMock/Sidekiq/ActiveJob),
  log dedup, signal handling. Implementation detail, not public API.
- `lib/data_shifter/railtie.rb` — rake task registration, lazy shift loading.
- `lib/generators/` — `rails g data_shift`.
- `spec/dummy_app/` — a full Rails app; specs run against it, not against `lib/` in isolation.
  Fixture shift files live in `spec/dummy_app/spec/fixtures/shifts/` (used for tests needing a real,
  named, file-backed class — e.g. `inline_csv`'s `__END__`-section resolution needs
  `Object.const_source_location`, which anonymous `Class.new` specs can't provide).

## Workflow

- TDD: write a failing spec first, watch it fail, then implement. This codebase follows that
  discipline; match it.
- Run specs from `spec/dummy_app/`: `cd spec/dummy_app && bundle exec rspec`. First run needs
  `bundle install` there too (separate `Gemfile.lock` from the gem root).
- Rubocop runs against the gem root only (`spec/dummy_app/**/*` is excluded in `.rubocop.yml`):
  `bundle exec rubocop -A`. Pre-commit hook (husky + lint-staged) auto-corrects staged `.rb` files.
  `rake` (default task) runs both spec and rubocop — same as CI.
- The gem tracks `axn` via a git pin (`branch: "main"`) in both Gemfiles until axn cuts a release
  with the features this gem depends on. `bundle update axn` in both the root and
  `spec/dummy_app/` to pick up upstream changes; re-run the full suite after.

## Conventions

- No production code without a failing test first (see Workflow).
- Public per-shift DSL (`collection`, `process_record`, `task`, `progress`, `suppress_repeated_logs`,
  `transaction`, `throttle`, `allow_external_requests`, `inline_csv`) is the stable surface — changes
  here are user-facing breaking changes. `Internal::*` is not.
- Update `README.md` and `CHANGELOG.md` (`[Unreleased]` or the in-progress version heading) for any
  user-facing DSL or config change.
- Version is pre-1.0 (`lib/data_shifter/version.rb`); bump patch for additive DSL sugar, minor for
  anything that changes existing behavior or public API shape.
