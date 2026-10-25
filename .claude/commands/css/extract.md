---
description: Extract one duplicated class cluster into the right abstraction — a Rails partial with strict locals, a ViewComponent, or a class-list helper — and verify the rendered HTML is unchanged.
argument-hint: "<cluster id from the census (D01) or a class string or a description>"
allowed-tools: Bash(ruby bin/css_census.rb:*), Bash(bin/css_check:*), Bash(bin/rails:*), Bash(bin/rspec:*), Bash(bundle exec:*), Bash(rg:*), Bash(git:*), Bash(cat:*), Bash(echo:*), Bash(head:*), Bash(tail:*), Bash(sed:*), Bash(find:*), Bash(sort:*), Bash(uniq:*), Read, Edit, Write, Glob, Grep
---

# Extract cluster: `$ARGUMENTS`

## Step 0

Confirm `tmp/css-audit/census.json` and `tmp/css-audit/plan.md` exist. If not, stop and say to
run `/css:census` then `/css:plan`.

## Your task

One cluster, one commit. Read `docs/css-dry-rules.md` before choosing a rung.

1. **Resolve the target.** If `$ARGUMENTS` is a cluster id, look it up in
   `tmp/css-audit/census.json`. Otherwise grep for the class string. Print the full call-site
   list and the count, and confirm it matches the census — if the code moved since the audit,
   re-run `/css:census` rather than working from stale line numbers.

2. **Read every call site before designing anything.** All of them, not a sample. The
   abstraction's API is determined by how the *last* two call sites differ from the first, and
   an interface designed from three examples always breaks on the fourth. Note for each site:
   what varies (text, href, icon, state), what is conditional, and what layout classes the
   parent is passing in.

3. **Choose the rung and justify it in one line.**
   - Repeated markup → a partial in `app/views/common/` (where the app keeps its shared partials), with
     **strict locals**: `<%# locals: (title:, href: nil, variant: :default, extra_class: nil) %>`.
     Strict locals are required; they turn a mis-render into a loud error and document the API.
   - Repeated markup that needs its own tests, slots, or real Ruby → a ViewComponent/Phlex
     component, but only if the app already uses one. Do not introduce a component framework
     inside a CSS refactor.
   - Same classes, different markup → a helper returning `token_list(...)`. Never build class
     strings with ternaries or interpolation.
   - Nothing above fits → say so and stop rather than reaching for `@apply`.

4. **Design the variant API from the evidence, not from imagination.** Variants that exist in
   the call sites get parameters; variants you can imagine do not. If a caller needs to
   override a default (pass `p-8` where the partial defaults to `p-4`), use `tailwind_merge`
   rather than concatenating and hoping about source order. If the gem is not installed, say
   so and either propose adding it or design the API so overriding is unnecessary.

5. **Convert one call site, run `bin/css_check`, and confirm the HTML diff is empty.** An
   empty diff proves the abstraction reproduces the original exactly. Only then convert the
   rest. If the diff is not empty on the first site, the abstraction is wrong — fix it before
   multiplying the error across twenty files.

6. **Watch for the silent failure mode:** if any class string ends up inside a Ruby file, a
   constant, or a helper, confirm that path is covered by Tailwind's source globs
   (`content:` / `@source`). `bin/css_check` should catch a dropped utility; check its
   compiled-CSS section explicitly rather than trusting the HTML diff alone.

7. **Verify and report:**
   - `bin/css_check` — HTML diff empty (or, if not, every line explained).
   - Re-run the census; show the duplicate cluster is gone and no new one appeared.
   - Look at one converted page per variant.
   - Report: the partial/helper created, its API, call sites converted, tokens removed, and
     anything left unconverted with the reason.

Do not batch multiple clusters into this run, however tempting the neighbouring duplication
looks. Note it and let me run `/css:extract` again.
