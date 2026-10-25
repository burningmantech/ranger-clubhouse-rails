# CSS refactor baseline (2026-09-19)

Captured on branch `css-refactor` at `fe16f248` ("Add rails-hyperdrive for development"). The
only uncommitted changes at capture time were the harness itself and the new coverage tests; no
application code changed.

## Stylesheet: `tmp/css-audit/tailwind.base.css`

| | |
| --- | --- |
| Build | `tailwindcss -i app/assets/tailwind/application.css -o … --minify` (Tailwind 4.3.3, daisyUI 5.7.37), the same command `tailwindcss:build` runs, written to `tmp/` so a running `tailwindcss:watch` can't overwrite it |
| Size | **563,506 bytes** since P2 (`7c1ad116`). It was 595,062 before; that build is kept as `tailwind.base.pre-p2.css`. |
| Style rules | **4,103** (was 4,346). Rule preludes, nested rules included, `@`-rules excluded. |
| Class selectors | **1,867** distinct (was 2,009) |

The HTML snapshots were **not** re-captured for P2. It changed no markup: a full run showed
changes only on the OAuth-clients pages, whose uncommitted edits aren't P2's. Re-capturing would
have baked those edits into the base.

## HTML snapshots: `tmp/css_snapshots_base/`

**3,984 snapshots from 4,854 tests** (`test/controllers`, `test/integration`, `test/helpers`), with
0 failures. A full run takes about 2 minutes.

Each HTML, Turbo Stream or JSON-embedded-HTML response an integration test receives becomes
`<TestClass>/<test>-<hash>/<n>.html`. Everything a view test renders becomes one snapshot too.

**Normalization** (`test/support/css_snapshot.rb`):
- **Kept:** the element tree, one tag per line. Class tokens are sorted and de-duplicated. Kept
  attributes: `style`, ids and labels, ARIA, `role`, `type`, form state, `data-controller`,
  `data-action`, `data-*-target`, `data-label`, `data-theme`.
- **Dropped:** `<head>`, scripts, hidden inputs (including CSRF tokens), `href`, `src`, other
  `data-*` values, and query strings.
- **Masked:** digits, hex runs (random ids and digests), and month/day names become `#` or `D`.
  Records created in a test get fresh ids on every run, and pages print today's date.

**Determinism:** two unchanged full runs are identical, except that one table
(`Ticketing::AccessDocumentsController`, rows tied on their sort key) can return its rows in
either order. `bin/css_check` lists a file like that as "reordered only" (same lines, different
order) and doesn't count it as a change.

## Coverage

| Scope | Rendered in the baseline |
| --- | --- |
| View files named in `plan.md` | **101 / 102**. The miss is `common/_legal_name_disclaimer.html.erb`, which nothing renders anywhere and U19 deletes. |
| Views with a variant class attribute (`class="…<%`, `class_names(`, `"…#{`) | **59 / 59** |
| Layouts in `app/views/layouts` | **27 / 27** |
| All view files | 877 / 1,020 (86%) |

Coverage added for this baseline, because no existing test rendered these:
- `test/controllers/me/agreements_controller_test.rb` (new): the empty state, pending, signed,
  and show.
- `me/tickets`: the provisions and SO SAP sections after finishing, and the announce-period hub.
- `person/timesheets`: the backfill form as an admin.
- `mentoring/alpha_pods`: a member's edit form.
- `test/helpers/partials_render_test.rb` (new): eligible positions, all four Moodle-account shapes,
  the three timesheet-confirm stages, and every status medallion state and size.
- The harness snapshots the JSON `html` fields that autocomplete returns.

**Not covered:**
- **System tests** (178, browser-driven): open modals, toggled disclosures, and anything
  JavaScript adds or removes after load.
- **Mailer views** (`mail/layouts/mailer`): no unit in the plan touches them.
- **Computed styles.** A snapshot sees class names, not what they paint. It can't tell that
  `btn` looks different from the hand-rolled button it replaces, or that a token re-maps to a
  new colour.
- **Helper markup on pages no test renders.** The 14% of views never rendered aren't in the plan.

## Checking a unit

```
bin/css_check                      # full suite (~2 min) + stylesheet diff
bin/css_check test/controllers/me  # just those tests; the diff covers what ran
bin/css_check --css                # stylesheet only (~1 s)
bin/css_check --baseline           # after a visual unit is accepted, make its result the new base
```

It exits 1 when a selector left the compiled stylesheet while its class is still written in
`app/views`, `app/helpers`, `app/javascript`, `app/presenters`, `app/lib`, `app/components` or
`config`.

It also exits 1 when an `@utility` declared under `app/assets/stylesheets` or
`app/assets/tailwind` has no rule inside the build's `@layer utilities` while its name is still
written in those directories. That one reads the build, not the diff, so a baseline captured on
a tree that is already broken does not hide it. See
[the utility the selector diff could not see](#the-utility-the-selector-diff-could-not-see-2026-10-01).

Since P2, docs, skills and tests no longer feed the build. A class that leaves the views now
leaves the stylesheet, and the selector diff shows it.

## Proof runs (2026-09-19)

1. `profile_photos/new.html.erb:24`, `p-4` → `p-6`: **6 changed** (the six tests that render the
   photo upload page, each showing `-p-4` / `+p-6`), 0 noise, 1 reordered only. Stylesheet
   unchanged (`p-6` is already compiled). Exit 0.
2. Reverted: **0 changed**, 1 reordered only, stylesheet identical. Exit 0.
3. `@source not "../../../app/helpers/sidebar_helper.rb"` added temporarily: 9 selectors removed,
   **FAIL** listing each with `sidebar_helper.rb:line` (`.bg-[#000000]`, `.h-[140px]`, …). Exit 1.
   Reverted.

## Source globs (step 5)

**Option A landed as `7c1ad116`.** It sets `@import "tailwindcss" source(none);`, and Tailwind
now reads only `app/views`, `app/helpers`, `app/javascript`, `app/lib` and `config`. The inert
`stylesheets/*.css` line is gone, and AGENTS.md states the same list. `app/presenters` holds no
class strings today; if it ever does, it needs its own `@source` line.

**Verification:**
- B: 142 selectors were removed, and none is still written in the code once comment lines are
  skipped (`72615acc`).
- A: no snapshot changed except the OAuth-clients pages, which were being edited at the same time.
- None of the 142 classes appears in any of the 3,984 baseline snapshots. The one hit, `mb-10`,
  is a value a form-builder test passes itself.
- C: `/` and `/me` (Firecracker, dark theme) on :3210 load the new sheet. No element uses a
  removed class, and there are no console errors.

## The utility the selector diff could not see (2026-10-01)

The B line above was true and one rule short. `@utility ac-filter-chip` left the build with the
142 and was never counted among them.

- Its only mention in a scanned file was `` `ac-filter-chip${…}` `` in
  `autocomplete_controller.js`: glued to a placeholder, which gives Tailwind no whole word to
  read. Until P2 it compiled because automatic detection read the name from
  `docs/DESIGN-GUIDE.md`.
- The selector diff asks whether a class *name* left the stylesheet. This one did not.
  `autocomplete.css`'s reduced-motion block (`.ac-option, .ac-filter-chip { transition: none }`)
  is hand-written and went on naming it, so nothing was removed and the check passed. The search
  dialog's filter chips rendered with no padding, radius or border until the JS was fixed in
  `8d74cba0` (2026-09-30).
- Every baseline captured while it was broken already lacked the rule
  (`tmp/css-audit/tailwind.base.css` of 09-20 does), so no diff against one could have reported
  the loss, however "removed" was defined.

So the new check is not a diff. `CssMatchers.compiled_utilities` collects the class names with a
rule inside `@layer utilities`, and every `@utility` the stylesheets declare has to be among them
or be written nowhere in the code. A variant or an important in front is the same utility. A
longer name is not a use: `flex-center-gap-2` does not write `flex-center`.

**Known state:** 94 declared, 5 not emitted (`box-theme-success`, `-warning`, `-error`, `-info`,
`-secondary`). `boxes.css` only ever `@apply`s those, no code writes them, and they pass.

**Proof run**, in a scratch copy with the pre-fix JS line put back:

1. The script as it was: 557,605 → 556,069 bytes, 4,054 → 4,050 rules, "no selector added or
   removed". Exit 0.
2. The script now: the same line, then `6 not emitted`, then
   **FAIL** `.ac-filter-chip  app/javascript/controllers/autocomplete_controller.js:708`. Exit 1.
3. The untouched tree: `94 @utility declared, 5 not emitted`. Exit 0.

**The lint catches the line itself.** `bin/css_lint.rb` fails in any mode on a placeholder glued
to a class name where JS sets classes: `className`, a `classList` call, an HTML `class=`. On the
same scratch copy it reports `unscannable_class_names: 1` at that line. It reads `app/javascript`
whatever the roots, so the ratcheted numbers for views and helpers did not move. A class list
built in a variable first and assigned on another line is not seen.

**Still open.** 76 class names have a rule both inside and outside the utilities layer. 23 are
`@utility` and now covered. The other 53 are daisyUI's and Tailwind's own, named again by a
first-party selector (`btn-error`, `badge-soft`, `animate-pulse`, `tab-active`), and the same
hole is open for them: nothing declares them, so the build cannot be asked. Diffing the two
builds' utilities layers would close it, and would also fail any unit that moves a rule out of
that layer on purpose. Not done.
