# CSS refactor plan (2026-09-19)

Built from `tmp/css-audit/findings.md` (2026-09-19) and `census.json`, framed against
`docs/css-dry-rules.md`. **No application file was edited while planning.**

This replaces the Sep 5 plan, which is archived at `prev-2026-09-05/plan.md`. Of its 18 units,
16 have landed. Its U4 (the view `!important`s) and U16 (folding `mb-3` into `.instruction-list`)
were measured and declined, and both decisions still stand.

## Corrections made to the findings while planning

1. **The stylesheets `@source` line does nothing.** Tailwind never reads `.css` files as content,
   even when `@source` names them. I confirmed this with a scratch build, and findings §0 is fixed.
2. **New tier-1 bug: the margins written on `.instruction-list` terms don't apply.**
   `accessibility.css` does `@apply space-y-1` outside any `@layer`, which compiles to
   `:where(.instruction-list > :not(:last-child)) { margin-block-start: 0 }`. Unlayered CSS beats
   every layered utility, so the **111 `<dt class="mt-2">` and 2 `mt-3` do nothing**.
   - Checked on the live stylesheet on :3000: `margin-top` computes to **0px**, and the gap
     between an answer and the next question is **4px with or without `mt-2`**.
   - A control `<p class="mt-2">` outside the list computes to 8px.
3. **Withdrawn: findings §5.1's "fold `mb-3` into `.instruction-list`".** The Sep 5 plan measured
   it: the margin is present exactly when content follows the list, and absent when the list ends
   its container. That decline stands. Item 2 above is about the spacing *inside* the list, which
   is new.
4. **More interpolated class names than findings B4 listed:**
   - `table_helper.rb:296` builds `align-#{…}`.
   - `icon_helper.rb:53,58` build `ms-#{…}` and `me-#{…}`.
   - One of them is broken today: section badges ask for `size: "md"`, which becomes `text-md`
     (findings B3b).
5. **B3 (`small`) is in a partial that nothing renders** (unreferenced since the first commit). It
   moves to the dead-code unit.
6. **B5's striped-row `!`s are not scheduled.** They are documented at both sites
   (`table_helper.rb:36-45`, `SeverityStyleHelper`) and hidden behind the row `state:` API, so
   they sit under the parked precedence decision.
7. **The sidebar highlight probably goes stale after stream navigation.** This is from reading
   the code, not verified:
   - `active_links_controller.js:43-51` moves `active` and `aria-current` to the new link, but not
     the `!text-[#ffc107] !border-r-[#ffc107]` classes the server put on the old one.
   - U18 fixes it if it's real.

---

## Ordered units

Order is by gate, then tier, then tokens removed per call site within a tier; dependencies can
override that. "Eyes" means a person has to look at a screen: "yes" is a full check, "light" and
"spot" are a quick look.

| id | title | tier | rung | risk | sites | files | eyes | tokens − | census Δ |
| --- | --- | --- | --- | --- | ---: | ---: | --- | ---: | ---: |
| **P1** | ~~Run `/css:baseline`~~ **done**: see `baseline.md` (3,984 snapshots, `bin/css_check`) | gate | — | none | — | 7 | no | 0 | 0 |
| **P2** | ~~Make the Tailwind scan contract explicit~~ **done**: option A, `7c1ad116` | gate | CSS config | mechanical | 142 selectors | 2 | spot | 0 (−31.5 KB) | 0 |
| **P3** | Fix the census blind spots and widen the ratchet | gate | tooling | none | — | 2–3 | no | 0 | baseline rises |
| **U1** | ~~Photo-crop controls → ButtonHelper~~ **done**: `8657a71a` | 1 | 1 | visual | 5 | 1 | yes | 20 | −20 |
| **U2** | `.instruction-list` question spacing: remove 113 dead margins | 1 | 5 | visual (b) / mechanical (a) | 113 | 63 | yes (b) | 113 | 0 |
| **U3** | ~~Classes that compile to nothing → real utilities~~ **done**: `f56a83a3` | 1 | 2 | visual | 4 (+9 renders) | 3 | yes | 0 | 0 |
| **U4** | ~~Interpolated class names → frozen lookups~~ **done**: `cf41e43b` | 1 | 4 | mechanical | 8 expressions | 5 | no | 0 | 0 |
| **U5** | Agreement status tints → semantic tokens ✅ `b882c928` | 2 | 2 | visual | 5 lines / 9 tokens | 1 | yes | ~4 | 0 |
| **U6** | Hero "signature" amber → theme tokens ✅ `dd4df729` | 2 | 2 | mechanical* | 8 lines / ~26 tokens | 5 | light | ~14 | ~0 |
| **U7** | Neutral palette → base/text tokens ✅ `444317b3` | 2 | 2 | visual | 18 lines / ~27 tokens | 3 | yes | ~15 | ~0 |
| **U8** | Always-dark chrome (sidebar, navbar) → theme tokens ✅ `c9042b96` | 2 | 2 | mechanical | 16 tokens | 4 | light | ~0 | 0 |
| **U9** | Pin the print layout to the light theme (verify first) | 2 | 2 | visual | 1 | 1 | yes | +1 | 0 |
| **U10** | Navbar search trigger → ButtonHelper ghost button | 3 | 1 | visual | 1 | 1 | yes | ~11 | 0 |
| **U11** | Hand-rolled cards and `ui_card` → `card-standard` | 3 | 1 | visual | 7 (+11 `ui_card` renders) | 7 | yes | ~24 | −6 |
| **U12** | Checkbox tile partial | 4 | 3 | structural | 4 | 5 | no | ~30 | −20 |
| **U13** | Icon list item helper | 4 | 4 | structural | 21 | 11 | spot | ~100 | −66 |
| **U14** | Autocomplete item layout partial | 4 | 3 | structural | 3 partials | 4 | spot | ~60 | −45 |
| **U15** | Admin log data block helper | 4 | 4 | structural | 3 | 4 | no | ~12 | 0 |
| **U16** | Admin log text classes → constants | 4 | 4 | mechanical | 23 | 5 | no | ~85 | −70 |
| **U17** | Mobile full-width action buttons → ButtonHelper option | 4 | 4 | visual | 18 | 6 | yes | ~54 | −46 |
| **U18** | Sidebar active state into `sidebar.css` | 5 | 5 | visual | 1 | 3 | yes | 4 | 0 |
| **U19** | Delete dead Bootstrap helpers and the dead disclaimer partial | 5 | — | mechanical | 0 callers | 3 deleted | no | ~20 | 0 |
| **U20** | Delete unreferenced selectors and the docs-only utility | 5 | 5 | mechanical | 11 selectors | 5 | no | 0 | 0 |
| **U21** | Stop spelling a floor the size already carries | 4 | 4 | mechanical | 43 dead `min-h-9` | 35 | no | 43 | 0 |

\* mechanical only if the new tokens reproduce the palette values exactly (the sidebar
precedent in `application.css:118-132`).

**Totals.**
- About **580 class tokens** are deleted from source.
- Census redundant tokens (all roots) go from **2,895 to about 2,620 (−275)**, and the views-only
  lint figure from 2,774 to about 2,510.
- 10 units need a full screen check and 4 more a light or spot check.
- The redundant tokens that remain are mostly layout-primitive and typographic pairs in the
  *Do NOT DRY* list, or clusters below the third-occurrence rule. The metric isn't the goal.

---

## Gates: run these before tier 1

### P1 · Run `/css:baseline`

`docs/css-dry-rules.md` §3 requires three checks on every refactor commit:
- A: rendered-HTML equivalence
- B: a compiled-CSS diff
- C: a visual check

Nothing in `test/support/` does A today (no `css_snapshot` helper, no `tmp/css_snapshots`).
`.erb` has no linter, so without this no machine checks that a refactor left the markup alone.
**This is stage 3 of the pipeline, and the first thing to run.**

### P2 · Make the Tailwind scan contract explicit

**Done (2026-09-19), as option A in `7c1ad116`.** 142 selectors left the build, taking it from
595,062 to 563,506 bytes. That's 31.5 KB, not the 43 KB predicted, because scanning `app/lib`
brings back ~11.7 KB: words there are also daisyUI class names. "the timeline" in a
`ground_hog_day.rb:24` message string compiles the whole daisyUI `.timeline` component, and
Ruby's `select!` (`handle_checker.rb`, `intake.rb`, `people_by_location_report.rb`) compiles
`.select!`. No view uses either. Narrowing the line to
`app/lib/status_change_warnings.rb`, the one `app/lib` file with class strings, would drop that
too, at the cost of a contract with an exception in it. That's your call; it's not scheduled.
Verification is in `baseline.md` § Source globs.

**Artifact:** `app/assets/tailwind/application.css:1` and `:189-193`, plus the Styles section of
`AGENTS.md`.

Today, auto-detection scans the whole repo, so 146 classes that exist only in docs, skills, tests
and `.github` are compiled: **43 KB, 7.3 % of the minified sheet**. The list is in
`tmp/css-audit/p2-auto-only-selectors.txt`. It includes palette classes the house rules ban
(`text-red-800`, `bg-blue-600`, `text-gray-700`), and they would render if a view used them.
`AGENTS.md` describes an explicit list, but the config doesn't implement one.

- **Option A (recommended).** `@import "tailwindcss" source(none);`, keep the explicit `@source`
  lines for `app/views`, `app/helpers`, `app/javascript` and `config`, **add `app/lib`**
  (`status_change_warnings.rb` holds class strings), and **delete the inert
  `../stylesheets/**/*.{css,scss}` line**. Then make `AGENTS.md` say exactly that. This is one
  word plus two lines, and it makes the existing documentation true.
- **Option B.** Keep auto-detection, add `@source not` for `docs`, `ai`, `.github`, `bin` and
  `test`, and rewrite `AGENTS.md` to describe auto-detection.

**Risk: mechanical.** None of the 146 classes is used by app markup. The only hits in app code
are English words in Ruby (`diff`, `timeline`, `shrink`) and classes the explicit sources already
cover. **Verification:** B, where the diff must be exactly the 146 selectors; the system suite;
and C on two pages. **Needs your decision: A or B.**

### P3 · Fix the census blind spots and widen the ratchet ✅ `c90e4ddb` (+ `c99c367e`)

**Artifact:** `bin/css_census.rb`, `.css-baseline.json`, and `bin/css_lint.rb` if its roots are
hard-wired.

The census reports 2 palette colours where app code holds 102, and 2 `!` utilities where it holds
16. Changes:
- `PALETTE`: strip variant prefixes before matching, allow a `/NN` opacity suffix, and add the
  `neutral-NNN` hue. Bare `neutral` is daisyUI's semantic colour and stays allowed.
- `BARE_BW`: allow `/NN`.
- Scan class-like string literals in `.rb`: helper constants and `class_names(...)` arguments.
- Add `.js` to `exts`.
- Stop matching the Ruby assignment `style = "…"` as an inline style (`icon_helper.rb:40`).
- Then add `app/helpers` to the lint roots and re-baseline.

**U5 proved the hole is real, not theoretical.** `PALETTE` anchors a bare
`{util}-{color}-{shade}` (`\A...\z`), so it matches none of: a `dark:` prefix, a directional
infix (`border-l-green-500`), or an `/opacity` suffix (`bg-green-50/50`). Every string U5 just
deleted passed `--strict` clean, in a view or a helper. `dashboard_helper.rb`'s dead maps
(U19) carry the same pattern and are equally invisible.

**Verification:** the new census must reproduce the hand counts in findings §3: 102 pinned colour
uses in views and helpers, and 16 `!` utilities. **Needs your OK** to add helpers to the lint roots
(memory: `--update-baseline` needs the user's approval). Until this lands, a helper-only unit
can't move the ratchet at all.
**Done — the ratchet was lowered first (`c99c367e`), then widened (`c90e4ddb`).**

Lowering: eleven units had landed without touching the ceiling, so views had drifted 10 clusters
and 209 tokens below it. `duplicate_clusters` 299 → 289, `redundant_tokens` 2774 → 2565.

Widening, with the rise attributable: **views alone still read 289 / 2565 after the census
changes**, identical to before, so nothing about the existing measurement moved. Views + helpers
read 318 / 2756. Palette goes 2 → 32, almost all of it `dashboard_helper`'s dead maps (U19), which
no version of the tool had ever seen.

Four holes closed, not the one the entry predicted:
- `PALETTE` now allows a variant prefix, a directional infix and an `/opacity` suffix, plus the
  `neutral` ramp (shadeless `bg-neutral` stays clean).
- `ARBITRARY` counted `has-[:checked]:` **variants** as values. Fixed by testing only the utility
  after the last colon at bracket depth zero — 18 → 14.
- `IMPORTANT` looked at the whole token, so `hover:!bg-x` read clean and Tailwind 4's suffix form
  `hidden!` was caught only by luck.
- `STYLE_ATTR` matched the Ruby assignment `style = "regular"`.

Class strings in `.rb` and `.js` are now scanned — constants, helper arguments, Stimulus values —
guarded by `classy?`, which needs every token class-shaped and at least one a recognisable utility,
so `"app/assets/x.css"` and `"created_at desc"` stay out. A string already claimed as `class=` is
not double-counted.

**The rules live in `lib/css_matchers.rb` with a test** (`test/lib/css_census_matchers_test.rb`,
5 runs / 39 assertions) that pins the exact strings U5 deleted, the tokens this workstream
introduced (`ring-signature-edge`, `bg-chrome/80`, `card-standard`), and the variant/suffix cases.


---

## Tier 1: correctness

### U1 · Photo-crop controls → ButtonHelper

**Done (2026-09-19) in `8657a71a`.** Decisions made while in the file:
- **`:secondary`, not `:primary`.** Submit Photo is the page's one primary action, and five
  filled primaries above it would compete, which breaks the single-primary-action rule.
- **Default size plus `min-h-9`,** the navbar Menu button's precedent. The one-off `lg:btn-sm`
  knob is gone, and so is its only compiled selector.
- **Labels from `lg`,** not `sm`, which is kept for field widths.
- **The icon rides in the label,** the house way (`bmid/manage_helper.rb:300`), so a lone icon
  stays centred. `aria-label` names each control in full.

Checked with a throwaway system test on the test DB, since dev has no pending photo:
- at 1280px, 36px tall and labelled
- below `lg`, 41×36 and icon-only with the icon offset 0
- light and dark themes
- `bin/css_check`: only the crop snapshot changed

A harness fix rode along as `08316c42`, masking clock-measured durations.

The original sizing for this unit, kept for the record:

| | |
| --- | --- |
| Rung / artifact | 1: daisyUI `btn` through `ButtonHelper#button_action(label, :primary, nil, icon:, size: "base", class: "lg:btn-sm", data: { action: … }, title:)` |
| Sites | `profile_photos/crop.html.erb:78,82,86,90,94` |
| Risk | visual: these buttons have never had button styling |
| Verification | A: diff expected (btn classes). C at `/me/profile/photos/:id/crop` (needs an uploaded photo), 375 px and desktop, both themes; confirm ≥ 36 px height. No test mentions `photo-cropper`. |
| Depends | P1 |
| Estimate | 1 file · eyes yes · −20 tokens (census D29) |

Since `907d14b0` (2026-03-06) deleted `@utility btn-base`, these five controls have carried only
`btn-primary`. In daisyUI 5 that class only sets variables, so every visible property is missing.
The labels are `hidden sm:inline`, but the design rule reserves `sm:` for form-field width, so
`lg:inline` is the compliant choice. Decide that while you're in the file. The `bg-gray-800` and
`bg-gray-500` on lines 102 and 104 stay; see *Do NOT DRY*.

### U2 · `.instruction-list` question spacing ✅ `74ca7e40`

| | |
| --- | --- |
| Rung / artifact | 5: the existing class, `app/assets/stylesheets/accessibility.css:83` |
| Sites | 111 `<dt class="mt-2">` + 2 `<dt class="mt-3">` in 62 view files; full list in Appendix A |
| Risk | **visual** under (b); **mechanical** under (a) |
| Verification | A: every diff hunk must be a `class="mt-2"` or `class="mt-3"` removal on a `<dt>`. C: computed `margin-top` of a non-first `<dt>` is 8px under (b) and 0 under (a). Pages: the register form, `/people/create-account`, `/me/profile/:section_id/edit` (identity), `/me/profile` (the `profile/show` lists), `/` (login). |
| Depends | P1 |
| Estimate | 63 files · eyes yes (b) · −113 tokens (single-class attributes, so the census can't see them) |

All 106 lists share one role: question/answer pairs. Every one of the 111 `mt-2` sits on a
non-first `<dt>`, and none of them has ever rendered. Choose one:
- **(b) Recommended.** Add `.instruction-list dd + dt { margin-block-start: calc(var(--spacing) * 2); }`
  next to the existing rule. It must be **unlayered**, or the `:where()` rule still wins. Then
  delete the 113 tokens.
  - This gives the spacing the authors wrote 111 times: the gap between pairs goes from 4px to 8px.
  - It also reaches 13 later `<dt>`s in 6 files that never had `mt-2`: `profile/show` 4,
    `sessions/new` 3, `profile_languages/index` 2, `_burn_weekend_shift_recommendation` 2,
    `person/work_history/index` 1, `_hours_not_eligible` 1.
  - The crop page's `mt-3` would have given 12px; it gets 8px.
  - `_mvr_eligible` doesn't move: its `space-y-3` margin collapses with the new one.
- **(a) Fallback.** Delete the 113 tokens and leave the 4px rhythm as it has always rendered.

**Done — `74ca7e40`, option (b).** 531 snapshots, every diff line a `<dt>` class removal and
nothing else. Stylesheet +68 bytes, +1 rule.

Measured before: every gap in the list was **4px** — inside a pair and between pairs alike — and
both `mt-2` and `mt-3` computed `margin-top: 0px`. So a question grouped with the answer *above*
it exactly as strongly as with its own, in the one component whose job is making Q&A scannable.
Measured after: **4px inside a pair, 8px before the next question**, first `<dt>` still flush.

The rule is `.instruction-list dd + dt { margin-block-start: calc(var(--spacing) * 2) }`,
unlayered, with a real selector — `:where()` would tie 0-0-0 with `space-y-1`'s own.

Both preconditions checked before the sweep: all 62 files use `instruction-list`, and no margined
`<dt>` was the first in its list.

**No ratchet movement**, exactly as the estimate warned: `classy?` requires two or more tokens, so
a bare `class="mt-2"` was never counted as debt. The 113 were invisible to the census in both
directions.

**The docs described a feature that does not exist.** `DESIGN-GUIDE.md` and the `design-content`
skill both state that `<dt>`/`<dd>` carry "Q:" and "A:" prefixes in brand and muted colour, drawn
with `::before` and spaced by `pl-5`. There is no such rule in `accessibility.css` and the
computed `::before` content is `none`. DESIGN-GUIDE's "Styling" list was wrong in every line too
(`space-y-2`, `relative pl-5`). All corrected to describe what exists, plus the two stale
`<dt class="mt-2">` examples in `design-forms` and DESIGN-GUIDE.
**Built — `bb3acf73`.** Decoration, not content: `content: "Q:" / ""` so a screen reader
gets an empty string rather than re-announcing what the `<dl>` already says. `boxes.css` needed a
line too, because `.box-warning *` cannot match a pseudo-element and the Q: kept its brand blue
inside an amber box.


### U3 · Classes that compile to nothing → real utilities

**Done (2026-09-19) in `f56a83a3`.** One deviation from the plan: the alert heading rows got
**`bg-base-200`, not `bg-base-300`.** The plan assumed striped tables, but both are
`striped: false`. Their rows are `base-100` and hover to `base-300`, so `base-300` would read as a
permanently hovered row. `base-200` is the column header's own band.

Verification:
- `bin/css_check`: 263 snapshots changed, and a line-by-line check proved each one differs only
  by `text-md`→`text-base` or `bg-surface-secondary`→`bg-base-200`. The stylesheet is unchanged.
- C: `/me/profile`, both themes. The heading rows match the thead (`0.96` light, `0.22` dark)
  over `base-100` rows.
- C: `/timesheets/early-late-checkins`. The section badges are 14.4px, and no `text-md` is left.

`/simplify` skipped two findings: the unused `ui_card_title` sizes (an API change) and moving the
heading rows onto `t.row`/`t.cell`, which would bring data-row hover and padding onto a heading.

The original sizing for this unit, kept for the record:

| | |
| --- | --- |
| Rung / artifact | 2: real tokens and scale steps |
| Sites | `profile/_alerts.html.erb:35,76` `bg-surface-secondary` → `bg-base-300` (base-200 is already the stripe colour; `ROW_STATES[:total]` precedent). · `ui_components/ui_section_helper.rb:120` `size: "md"` → `size: "base"` (the 2026-09-03 decision). · `ui_components/ui_card_helper.rb:26` `md: "text-md"` → `"text-base"` |
| Risk | visual: the two group-header rows gain a fill; the 9 section badges go from 0.875 to 0.9 rem; `ui_card_title` has no `:md` caller, so it doesn't change |
| Verification | A: diff limited to those tokens. C at `/me/profile` (alerts table), and a `ui_section … badge:` page, e.g. `timesheets/early_late_checkins`. No test pins these strings. |
| Depends | P1. **Blocks U4**, whose lookup would raise on `"md"`. |
| Estimate | 3 files · eyes yes · 0 tokens |

### U4 · Interpolated class names → frozen lookups

**Done (2026-09-19) in `cf41e43b`, and folded into the baseline.** Rendering is identical:
- 447 snapshots differ only by three dead classes (`icon-secondary` ×797, `icon-primary` ×25,
  `box-primary` ×1).
- The stylesheet is unchanged.
- 4,854 tests ran with 0 errors, so no lookup misses a value used today.

Found along the way:
- `vc_stage_badge` passes `:info`, so `icon-info` stays in the tint map.
- `roster_action_variant` returns `:primary` (a button variant) as a **callout** type. The grant
  callout has always had an info icon on an untinted box. U4 keeps that on purpose; whether to
  tint it is a design question for the user.
- `/simplify`'s altitude reviewer confirmed the lint could never have caught these eight sites
  (views-only roots, and only `class=`/`class:` literals). That is more evidence for **P3**.

The original sizing for this unit, kept for the record:

| | |
| --- | --- |
| Rung / artifact | 4: frozen `{ key => "literal" }` hashes read with `fetch` (house rule 1) |
| Sites | `ui_components/badge_helper.rb:37` (`text-#{size}`), `:50` (`icon-#{variant}`) · `table_helper.rb:156` (`text-#{size}`), `:296` (`align-#{alignment}`) · `icon_helper.rb:53` (`ms-#{…}`), `:58` (`me-#{…}`) · `ui_components/notice_box_helper.rb:24` (`box-#{type}`) · `vc/applications_helper.rb:48` (`vc-progress-#{state}`) |
| Risk | mechanical. HTML is identical except that `icon-primary` and `icon-secondary` drop off the icons of at least 34 badges; they match no rule today, so rendering is identical too |
| Verification | A: identical apart from those two dropped tokens. B: the compiled CSS must not change, because every value was already compiled through a literal somewhere else. Specs: `test/helpers/table_helper_test.rb`, `test/system/me/awards_test.rb` and `test/controllers/shift_operations/mass_signout_controller_test.rb` (they pin `box-accent`), and the qualifications and languages-known controller tests (they pin `icon-success`) |
| Depends | U3 |
| Estimate | 5 files · eyes no · 0 tokens |

Values in use today: badge sizes xs, sm and base; table sizes base and sm; row align `:middle`;
icon margins 1 and 2. `fa-#{style}`, `fa-#{name}` and `fa-#{size}` (`icon_helper.rb:48,62`) are
**out of scope**: they resolve against the plain-CSS FontAwesome subset, not Tailwind, and
`verify_icon_available!` already guards the names.

---

## Tier 2: the theme

These must land before any tier-4 extraction, so no new partial bakes in a palette colour.

### U5 · Agreement status tints → semantic tokens

| | |
| --- | --- |
| Rung / artifact | 2: `success` / `warning`, with `base-300` or `line` for neutral |
| Sites | `agreement_helper.rb:6-7` (border map), `:13-14` (tint map), `:43` (fallback) |
| Risk | visual: hues move to the theme's own. The `border-l-gray-300` fallback has **no dark twin** today and draws a bright border in dark mode, which this fixes. |
| Verification | A (`Me::AgreementsControllerTest` snapshots the pending and signed states) and C at `/me/agreements`, both themes, using the navbar toggle (it sets both `.dark` and `data-theme`). Check text contrast on each tint by computing `color-mix`, not by reading canvas pixels. |
| Depends | P3, if you want the ratchet to register the drop |
| Estimate | 1 file · eyes yes · ~−4 tokens (the `dark:` twins go) |

**Done — `b882c928`.** The borders are the non-directional `border-success/30` /
`border-warning/30`, exactly as `UiAccentCardHelper::BORDER_VARIANTS` spells them: the card
already sets its width with `border-l-4`, so only the left edge is drawn and the directional
spelling bought nothing. Every class was already compiled, so the stylesheet came out
**byte-identical** — 563419 bytes, 4102 rules, no selector added or removed. Two snapshots
changed, both the agreement card. `not_available` keeps its pre-existing `border-l-secondary`;
it was not part of this unit. The two readers use `fetch`, and the dead `unless config` guards
in `agreement_badge` / `agreement_icon` went with the dead fallbacks.

**Changed during `/css:baseline`.** `dashboard_helper.rb`'s `STEP_BORDER_COLORS`, `STEP_BG_COLORS`,
`dashboard_step_border_class` and `dashboard_step_bg_class` are never called: no caller in
`app/`, `test/`, `lib/` or `config/`, and no dynamic `send`. The dashboard's task cards take their
colour from `dashboard_step_variant`. So 27 of findings §3's 102 pinned colours are dead code, and
they move to U19.

### U6 · Hero "signature" amber → theme tokens

| | |
| --- | --- |
| Rung / artifact | 2: new `@theme` colours with `.dark` values in `application.css`, e.g. `--color-hero-ring`, `--color-hero-tile`, `--color-hero-tile-content`, following the sidebar block at `:118-132` |
| Sites | `ui_components/ui_hero_panel_helper.rb:19,21,24,26,40` · `ui_components/ui_progress_box_helper.rb:8` (icon badge gradient and ring) · `common/_trophies.html.erb:9` · `components/hero-panel.css:11` |
| Risk | mechanical, **if** each token reproduces its light and dark palette value exactly, including alpha. Unify the alphas only as a separate, reviewed change. |
| Verification | B, plus a light C at `/me` (welcome hero stats), `scheduling/event_stats`, `/me/awards` and the dashboard progress box, both themes |
| Depends | **design-rules approval**, because this names new colour tokens. If that's pending, run U7 first. |
| Estimate | 5 files · light check · ~−14 tokens |

DESIGN.md calls the faint amber ring the app's recognisable signature. Right now it is spelled out
in palette classes in four places and cannot be re-themed.

**Done — `dd4df729`.** Three tokens: `--color-signature-edge` (the outline) plus `--color-hero-tile`
and `--color-hero-tile-content` (the amber stat tile), declared beside `--color-heading` and
`--color-body-subtle`, which are the right precedent — the sidebar block is *not*, because its own
comment says it carries no dark override.

- **The name matters more than the plan assumed.** `--color-hero-ring` was wrong twice over: `hero`
  names a call site (two of the four consumers are a trophy badge and the dashboard progress badge),
  and `ring` bakes the property in, against `--color-line` → `border-line`. Role noun, no stutter.
- **The progress box was folded in after all** (user's call). Its ring was the same amber at `/50` in
  both themes rather than `/40` and `/30` — drift, not a decision. Its warm gradient is still raw
  palette on purpose; turning it into a theme-derived mix repaints the badge. That is a unit of its
  own, and `SECTION_BASE` one line above it (`bg-white dark:bg-gray-800`) belongs to **U7**.
- **Colour equality was proven, not assumed:** a baked-in alpha and Tailwind's `/30`
  (`color-mix(…, transparent)`) rasterize to the same sRGB bytes — ring `234,202,178`, tile
  `215,194,180`.
- Stylesheet −8 palette selectors / +3 token selectors, −1242 bytes. 12 snapshots changed, all the
  trophy badge and the progress badge.
- `TILE_BASE`/`LABEL_BASE`/`VALUE_BASE` extracted (third occurrence); `:warning` and `:pending` share
  one `AMBER_TILE`. Neither has a caller today — the only live `stat_badge`s are `:flame` and
  `:award` — but both are documented options, so they were kept rather than dropped. **Open: delete
  them in U19?**
- Docs that would have misled the next unit were fixed: `design-foundations` listed the legal bridge
  tokens (a reader would have concluded `ring-signature-edge` compiles to nothing), and
  `css-dry-rules.md` rung 2 mapped `bg-amber-*` → `warning` with no exception row.
- `public/*.html` hand-copy the two oklch values and cannot consume a token; their comments now name
  it so `grep signature-edge` finds them.
- Pre-existing, untouched: the progress badge has no `shrink-0` and squeezes to 20×40 on a phone.

### U7 · Neutral palette → base/text tokens

| | |
| --- | --- |
| Rung / artifact | 2: the ladder's standard map |
| Sites | `ui_components/ui_progress_box_helper.rb:7`: `bg-white dark:bg-gray-800` → `bg-base-100` (or `-200` after C), `ring-gray-200/60 dark:ring-gray-700/60` → `ring-line` or `ring-base-300` · `me/vehicles_dashboard/_eligible_positions.html.erb:12` → `text-stone-muted`, `:16` → `bg-base-200` · `common/_timesheet_confirm.html.erb:13,40,43,65,69,79,82,94,100,107,108,117,118`: drop the `dark:text-stone-*` overrides, putting `text-heading` on the headings and letting the rest inherit `text-body`; `hover:text-stone-700 dark:hover:text-stone-300` (lines 40 and 79) → `hover:text-heading` |
| Risk | visual. Dark-mode surfaces move furthest: gray-800 is L≈28, base-100 is L 18. |
| Verification | A and C at `/me` (progress box), `/me/vehicles` and `/me/timesheet` (confirm section), both themes |
| Depends | P1. Must land **before U13**, whose sites include `_timesheet_confirm`. |
| Estimate | 3 files · eyes yes · ~−15 tokens |

**Done — `444317b3`.** 11 palette selectors out, **none in** — every replacement was already
compiled. −1498 bytes. Three snapshots, all pure class swaps.

- The progress box took `bg-base-100 border border-line`, not the plan's `ring-line`: that class is
  written nowhere and compiled nowhere, while `border-line` is in thirty-odd files and is what
  `UiCardHelper::CARD_BASE` and `.box-default` already say. In this light theme base-100 (97.5) is
  *lighter* than base-200 (96) and base-300 (92), so no token can lift a card above the page —
  which is why every card here is flat fill plus an outline. The box now matches its neighbours.
- The list panel took `bg-default`, not `bg-base-200`: same computed value, but its three siblings
  in `me/vehicles_dashboard/` all say `bg-default`, and design-foundations reserves that spelling
  for neutral inner boxes.
- **Three classes in `_timesheet_confirm` could never paint.** `boxes.css` keeps
  `.box-warning *:not(.btn, .badge) { color: inherit }` outside `@layer` on purpose, so it beats any
  `text-*` utility on a descendant; inside the warning state a `text-heading` renders amber.
  Verified in the browser: heading ink wins inside `box-accent-success` and `box-accent-error`, and
  loses inside `box-accent-warning`. See [[unlayered-css-beats-utilities]].
- **The planned `hover:text-heading` was a no-op**: `ACCORDION_SUMMARY_BASE` already carries
  `text-heading`, and no other accordion in the app changes colour on hover. Both summaries lose the
  hover and the now-dead `transition-colors`. **Open design question: `collapse-title` has no hover
  affordance anywhere**, which design-foundations says a clickable element should have.
- Emphasis stayed weight, not ink (`text-colors.css` says so outright), so a lede and two branch
  labels kept `font-semibold` alone. Those two labels are questions, and design-content says a
  question is the signal it belongs in body copy — promoting them to real `<h4>`s would mean
  rewriting the copy first. **Left for a content pass.**
- After U7 the raw-palette sweep over views+helpers is **18 hits in 6 files**: the crop page
  (documented exception), `layouts/print.html.erb` (U9), navbar + sidebar chrome (U8), and
  `ui_sticky_progress_helper.rb` / `me/message_helper.rb` (unclassified).

### U8 · Always-dark chrome (sidebar, navbar) → theme tokens

| | |
| --- | --- |
| Rung / artifact | 2: `@theme` tokens beside the existing `--color-sidebar-*` |
| Sites | `sidebar_helper.rb:23-38` (`text-white` ×8) · `:73` `bg-[#000000]` → new `--color-sidebar` (`--color-sidebar-title` is the same black on purpose, "same as the aside"; consider `var(--color-sidebar)`) · `:93` `border-[#101010]` → the **existing** `border-sidebar-divider` · `:140` `#ffc107` ×2 → new `--color-sidebar-active` (the `!`s stay until U18) · `components/sidebar.css` (`@apply text-white` in `sidebar-link-hq`, `sidebar-group-title-hq`, `sidebar-link-default`) · `application/_top_menu.html.erb:1` `bg-black/80 text-white/80` → navbar tokens |
| Risk | mechanical, if the values are exact. Mapping `text-white` onto the existing `--color-sidebar-content` (#f0f0f0) would be a visible change and a separate decision. |
| Verification | B. Update `test/helpers/sidebar_helper_test.rb`, which pins `ffc107`. Light C in the `me`, `admin` and `hq` sidebar themes and on the navbar at 375 px. |
| Depends | P1. **Blocks U18.** |
| Estimate | 4 files · light check · ~0 tokens; removes 3 arbitrary values and 4 hex literals |

**Done — `c9042b96`.** 7 selectors out, 6 in. **No arbitrary value is left anywhere Tailwind
scans.** 3429 snapshots changed, because the chrome renders on every page, and the changed class
tokens are exactly the six swaps.

- Only **one** value turned out to be shared: the black. `--color-chrome` carries it (the navbar
  wears it at 80%). The ink is sidebar-only, so it kept its existing name, `--color-sidebar-content`
  — no rename.
- **The navbar's ink class was dead and is deleted, not tokenised.** The bar has 31 text nodes and
  every one sets its own colour through `neutral-content` (`navbar.css:12-22` explains why);
  forcing the `<nav>` to red moves none of them. Tokenising it would have minted a second name for
  a role `neutral-content` already fills, at a different value — it flips 98/90 with the theme,
  the chrome ink does not.
- **`--color-sidebar-title` is deleted**, not converted: `sidebar.css` already called its black
  "the same as the aside", so it applies `bg-chrome`.
- `--color-sidebar-active` stays a **hex literal**. `#ffc107` → `oklch(84.42% 0.1722 84.93)` renders
  `color(srgb 1.00002 0.756914 0.0266349)` against the hex's `color(srgb 1 0.756863 0.027451)` —
  same 8-bit colour, not the same value, and a hair outside sRGB.
- **Tailwind 4.3.3 does follow `var()` between `@theme` declarations** (probed against the actual
  binary), so a token may reference another. The earlier assumption that it would be tree-shaken
  was wrong. See [[tailwind-scan-contract]].
- The user approved the one visible change: eleven `text-white` and one `text-sidebar-content` on
  the same black become one ink, 21:1 → 18.9:1.
- **`!border-r-[5px]` stays** and now carries the written reason AGENTS.md wants: it is the width
  `old_sidebar.scss` used and is not a step on Tailwind's scale (0/1/2/4/8). U18 moves it to CSS.
- Left on purpose, flagged to the user: the sidebar utility table in `docs/DESIGN-GUIDE.md` is
  stale well beyond this unit (pre-daisyUI strings for four utilities, two utilities that do not
  exist, a 180px logo that is 140px). Only the rows U8 made wrong were fixed.
- After U8 the raw-palette sweep is **8 classes in 4 files**: `layouts/print.html.erb` ×3 (U9),
  `profile_photos/crop.html.erb` ×2 (documented exception), and **3 unclassified** —
  `ui_sticky_progress_helper.rb` (`bg-white dark:bg-gray-900`) and `me/message_helper.rb`
  (`bg-white`).

### U9 · Pin the print layout to the light theme ✅ `b93ac02c`

| | |
| --- | --- |
| Rung / artifact | 2: `layouts/print.html.erb:6` → `<html lang="en" data-theme="light">` with no `.dark` |
| Sites | 1 |
| Risk | visual (on screen only) |
| Verification | **Reproduce first.** Emulate a dark OS (on layouts with no toggle, `prefers-color-scheme` decides), open a print view such as the training sign-up sheet, and compare the on-screen heading colour with the surface. If the mismatch isn't there, drop the unit. |
| Estimate | 1 file · eyes yes |

**Done — `b93ac02c`. The bug reproduced, and it is worse than this entry guessed.** Not a mismatch
of taste: on a dark OS a print page rendered **headings at 1.38:1** against the surface. Measured,
both states: bare `<html>` + `prefers-color-scheme: dark` → 1.38:1; `data-theme="light"` → 12.71:1.
Body text was fine either way (8.45 / 8.59), which is why it survived — `base-content` is daisyUI's
own and moves with the surface, so only headings vanished.

Mechanism, each link verified: `application.css:4` declares `dark --prefersdark`, daisyUI compiles
`@media (prefers-color-scheme:dark){:root:not([data-theme])}`, `--color-heading` /
`--color-body-subtle` / `--color-line` are overridden only under `.dark, [data-theme="dark"]`, and
the theme controller lives in `_top_menu` — which this layout does not render. 41 snapshots across
9 test classes changed by exactly one line.

**Bigger finding, NOT fixed here — `layouts/application.html.erb:2` has the same hole.** It is a
bare `<html lang="en">`, and `_top_menu` (which carries `data-controller="theme"`) renders only
`if authenticated?` at `:42`, in `connect()`, after JS boot. So a dark-OS user gets the incoherent
state **permanently on any unauthenticated page through that layout**, and as a first-paint flash on
every authenticated one. Dropping `--prefersdark` needs **two** edits — `application.css:4` and
`:47` (`prefersdark: true` in the theme block re-enables it alone; the bundle carries two such media
blocks, one with daisyUI's stock palette and one with ours). The complete fix pairs that with a
blocking inline `<head>` script that applies the stored theme before first paint. **Needs the
user's decision: it changes first paint for every dark-OS user.**

---

## Tier 3: daisyUI component substitution

### U10 · Navbar search trigger → ButtonHelper ghost button ✅ `7a46ff8f`

| | |
| --- | --- |
| Rung / artifact | 1: `button_action(label_html, :ghost, nil, data: { action: "search-bar#open" }, aria: { label: … }, class: …)`. `render_button_content` accepts an HTML label, so the icon, the `lg:` label and the `<kbd>` go inside it. |
| Sites | `application/_search_bar_placeholder.html.erb:52` |
| Risk | visual. daisyUI 5.7's `btn-ghost` paints `base-content`; `navbar.css` already overrides that for the other navbar buttons, so confirm it reaches this one. |
| Verification | C on the navbar at 375 px (icon only, ≥ 36 px) and desktop, both themes. Spec: `test/system/search_bar_hotkey_test.rb`. |
| Estimate | 1 file · eyes yes · ~−11 tokens. This is the one raw `<button>` left that breaks the ButtonHelper rule. |

**Done — `7a46ff8f`.** 11 hand-rolled classes → `btn btn-ghost btn-sm` plus 4 kept.
`.hover:bg-neutral-content/10` out, nothing in. 2627 snapshots changed by the trigger alone.

- **The estimate's last sentence was wrong.** `app/views/application/_top_menu.html.erb:53` is a second
  raw `<button>`, and it is exactly `button_action`-shaped: ghost, Stimulus `data-action`,
  `aria-label`, no form. (The other three raw buttons are `role="tab"` elements and the camera
  shutter, all legitimately outside ButtonHelper.) **Done in U10b.**
- Spacing is margins, not `gap-2`: `buttons.css:8` forces `gap: 0 !important` on every `.btn`, so a
  gap utility compiles and loses. The margin hangs on the element that hides below `lg` — the
  `crop.html.erb:86` idiom — so no `lg:` prefix is needed and the stylesheet gains nothing.
- `icon:` could not be used: `render_button_content` builds the icon from a literal options hash
  with no class hook (so no `/70` dimming) and adds an unconditional `me-2` (8px off-centre in the
  icon-only button).
- Deliberate visual changes: hover is now daisyUI's ghost pill (navbar.css sets `--btn-rest-fg`
  only, by design), and the label drops 14px → 12px, matching Menu and Bug Report.
- Measured: 128×36 with 8px gaps at 1280; 36×36 icon centred at 375 **and 320**, with no bar
  overflow at 320 despite the `flex-shrink: 0` that `.btn` brings.

### U10b · Theme toggle → ButtonHelper ✅ `961f2241`

| | |
| --- | --- |
| Sites | `application/_top_menu.html.erb:53` |
| Risk | visual, and it carried a **decision**: the toggle had no size class, so it rendered at daisyUI's default **40px** while every other control on the bar was 36px (measured: `[36, 36, 40, 36, 36]`). `button_action` always emits a size class, so the conversion had to pick one. |
| Estimate | 1 file · eyes yes · needs the user's call on the 4px |

**Done — `961f2241`.** The user took **36px** (`btn-sm`, the default) and kept the **circle**.
Measured after: `[36, 36, 36, 36, 36]`. `btn-circle` takes its width and height from `--size`
(`width:var(--size);height:var(--size);border-radius:3.4e38px`), which is exactly why the missing
size class showed up as a size bug — and why `btn-sm` fixes it without touching the shape. The
circle stays on purpose: it is the only round control on the bar, but a circle reads as a state
toggle rather than an action, so it is not drift.

- **The icon span's `w-5 h-5` was dead markup.** `theme_controller.updateIcon()` does
  `icon.className = ""` and then writes the `<i>` itself, so the classes are erased on its first
  `connect()` and never survive to a painted frame. The live DOM shows `class=""`. Dropped.
- The controller is on the `<nav>` (`data-controller="theme mega-menu"`), so the button passes
  `nil` as `button_action`'s controller argument and carries only `data: { action: … }` — the
  same shape U10 used for the search trigger.
- Rendered delta is two lines on every page: `btn-circle btn-ghost` → `btn-circle btn-ghost
  btn-sm` plus `name="button"`, and the span loses its classes. 3429 snapshots, one shape.
  Stylesheet unchanged — `w-5`/`h-5` survive in five other files.
- Verified in the browser at 375px and 1280px in both themes: 36×36, still circular, no bar
  overflow, sun/moon still swaps on click.

**Trap found while folding this unit — see the `tailwindcss:watch` note in the harness section.**

### U10c · `gap: 0 !important` on `.btn` ✅ `d1374ce4`

`buttons.css:8-10` had no written reason, which AGENTS.md requires. Migration debris: it arrived
in `3f9369d6`, two commits after `907d14b0` replaced the hand-rolled Flowbite `btn-*` system with
daisyUI's `.btn`, whose own `gap: .375rem` then stacked on top of every margin the Flowbite
buttons already had. Suppressed rather than reconciled.

The unit as planned: delete the `!important`, delete the `end: 2` in `render_button_content`, and
delete every hand-written margin beside a button icon, leaving daisyUI's gap as the single number.
**Done exactly that — user took 6px (daisyUI's own) over keeping today's 8px.**

**It is a bug fix, not only tidying.** Two call sites were already asking for a gap and being
ignored by the `!important`:

| site | asked for | rendered |
| --- | --- | --- |
| `.mega-menu-cat-btn` (`@apply … gap-3 …`) | 12px | 0 |
| `vehicles/paperwork` eligibility (`class="btn … gap-1.5"`) | 6px | 0 |

Both now render what they asked for. The mega menu's category rows had their icons flush against
the titles; they are 12px apart, as written — the most visible single change in the unit.

**Eleven sources of spacing became one**: `render_button_content`'s unconditional `end: 2`, plus
ten hand-written `ms-*`/`me-*` (`navigation_helper` chevron, `_dropdown_scroll_list` letter,
`_top_menu` kbd, `_search_bar_placeholder` label + kbd, `filter_bar_helper` badge, `crop`,
`slots/position`, `bmid/manage_helper`, `_messages_panel_header` ×4, `rollcall` ×2).

**Measured on the snapshot corpus, not by grep.** A margin only matters on a child that is
actually a flex item: an `sr-only` radio is `position:absolute` and a `hidden` label is
`display:none`, and neither takes a gap or contributes its margin. Counting them made the first
pass claim 10,028 buttons would gain 6px when the real number was **581**. The corpus scan doubles
as the acceptance test — it converged 19,439 → 134 → 58 → 4 → **0** elements carrying a margin
inside a `.btn` across 3,989 rendered pages.

Everything else moves 2px (8px → 6px). The two that gain are the directory letter picker and the
Menu chip, 4px before. B: −21 bytes, −1 rule, no selector added or removed. 3584 snapshots.

**Also corrected the docs that generate the habit** — `DESIGN-GUIDE.md`'s `fa_icon` margin example
and `design-components`, which now say outright not to pass `start:`/`end:` to an icon inside a
button.

**Left alone, flagged:** `bmid/titles` renders an `edit_link` whose label is *itself* a pen icon,
so the button holds two identical pen glyphs 6px apart (40 instances). That is a duplicate-icon
bug, not a gap bug.

### U11 · Hand-rolled cards and `ui_card` → `card-standard` ✅ `3ff9283d`

| | |
| --- | --- |
| Rung / artifact | 1: `@utility card-standard` (`components/cards.css`, "the app's one card": `card bg-base-100 border border-line`) |
| Sites | `ui_components/ui_card_helper.rb:7` (`CARD_BASE`, 11 renders) · `scheduling/shift_lead/_status_band.html.erb:20` · `common/schedule/_signed_up_row.html.erb:6` · `profile_photos/new.html.erb:24` · `me/dashboard/_announcements_section.html.erb:9` · `alerts/_alert_group.html.erb:8` and `ticketing/access_documents/_summary_legend.html.erb:9` (both legend panels keep `bg-base-200`) |
| Risk | visual. `rounded-lg` is 16px in this theme and `.card` gives 12px. The legends' `border-base-300` becomes `border-line`, which is the rule `cards.css` itself states. |
| Verification | A: diff expected. C at `/me` (announcements), `/me/schedule`, `/me/profile/photos/new`, `/me/alerts/edit`, the shift-lead page, the access-documents summary, and two `ui_card` callers (`timesheets/on_duty`, `mentoring/alpha_pods`) |
| Depends | P1 |
| Estimate | 7 files · eyes yes · ~−24 tokens |

**Done — `3ff9283d`.** 212 snapshots by the card swap alone; stylesheet +6 bytes, same rule count.

- `CARD_BASE` **deleted**, not repointed: `ui_card` writes the literal. A constant holding one
  utility name was a second spelling of a name the CSS already owns, and `grep card-standard`
  silently missed every `ui_card`.
- **Seven** sites, not six. `me/vehicles_dashboard/_pvr_requests.html.erb:6` was missing from the
  list and is the same object as the schedule row. Its `hover:shadow-md` survives: `.card` sets a
  `transition` shorthand, but `.transition-shadow` emits 107 KB later in the bundle, so the call
  site wins.
- The 8px on the schedule row is `.card`'s flex stopping a margin collapse — the additional-info
  partial has no padding or border, so its last child's bottom margin escaped and merged with the
  actions row's `mt-2`. Isolated by toggling `display` on the element, which is the only way to
  test this without a false comparison.
- `CARD_IMAGE` was `rounded-t-lg`: a 16px corner inside a 12px card.
- **The docs described a card that does not exist.** `DESIGN.md` gave it a shadow and 16px padding;
  `DESIGN-GUIDE` mapped it to `card card-border bg-base-100 shadow-sm` (card-border is the thing
  `cards.css` deliberately avoids) and documented a `card-soft` that exists nowhere. `rounded-xl`
  and `rounded-2xl` turn out to be **aliases** of `base` and `lg`, so the radius table read as a
  ladder that doubled back.
- **Still open:** "one card" is true of the card *utility*, not of every base-100 panel with a
  border-line edge. `ActionBoxHelper::ACTION_BOX_BASE` (8 callers) is `card-standard` plus padding
  and alignment, differing only in radius; `UiDisclosureHelper::CARD_WRAPPER_BASE` (22 callers) and
  `UiProgressBoxHelper::SECTION_BASE` are near neighbours. A later unit could fold those.

The Sep 5 plan adopted `card-standard` (6 uses) but never folded `ui_card` onto it, so the app
still has two card systems. **Excluded because they aren't cards:**
`shift_operations/payroll_export/index.html.erb:165` (a grand-total bar), `me/agreements/index.html.erb:58`
(a large empty state), `vc/applications/extract_handles.html.erb:26` (a read-only text well), the
checkbox tiles (U12) and the log data blocks (U15).

---

## Tier 4: extraction

All of these land after tier 2, so nothing extracted carries a palette colour.

### U12 · Checkbox tile partial ✅ `1caac177`

| | |
| --- | --- |
| Rung / artifact | 3: `app/views/common/_checkbox_tile.html.erb` with strict locals (e.g. `<%# locals: (align: :center) %>`), extracted from the tile inside `_checkbox_grid` and rendered with `render layout:` |
| Sites | `common/_checkbox_grid.html.erb:8` · `person/timesheets/backfill.html.erb:23` · `vc/handle_checker/index.html.erb:65` · `admin/action_logs/index.html.erb:51` (`items-start` variant) |
| Risk | structural. The A diff must be **empty**. |
| Estimate | 5 files · eyes no · ~−30 tokens (census D31, weight 20) |
**Done — `1caac177`.** The A diff is empty, as required: 3982 snapshots captured, and the only 19
that differ are the standing OAuth + clock noise. Stylesheet byte-identical. `redundant_tokens`
fell 2744 → 2723.

- Alignment comes through a **frozen lookup with `fetch`**, not a ternary: `align` is a
  caller-supplied name, and a ternary renders `:top` or `"start"` as centred without complaining.
  `me/tickets/_item_details.html.erb:9-18` makes the same argument in the same place.
- `render layout:` + strict locals + `yield` is confirmed as the house idiom for wrapper
  extraction (`hq/shift_manage/_section`, `common/_entry_card_grid`).

### U12b · Fold action_logs into `_checkbox_grid` ✅ `44a4fc16`

`admin/action_logs/index.html.erb:49-58` is not just a copy of the tile — it re-implements the
**whole of `common/_checkbox_grid.html.erb:6-14`**: same grid classes, same span, same `shrink-0`.
The only deltas are that `EVENT_FILTER_OPTIONS` yields `|label, value|` where the partial expects
`|value, label|`, no `id_prefix`, and the `:start` alignment. `_checkbox_grid` already has **nine**
other callers. U12 extracted the inner wrapper and left the outer duplicate standing at the one
site that most needed it.

**Not folded into U12 because it changes output:** `_checkbox_grid` gives every input an id built
from `id_prefix` and the value, and action_logs currently emits no id at all. Check whether any JS
or test targets those inputs before converting. Doing it also removes the only `align: :start`
caller, which would let the tile drop the local.

Same review, worth their own small units:
- **`cursor-pointer` is missing** on the tile (and was before the extraction). Twelve house
  precedents have it on a label that is the hit area, including `form_helper.rb:817`, whose comment
  says `# min-h-9: this label is the hit area`. `select-none` belongs with it — a 36px tile tapped
  twice on a phone selects its own label text. Breaks byte-identity, so it needs its own
  re-snapshot.
- **Nine more views hand-write `"checkbox checkbox-primary checkbox-sm"`** instead of
  `AppFormBuilder::CHECKBOX_CLASSES`, and `UiComponents::BulkSelectHelper::CHECKBOX_CLASSES` is a
  verbatim second copy of that constant.

**Done — `44a4fc16`**, all three. 170 snapshots, two shapes, stylesheet unchanged.

**The plan had the id risk backwards, and the fold is a bug fix.** action_logs was not emitting
"no id" — it was emitting **one id on all 23 checkboxes**,
`id="action_log_filter_form_event_filters_"`, which `check_box_tag` auto-derives from the array
name. 23 duplicate DOM ids, invalid markup, and invisible to the earlier duplicate-id sweep
because nothing spells it in source. The grid builds an id per value, so there are 23 distinct
ones now. Verified before converting: 23 values → 23 distinct `parameterize` results (no
collisions — `bmid-%` → `bmid`, `email-%` → `email`), and nothing in `app/javascript` or `test/`
targets those inputs by id; the only test references are query params.

`_checkbox_grid` gained one local, `align:` (`:center` default), which also decides whether the
box gets `mt-0.5`. `EVENT_FILTER_OPTIONS` reads `[label, value]`, so the call site passes
`.map(&:reverse)` — the same shape `clubhouse1_log` already uses.

The tile's `cursor-pointer select-none` moves 2,567 labels app-wide, which is the bulk of the 170
snapshots. The constant dedup went 11 spellings → 1.


### U13 · Icon list item helper ✅ `233b4ff7` + `47b3aad5`

| | |
| --- | --- |
| Rung / artifact | 4: a new helper `ui_icon_item(icon, icon_type = :solid, tone: nil, &block)` in `app/helpers/ui_components/` (the markup repeats, but the content is free-form) |
| Sites | `common/_timesheet_confirm.html.erb:16,22,28` · `common/timesheet/edit.html.erb:59,67,71,75` · `me/announcements/index.html.erb:18,22,33,37` · `me/tickets/_claimed_overview.html.erb:160` · `me/tickets/_item_details.html.erb:17` · `me/tickets/_section_detail.html.erb:156` · `me/tickets/_ticket_gift_conditions.html.erb:4,8,12` · `me/tickets/review.html.erb:22,35,41` · `me/tickets/_ticket_overview_item.html.erb:26` (a `<div>` variant; include it only if the helper takes `tag:`) |
| Risk | structural. The A diff must be empty except the icon offset at `common/timesheet/edit` (`mt-1` → `mt-0.5`, ×4). Keep an `icon_class:` escape if that 2px is deliberate. |
| Verification | A, plus a spot C at `/me/tickets/review` and `/me/announcements` |
| Depends | **design-rules approval** (a new UI helper). **U7 first** (`_timesheet_confirm`). |
| Estimate | 11 files + a helper test · spot check · ~−100 tokens (census D03, weight 66) |
**Done — `233b4ff7`, polished in `47b3aad5`.** 20 sites in 8 files. 19 byte-identical; the 20th is
the approved `mt-1` → `mt-0.5`, one snapshot, four lines.

- **Converting ERB by regex over a whole block is a trap.** The first attempt mangled the sites
  carrying a `<span>` inside each branch of a conditional. Match only the canonical shape
  mechanically (15 of 20) and hand-do the rest. Ruby's `/x` flag also strips the literal spaces
  inside `class="flex items-start gap-2"`, so the strict pattern matched nothing until `/x` came off.
- `tone:` stays a raw class string, confirmed right: the five tones in use span two families
  (`icon-*` tints and the neutral greys), so an enum would have to name their union, and nothing
  keys off the value the way `ui_badge`'s variant does.
- `47b3aad5` adds the missing-block guard its siblings have and the `docs/UI-COMPONENTS.md` entry
  that design-rules' approval process ends with.

### U13b · The twin cluster and the missing `<ul>` ✅ `d0bf5125`

- **`flex-center-gap-2` is the same item in different clothes**, at `me/tickets/_claimed_overview.html.erb:180`,
  `me/tickets/_section_detail.html.erb:112` — the *same two files* as converted sites — and a third
  spelling at `me/tickets/provisions.html.erb:48` (`flex items-center gap-3`, icon
  `text-stone-icon shrink-0 w-5 text-center`). The knob that would absorb them is `align:`
  (`:start` / `:center`), not the `tag:` that was considered and rejected. 20 → 23 closes the cluster.
- **The `<ul>` parent is still hand-written four ways** across the 8 converted files: `space-y-1`
  (×11), `space-y-1.5  text-body` (with a stray double space, `me/announcements/index.html.erb:17,30`),
  `space-y-2 ml-1`, `list-none space-y-2 ml-0`. This repo ships the parent with the child —
  `ui_stat_row` wraps `ui_stat_box`, `ui_label_value` yields a builder — and there is no
  `ui_icon_list`. Do **not** assert the parent from inside `tag.li`: it cannot see it.
- A 4th `<div>` variant exists at `me/tickets/_landing.html.erb:154` (body is an `<h3>`), and the
  wrapper-div shape (`common/_timesheet_confirm.html.erb:100,110` +
  `me/tickets/_ticket_overview_item.html.erb:26`) is now its own 3-occurrence cluster, i.e. at this
  repo's extraction threshold.
- Settle while nearby: `me/tickets/review.html.erb:38` passes `tone: "text-stone-icon"` where the
  SAP lists pass `"text-stone-subtle"`.


Dropped from the census cluster: `teams_positions/team_records/index.html.erb:69` and
`position_records/index.html.erb:75`, which are status wrappers, not icon items.

**Done — `d0bf5125`.** 35 snapshots, −20 bytes, one selector removed (`.ml-0`, now unwritten).
Clusters 302 → 300, tokens 2596 → 2577.

- **The twin: 2 of 3, not 3.** `_claimed_overview` and `_section_detail` converted. **No `align:`
  knob was needed** — measured, `items-start` + `mt-0.5` puts the icon 2px higher than
  `items-center` on a one-line label with the row the same height, and on a wrapping label it puts
  the icon on the first line, which is the whole point of the helper.
  `provisions.html.erb:48` is **deliberately left**: it is the standalone page, not an inline card
  list, and carries `gap-3`, `space-y-2` and `w-5 text-center` so a column of mixed glyphs aligns.
  Converting it trades four visual changes for one census number. Belongs in **Do NOT DRY**.
- **The parent: normalised, not extracted** (user's call). All 19 are `<ul class="space-y-1">`.
  The resets were dead — a bare `<ul>` already computes `list-style:none`, `margin-left:0`,
  `padding-left:0` under preflight, measured in the browser — and `text-body` computed identical
  to the inherited ink at every site, re-checked on the live pages after removal.
- **The sibling was extracted** (user's call): `common/_icon_block.html.erb`, the block form of
  `ui_icon_item` — icon in its own `shrink-0` column beside a `flex-1 min-w-0` body of any height.
  Three callers, one of which (`_ticket_overview_item`) was already a partial and kept its own
  `<h4>` inside. It **yields rather than taking a title**: two callers lead with a `<p>` and one
  with an `<h4>`, and folding that in would need a knob each. `gap-3` (2 of 3 wrote it); the
  ticket overview card gains 4px.
- **Tones settled to `text-stone-icon`** at four sites that said `text-stone-subtle`. Same ink —
  both resolve to `--color-body-subtle` — and 21 of the app's 26 `fa_icon` tones already say
  `text-stone-icon`. The plan had this backwards: `review.html.erb:38` was the one that agreed
  with the app, and the SAP lists were the outliers.
- `_landing.html.erb:154` stays out: its icon is not in a wrapper div and its body is an `<h3>`,
  so it is a 4th variant rather than a member of the 3-cluster.

### U14 · Autocomplete item layout partial ✅ `08c5c4f6`

| | |
| --- | --- |
| Rung / artifact | 3: `app/views/autocomplete/_item.html.erb`, `<%# locals: (icon:, title:, photo: nil, lines: []) %>`. This absorbs the placeholder avatar circle (D39) and the meta lines (D26). |
| Sites | `autocomplete/_asset_item.html.erb:9-18` · `_person_item.html.erb:14-41` · `_vehicle_item.html.erb:36-48` |
| Risk | structural. The A diff must be empty. `autocomplete_controller.js` doesn't select item internals by class (checked). |
| Verification | A, plus a spot C on a people and a vehicle autocomplete |
| Estimate | 4 files · spot check · ~−60 tokens (census D26 + D39 + the title cluster, ~45) |
**Done — `08c5c4f6`.** Byte-identical: 25 autocomplete snapshots, 0 changed; full run shows only
the standing OAuth + clock noise. No spot check was needed — identical bytes render identically.

- The plan's `lines: []` of plain strings would have changed the source bytes, because the person
  row wrote `&lt;` and `&bull;` as entities. `&lt;` survives untouched (ERB escapes `<` back to it),
  and `&bull;` becomes a literal `•`, which Nokogiri decodes to the same text node — so the
  snapshot does not move and neither does the render.
- **Coverage nearly read as a false negative.** Grepping the baseline for `rounded-full bg-neutral`
  returns nothing, which looks like "these rows aren't snapshotted". They are: the harness **sorts
  class tokens**, so it is stored as `bg-neutral flex h-8 items-center justify-center rounded-full`.
  Never probe snapshot coverage with a multi-class string.


### U15 · Admin log data block helper ✅ `a79e6939`

| | |
| --- | --- |
| Rung / artifact | 4: one helper, e.g. `log_data_block(content, max_height: nil)`, shared by the log helpers (the same family that gained `ui_pager` in `f7e108d4`) |
| Sites | `admin/action_logs_helper.rb:86` · `admin/request_logs_helper.rb:123` · `admin/error_logs_helper.rb:145` (the third occurrence) |
| Risk | structural. The A diff must be empty apart from class order. |
| Estimate | 4 files · eyes no · ~−12 tokens (in helpers, so invisible to the lint until P3) |
**Done — `a79e6939`.** The helper is `ui_data_block(content, max_height: nil)` in
`app/helpers/ui_components/`, following `ui_pager`'s placement — the same family this unit's three
callers belong to. Tested and documented in `docs/UI-COMPONENTS.md`, per design-rules' last step.

- The three sites spelled the overflow three ways: `overflow-x-auto`, `overflow-auto`, and
  `overflow-x-auto overflow-y-auto`. **All three compute identically** — a box with one axis `auto`
  and the other `visible` resolves both to `auto`. Verified in the browser: same computed values,
  same geometry. 17 snapshots change by that one token and nothing else.
- `max_height` stays the caller's, as a whole class name (`max-h-56`, `max-h-80`), because how much
  of a payload is worth showing before it scrolls is a per-page judgement. The strings live in
  `app/helpers`, which Tailwind scans.
- **The suite caught a real break:** `Admin::ActionLogsHelperTest` is an `ActionView::TestCase`, so
  it only includes the helper it names — moving the block out turned a passing test into a
  `NoMethodError`. Any future helper extraction out of a tested helper needs the same include added.


### U16 · Admin log text classes → constants ✅ `d5e9fd42`

| | |
| --- | --- |
| Rung / artifact | 4: two role constants in one shared module, e.g. `LOG_TEXT = "text-sm leading-snug text-body"` (cells, spans, divs; cells add `align-middle`) and `LOG_DETAIL_HEADING = "font-semibold mb-2 text-heading text-sm"` |
| Sites | D10 `admin/action_logs/index.html.erb:107,110,116`, `admin/bug_reports/index.html.erb:35,43`, `admin/error_logs/index.html.erb:63,69,72`, `admin/request_logs/index.html.erb:89,95` · N04 `admin/action_logs/index.html.erb:56,114`, `admin/request_logs/index.html.erb:94,103,106,108` · D18 `admin/action_logs/index.html.erb:136,147,153`, `admin/error_logs/index.html.erb:81,93,100`, `admin/request_logs/index.html.erb:130,136` |
| Risk | mechanical: the class strings are identical, so rendered HTML only differs in token order |
| Estimate | 5 files · eyes no · ~−85 tokens (census D10 + D18 + N04, ~70) |
**Done — `d5e9fd42`.** 28 sites in 5 files, output byte-identical (68 snapshots, 0 changed — the
tokens come out in a different order, which the harness normalises). `duplicate_clusters` 318 →
313, `redundant_tokens` 2756 → 2674.

- **Helper methods, not the bare constants this entry proposed.** ERB cannot resolve an included
  module's constant unqualified — it raises `uninitialized constant`, tested in a throwaway
  ActionView::TestCase rather than assumed — so the constant form would have meant
  `Admin::LogStylesHelper::LOG_TEXT` at every call site, longer than the string it replaces.
- **More sites than listed.** `admin/clubhouse1_log/index.html.erb` was not in the entry and holds
  3 of the 20, aligned `align-top` where the other four tables centre. Alignment and wrapping stay
  with the caller for exactly that reason — folding them in would have cost a knob per exception.
- No helper test: the two methods join strings, and the 68 snapshots already pin their output.
- The alternative this entry floats — table-level inheritance through `ui_table class:` and
  `t.row align:` — is still open and would remove more. It moves classes between elements, so it
  needs its own A check on computed styles.


The alternative is table-level inheritance: the text classes on `ui_table class:` and alignment
through the existing `t.row align:` option. `vertical-align` reaches cells by inheritance from
`:where(.table-container tbody)` (`tables.css:70-75`), and an explicit `align-*` on a row or cell
still wins. That removes more tokens, but it moves classes between elements, so it's a structural
change. Do the constants first. Consider inheritance afterwards, and only if A shows computed
styles unchanged.

### U17 · Mobile full-width action buttons → ButtonHelper option ✅ `88842542`

| | |
| --- | --- |
| Rung / artifact | 4: a `button_link` / `button_action` option, e.g. `full_width: :mobile` → `w-full lg:w-auto`, in `button_helper.rb` |
| Sites | D05 (`sm:`) `common/schedule/index.html.erb:40,50,58,65`, `common/timesheet/index.html.erb:57,65,74,82`, `person/timesheets/index.html.erb:59,62,71,82,87` · D30 (`lg:`) `common/shift_manage/_start_shift.html.erb:15,45`, `common/shift_manage/_too_short_modal.html.erb:20,34,57` |
| Risk | visual. The 13 `sm:` sites stay full-width up to 1024px instead of 640px, following the design rule that `sm:` is for field width only. The `justify-center` goes because `.btn` already centres. `text-base py-3` stays, pending a size decision (it may belong in `size: "base"`). |
| Verification | A, plus C at 700px and desktop on `/me/schedule`, `/me/timesheet` and a shift-manage start page |
| Estimate | 6 files · eyes yes · ~−54 tokens (census D05 + D30, net ~46) |
**Done — `88842542`.** 22 sites in 7 files, `full_width: true` on `button_link` / `button_action` /
`submit_button` / `cancel_button` / `button_classes`. `.sm:w-auto` has left the stylesheet
entirely. 41 snapshots change, every one by this swap alone.

- **The breakpoint moved to `lg` at the user's call**: those 13 buttons are now full-width to
  1024px, not 640px. Measured at 700px (they fill the container) and 1280px (the confirm button is
  176px in a 993px row).
- `justify-center` went with them: `.btn` sets `justify-content: center`, read out of the compiled
  rule rather than assumed.
- **`AppFormBuilder` includes `ButtonHelper` but is not a view context**, so `class_names` raises
  there. Both class builders keep string interpolation. The suite caught this in 11 places —
  `form_helper.rb:482` calls `button_classes` from `AppFormBuilder#submit`.
- Three sites on `profile_photos/crop.html.erb` were not on this list and are the same pattern.
- `text-base py-3` still sits at 18 call sites. It is a size, and `size: "base"` is not it
  (`btn-md` is 0.875rem and 40px tall, these want 0.9rem and py-3). **Still open**, as this entry
  said.


---

## Tier 5: the CSS layer and dead CSS

### U18 · Sidebar active state into `sidebar.css` ✅ `7155c0fc`

| | |
| --- | --- |
| Rung / artifact | 5: an `&.active` (or `&[aria-current="true"]`, but **not** a bare `[aria-current]`, because the JS writes `"false"`) state inside `sidebar-link-default` and `sidebar-link-hq`, using `--color-sidebar-active` from U8. Delete the `!` string at `sidebar_helper.rb:140`. |
| Risk | visual: the highlight should look the same, and it would then follow `active_links_controller.js:43-51` after stream navigation. Reproduce the stale highlight in C first: if it's real, this is a bug fix and could move up. |
| Verification | C: navigate by stream-nav between two sidebar pages and watch the highlight. Spec: `test/helpers/sidebar_helper_test.rb`. |
| Depends | **U8** |
| Estimate | 3 files · eyes yes · −3 `!` and −1 arbitrary value |
**Done — `7155c0fc`.** 3 `!important` utilities and the app's last arbitrary border width leave the
stylesheet. 2632 snapshots change, every one by dropping those three classes.

- **The stale highlight is real, and was reproduced before anything changed.** Doing to the DOM
  exactly what `active_links_controller` does — remove `active` from one link, add it to another —
  left `rgb(255,193,7)` and the 5px border on the link that lost it, and gave the link that gained
  it neither.
- **It is latent, not live.** Nothing passes `use_turbo: true`, so no sidebar link carries
  `click->stream-nav#follow`, so `turbo:after-stream-nav-render` never fires from the sidebar. It
  would have been wrong the moment one did.
- Keyed on `.active`, **not** `[aria-current]`: the controller writes `aria-current="false"` rather
  than removing the attribute, so a bare attribute selector matches every link.
- Unlayered on purpose — it has to beat the colour `sidebar-link-*` applies to every link, which is
  precisely what the `!important` was for.
- **Verified with clones.** These links carry `transition-colors`, so a live element reads back a
  stalled mid-transition value (the `oklab(...)` tell). A clone has never transitioned: any link
  with `active` computes `rgb(255,193,7)` + 5px, any link without computes neither.
- The helper test asserted the utility strings as a proxy for "active"; it now asserts the class
  and `aria-current`, which is what the helper decides.


### U19 · Delete dead Bootstrap helpers and the dead disclaimer partial ✅ `2a3d96e7`

To delete:
- `app/helpers/nav_menu_helper.rb` (`nav_menu_bar`, `nav_menu_dropdown`)
- `app/helpers/me/message_helper.rb` (`folder_select`)
- `app/views/common/_legal_name_disclaimer.html.erb`
- the palette maps in `app/helpers/dashboard_helper.rb:2-24` (`STEP_BORDER_COLORS`,
  `STEP_BG_COLORS`) and their two methods at `:61-67`

Nothing in `app/`, `test/`, `config/` or `lib/` references any of them; the partial has been
unreferenced since the first commit.

**Risk: mechanical.** **Verification:** the full test suite, a grep for `send(` and dynamic
`render` of those names, and `bin/css_check`, whose diff must be empty. 3 files deleted and 1
trimmed. That removes ~20 dead Bootstrap tokens and 27 dead palette tokens.
**Done — `2a3d96e7`.** Nothing rendered changes: the only 19 differing snapshots are the standing
OAuth + clock noise. The stylesheet loses **22 selectors and 3598 bytes**, and `bin/css_check`
confirms none of them is still written anywhere.

**`hardcoded_palette_tokens` falls 32 → 6**, which is the whole point: 26 of the 32 the ratchet had
only just learned to see were `dashboard_helper`'s dead maps.

- **The entry's dead list needed checking, not trusting.** `folder_select` looked referenced three
  times; every hit was the *partial* `folder_selector`. A word-boundary grep settles it, a
  substring grep does not.
- `nav_menu_dropdown` never worked: it takes a block and renders an empty `<ul>` without ever
  calling it.
- A `bg-white` I had previously counted in `ui_sticky_progress_helper.rb` is inside a **comment**,
  so Tailwind never scanned it and it was never compiled. My earlier raw-palette sweep overcounted
  by grepping source text rather than live code.

**All that is left in views and helpers**: the progress badge's four gradient stops (U10c), the two
deliberate `profile_photos/crop.html.erb` exceptions, and `print:bg-white`.


### U20 · Delete unreferenced selectors and the docs-only utility ✅ `aa0836c4`

Selectors to remove:
- `accessibility.css`: `scroll-region`, `force-scrollbar`
- `components/boxes.css`: `.box-highlight`, which also takes the only palette class left in a
  first-party `@apply`, `border-amber-50`
- `components/vc-applications.css`: `vc-assign-chip`, `vc-assign-other`
- `login.css`: `login-beta`, `login-beta-warn`, `login-countdown-dot`, `form-help-text`, `help-text`
- `components/flex-patterns.css:13`: `@utility inline-flex-center`, which only docs reference,
  so it compiles only because of auto-detection until P2

Also fix the stale comment at `accessibility.css:31` ("13 other elements use"). **Before
deleting, re-grep** for dynamic construction (`login-#{`, `vc-assign-#{`) and JS `classList`.
Keep `vc-assign-mine` and `vc-assign-none`, which are used. **Risk: mechanical.**
**Verification:** B must lose exactly these rules. 5 files.
**Done — `aa0836c4`.** B lost exactly those ten and 2748 bytes. Nothing rendered changes: the only
19 differing snapshots are the standing OAuth + clock noise, and a rule matching no element cannot
change a render.

- `inline-flex-center` was **already absent from the build** — P2 turned off automatic detection
  and only documentation mentioned it. Deleting the definition stops the file advertising a utility
  that compiles to nothing. `inline-flex-center-gap-2` (13 users) stays.
- The `login-countdown-dot` deletion took two more rules with it: `.login-countdown--burn
  .login-countdown-dot` and `@keyframes login-ember` styled an element the markup never renders —
  burn night shows a flame icon now.
- `.login-field .form-help-text` / `.help-text` name classes the form builder never emits; it
  writes utilities through `HELP_TEXT_CLASSES`.
- The `tap-target-link` comment claimed `inline-flex-center` had 13 users. It was counting
  `inline-flex-center-gap-2`, a different utility — the same substring trap as `folder_select` in
  U19.

### U20b · The VC assignment chips drifted ✅ `6a328023`

`app/views/vc/applications/show.html.erb:9-19` renders three assignment states three different
ways. Two use the colour-only modifiers **without** `vc-assign-chip`, so they get the tint but none
of the pill shape, padding or 36px target it supplies. The third ignores the system and hand-rolls
`text-warning font-semibold text-lg` where `vc-assign-other` existed for exactly that case.

U20 deleted the two unused rules as planned (user's call), so restoring the chip means writing them
again — deliberately, with a decision behind it. Fixing it is a **visible** change: the two working
chips would gain pill shape and padding.

**Done — `6a328023`, and NOT by restoring the chip.** Measuring killed that plan:

- It sits in `panel.description`, which design-rules says is one sentence of prose, and the action
  bar directly below is already a row of `vc-progress-item` chips. A fourth chip there competes
  with the title and repeats its own neighbour.
- Callsigns run to **37 characters** (`Julia Croft / Gadget (Org BMID Person)`). "Assigned to …"
  wraps to three lines at 375px. A `ui_badge` has a **fixed 24px height**, so it clips — measured
  343×24 against 45px of text. A `min-h-9` chip survives (343×37, unclipped), a badge does not.
  Worth remembering generally: **`.badge` is fixed-height and cannot hold wrapping text.**

So the hand-rolled third state was the one doing it right. All three are now that shape — bold
text, one token apart — built in `Vc::ApplicationsHelper#application_assignment_note` from a
frozen ink map with `fetch`. The whole `vc-assign-*` family is gone: −676 bytes, −7 rules.

- **Copy bug fixed**: the unassigned state read "Application is **unsigned**". Nobody signs an
  application; the rest of the app says "unassigned".
- **Only the unassigned state had a snapshot behind it**, which is exactly how the other two
  drifted unnoticed. The helper now has a test covering all three states plus the shared shape.

Clusters 298 → 297, tokens 2539 → 2536.


---

### U21 · Stop spelling a floor the size already carries ✅ `562207f1`

**The unit's premise was obsolete.** It was written against `btn-sm` being 32px. It has not been
since `9fe2dbd9` (2026-08-19), which put the floor in `accessibility.css` on the size itself:

```css
.btn-sm, .select-sm, .btn-toast-close, .sidebar-close-btn, .sidebar-toggle-btn {
    --size: calc(var(--size-field, 0.25rem) * 9);
}
```

So there were never ~660 buttons below the floor, and nothing needed to grow. What was left was
the opposite unit: 43 call sites spelling a class that changed nothing. Rendered output loses one
class per button and changes in no other way; B is byte-identical.

**Why the class kept being written:** the docs said to, and the docs still recorded `btn-sm` as
32px — `DESIGN-GUIDE.md`, `UI-COMPONENTS.md` and the `design-components` / `design-foundations` /
`design-layouts` skills each carried the instruction *and* the stale reason. Deleting the classes
without correcting those five files would have left the generator running. That is the half of
this unit that is worth more than the 43 tokens.

`export_csv_link` added its own `min-h-9` (`button_helper.rb:198`) for the same wrong reason; it
goes too, so the helper is what the docs now point at instead of a hand-written class.

**What keeps `min-h-9`**: elements nothing floors — a `<label>` wrapping a checkbox, a `<summary>`,
a bare link (`LinkHelper`), a `select` that is not `select-sm`. The navbar's sidebar toggle is a
raw `<label>`, but a `btn-sm` one, so it loses the class with the buttons.

**Three tests pinned the floor by asserting its old implementation** (`top_menu_test.rb:33,61-62`,
`filter_bar_helper_test.rb:97-98`). They now assert `btn-sm` — the thing that provides the floor,
and the thing a call site can still get wrong by passing `size:`.

**Done — `562207f1`.** 35 files. 3449 of 3989 snapshots differ, all of them the navbar's three
buttons on every page. B byte-identical: 553912 bytes, 4016 rules, no selector added or removed.
The only failures are the standing OAuth ones from the user's own uncommitted work.

## The precedence pass — partly done ✅ `36d509da`, the rest scoped

First-party component CSS (`base.css`, `boxes.css`, `tables.css`, `accessibility.css`,
`components/trix.css`, …) is written outside `@layer`, so it beats every utility regardless of
specificity. That choice is behind:
- `!pt-0` on the action-log continuation row (against `.responsive-table td`, as measured on
  Sep 5)
- `!border-b-0` on the same row, against the row's border utilities
- `RICH_TEXT_ERROR_CLASSES` (`!border-error !border-2`, `form_helper.rb:98-106`, documented)
- U2's dead margins
- `hidden!`, which also exists because of this, though it is really a contract with the JS

Its cousin, the `odd:`/`even:` stripe, forces four `!bg-*` row states in `table_helper.rb:42-45`
and `severity_style_helper.rb:14-15`.

Wrapping first-party component files in `@layer components` would let utilities win without `!`,
the canonical Tailwind model. It would also switch on every utility that is silently losing today,
across the whole app.

**Done for `tables.css` and both Trix stylesheets — `36d509da`. `important_tokens` 5 → 2.**
The blanket wrap the plan imagined is not available, and a screenshot sweep was the wrong
instrument. What replaced it:

- **The instrument.** Snapshots cannot see a CSS-only change, so the check is a cascade walk of
  the CSSOM across 11 pages: for every element, every property an unlayered rule and a utility
  both set, **with both values** — property overlap alone is mostly no-ops. 21 real differences
  before, 19 after; the two that went are exactly the two this commit fixed. Rebuild it from
  `scratchpad/cascade.js` before touching another file.
- **`@utility` cannot be nested.** 18 of the 48 first-party files declare one, so they cannot be
  wrapped or imported with `layer()` — it is a hard build error. Those need per-file surgery
  around the `@utility` blocks, the way `boxes.css` and now `tables.css` do it.
- **Layering a file also makes it lose to other UNLAYERED first-party CSS.** Caught as a
  regression: layering `components/trix.css` alone handed the win back to the vendored
  `stylesheets/trix.css`. Both had to move. Check the whole cascade, not just utilities.
- **Four rules must never be layered**, each now carrying its reason: the reduced-motion
  `.animate-pulse` override (accessibility), `.badge :is(.icon-*)` forcing an icon to inherit,
  U18's `.sidebar-nav-item.active`, and `tables.css`'s card-layout `text-left`.

**What is left**, and why it was not swept in:
- ~~`base.css`'s `p` and `a`~~ — **done, `90a19635`.** The comment said "several hundred
  paragraphs"; it is **166** (mb-3 ×109, mb-4 ×24, mb-1 ×15, my-4 ×11, my-3 ×4, one each of mb-0,
  my-1, mb-8). The 123 `mb-2` and 23 `my-2` do not move — `my-2` sets the same 8px the rule was
  forcing, so only its top was ever live, which is why the honest number is 166 and not the 189 a
  grep gives. The link side was far smaller than the comment implied: of **84,406** rendered
  `<a>`, 70,919 already carried `no-decoration`, 248 carried `underline` (what the rule applies
  anyway), and **7** carried a colour that was losing. No button moved: none of 24,353 carries a
  `cursor-*`. `@utility link` stays at top level — @utility cannot be nested.
  `turbo-frame` followed in `d9a1c58a`, guard and all -- it existed for the same reason the
  deleted `.responsive-table tr.hidden` patch did. base.css is now fully layered bar `@utility
  link`, which cannot be.
- The other 16 `@utility`-bearing files and the ~29 clean ones, where the instrument found **no
  current conflict**. Layering them changes nothing today and buys only that a utility written
  tomorrow works as written. Worth doing file-by-file when one is next touched, not as a sweep —
  several (`login.css` especially, which depends on being the last import) carry source-order
  assumptions the instrument does not model.

**Correction, 2026-09-20 — the instrument was blind to daisyUI, and this section leaned on it.**
`bin/css_cascade.js` filed a rule under the *nearest* layer name, and CSSOM names a nested block
by its own name alone. daisyUI compiles every component into
`@layer utilities { @layer daisyui.l1.l2.l3 { … } }`, so all 1,480 of its rules landed under
`daisyui.…`, matched neither branch of the walk, and were dropped: first-party CSS was only ever
compared against Tailwind's utilities and our own `@utility` classes. It came to light when a rule
forcing `display: block !important` onto every `.btn` in a stacked `.button-row` — a live,
app-wide bug — was reported as no conflict. The walk now carries the *outermost* layer, and lets
`utilities`' own rules outrank its sublayers, which is what the cascade does.

The same 13 pages, old walk against new: **19 → 29**, nothing lost, no value changed. The ten new
lines are four rules, and each is one that **must never be layered** — eight, then, not four:

| rule | file | layered, it loses |
| --- | --- | --- |
| `.btn-sm, .select-sm, …` — `--size: … * 9` | `accessibility.css` | the 36px touch floor, app-wide: daisyUI's `.btn-sm` says `* 8`, 32px |
| `[data-theme="dark"] .btn-error` — `--btn-color` | `components/buttons.css` | the darkened dark-mode fill, back to `var(--color-error)` |
| `.navbar .btn-ghost:not(dialog *)` — `outline-color` | `components/navbar.css` | the focus ring's ink on the always-dark bar, back to base-content |
| `[data-theme="dark"] .badge-soft.badge-secondary` — `color`, `background-color` | `components/badges.css` | the neutral chip, back to gray-on-gray |

So "no current conflict" above is wrong for those four files: layering any of them is a
regression, not a no-op. It is a floor, too — a walk finds only what its pages carry, and
`badges.css`'s dark `badge-error` rule is the same shape on a badge none of the 13 rendered.
Re-run the walk before layering anything; the claim was only ever as good as the instrument.

**What was already layered is sound.** Checked the other way round, as a one-off: the 137
first-party rules now in `@layer components` against daisyUI's bare classes on 11 pages, then
against all 1,480 daisyUI rules *whatever their selector*, element by element, on 6 pages at
1280px and 5 at 390px (134 of the 137 are live there). No layered declaration loses to daisyUI
anywhere. That probe is not in the script, which still reads bare `.class` rules only and so
cannot see `.table :where(th, td)`.

**Inversion, measured 2026-10-03 — layering the fold killed its own padding.** Once `36d509da`
put the responsive fold in `@layer components`, its `.responsive-table th, td { px-0 py-1 }`
lost to the `@utility` every helper cell carries: `table-cell-td` (`p-1.5`) on each td and
`table-row-header` (`p-1.5 … whitespace-nowrap`) on each row-header th. In a browser at 390px,
across 101 responsive tables on 47 pages, th and td kept 6px on every side; only a raw cell with
no helper class took the fold's padding, and no responsive table has one. The nowrap half was
fixed in `68ee449d`. On 2026-10-04 the owner kept the 6px as the design, so the dead `px-0 py-1`
went, and with it `.responsive-table td.table-detail-cell { p-3 }`, which had only existed to
beat that padding and lost to the identical `table-detail-cell` utility anyway. Measured on 263
pages (494 visible responsive tables, 80 pages) at 1280 and 390: the compiled diff is those two
rules, every cell's computed padding and white-space is unchanged, and 492 of 494 boxes match
at each width. The two that moved per width (the request and action logs at 1280, Radio
Checkout at 390) were data between loads: re-injecting the old rules into the same DOM changed
nothing, while the same rules gave a raw test cell `4px 0`, so the A/B could see a change.
**The cascade walk could not have found this, twice over:** it reads unlayered rules only, so a
layered rule losing to a utility is outside it; and it intersects CSSOM longhand names, where
Tailwind 4's `px-*` (`padding-inline-start/-end`) and `p-*` (`padding-top/right/bottom/left`)
share none. Any layering commit needs a computed-style probe, not the walk.

**The 2 remaining `!` utilities stay**: `table_helper.rb`'s `!bg-*` row states fight the
`odd:`/`even:` stripe, which is utility-vs-utility — layering cannot help — and
`person/provisions`' `hidden!` is a contract with its JS.

---

## Do NOT DRY

**Measured and declined (carried forward)**
- **`instruction-list mb-3`** (D01, ×63): the margin is present exactly when content follows the
  list, and absent when the list ends its container (Sep 5 table: 71/0 vs 0/25). Folding it would
  add 12px of dead space to 25 lists.
- **`hidden!`** in `tabs_controller.js:70,82`, `toggle_controller.js:46,55` and
  `person/provisions/_section.html.erb:28`: a contract with the JS, not a cascade fight.
- **The 10 dynamic inline styles**: the stat-meter segment widths (`_pipeline_card:33`,
  `_decision_card:30-32`), the alpha-pod column widths (`print_sheet:68`), the photo sizes taken
  from `PersonPhoto` constants (`_photo_none:2`, `me/directory/index:50`, `crop:105`, where the
  Ruby constant is the one source shared with image processing), and `position-anchor` (daisyUI's
  documented popover pattern). The Sep 5 plan decided these weren't worth a commit.
- **`profile_photos/crop.html.erb:102,104`** (`bg-gray-800`, `bg-gray-500`): a constant neutral
  behind the crop canvas, so a photo is judged the same way in either theme.

**Structurally identical, semantically unrelated**
- **`text-sm text-stone-muted`** (D02 ×57, plus ~32 with margin variants): two utilities that
  already name the role. The variants are layout. There is also an open design question first:
  `text-sm` is 0.875 rem against 0.9 rem body text, and whether a secondary line should differ in
  size at all is a design-scale decision. Revisit only after that is answered.
- **The heading family** (D07 ×25, D12 ×16, N02/N03/N06, ~90): different heading levels in
  unrelated features. `ui_section` and `ui_card_title` already own the structured headings.
  Coupling the rest breaks the first time one page needs a different weight.
- **Layout primitives**: D04 `flex flex-wrap gap-2 items-center` and its N01 family (37 uses),
  D19 `flex flex-col gap-y-1`, and the grid/flex near-families. This is how Tailwind is meant to be
  used. The exact three-token case already has `flex-center-gap-2` (44 uses, Sep 5 U14).
- **`checkbox checkbox-primary checkbox-sm`** (D24): already daisyUI.

**Below the third-occurrence rule**
- The status tint maps in `dashboard_helper` and `agreement_helper`: they look alike after U5,
  but there are two, and they key different enums.
- The legend panels (C01): after U11 they share `card-standard`, but their inner layouts differ
  (wrapping flex vs grid).
- The full-bleed link rows at `me/dashboard/_announcements_section:34` and `me/tickets/_landing:214`:
  two pages, and not buttons.

**Looks like a component to a regex; isn't one**
- The search `<dialog>` (C03): a native dialog by design, which the file explains.
- C04 `vc/spigot_flow_report/_callsign_cell:8`: already daisyUI 5's popover dropdown.
- C09 `cruise_direction/_pod:61`: a SortableJS row.
- The payroll grand-total bar, the agreements empty state, and the extract-handles text well.
- **The avatar placeholder → `avatar avatar-placeholder`**: it still needs the size, colour and
  radius utilities, adds a wrapper, and saves about one class per site. U14 absorbs it instead.

**Deliberate fixed colour**
- **Print sheets** (109 raw colours across 5 files) and **`print:bg-white`**: this is paper.
- **`credit-chart.css`** (17 hex): a categorical series palette with dark pairs. daisyUI has no
  equivalent, and it is already variables (`--ct-s1..8`).
- **`mail/layouts/mailer.html.erb`** (96-line inline `<style>`, `email-*` classes): email clients
  need it this way.

**Churn**
- Commit counts over 90 days are inflated by "checkpoint" commits (`app/views/common` 96,
  `app/assets/stylesheets` 98), so they don't single out any directory.
- `.scratch/` has no open feature touching these files.
- Land the units touching `common/timesheet*`, `me/tickets` and `admin/*_logs` promptly (U2, U7,
  U13, U16, U17), because those areas move weekly.

---

## Verification recipes

- **A (rendered HTML)** uses the P1 harness (`css_snapshot` from rules §3).
  1. Run the affected controller and system tests on the base commit.
  2. `cp -r tmp/css_snapshots tmp/css_snapshots_base`.
  3. Refactor, run the tests again, then `diff -ru`.
  - A daisyUI substitution is expected to diff; an extraction must not.
- **B (compiled CSS)** needs a one-off build, because `tailwindcss:watch` keeps removed
  candidates:
  ```
  $(bundle exec ruby -e 'require "tailwindcss/ruby"; print Tailwindcss::Ruby.executable') \
    -i app/assets/tailwind/application.css -o <scratch>/after.css --minify
  ```
  Diff the class-selector sets before and after. Until P2 lands, a class that leaves the views but
  still appears in `docs/` won't disappear from the build.
- **C (visual)**:
  - Use the `clubhouse3-alt` server on :3210 (:3000 is RubyMine's) and dev login at `/sign-in-as`.
  - Switch themes with the navbar toggle; setting only `data-theme` fakes a contrast bug.
  - Resize the viewport before any geometry probe.
  - Measure contrast on tokens with `color-mix`, never by reading canvas pixels of `oklch()`.
- **Before every unit**, grep `test/` for the strings it changes. This repo's tests pin exact
  markup. Known pins: `ffc107` (sidebar), `box-accent` (2 files), `icon-success` (2 files),
  `table-row-striped` (2), `text-stone-muted` (2).

## Recommended order

```
P1 → P2 → P3 → U1 → U2 → U3 → U4 → U5 → U6 → U7 → U8 → U9 → U10 → U11
   → U12 → U13 → U14 → U15 → U16 → U17 → U18 (needs U8) → U19 → U20 → U21

decisions: P2 (option A or B) · P3 (helpers in lint roots) · U2 (b or a)
           · U6 and U13 (design-rules approval) · the parked precedence pass
```

---

## Appendix A: U2 sites (113 in 62 files)

```
admin/oauth_clients/_form.html.erb: 10
admin/permissions/edit.html.erb: 11,17
admin/permissions/new_art.html.erb: 13,15
admin/rbs_alerts/edit.html.erb: 14,26
alerts/edit.html.erb: 71,73
bmid/titles/_form.html.erb: 7,10
common/_event_summary_breakdown.html.erb: 18
common/provisions/_form.html.erb: 55
communication/announcements/_form.html.erb: 7,29
communication/mail_templates/edit.html.erb: 50
communication/rbs_broadcasts/_message_fields.html.erb: 17
communication/rbs_phone_numbers/index.html.erb: 29
communication/survey_questions/_form.html.erb: 13
communication/surveys/_form.html.erb: 12
communication/surveys/index.html.erb: 88,93,98
me/dashboard/_dashboard_past_prospective.html.erb: 17,22
me/passkeys/index.html.erb: 52,54,56,58,60
me/passkeys/new.html.erb: 34
me/tickets/_announce.html.erb: 42,64,72
me/tickets/provisions.html.erb: 94
me/tickets/sap_so.html.erb: 64,68
me/volunteer_history/index.html.erb: 15
people/create_account/new.html.erb: 56
person/awards/_form.html.erb: 11
person/timesheets/backfill.html.erb: 17
person/training/_moodle_account.html.erb: 65
person/unified_flagging/show.html.erb: 95
profile/_languages.html.erb: 12
profile/camp_edit.html.erb: 18,20
profile/clothing_edit.html.erb: 19,21,23
profile/emergency_contact_edit.html.erb: 19,21
profile/identity_info_edit.html.erb: 49
profile/mailing_address_edit.html.erb: 20
profile_photos/crop.html.erb: 36,47            (mt-3)
quartermaster/swag/_form.html.erb: 7
register/_acknowledge.html.erb: 11
register/_closed.html.erb: 12,14,16
register/_form.html.erb: 56,78
register/_success.html.erb: 12,14
register/_volunteer.html.erb: 12,14
scheduling/early_arrivals/index.html.erb: 59,66
scheduling/event_stats/index.html.erb: 37,42,91,142
scheduling/sandman_qualified/index.html.erb: 32,39,44,52
scheduling/shift_lead/_legend.html.erb: 20,28,36,43,55
shift_operations/rollcall/index.html.erb: 35,40
teams_positions/position_lineups/_form.html.erb: 15
teams_positions/position_records/_form.html.erb: 117,163,201
teams_positions/team_records/_form.html.erb: 10,57
ticketing/access_documents/index.html.erb: 27
ticketing/bulk_access_documents/_formats.html.erb: 67,73
ticketing/claimed_with_no_signups/index.html.erb: 36,41
ticketing/expiring/index.html.erb: 32,37
ticketing/sap_candidates/index.html.erb: 36
ticketing/statistics/index.html.erb: 40,42,44
ticketing/unclaimed_with_signups/index.html.erb: 32
timesheets/correction_stats/index.html.erb: 45,56,62
vc/application_import/index.html.erb: 70,76
vc/create_prospectives/index.html.erb: 101,106,111
vc/reserved_handles/_form.html.erb: 9
vc/reserved_handles/upload.html.erb: 115
vc/spigot_flow_report/index.html.erb: 31
vehicles/registry/_form.html.erb: 11
```

All paths are relative to `app/views/`. Regenerate with the scan in the planning session: every
`<dt>` carrying an `m[ty]-*` class inside a `<dl class="…instruction-list…">`.
