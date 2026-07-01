# AGENTS.md

For agents working on this gem (not for downstream apps writing shift files — see README).

## Structure

- `lib/data_shifter/shift.rb` — DSL + execution engine (collection/process_record, `task`,
  transactions, throttle, dry-run guards, `inline_csv`).
- `lib/data_shifter/internal/` — output, side-effect guards, log dedup, signal handling. Not public API.
- `lib/data_shifter/railtie.rb` — rake task registration, lazy shift loading.
- `lib/generators/` — `rails g data_shift`.
- `spec/dummy_app/` — full Rails app; specs run against it (own `Gemfile`/`Gemfile.lock`). Shift
  fixtures needing a real file-backed class (e.g. `inline_csv`'s `__END__` resolution via
  `Object.const_source_location`) live in `spec/dummy_app/spec/fixtures/shifts/`.

## Axn

`Shift` includes `Axn` (config on `Axn::Configurable`, `task "label", SomeAxn` calls
`Axn::Result`/`call!`). For Axn semantics: `bundle show axn`, then read `AGENTS-consuming.md` there.

## Commands

- Specs: `cd spec/dummy_app && bundle exec rspec`
- Lint: `bundle exec rubocop -A` (gem root only; `spec/dummy_app/**/*` excluded)
- `rake` (default task) runs both — matches CI
- `axn` is git-pinned to `branch: "main"` in both Gemfiles; `bundle update axn` in both to bump

## Conventions

- TDD: failing test before implementation
- Public DSL: `collection`, `process_record`, `task`, `progress`, `suppress_repeated_logs`,
  `transaction`, `throttle`, `allow_external_requests`, `inline_csv` — changes here are breaking
- Update `README.md` + `CHANGELOG.md` for DSL/config changes
- Pre-1.0: patch for additive DSL, minor for behavior/API shape changes
