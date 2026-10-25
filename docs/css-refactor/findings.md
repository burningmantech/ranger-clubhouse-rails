# CSS census — findings (2026-09-19)

**Read-only.** No application file was edited. Framed against `docs/css-dry-rules.md`.
Scope: the census's default roots (no path argument was given).

- Raw data: `tmp/css-audit/census.txt` (top 60), `tmp/css-audit/census.json` (top 200), plus
  `census-views.json` / `census-helpers.json` (per-root, for the comparisons below).
- The previous audit (2026-09-05) is archived in `tmp/css-audit/prev-2026-09-05/`.
  `census-before.*` was left alone. `plan.md` is still the Sep 5 plan and is now stale.
- Reproduce: `ruby bin/css_census.rb --min 2 --top 60`

---

## 0. Ground truth the census can't see

| Fact | Value | Source |
| --- | --- | --- |
| Tailwind | **4.3.3** (`tailwindcss-ruby`) via `tailwindcss-rails` 4.6.0 | `Gemfile.lock:458-461` |
| daisyUI | **5.7.37** (installed and declared) | `node_modules/daisyui/package.json`, `package.json` |
| Theme config | daisyUI 5 style: `@plugin "daisyui/theme" { … }` in the CSS entrypoint | `app/assets/tailwind/application.css:3-79` |
| Themes | `light --default`, `dark --prefersdark`, both fully defined in OKLCH | `application.css:7-79` |
| App tokens | `@theme`: `--color-heading/-body/-body-subtle/-line/-default*`, six `--color-sidebar-*`, `--text-base: 0.9rem`, radii, `--container-brand` | `application.css:81-173` |
| Dark overrides | `.dark, [data-theme="dark"]` re-sets `--color-line/-body-subtle/-heading` | `application.css:175-187` |
| `dark:` variant | `@custom-variant dark (&:where(.dark, .dark *))`: **class only**, not `data-theme` | `application.css:209` |
| Component tooling | No ViewComponent, Phlex or `tailwind_merge`; no `app/components/` | `Gemfile`, `ls app/` |
| Helper layer | 175 helper files; 23 in `app/helpers/ui_components/`; 126 class-string constants in 39 files; 61 `class_names(` calls | `app/helpers/**` |
| Stylesheets served | One: `tailwind` (all first-party CSS is `@import`ed into the Tailwind entry) | every `layouts/*.erb` |

### Theme definition (excerpt, verbatim)

```css
@plugin "daisyui" {
    themes: light --default, dark --prefersdark;
}
@plugin "daisyui/theme" {
    name: "light";
    --color-base-100: oklch(97.5% 0.005 80);
    --color-base-content: oklch(40% 0.01 60);
    --color-primary: oklch(0.52 0.2 262);
    …
}
@plugin "daisyui/theme" {
    name: "dark";
    --color-base-100: oklch(18% 0.005 260);
    --color-base-content: oklch(75% 0.01 80);
    --color-primary: oklch(0.68 0.19 262);
    …
}
```

### What Tailwind actually scans (verified by building twice)

`application.css:1` is `@import "tailwindcss";` with **no `source(none)`**, so Tailwind 4's
automatic detection is on. It scans the whole repo minus `.gitignore` / `.git/info/exclude`
(the worktrees are excluded), `node_modules`, and CSS files. The five `@source` lines
(`application.css:189-193`) add to that; they don't restrict it:

| Path | Scanned? | How |
| --- | --- | --- |
| `app/views`, `app/helpers`, `app/javascript`, `config` | yes | auto **and** `@source` (so the `@source` lines are redundant) |
| `app/assets/stylesheets/**/*.css` | **no** | Tailwind never reads `.css` as content, even when `@source` names it. I checked with a scratch build: a class that appeared only in a comment in a `@source`d `.css` file was not generated, while the same test with an `.html` file was. `application.css:189` does nothing. That is also why an unused `@utility` is never emitted, e.g. `box-theme-*`, which is only `@apply`d. (Correction, made during `/css:plan`: the first version of this row said "yes".) |
| `app/presenters`, `app/lib`, `app/models`, `app/controllers` | **yes** | auto only |
| `docs/`, `ai/skills/`, `.github/`, `bin/`, `test/`, `DESIGN.md`, `AGENTS.md`, `.claude/commands` | **yes** | auto only |

Method: I built the stylesheet as-is, then built it again from a copy of the entry with
`source(none)` (both builds are in the scratchpad). Minified size is **595,062 B** as-is
(the same size as the current `app/assets/builds/tailwind.css`) and **551,763 B** with
`source(none)`, a difference of **43 KB / 7.3 %** (5.7 KB gzipped). The extra classes come from
prose. For example, `text-red-800` exists only in `docs/css-dry-rules.md` and is compiled.
`AGENTS.md` says app/lib, app/models, app/presenters and app/controllers are *not* scanned, but
no current config matches that.

### Hand-written CSS (first-party, `app/assets/stylesheets/**`)

**50 files, 4,751 lines, 95 `@utility`, 318 `@apply`, 8 `!important` declarations, 143 raw colour
literals, 3 palette classes inside `@apply`.** Third-party/generated files are excluded:
`fontawesome-subset.css` (4,232), `trix.css` (470), `vanilla-calendar-pro.css` (34).

Largest: `alpha-sheets.css` 331, `trainers-report.css` 317, `shift-lead-sheet.css` 301,
`acceptance-sheet.css` 287, `login.css` 265, `tables.css` 235, `photo-board.css` 206,
`autocomplete.css` 194, `hq-window.css` 171, `signup-sheet.css` 171, `hq-forecast.css` 165,
`mega-menu.css` 163, `components/trix.css` 141. The five print-sheet files hold 109 of the 143 raw
colours. Separately, 8 views carry inline `<style>` blocks (249 lines): mailer layout 96,
`profile_photos/crop` 82, and five print views plus the print layout 71.

Unreferenced selectors (candidates for `/css:deadcss`, not verified further): `scroll-region`,
`force-scrollbar` (accessibility.css); `box-highlight` (boxes.css); `vc-assign-chip`,
`vc-assign-other` (vc-applications.css); `login-beta`, `login-beta-warn`, `login-countdown-dot`,
`form-help-text`, `help-text` (login.css). `@utility inline-flex-center` is referenced only by docs.

---

## 1. Scale

| Metric | All default roots | `app/views` (lint roots) | Sep 5 before-baseline (views) |
| --- | ---: | ---: | ---: |
| files scanned | 1,201 | 1,020 | 1,006 |
| class attributes (static / dynamic) | 4,517 (4,422 / 95) | 4,241 (4,163 / 78) | 4,348 |
| distinct class strings | 1,464 | 1,364 | 1,412 |
| **duplicate clusters** | **312** | **299** | 332 |
| **redundant tokens** | **2,895** | **2,774** | 3,255 |
| near-duplicate families | 40 | 49 | 46 |
| unscannable / palette / arbitrary / `!` / inline style | 0 / 2 / 19 / 2 / 11 | 0 / 2 / 16 / 2 / 10 | 0 / 29 / 18 / 4 / 14 |

`ruby bin/css_lint.rb --strict` passes. Every ceiling in `.css-baseline.json` equals today's count.

The default roots cover 1,020 view files, 176 helper files and 5 presenter files. `app/javascript`
contributes **0** files because the census's `exts` doesn't include `.js`, so class strings in
Stimulus controllers are never counted.

---

## 2. Correctness bugs (broken now)

**B1. The photo-crop controls are unstyled buttons.** `profile_photos/crop.html.erb:78,82,86,90,94`
(×5: Zoom In/Out, Rotate Left/Right, Reset) use `btn-base btn-primary py-2 px-3 lg:btn-sm`.
Nothing has defined `btn-base` since commit `907d14b0` (2026-03-06) deleted `@utility btn-base`. In
daisyUI 5, `.btn-primary` only sets `--btn-color`, `--btn-fg` and `--btn-soft-bg`, and every visible
property lives on `.btn`. So these render as bare icon + text on Tailwind preflight's transparent
button. They are also raw `button_tag` calls, which breaks the ButtonHelper hard rule. Checked in
the code and the compiled CSS; no screenshot taken. → rung 1 (`btn`), through ButtonHelper.

**B2. `bg-surface-secondary` doesn't exist.** `profile/_alerts.html.erb:35,76` (×2). The "Pre &
Post Event" and "On Playa" group-header rows lose their fill. This class was flagged dead on
2026-08-11 and is still in place. → rung 2 (a real `base-*` token).

**B3. `small` is a Bootstrap class with no rule, but it sits in dead code.**
`common/_legal_name_disclaimer.html.erb:1` is never rendered: nothing in `app/`, `test/` or
`config/` references the partial, and it has been unreferenced since the first commit. So this is
something to delete, not a live bug. (Correction, made during `/css:plan`.)

**B3b (found during `/css:plan`). `text-md` doesn't exist.** `ui_section_helper.rb:120` renders
every section badge as `ui_badge(..., size: "md")`, and `badge_helper.rb:37` interpolates that
into `text-md`, which matches no rule. That affects 9 `ui_section … badge:` sites, which fall back
to the badge's own 0.875 rem. `ui_card_helper.rb:26` also maps `md: "text-md"`, though no caller
passes `:md`.

**B4. Class names built by interpolation inside helpers.** The census reports 0 because it only
reads `class=` / `class:` literals.
- `ui_components/badge_helper.rb:50` builds `"icon-#{variant}"`. The variants are primary,
  secondary, error, success and warning, but `icons.css` defines only success, warning, error and
  info. **At least 34 call sites** pass `icon:` with `:primary` or `:secondary` and emit `icon-primary` or
  `icon-secondary`, which match nothing; the icon inherits the badge colour. `icon-success`,
  `-warning` and `-error` compile only because views also spell them out literally.
- `badge_helper.rb:37` and `table_helper.rb:156` build `"text-#{size}"`, which compiles only
  because the same sizes appear literally elsewhere.
- `notice_box_helper.rb:24` (`box-#{type}`) and `vc/applications_helper.rb:48`
  (`vc-progress-#{state}`) are safe, because both target plain CSS selectors that are always
  emitted. Scanner-based audits still can't see them.

→ rule 1: a frozen lookup hash.

**B5. `!important` fights.** The census counts 2; app code has **16**:
- views ×3: `admin/action_logs/index.html.erb:96` `!border-b-0`, `:123` `!pt-0`;
  `person/provisions/_section.html.erb:28` `hidden!`
- helpers ×9: `table_helper.rb:43-44` `!bg-success/10` and `!bg-base-300`;
  `severity_style_helper.rb:14-15` `!bg-error/10` and `!bg-warning/10`; `form_helper.rb:106`
  `!border-error !border-2`; `sidebar_helper.rb:140` `!text-[#ffc107] !border-r-[5px] !border-r-[#ffc107]`
- JS ×4: `tabs_controller.js:70,82` and `toggle_controller.js:46,55` toggle `hidden!`

**One abstraction causes four of them.** `@utility table-row-striped` (`tables.css:56-57`) paints
rows with `odd:`/`even:`, which is `:nth-child` at specificity 0,2,0, so every row-state tint has
to be `!`. → rung 5: fix the abstraction, not the callers. The action-log pair exists because
`ui_table` has no "continuation row" option (rung 4). First-party CSS adds 8 `!important`
declarations: `buttons.css` 4, `mega-menu.css` 2, and `login.css` 2, the last two being the
standard reduced-motion pattern.

**B6. Inline styles (11).** Not broken, but they break rule 3:
- 1 false positive: `icon_helper.rb:40` is the Ruby assignment `style = "regular"`.
- 5 dynamic percentages written straight to `width:` (rule 3 wants a custom property):
  `ticketing/statistics/_pipeline_card.html.erb:33`, `timesheets/correction_stats/_decision_card.html.erb:30-32`,
  `mentoring/alpha_pods/print_sheet.html.erb:68`.
- 3 photo dimensions from Ruby constants: `common/_photo_none.html.erb:2`, `me/directory/index.html.erb:50`,
  `profile_photos/crop.html.erb:105`. These are theme-token candidates.
- 1 is daisyUI 5's documented popover-anchor pattern and legitimate:
  `vc/spigot_flow_report/_callsign_cell.html.erb:9`.
- 1 is in a test fixture.

**Not bugs:** `nav_menu_helper.rb` (Bootstrap navbar) and `me/message_helper.rb` (Bootstrap
`d-block rounded-2 bg-white`) are full of classes that don't exist, but nothing in `app/` or `test/`
calls them. They are dead code to delete (`/css:deadcss`), not live defects.

---

## 3. Theming debt

**The census counts 2 palette tokens (the `crop.html.erb` exception). The real count is 102 pinned
colour uses in 12 files:** 84 palette, 14 white/black, 4 arbitrary hex. The census's `PALETTE`
regex is anchored (`\A(bg|text|…)-hue-\d+\z`), so it misses:
- variant prefixes (`dark:text-stone-100`)
- opacity suffixes (`ring-amber-200/40`)
- the `neutral-NNN` hue
- anything outside a `class=` / `class:` literal (helper constants, `class_names(...)` arguments)

The lint ceiling `hardcoded_palette_tokens: 2` inherits the same blind spot.

| Pinned | File | What |
| ---: | --- | --- |
| 27 | `helpers/dashboard_helper.rb` | status border and tint map (green/red/amber/gray/blue, light/dark pairs). **Dead code:** nothing calls these maps or their two methods (found during `/css:baseline`), so the live total is 75 |
| 17 | `views/common/_timesheet_confirm.html.erb` | `dark:text-stone-100/200`, `hover:text-stone-700`, `dark:hover:text-stone-300` |
| 14 | `helpers/ui_components/ui_hero_panel_helper.rb` | amber stat tiles plus the hero ring |
| 12 | `helpers/sidebar_helper.rb` | `text-white` ×8, `bg-[#000000]`, `border-[#101010]`, `#ffc107` ×2 |
| 10 | `helpers/ui_components/ui_progress_box_helper.rb` | `bg-white dark:bg-gray-800`, gray rings, amber→orange gradient |
| 9 | `helpers/agreement_helper.rb` | the same status map as the dashboard, second copy |
| 4 | `views/me/vehicles_dashboard/_eligible_positions.html.erb` | `text-neutral-600`, `bg-neutral-100` plus dark pairs |
| 2 | `views/application/_top_menu.html.erb` | navbar chrome `bg-black/80 text-white/80` |
| 2 | `views/common/_trophies.html.erb` | hero ring again |
| 2 | `views/layouts/print.html.erb` | `print:bg-white` (paper; deliberate) |
| 2 | `views/profile_photos/crop.html.erb` | the documented exception |
| 1 | `helpers/me/message_helper.rb` | dead helper |

- **94.1 % of the 1,732 colour utilities in views and helpers are already theme-driven:** 1,147
  project tokens (`text-stone-muted`, `text-heading`, `border-line`, …), 474 daisyUI semantic, 9
  keywords.
- **The sidebar token went unused.** `@theme` defines `--color-sidebar-divider` with the comment
  "was #101010", yet `sidebar_helper.rb:93` still writes `border-[#101010]`. The sidebar background
  `bg-[#000000]` (`:73`) and the active highlight `#ffc107` (`:140`) have no token.
- **Status tints are duplicated.** `dashboard_helper.rb` and `agreement_helper.rb` both carry the
  same light/dark status tint pairs.
- **CSS layer:**
  - Palette inside `@apply` ×3: `hero-panel.css:11` `ring-amber-200/40 dark:ring-amber-700/30` (the
    hero ring, also copied into the hero helper ×3 and `_trophies`), and `boxes.css:32` `border-amber-50`.
  - Raw colours outside print: `credit-chart.css` 17 (an 8-series categorical palette with dark
    pairs; daisyUI has no equivalent), `login.css` 12 (mostly relative colours derived from theme
    variables), and 5 others.

**Can the app be re-themed or dark-moded? Yes.** Dark mode works app-wide:
`theme_controller.js` sets both `.dark` and `data-theme`, and the neutral text ramp in
`text-colors.css` now derives from the theme's ink and paper. A new theme would reach everything
except the 12 files above, the 3 `@apply` spots, the credit-chart series and the print sheets.

One seam: `dark:` keys only off `.dark`, while daisyUI keys off `data-theme` or
`prefers-color-scheme`. `layouts/print.html.erb` mounts no theme controller and sets neither. On a
dark-OS machine it should therefore show daisyUI's dark surfaces with the *light* values of
`--color-heading/-line/-body-subtle`. This is from reading the code only; I haven't checked it in a
browser.

---

## 4. Component debt (hand-rolled daisyUI equivalents)

The census found 16 candidates, each used once or twice. Verified the top 3:

| # | Site | Verdict | Target |
| --- | --- | --- | --- |
| C01 | `alerts/_alert_group.html.erb:8`, `ticketing/access_documents/_summary_legend.html.erb:9` | **Real**, same role: a legend panel (the second file's header comment says it copies the first). Only 2 uses, so below the extract-on-third rule. | rung 1 `card card-border` / `ui_card` |
| C02 | `application/_search_bar_placeholder.html.erb:52` | **Real**: a hand-rolled ghost button, raw `<button>` (hard-rule breach), 1 use | rung 1 `btn btn-ghost` via ButtonHelper. daisyUI 5.7's `btn-ghost` paints `base-content`; `navbar.css` already overrides that for the other navbar buttons. |
| C03 | `_search_bar_placeholder.html.erb:71` | **Dropped.** Not a card: it's the native search `<dialog>`, and the file explains why the dialog itself is the box (backdrop-click detection). | — |

The other 13, grouped (spot-checked, not fully verified):
- **Bordered surface boxes** (`rounded-lg border border-line bg-base-100 p-N`): 9 in views,
  including C08 `scheduling/shift_lead/_status_band:20`, C11 `profile_photos/new:24`,
  C13 `common/schedule/_signed_up_row:6`, C14 `me/dashboard/_announcements_section:9` and C16
  `vc/applications/extract_handles:26`. `ui_card` is hand-rolled too
  (`CARD_BASE = "bg-base-100 border border-line rounded-base flex flex-col"`, 11 uses) → rung 1
  at the helper, then reuse it.
- **Status panels** C07 `me/vehicles_dashboard/index:30` and C15 `profile_photos/new:160` → the
  existing `ui_callout_box` (~480 uses) or `alert`.
- **Link rows** C05 `me/dashboard/_announcements_section:34` and C06 `me/tickets/_landing:214`: two
  near-duplicate clickable rows, not buttons → daisyUI `list`/`list-row` or `menu`.
- **Log data blocks**: C10 `admin/action_logs_helper.rb:86`, C12 `admin/request_logs_helper.rb:123`,
  plus a third copy at `admin/error_logs_helper.rb:145`. That is a third occurrence → rung 4, one
  helper (the same family that just gained a shared `ui_pager`).
- **Dropped**: C04 is daisyUI 5's own popover-dropdown pattern. C09 is a SortableJS row, not a button.
- **Avatar circle** (D39, ×3): `bg-neutral … rounded-full w-8 h-8` in the three `autocomplete/_*_item`
  partials → rung 1 `avatar avatar-placeholder`.

---

## 5. Structural debt (duplicate and near-duplicate clusters)

Verified: #1 to #4. The rest are as the census reports them.

1. **`<dl class="instruction-list …">`: 106 uses, all Q&A definition lists.** 63 add `mb-3` (D01,
   ~124 tokens), 9 add `my-4` and 6 add `mb-4`. Another **111 `<dt class="mt-2">`** space the pairs;
   the census can't see these because single-class attributes fall under its `min_tokens`. The class
   already exists (`accessibility.css:83`) → **rung 5: move the default margin and the dt spacing into
   `.instruction-list`.** This is the biggest token win on the list.
2. **`text-sm text-stone-muted`: ×57 (D02).** It is a secondary or meta line under a primary value
   (26 div, 16 p, 12 span, 3 in helpers). The `mt-*`/`mb-*` variants add D09 ×13, D14 ×11 and
   D28 ×8, about 89 in the family → rung 4/5 (a named role). Before naming the role, `/css:plan`
   should decide whether `text-sm` belongs in it: it is 0.875 rem against 0.9 rem body text, a
   0.4 px difference whose visible effect is mostly line-height.
3. **`flex gap-2 items-start`: ×23 (D03).** 21 of these are one role: an icon-bulleted list item
   (`<li>` + `fa_icon …, class: "<tone> mt-0.5 shrink-0"` + text) in /me tickets, announcements,
   and the timesheet confirm and edit pages. The icon offset drifts (`mt-0.5` vs `mt-1` ×4). I
   dropped 2: `teams_positions/team_records/index:69` and `position_records/index:75` are different
   wrappers. → rung 3 (partial/helper).
4. **`w-full sm:w-auto justify-center text-base py-3`: ×13, plus ×5 with `lg:w-auto` (D05/D30).**
   These are class overrides passed to `button_link` etc. in 5 files: the schedule, timesheet and
   shift-manage action bars. It drifts between `sm:` and `lg:`, and the design rule sanctions `sm:`
   only for field width → rung 4 (a ButtonHelper option).
5. **Heading family**: `font-semibold text-heading` plus size/margin variants (D07 ×25, N02 25 uses in
   4 variants, N03 16, N06 10, D12 `font-medium text-heading` ×16). About 90 uses with drift
   → rung 4.
6. **Admin log tables**: `align-middle leading-snug text-body text-sm` (D10 ×10, N04 15 uses) and
   `font-semibold mb-2 text-heading text-sm` (D18 ×8) across the action/bug/error/request log index
   views → rung 4 (a `ui_table` cell option).
7. **Autocomplete item partials**: D26 ×8, D39 ×3 and D21’s autocomplete sites, all in `_asset_item`, `_person_item` and
   `_vehicle_item` → rung 3 (one shared partial).
8. **Checkbox tiles** (D31, ×3 × 10 classes): `common/_checkbox_grid`, `person/timesheets/backfill`
   and `vc/handle_checker/index` → rung 3 (reuse `_checkbox_grid`).
9. **Layout primitives**: `flex flex-wrap gap-2 items-center` (D04 ×17; N01 has 11 variants and 37
   uses). The `flex-center-gap-2` `@utility` (31 uses) already exists. This is low value: layout
   utilities in markup are how Tailwind is meant to be used. Leave it unless a role emerges.

---

## 6. Blockers (settle these before refactoring)

1. **The scan contract is accidental.** Auto-detection is on, and `AGENTS.md` describes a config
   that doesn't exist (§0). Two consequences:
   - Class strings moved into `app/presenters` or `app/lib` would work today only because of
     auto-detection. Someone adding `source(none)` to cut the 43 KB of doc-driven CSS would
     silently break them.
   - Verification check B (the compiled-CSS diff) can't show a class leaving the views if docs,
     skills or tests still mention it. Banned palette classes (`text-red-800`, `bg-blue-600`,
     `text-gray-700`) are compiled and would render.

   Decide the contract, `source(none)` plus explicit `@source` or auto-detection written down,
   before any extraction into Ruby outside `app/helpers`.
2. **The measuring tools are blind where the debt is moving.** The lint ratchet reads only
   `app/views` (`.css-baseline.json`). The census misses helper constants, `class_names(...)`
   arguments, variant-prefixed or opacity-suffixed palette tokens, `neutral-NNN`, `!` utilities in
   helpers, and every `.js` file. A plan step that moves classes from views into helpers will
   *lower* the numbers while the debt moves out of sight. Palette reads 2 against an actual 102;
   `!important` reads 2 against 16. The census regexes need fixing, or helpers measured separately,
   before the ratchet can guard this work. `--roots app/helpers` shows 13 clusters and 48 redundant
   tokens today, both undercounts.
3. **Tests pin markup.** `table-row-striped` is asserted in 2 test files, `text-stone-muted` in 2
   and `!bg-` in 1. Grep `test/` before changing any helper's output.
