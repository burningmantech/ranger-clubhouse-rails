# CSS refactor — the record

The written output of the CSS DRY workstream that shipped in `f7feb7ec` (28 planned units, the
two parked precedence passes, and the dark-mode hole one of them turned up). Kept in the repo
because it is the only place several measured facts are written down.

| file | what it is |
| --- | --- |
| [plan.md](plan.md) | Unit by unit: what each one changed, what it measured, what landed, and what was deliberately **not** done. The long one, and the one to read. |
| [findings.md](findings.md) | The census interpretation the plan was built from — the "why" behind the unit list. |
| [baseline.md](baseline.md) | What the behaviour harness captured, and how to rebuild it. |

## These are a record, not a live working copy

The `/css:census`, `/css:plan` and `/css:extract` commands read and write **`tmp/css-audit/`**,
which is gitignored and is still their working directory. Paths inside these documents that point
at `tmp/css-audit/…` are correct and were left alone — the raw census JSON and the compiled
baseline stylesheets genuinely live there, and are regenerable rather than tracked:

- `ruby bin/css_census.rb` rebuilds the census
- `bin/css_check --baseline` rebuilds the snapshot and stylesheet baselines, which are
  per-checkout and must be captured on a clean tree before the harness means anything

So a fresh clone gets the reasoning here, and regenerates the data.

## The tooling these describe

| | |
| --- | --- |
| `bin/css_check` | Behaviour harness: renders ~4,000 snapshots with class tokens sorted, diffs them, and diffs every compiled selector. Exits non-zero if a selector stopped compiling while something still writes it, or if a declared `@utility` is missing from the compiled utilities layer while something still writes it — see [baseline.md](baseline.md) for why the second is not a diff. |
| `bin/css_census.rb` | Duplicate-class inventory. |
| `bin/css_lint.rb` | The ratchet, against `.css-baseline.json`. `--strict` to fail. A class name built by interpolation fails in any mode, in views, helpers and `app/javascript`. |
| `bin/css_cascade.js` | Which utilities are losing to first-party CSS. **The harness is blind to CSS-only changes** — no markup moves, so every snapshot matches — and this is the instrument for that gap. Read its header before using it. |
| `lib/css_matchers.rb` | What counts as a palette colour, an arbitrary value, an `!important`, a class name glued to a JS placeholder — and which utilities a stylesheet declares and which a build compiled. Tested by `test/lib/css_census_matchers_test.rb`. |

Rules and rationale: [../css-dry-rules.md](../css-dry-rules.md).
