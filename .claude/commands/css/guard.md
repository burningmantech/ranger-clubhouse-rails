---
description: Lock in the CSS cleanup — keep the house rules in AGENTS.md current, extend the lint script that fails on regressions (hardcoded palette colors, interpolated class names, duplicate clusters over threshold), and wire it into CI.
argument-hint: "[optional: 'strict' to fail the build, default is warn-only]"
allowed-tools: Bash(ruby bin/css_census.rb:*), Bash(ruby bin/css_lint.rb:*), Bash(bin/css_check:*), Bash(git:*), Bash(cat:*), Bash(ls:*), Bash(chmod:*), Bash(echo:*), Bash(head:*), Bash(tail:*), Bash(sed:*), Bash(find:*), Bash(sort:*), Bash(uniq:*), Read, Edit, Write, Glob, Grep
---

# Lock in the CSS rules

## Step 0 — current state

```bash
ls -1 AGENTS.md .claude/CLAUDE.md docs/css-dry-rules.md bin/css_census.rb bin/css_lint.rb .css-baseline.json 2>/dev/null
ls -1 .github/workflows/ 2>/dev/null
ruby bin/css_census.rb | head -16
```

## Your task

A DRY pass decays within a quarter unless the rules are written down where they will be read
and checked by something that is not a person's memory.

1. **Read the ratchet.** The ceiling is already recorded in `.css-baseline.json`. Run
   `ruby bin/css_lint.rb` to compare the current census against it. The numbers may go down,
   never up. A metric above its ceiling is a regression: fix the source, and never re-record
   the ceiling to absorb it. Lower the ceiling with `ruby bin/css_lint.rb --update-baseline`
   only when every metric is at or below its ceiling, and only with the user's approval.

2. **Check the CSS rules in `AGENTS.md`** (Styles > CSS Rules, imported by
   `.claude/CLAUDE.md`). It is the canonical copy: a pointer to `docs/css-dry-rules.md`, not a
   copy of it. Confirm it still states the five rules that actually get violated, and add only
   what is missing:
   - Check for a daisyUI component class before writing utilities.
   - Semantic theme tokens only in views — no `bg-white`, no `text-gray-*`, no `bg-blue-*`.
   - Never build a class name by interpolation; use a frozen lookup hash with `fetch`.
   - Extract on the third occurrence: a partial with strict locals, a helper, or an `@utility`.
   - No inline `style=`, no arbitrary values, no `!important`, without a written reason.

   Keep the five rules terse. The section's other paragraphs (the `@source` scan list,
   `@utility` nesting, `bin/css_check`'s blind spot) are load-bearing: read
   `docs/css-refactor/plan.md` before trimming any of them.

3. **`bin/css_lint.rb`** — extend the existing check rather than rewriting it. It is built on
   the census, suitable for CI and a pre-commit hook, and must fail (non-zero exit) on:
   - any class name built by interpolation (this is a correctness bug, always hard-fail)
   - hardcoded palette colors above the recorded threshold
   - duplicate clusters above the recorded threshold
   - new `!important` utilities or inline styles

   Its baseline (`.css-baseline.json`, lowered with `--update-baseline` as in step 1) compares against the recorded
   numbers rather than against zero, so the check is a ratchet on an imperfect codebase
   instead of a wall no one can get over. Default to warn-only unless `$ARGUMENTS` says
   `strict`.

4. **Wire it in**: a CI step in the existing workflow, and optionally a pre-commit hook that
   runs it only on changed view files. Follow whatever conventions the repo's other checks
   use rather than inventing a new pattern.

5. **Prove it fires.** Add a deliberate violation (an interpolated class name and a
   `bg-blue-600`), run the linter, show me it fails with a clear message that names the file,
   the line, and the fix. Then revert. Show me both runs.

6. **Leave the audit reproducible**: keep `bin/css_census.rb`, `docs/css-dry-rules.md` and the
   baseline JSON (`.css-baseline.json`) in the repo, and keep the note in `AGENTS.md`
   (Styles > CSS Rules) that `/css:census` regenerates the report.

Report: what the thresholds are, what will now fail a build, and the one or two rules that are
recorded but not machine-checkable — those are the ones code review still has to catch.
