# DataShifter

Rake-backed data migrations (“shifts”) for Rails apps, with **dry run by default**, progress output, and a consistent summary. Define shift classes in `lib/data_shifts/*.rb`; run them as `rake data:shift:<task_name>`.

## Installation

```ruby
# Gemfile
gem "data_shifter"
```

```bash
bundle install
```

No extra setup in a Rails app: the railtie registers the generator and defines rake tasks by scanning `lib/data_shifts/*.rb`.

## Quickstart

Generate a shift (optionally scoped to a model):

```bash
bin/rails generate data_shift backfill_foo
bin/rails generate data_shift backfill_users --model=User
```

Add  your logic to the generated file in `lib/data_shifts/`.

Run it:

```bash
rake data:shift:backfill_foo
COMMIT=1 rake data:shift:backfill_foo
```

## How shift files map to rake tasks

DataShifter defines one rake task per file in `lib/data_shifts/*.rb`.

- **Task name**: derived from the filename with any leading digits removed.
  - `20260201120000_backfill_foo.rb` → `data:shift:backfill_foo` (leading `<digits>_` prefix is stripped)
  - `backfill_foo.rb` → `data:shift:backfill_foo`
- **Class name**: task name camelized, inside the `DataShifts` module.
  - `backfill_foo` → `DataShifts::BackfillFoo`

Shift files are **required only when the task runs** (tasks are defined up front; classes load lazily).
The `description "..."` line is extracted from the file and used for `rake -T` output without loading the shift class.

## Defining a shift

Typical shifts implement:

- **`collection`**: an `ActiveRecord::Relation` (uses `find_each`) or an `Array`/Enumerable
- **`process_record(record)`**: applies the change for one record

```ruby
module DataShifts
  class BackfillCanceledById < DataShifter::Shift
    description "Backfill canceled_by_id"

    def collection
      Bar.where(canceled_by_id: nil).where.not(canceled_at: nil)
    end

    def process_record(bar)
      bar.update!(canceled_by_id: bar.company.primary_contact_id)
    end
  end
end
```

## Dry run vs commit

Shifts run in **dry run** mode by default. In the automatic transaction modes (`transaction :single` / `true`, and `transaction :per_record`), DB changes are rolled back automatically.

- **Dry run (default)**: `rake data:shift:backfill_foo`
- **Commit**: `COMMIT=1 rake data:shift:backfill_foo`
  - (`COMMIT=true` or `DRY_RUN=false` also commit)

Non-DB side effects (API calls, emails, enqueued jobs, etc.) obviously cannot be automatically rolled back, so guard them with e.g. `return if dry_run?`.

## Transaction modes

Set the transaction mode at the class level:

- **`transaction :single` / `transaction true` (default)**: one DB transaction for the entire run; dry run rolls back at the end; a record error aborts the run.
- **`transaction :per_record`**: in commit mode, each record runs in its own transaction (errors are collected and the run continues); in dry run, the run is wrapped in a single rollback transaction.
- **`transaction false` / `transaction :none`**: CAUTION: NOT RECOMMENDED. No automatic transactions and no automatic rollback; ⚠️ **you must manually guard DB writes AND side effects with `dry_run?`.**

```ruby
module DataShifts
  class BackfillLegacyId < DataShifter::Shift
    description "Per-record so one failure doesn't roll back all"
    transaction :per_record

    def collection = Item.where(legacy_id: nil)
    def process_record(item)
      item.update!(legacy_id: LegacyIdService.fetch(item))
    end
  end
end
```

```ruby
module DataShifts
  class SyncToExternal < DataShifter::Shift
    description "Side effects outside DB"
    transaction false

    def process_record(record)
      return if dry_run?

      record.update!(synced_at: Time.current)
      ExternalAPI.notify(record)
    end
  end
end
```

## Progress, status, and output

- **Progress bar**: enabled by default (requires `ruby-progressbar`), and only shown for collections with at least 5 records.
- **Header**: prints mode (DRY RUN vs LIVE), record count, transaction mode, and available status triggers.
- **Live status (without aborting)**:
  - `STATUS_INTERVAL=60` prints a status block periodically (checked between records)
  - **macOS/BSD**: `Ctrl+T` (SIGINFO)
  - **Any OS**: `kill -USR1 <pid>` (SIGUSR1)

## Resuming a partial run (`CONTINUE_FROM`)

If your `collection` is an `ActiveRecord::Relation`, you can resume by filtering the primary key:

```bash
CONTINUE_FROM=123 COMMIT=1 rake data:shift:backfill_foo
```

Notes:

- Only supported for `ActiveRecord::Relation` collections (Array-based collections—like those from `find_exactly!`—cannot be resumed).
- The filter is `primary_key > CONTINUE_FROM`, so it’s only useful with monotonically increasing primary keys (e.g. `find_each`'s default behavior).

## Operational tips

### Safety checklist (recommended)

- **Start with a dry run**: run the task once with no environment variables set, confirm logs and summary look right, then re-run with `COMMIT=1`.
- **Make shifts idempotent**: structure `process_record` so re-running is safe (for example, update only when the target column is `NULL`, or compute the same derived value deterministically).
- **Guard side effects explicitly**: even in dry run, API calls / emails / enqueues are not rolled back. Use `dry_run?` helper to skip side-effectful code.

### Choosing a transaction mode (behavior + guidance)

- **`transaction :single` (default)**:
  - **Behavior**: the first raised error aborts the run (all-or-nothing).
  - **Use when**: partial success is worse than failure, or you want a clean rollback on any unexpected error.
- **`transaction :per_record`**:
  - **Behavior**: in commit mode, records are committed one-by-one; errors are collected and the run continues; the overall run fails at the end if any record failed.
  - **Use when**: you want maximum progress and are OK investigating/fixing a subset of failures.
- **`transaction false` / `:none`**:
  - **Behavior**: no automatic transaction wrapper (even in dry run) and no automatic rollback.
  - **Use when**: you have intentional external side effects, or you’re doing your own transaction/locking strategy—**but always guard writes/side effects with `dry_run?`.**

### Performance and operability (recommended)

- **Prefer returning an `ActiveRecord::Relation` from `collection`** for large datasets (DataShifter iterates relations with `find_each`).
- **Be aware `count` happens up front for relations** to print the header and size the progress bar. On very large/expensive relations, that extra query may be non-trivial.
- **Use status output for long runs**: set `STATUS_INTERVAL` in environments where signals are awkward (for example, some process managers).

## Utilities for building shifts

### `find_exactly!` (fail fast for ID lists)

Use `find_exactly!(Model, ids)` to fetch a fixed list and raise if any are missing:

```ruby
def collection
  ids = ENV.fetch("BUYBACK_IDS").split(",").map(&:strip)
  find_exactly!(Buyback, ids)
end

def process_record(buyback)
  buyback.recompute!
end
```

### `skip!` (count but don’t update)

Mark a record as skipped (it will increment “Skipped” in the summary):

```ruby
def process_record(record)
  skip!("already done") if record.foo.present?
  record.update!(foo: value)
end
```

### Throttling and disabling the progress bar

```ruby
class SomeShift < DataShifter::Shift
  throttle 0.1       # sleep seconds between records
  progress false    # disable progress bar rendering
end
```

## Generator

| Command | Generates |
|--------|----------|
| `bin/rails generate data_shift backfill_foo` | `lib/data_shifts/<timestamp>_backfill_foo.rb` with a `DataShifts::BackfillFoo` class |
| `bin/rails generate data_shift backfill_users --model=User` | Same, with `User.all` in `collection` and `process_record(user)` |
| `bin/rails generate data_shift backfill_users --spec` | Also generates `spec/lib/data_shifts/backfill_users_spec.rb` when RSpec is enabled |

The generator refuses to create a second shift if it would produce a duplicate rake task name.

## Testing shifts (RSpec)

This gem ships a small helper module for running shifts in tests:

```ruby
require "data_shifter/spec_helper"

RSpec.describe DataShifts::BackfillFoo do
  include DataShifter::SpecHelper

  before { allow($stdout).to receive(:puts) } # silence shift output

  it "does not persist changes in dry run" do
    result = run_data_shift(described_class, dry_run: true)
    expect(result).to be_ok
    # TODO: add some check confirming data is unchanged
  end

  it "persists changes when committed" do
    result = run_data_shift(described_class, commit: true)
    expect(result).to be_ok
    # TODO: add some check confirming data is changed
  end
end
```

## Optional RuboCop cop

If you use `transaction false` / `transaction :none`, you should guard writes and side effects with `dry_run?`. You can help avoid mistakes by linting that the helper is at least called once via the bundled cop:

```yaml
# .rubocop.yml
require:
  - data_shifter/rubocop
```

## Requirements

- Ruby ≥ 3.2.1
- Rails (ActiveRecord, ActiveSupport, Railties) ≥ 6.1
- `axn` (Shift classes include `Axn`)
- `ruby-progressbar` (for progress bars)
