---
description: Replace hardcoded Tailwind palette colors (bg-white, text-gray-900, bg-blue-600) with daisyUI semantic theme tokens across Rails views, so the app can actually be themed and dark-moded.
argument-hint: "[scope, e.g. app/views/admin | 'grays only' | 'brand blues']"
allowed-tools: Bash(ruby bin/css_census.rb:*), Bash(bin/css_check:*), Bash(bin/rails:*), Bash(rg:*), Bash(git:*), Bash(cat:*), Bash(echo:*), Bash(head:*), Bash(tail:*), Bash(sed:*), Bash(find:*), Bash(sort:*), Bash(uniq:*), Read, Edit, Write, Glob, Grep
---

# Palette colors → daisyUI semantic tokens

## Step 0 — current hardcoded color load

```bash
ruby bin/css_census.rb --format text --top 60 | sed -n '/HARDCODED PALETTE/,/ARBITRARY VALUES/p'
```

## Your task

Read `docs/css-dry-rules.md` §1 rung 2. This is tier-two work: it must land **before**
partials are extracted, or every extracted partial bakes in a literal color and has to be
edited a second time.

1. **Read the theme before changing anything.** Find how daisyUI is configured — `daisyui: {
   themes: [...] }` in `tailwind.config.js` (daisyUI 4) or `@plugin "daisyui/theme" { … }` in
   the CSS entrypoint (daisyUI 5) — and quote the current token values. Every substitution
   below has to be checked against what those tokens actually resolve to, not against what
   their names suggest.

2. **Build the mapping table first, and show it to me before editing.** For each distinct
   palette class in the census, propose the token, and mark each row:
   - `exact` — the token's computed value equals the palette value.
   - `close` — a small visible shift; list the before/after hex so I can accept it.
   - `gap` — nothing in the theme covers this. Do **not** force it into the nearest token.
     Either add a color to the theme definition, or leave the class alone and list it.

   Neutral scales are the usual trap: `text-gray-500` on a `bg-white` card is not
   `text-neutral`, it is `text-base-content/60`. Opacity on the content token is how daisyUI
   expresses de-emphasis; reaching for a different color instead is what breaks dark mode.

3. **Pair foreground with background.** `bg-primary` without `text-primary-content` produces
   unreadable text under any theme that is not the one you were looking at. Every background
   token substitution must set or verify the matching `*-content`, and you should check the
   resulting contrast rather than assuming.

4. **Apply in one mechanical pass per color family**, one commit per family (grays, then
   brand, then status colors). Use exact-token replacement, never a broad regex over the file:
   `bg-blue-600` inside a comment, a data attribute, a JS string, or a seeds file is not the
   same as one in a class attribute.

5. **Verify after each family:**
   - `bin/css_check` — the HTML diff should be exactly the intended class swaps and nothing
     else; the compiled-CSS diff should show the palette utilities dropping out.
   - Re-run the census and show that the hardcoded-color count fell by the expected amount.
   - Toggle every theme the app ships (`data-theme`) and look at one page per family. This
     step is the whole point of the change — if you cannot toggle themes, say so, because it
     means the substitution is unverified.

6. **Report what did not convert** and why, as a list. A theme gap that gets papered over
   with "close enough" is worse than the hardcoded color it replaced, because it looks
   converted in the census and is wrong on screen.

Scope: $ARGUMENTS
