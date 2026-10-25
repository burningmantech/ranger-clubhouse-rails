---
description: Stage 1 — read-only inventory of CSS class duplication across Rails views (Tailwind + daisyUI). Writes tmp/css-audit/census.{txt,json} and a findings summary. Never edits application code.
argument-hint: "[optional path filter, e.g. app/views/admin]"
allowed-tools: Bash(ruby bin/css_census.rb:*), Bash(mkdir:*), Bash(ls:*), Bash(cat:*), Bash(grep:*), Bash(rg:*), Bash(wc:*), Bash(git status:*), Bash(git log:*), Bash(echo:*), Bash(head:*), Bash(tail:*), Bash(sed:*), Bash(find:*), Bash(sort:*), Bash(uniq:*), Read, Glob, Grep, Write
---

# CSS census (read-only)

## Step 0 — stack fingerprint

Run these with the Bash tool before anything else. They read only.

```bash
ls -1 tailwind.config.js tailwind.config.ts config/tailwind.config.js app/assets/stylesheets/application.tailwind.css app/assets/tailwind/application.css app/assets/stylesheets/application.css 2>/dev/null
grep -hE "tailwind|daisy|view_component|phlex|tailwind_merge|erb_lint|erb-formatter" Gemfile package.json 2>/dev/null | head -30
ls -d app/views app/components app/helpers app/javascript 2>/dev/null
```

## Your task

This is an **audit only**. Do not edit a single application file in this command — not one
class attribute, not one stylesheet. The deliverable is a report. Any edit here destroys the
before/after baseline that later stages depend on.

1. Read `docs/css-dry-rules.md`. It defines the abstraction ladder and hard rules that the
   findings must be framed against. If it is missing, say so and use the rules in this repo's
   `CLAUDE.md`, or ask.

2. Run the census script and capture both formats:

   ```
   mkdir -p tmp/css-audit
   ruby bin/css_census.rb --min 2 --top 60 > tmp/css-audit/census.txt
   ruby bin/css_census.rb --min 2 --top 200 --format json > tmp/css-audit/census.json
   ```

   If `bin/css_census.rb` is not in the repo, say so and stop — do not improvise a grep-based
   substitute, because the whole point of the script is that the numbers are reproducible
   across runs and across sessions.

   Scope with `--roots` if $ARGUMENTS names a path.

3. Establish the ground truth the census cannot see, using Read/Grep:
   - **Tailwind major version and daisyUI major version** (from `package.json` / lockfile /
     `Gemfile.lock`). Every later recommendation depends on this.
   - **How the theme is configured**: `daisyui: { themes: … }` in `tailwind.config.js`
     (daisyUI 4) vs `@plugin "daisyui/theme" { … }` in the CSS entrypoint (daisyUI 5). Quote
     the current theme definition.
   - **Which paths Tailwind scans**: the `content:` array or the `@source` directives. Note
     explicitly whether `app/helpers`, `app/components`, `app/presenters` and any constants
     file are covered. This decides whether extraction to Ruby is safe at all.
   - **What component tooling already exists**: ViewComponent, Phlex, `tailwind_merge`, an
     existing `app/views/ui/` or `app/components/` directory, existing helpers that return
     class strings. Reuse beats inventing.
   - **Any hand-written CSS**: `@apply` blocks, custom component classes, legacy stylesheets
     still in the asset pipeline. List file and line counts.

4. Verify before reporting. Pick the top 3 duplicate clusters and the top 3 hand-rolled
   component candidates and open each cited file to confirm the finding is real and that the
   surrounding markup genuinely serves the same role. Drop anything that does not survive
   inspection and say which ones you dropped and why. The census is a regex; you are the
   judgement.

5. Write `tmp/css-audit/findings.md` containing:
   - Scale: files scanned, distinct class strings, duplicate clusters, redundant tokens.
   - **Correctness bugs first** — unscannable interpolated class names, `!important` fights,
     inline styles. These are broken now, not merely untidy.
   - **Theming debt** — hardcoded palette colors, with the count and what fraction of color
     usage is already semantic. Say plainly whether the app can currently be re-themed or
     dark-moded at all.
   - **Component debt** — hand-rolled daisyUI equivalents, each with the daisyUI class that
     replaces it, and how many call sites.
   - **Structural debt** — duplicate and near-duplicate clusters, each with a proposed rung
     from the ladder (component class / theme token / partial / helper / CSS layer).
   - **Blockers** — anything that must be fixed before refactoring is safe, especially source
     globs that do not cover the destination of a planned extraction.

6. Report in chat: the five findings with the best ratio of risk-or-tokens-removed to effort,
   each one sentence, with counts. Then stop and recommend `/css:plan`.

Do not propose fixes beyond naming the target rung. Sequencing is the next stage's job.
