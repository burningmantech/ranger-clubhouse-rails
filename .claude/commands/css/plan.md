---
description: Stage 2 — turn the CSS census into a sequenced, commit-sized refactor plan with risk ratings and verification steps. Writes tmp/css-audit/plan.md. Never edits application code.
argument-hint: "[optional focus, e.g. 'buttons only' or 'app/views/admin']"
allowed-tools: Bash(cat:*), Bash(ls:*), Bash(git log:*), Bash(git shortlog:*), Bash(rg:*), Bash(echo:*), Bash(head:*), Bash(tail:*), Bash(sed:*), Bash(find:*), Bash(sort:*), Bash(uniq:*), Read, Glob, Grep, Write
---

# CSS refactor plan

## Step 0

Check the census exists — `ls -la tmp/css-audit/`. If it does not, stop and say to run
`/css:census` first.

## Your task

Still no application edits. The output is a plan file plus a short chat summary.

1. Read `docs/css-dry-rules.md`, `tmp/css-audit/findings.md` and `tmp/css-audit/census.json`.
   If the census is missing, stop and say to run `/css:census`.

2. Group the findings into **work units**. A work unit is one commit: one concern, one
   reviewable diff, independently revertable. Good units look like:
   - "Replace the 14 hand-rolled buttons with `btn`" — one concern, one component.
   - "Map gray-scale palette classes to base-* tokens across app/views" — mechanical, wide.
   - "Extract the stat tile into `app/views/common/_stat_tile.html.erb`" — one partial, 6 call sites.

   Bad units mix concerns ("clean up the admin views") or span two rungs of the ladder.

3. Rank the units. Order is not by size — it is by dependency and risk:
   - **First: correctness.** Interpolated class names that never compile, `!important`
     fights, inline styles. These are bugs; they ship broken CSS today.
   - **Second: the theme.** Palette → semantic tokens must land *before* component
     extraction, or every partial you extract bakes in `bg-white` and has to be edited twice.
   - **Third: daisyUI component substitution.** Removes the most tokens per unit of risk and
     shrinks the surface that later extraction has to cover.
   - **Fourth: partial/component extraction** for what remains duplicated.
   - **Last: dead CSS and the CSS layer.**

   Within a tier, order by tokens removed per call site touched.

4. For each unit record, in a table plus a short paragraph:
   - id, one-line title, tier
   - target rung from the ladder and the concrete artifact (which daisyUI class, which partial
     path, which helper name)
   - call sites: exact `file:line` list from the census
   - **risk**: `mechanical` (pure token substitution, HTML output identical),
     `visual` (daisyUI component styling differs from the hand-rolled version — needs eyes),
     `structural` (markup shape changes — needs snapshot review and a screenshot)
   - **verification**: which of the three checks in the rules doc apply, and specifically which
     pages or specs to run
   - blockers / dependencies on other units

5. Flag anything that should **not** be DRYed. Say so explicitly with a reason. Common cases:
   - Two class strings that look identical but serve unrelated roles — coupling them creates a
     future conflict, and the abstraction will be torn apart within a quarter.
   - One-off marketing or email templates where local clarity beats reuse.
   - Anything in a directory being rewritten or deleted soon (check `git log` for churn).
   A plan with nothing in this section is a plan that has not thought about it.

6. Estimate honestly: per unit, roughly how many files change and whether a human needs to
   look at a screen. Total the redundant tokens removed so the effort has a number against it.

7. Write `tmp/css-audit/plan.md`. In chat, give the ordered unit list — id, title, risk, call
   site count — and name the first unit to run. Then stop.

Focus filter, if given: $ARGUMENTS
