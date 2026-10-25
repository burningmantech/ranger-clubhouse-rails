---
description: Stage 3 — build the safety net before refactoring CSS - normalized rendered-HTML snapshots, a compiled-CSS baseline, and a check script that proves a class refactor changed nothing it should not have.
argument-hint: "[optional: paths or specs to cover]"
allowed-tools: Bash(bin/rails:*), Bash(bin/css_check:*), Bash(bundle exec:*), Bash(bin/rspec:*), Bash(bin/dev:*), Bash(npx:*), Bash(yarn:*), Bash(mkdir:*), Bash(cp:*), Bash(diff:*), Bash(ls:*), Bash(cat:*), Bash(git:*), Bash(echo:*), Bash(head:*), Bash(tail:*), Bash(sed:*), Bash(find:*), Bash(sort:*), Bash(uniq:*), Read, Write, Edit, Glob, Grep
---

# Establish the refactor baseline

## Step 0 — current state

Run these first with the Bash tool:

```bash
git status --short
ls -1 spec/ test/ 2>/dev/null | head
ls -1 app/assets/builds/ 2>/dev/null
```

## Your task

A CSS DRY refactor is behaviour-preserving by definition, which means it can be **checked
mechanically**. Build that check now, on the pre-refactor commit, or every later stage is
guesswork. Read `docs/css-dry-rules.md` §3 first — this command implements it.

1. **Refuse to proceed on a dirty tree.** If `git status` is not clean, stop and say so: a
   baseline captured over uncommitted work is worthless.

2. **Snapshot harness.** `test/support/css_snapshot.rb` is the harness. Run the suite with
   `CSS_SNAPSHOT=1` and every HTML, Turbo Stream or JSON-embedded-HTML response an integration
   test receives, plus everything a view test renders, is written as normalized HTML to
   `tmp/css_snapshots/<TestClass>/<test>-<hash>/<n>.html`, with class tokens sorted so
   reordering never shows in a diff. Extend it rather than adding a second
   one: to cover a page, add or extend a Minitest test under `test/controllers`,
   `test/integration` or `test/helpers` (the suite `bin/css_check` runs).

   Cover, at minimum: every page in the plan's call-site list, plus one page per layout, plus
   any page with a conditional/variant branch in a class attribute (those are where an
   extraction most easily loses a state).

3. **Capture the baseline** on the pre-refactor commit with `bin/css_check --baseline`. It runs
   the snapshot suite, copies `tmp/css_snapshots` to `tmp/css_snapshots_base`, and builds
   `tmp/css-audit/tailwind.base.css`. Record the snapshot count, byte size and rule count it
   prints in `tmp/css-audit/baseline.md`.

4. **`bin/css_check`** — extend the existing script rather than rewriting it. It re-runs the
   snapshot suite, rebuilds the stylesheet, and prints three things:
   - the normalized HTML diff against `tmp/css_snapshots_base` (empty = pure refactor)
   - which CSS selectors were **removed** from the compiled stylesheet, and which were added
   - a non-zero exit if any selector disappeared that is still referenced in the codebase

   That last check is the one that catches the expensive mistake: a class string moved into
   `app/helpers` or a Ruby constant that Tailwind's source globs do not scan, so the utility
   silently stops being compiled and the page quietly loses its styling in production.

5. **Fix the source globs now if they are wrong.** Verify that Tailwind scans every path where
   class strings will live after the plan runs — `app/views`, `app/components`, `app/helpers`,
   `app/presenters`, `app/javascript`, and any constants file. Add missing `content:` entries
   (Tailwind 3) or `@source` directives (Tailwind 4) and rebuild. This is a prerequisite, not
   a cleanup task.

6. **Prove the harness works.** Deliberately change one class in one view (e.g. `p-4` → `p-6`),
   run `bin/css_check`, and confirm it reports the diff. Then revert. A safety net that has
   never caught anything is not known to be a safety net. Show me the output of both runs.

7. Commit any harness or coverage additions on their own — no application changes in this commit.

Report: what is covered, what is not, and which pages a human will still have to look at
because no snapshot can tell you that a `btn` looks different from the hand-rolled button it
replaced.

Extra coverage requested: $ARGUMENTS
