# Ad hoc shifts and step-based updates — design exploration

This doc explores supporting **targeted, ad hoc changes** to specific records (and multi-step updates) without the collection/per-record pattern. It’s based on the current `DataShifter::Shift` implementation and concrete workarounds in **teamshares/os-app** PRs 4189 and 4190 (accessed via `gh pr view` / `gh pr diff`).

## Implementation Status

**IMPLEMENTED**: The `ad_hoc` block DSL has been implemented in `DataShifter::Shift`. See [README.md](../README.md) for usage documentation.

Key features:
- `ad_hoc 'optional label' do ... end` blocks replace the need for `collection`/`process_record`
- Multiple blocks run in sequence with shared transaction/dry-run semantics
- Block labels appear in error messages and summaries
- `transaction :per_record` means per-block transactions (each block commits independently)
- Generator supports `--ad-hoc` option

---

## Reference: os-app PRs (data_shifter usage)

### PR 4190 — Conrad Legendy payout issues (PRO-1991)

**Goal**: One-off fix for Pumphouse: (1) make Conrad’s deferred Jan 2026 EBB approvable (restore snapshot, advance to pending_approvals); (2) extend signing window for his other repurchase agreement to end of week.

**Pattern**:
- `collection` runs several lookups (company by abbrev, user by name, distribution, deferred EBB, pending repurchase agreement) and returns **two records**: `[deferred_ebb, pending_ra]` — a `CapTable::Event` and a `RepurchaseAgreement`.
- `process_record(record)` **branches on record type**: `if record.is_a?(CapTable::Event) then make_deferred_ebb_approvable(record) else extend_repurchase_agreement_signing(record)`.
- `transaction :per_record` (each of the 2 records in its own transaction).

So: two distinct logical operations (fix EBB, extend RA) are forced into “collection of 2 heterogeneous records” + “process_record dispatches by class.” The “records” are just tokens to run two different code paths.

### PR 4189 — Fix orphaned Cap Table Events (PRO-1959)

**Goal**: Fix three unrelated data issues: (A) Select Sand & Gravel — fix SBTP 9495’s `associated_event_id` and reparent child EBBs; (B) MAN Marketing — create missing SBTP for EBB 9809 and link; (C) Rehoboth — create new IQEB for SBTP 10698, link, and fix cert state.

**Pattern**:
- `collection` = `find_exactly!(CapTable::Event, [9495, 9809, 10_698])` — three specific event IDs.
- `process_record(event)` **dispatches by id**: `case event.id when SSG_SBTP_ID then run_part_a!(event); when MAN_MARKETING_EBB_ID then run_part_b!(event); when REHOBOTH_SBTP_ID then run_part_c!(event); else skip! end`.
- Part A/B/C are completely different workflows (update + reparent; create SBTP + link; create IQEB + link + cert updates). The “record” is only used as a key to choose which part runs.
- `transaction :per_record`.

So: three named “parts” (A, B, C) are implemented as one shift with a 3-element collection and a big `case event.id` in `process_record`. No step names in the UI; no reuse of part logic; one failure reports as “record 9809” not “Part B”.

---

## A. Existing friction (from contract + PRs)

### Current contract

- **Required overrides**: Subclasses must implement `collection` and `process_record(record)`.
- **Flow**: `call` → `_for_each_record_in(collection)` → `_each_record_impl` → count/header → `_iterate` (find_each or each) → `_process_one(record)` → `process_record(record)`.
- **Count**: For relations, `total = records.count`; for arrays, `total = items.size`. Header always shows “Records: N …”.
- **Lifecycle**: Same for all runs — `around` (log dedup, side-effect guards when dry_run, transaction), `before` (_reset_tracking), body, `on_success`/`on_error` (_print_summary).

### Friction for ad hoc / targeted runs

1. **Forcing collection + process_record**  
   For a single logical change (or a small set of distinct operations), you still have to define `collection` and `process_record(record)`. The “record” often becomes a **dispatch key** rather than “the thing we iterate over”:
   - **PR 4190**: Collection returns two *heterogeneous* records (EBB + RepurchaseAgreement); `process_record` branches on `record.is_a?(CapTable::Event)` to run one of two unrelated code paths.
   - **PR 4189**: Collection returns three events by ID; `process_record` does `case event.id` to run one of three unrelated “parts” (A, B, C). The record is only used to select which part runs.
   Alternative (seen in shift_spec): override `call` and skip the loop entirely — then you lose the standard summary and still have to satisfy the base API.

2. **Unnecessary count and record-oriented UI**  
   `records.count` or `items.size` is always computed and shown (“Records: 2”, “Records: 3”). Progress bar, per-record stats, and CONTINUE_FROM are record-centric. For ad hoc runs like 4190/4189, the “N records” framing is misleading: what matters is “run these 2 or 3 *steps*” with dry-run protection.

3. **Multiple separate updates in one run**  
   When you want “do A, then B, then C” with one dry run (and optionally one transaction):
   - **What PRs do**: One shift, collection = list of records that *map* to A/B/C, `process_record` branches by type or id (4190: by class; 4189: by id). Works but: no named steps, no “Part B failed” in the summary, and the mental model is “iterate records” instead of “run steps.”
   - **Other options**: Three separate shifts (lose single transaction + single dry-run pass), or override `call` and do all updates in one method (no step boundaries, opaque failures).

---

## B. Single call without per-record counts (dry-run preserved)

**Goal**: One execution path that runs a **single** block (or method) with the same dry-run and transaction semantics, **without** collection, `process_record`, count, or progress.

### Option 1: New base class `DataShifter::OneOff` (or `AdHocShift`)

- Subclass of `Shift` (or same module inclusion) that:
  - Does **not** require `collection` / `process_record`.
  - Defines `call` to run a single method, e.g. `perform`, inside the existing lifecycle (same `around` hooks: transaction, dry_run rollback, side-effect guards).
- No call to `_for_each_record_in`; no count; no progress bar.
- Summary can be minimal: e.g. duration + “Dry run” or “LIVE” and the standard “no changes saved” / COMMIT=1 line when dry. No need for processed/succeeded/failed/skipped (or treat as 0/1/0/0 for compatibility).

**API sketch**:

```ruby
# lib/data_shifts/20260303120000_fix_single_company.rb
module DataShifts
  class FixSingleCompany < DataShifter::OneOff
    description "Fix company X by ..."

    def perform
      company = Company.find(123)
      company.update!(...)
    end
  end
end
```

- `OneOff#call` would: run `perform` (or a block passed at class level). Same `expects :dry_run`, same `around` hooks, so dry run still wraps in a transaction and raises `ActiveRecord::Rollback`, and side-effect guards still apply.

**Implementation outline**:

- Add `DataShifter::OneOff < DataShifter::Shift`.
- Override `call` to:
  - Call `_reset_tracking` (or a minimal variant so summary doesn’t assume records).
  - Call `perform` (subclass implements `perform`).
- Do **not** call `_for_each_record_in` or `_print_header(total)`.
- Optional: `_print_header` in Output could accept `total: nil` and print a single-line “Ad hoc run” (or skip the “Records: N” line). Summary already works if we set e.g. `@stats = { processed: 0, succeeded: 1, failed: 0, skipped: 0 }` for success, or leave as-is and accept “Processed: 0” for one-off.

### Option 2: Class-level “no collection” mode on `Shift`

- Add something like `one_off` or `no_collection` on `Shift` that:
  - Makes `call` run a single method (e.g. `perform`) instead of `_for_each_record_in(collection)`.
  - Keeps the same hooks and dry-run/transaction behavior.
- When `one_off` is true, `collection` and `process_record` are not used; subclasses implement `perform` instead.
- Header/summary: same as Option 1 (no count, or optional minimal header).

**Recommendation**: Option 1 (dedicated `OneOff` class) keeps the mental model clear (collection-based vs one-off) and avoids overloading `Shift` with two different execution modes. Rake/railtie can treat both as runnable shifts (same task naming if desired).

### Dry-run behavior (unchanged)

- `_with_transaction_for_dry_run`: in dry run, wrap in `ActiveRecord::Base.transaction` and raise `ActiveRecord::Rollback` after the body.
- `_with_side_effect_guards`: in dry run, apply WebMock, mailer, ActiveJob, Sidekiq guards.
- So a single `perform` (or block) still runs inside those wrappers; no code change needed for dry-run protection.

---

## C. Multiple separate updates: step-based runs using Axn steps

**Goal**: Define several logical updates as separate steps, run them in one go, with one transaction and one dry run (same semantics as today’s single-transaction shifts).

### Axn step strategy (recap)

- In `Axn::Mountable::MountingStrategies::Step`:
  - Parent class can define `step :name, StepClass` or `step :name, ... do ... end`, or `steps(Step1, Step2)`.
  - Parent’s `call` is generated: it runs each step in order, passing `@__context.__combined_data` (expects/exposes) and merges exposed data for the next step.
  - Steps are plain Axns; they don’t know about dry_run or DataShifter.

### How to combine with DataShifter

- We want: one “shift” that runs step 1, step 2, step 3, … in sequence, inside:
  - one transaction (and rollback on dry run), and
  - the same side-effect guards when dry_run.
- So the **parent** is a DataShifter shift (or one-off); the **body** of the run is “execute these steps in order”. No collection; no per-record count.

Two ways to wire this:

**Approach 1: DataShifter class that uses Axn’s step DSL**

- Introduce e.g. `DataShifter::StepShift < DataShifter::Shift` (or `< OneOff`).
- Include or use the same step DSL as Axn’s Mountable (e.g. `step :update_a, UpdateA; step :update_b, UpdateB`).
- Override `call` so that instead of `_for_each_record_in(collection)` or a single `perform`, we:
  - Run each registered step in sequence (with shared context: expects/exposes).
  - Rely on the existing `around` hooks so that this whole run is inside one transaction and one dry-run/guard wrap.
- Step classes are small Axns that do one update each (e.g. load record, update, expose nothing or a result). They receive `dry_run` (and any other context) from the parent; they don’t start their own transaction.

**Approach 2: Implement a minimal step runner inside DataShifter**

- Don’t depend on Axn’s Mountable step strategy.
- Add a `steps` DSL on a new class, e.g. `DataShifter::StepShift`:
  - `step :name, StepClass` or `step :name { ... }` registers a step.
  - `call` runs each step in order; each step is `step_class.call!(**context)` (or instance with same kwargs). Context can include `dry_run` and any exposes from previous steps.
- Same transaction/dry-run wrapper: the whole `call` runs inside existing `_with_transaction_for_dry_run` and `_with_side_effect_guards`, so all steps see the same transaction and dry_run.

**Recommendation**: Approach 2 is likely simpler and keeps data_shifter’s dependency on Axn to “core” only (expects, call, Result, hooks). We don’t need to pull in Mountable or the step strategy’s generated `call`; we only need the idea “run N steps in order with shared context.” Reuse the same hooks so that:

- `StepShift.call(dry_run: true)` runs: transaction (open) → guards on → step1.call!(dry_run: true) → step2.call!(…) → … → rollback (dry run) → guards off.
- On first step failure: `fail!` or raise propagates, transaction rolls back, summary prints.

**API sketch**:

```ruby
# Each step is a small Axn that expects what it needs (e.g. dry_run, ids) and does one update.
class DataShifts::UpdateCompanyA
  include Axn
  expects :dry_run
  def call
    return if dry_run  # or rely on transaction rollback only
    Company.find(123).update!(...)
  end
end

class DataShifts::UpdateCompanyB
  include Axn
  expects :dry_run
  def call
    Company.find(456).update!(...)
  end
end

module DataShifts
  class MultiFixCompanies < DataShifter::StepShift
    description "Update company A and B in one transaction"
    steps UpdateCompanyA, UpdateCompanyB
    # or: step :update_a, UpdateCompanyA; step :update_b, UpdateCompanyB
  end
end
```

- `StepShift.call(dry_run: true)` runs both steps inside one transaction and rolls back, so no DB changes. No collection, no count; summary can be step-oriented (e.g. “Steps: 2 run, 0 failed”) or minimal like OneOff.

### Step failure and error prefixing

- If we use Axn’s step strategy, we get “Step 1: …” / “Step 2: …” error prefixing from the mountable.
- If we implement our own runner, we can do the same: catch step failure and re-raise with “step_name: original message” so the summary/exception is clear.

### Data flow between steps

- For “update A then B then C”, steps might not need to pass data (each finds its own record). If they do (e.g. “step 1 loads X, step 2 uses X”), we can pass a context hash (e.g. `dry_run` + exposes from previous steps) into each `step_class.call!(**context)`.
- That matches Axn’s expects/exposes model; we can keep the same convention in our minimal runner.

---

## Summary

| Need | Approach | Notes |
|------|----------|--------|
| Single ad hoc change, dry run + transaction, no count | `DataShifter::OneOff` with `perform` | New class; same hooks; no collection/process_record; optional minimal header/summary. |
| Multiple named updates in one transaction + one dry run | `DataShifter::StepShift` with `steps(Step1, Step2)` | New class; `call` runs steps in order inside existing transaction/dry-run/guards; steps are small Axns. |
| Reuse Axn step machinery | Optional: use Mountable step strategy on a Shift-like class | Possible but ties data_shifter to Mountable; minimal step runner (Approach 2) keeps dependency smaller. |

Implementing B (OneOff) first gives a clear path for single-call ad hoc shifts. Then C (StepShift) can build on the same “no collection” idea and reuse the same lifecycle hooks, with a small step runner and optional step-name error prefixing.

---

## Implementation notes

### OneOff: `perform` and summary

- In `OneOff#call`, after `_reset_tracking`, call `perform`. On success, you can set `@stats[:succeeded] = 1` so the summary reads “Succeeded: 1” instead of 0, or leave stats as-is for minimal code.
- `_print_header` in `Output` currently requires `total`. For OneOff we can either skip the header (no `_print_header` call) or add a variant that omits the “Records: N” line (e.g. `print_one_off_header(io:, shift_class:, dry_run:, transaction_mode:)`).

### StepShift: minimal step runner

- Store steps as an array of `[name, step_class_or_block]`. DSL: `step :update_a, UpdateA` or `steps(UpdateA, UpdateB)` (names default to step class name or “Step 1”, “Step 2”).
- In `call`:
  - `context = { dry_run: dry_run }`
  - `steps.each do |name, step_klass|`
  - `result = step_klass.call!(**context)`
  - `fail! "#{name}: #{result.error}" unless result.ok?`
  - Merge step’s exposed data into context for the next step: `result.declared_fields` (on `Axn::Result`, from ContextFacade) gives the exposed keys; for each key `f`, `result.public_send(f)` is the value. So `context.merge!(result.declared_fields.map { |f| [f, result.public_send(f)] }.to_h)`.
- Each step therefore gets `dry_run` and any exposes from previous steps; failure aborts and prefixes with step name. No need to include Axn::Mountable or the Step strategy; just call step classes and merge exposes into context.

---

## Appendix: Refreshing PR content

PR details above were obtained with:

```bash
gh pr view 4190 --repo teamshares/os-app --json title,body,additions,deletions,changedFiles
gh pr diff 4190 --repo teamshares/os-app
gh pr view 4189 --repo teamshares/os-app --json title,body,additions,deletions,changedFiles
gh pr diff 4189 --repo teamshares/os-app
```
