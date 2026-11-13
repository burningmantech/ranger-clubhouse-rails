aRules a grep or a small lint could enforce. `tools/rule_checks.rb` already contains a first version of each pattern and wrote today's hits to `data/mechanical.tsv`; nothing here is wired into CI. "Hits" is what the pattern matches today; "Real" is how many departures from that rule the audit confirmed in total, so where Real is larger than Hits the pattern needs widening, and the note says how. Three guards already exist and are named for completeness: `bin/css_lint.rb` (palette colours, arbitrary values), `test/views/hero_description_test.rb` (HERO-02) and `test/views/list_indent_test.rb` (SPACE-02), plus `fa_icon` raising on a missing regular glyph (ICON-03).

**Safe to fail the build on** (few or no false positives):

| Rule | Match | Where | Hits | Real | Notes |
|---|---|---|---|---|---|
| COLOR-01 | `(text\|bg\|border\|ring\|fill\|stroke\|from\|to\|via\|divide\|outline\|decoration)-(slate\|gray\|…\|rose)-\d{2,3}`, and `-(white\|black)` | views, helpers, JS controllers | 4 | 15 | Three palette classes are real (`profile_photos/crop.html.erb:95,97`, `layouts/print.html.erb:59`); the fourth is the progress badge the guide records as legacy, so allowlist it. The other twelve are literal values: add `#[0-9a-fA-F]{3,8}\b`, `rgba?\(` and `oklch\(` for views and helpers (print-sheet `<style>` blocks, `boxes.css`, two helpers). |
| COLOR-08 | `btn-info`, `bg-blue-\d+` | views, helpers, JS | 0 | 0 | Clean today. |
| STYLE-01 | `\sstyle=["']` and `<style[\s>]` in a view; `style:\s*["']` in a helper | views, helpers | 18 + 13 | 37 | Most hold a computed width, height or position (progress bars, the credit chart, the HQ Gantt). The guide gives no exception, so either move them to a custom property or write the exception down. Email layout excluded. |
| SPACE-02 | `list-(disc\|decimal\|inside)` | views, helpers, JS | 0 | 3 | The banned classes are clean. The three real cases draw bullets by hand with `&bullet;` (the error summary in `form_helper.rb`, one dashboard task): add `&bullet;\|•` beside a `<ul>` or `<li>`. |
| SPACE-03 | a `class=` on `<dt>` or `<dd>` between `instruction-list` and `</dl>` | views | 6 | 4 | |
| BP-02 | a literal `1024px` (or `1023px`) in an `@media` query | stylesheets | 3 | 3 | The guide's stated form, `max-width: 1024px`, is clean. The three are `min-width: 1024px` and `width >= 1024px` in `mega-menu.css` and `label-value.css`: no dead band, but not `theme(--breakpoint-lg)`. |
| ICON-01 | `<i\s[^>]*class="[^"]*\bfa` | views | 1 | 7 | `hq/shift_manage/_todo_list.html.erb:65`. The others are glyph characters used as icons (⚑, ✓) and `fa-` class names written in JS; add `[⚑✓✗★]` in views and `fa-(solid\|regular)` in controllers. |
| ICON-02 | `<svg[\s>]` | views | 0 | 0 | Clean. |
| STAT-02 | `\.hero_stats\b\|\.stat_badge\b` outside `me/dashboard` and the helper | views, helpers | 0 | 0 | Clean. |
| COPY-08 | `\bstrftime\b` | views | 17 | 21 | All 17 real. Four more in area helpers: run it there too, skipping `date_time_helper.rb`. |
| COPY-09 | `"%g"`, or `$` followed by `number_with_(delimiter\|precision)` | views, helpers | 0 | 0 | Clean. |
| COPY-07 | three periods after a letter, in visible text or a string literal | views, helpers | 6 | 7 | Includes the `shared/_autocomplete` default placeholder "Search...". |
| TOUCH-01 | `min-h-\[36px\]`, `min-h-11`, `min-height:` | views, helpers, JS | 1 | 7 | The banned forms are clean. Add `min-h-(7\|8)` on a link or label (three real cases: 28px and 32px links) and `min-h-8` in component CSS (the mega menu's item links). |
| MODAL-02 | `Are you sure`, `Really (delete\|remove)` | views, helpers, JS, controllers | 0 | 0 | Clean. The 46 MODAL-02 findings are a different shape; see the warning list. |

**Useful as a warning that a reader settles** (the rule has exceptions a regex cannot see):

| Rule | Match | Hits | Real | What the reader decides |
|---|---|---|---|---|
| BP-01 | a class token starting `md:`, `sm:` or `2xl:`; skip `sm:w-*` inside `width:` | 58 | 41 | Almost a hard rule already. The 17 cleared are the sanctioned `md:` uses and `sm:` field widths passed as `class:`. |
| FORM-01 | `form_with\|form_for\|form_tag` on a line without `builder: AppFormBuilder`; `<form`; any `*_field_tag`, `select_tag`, `check_box_tag` | 72 | 66 | A row-selector `check_box_tag` and a one-button `button_to` are not forms. |
| BTN-01 | `<button[\s>]`; a `class` string containing the bare token `btn`; `button_classes(` in a view | 9 | 14 | The sort-heading button is the documented exception. |
| TABLE-01 | `<table[\s>]` | 12 | 11 | Ten are print sheets; decide once whether a print sheet may write its table by hand. |
| TABLE-02 | `responsive:\s*false` with no ERB comment on the three lines above | 50 | 4 | Most are short tables the rule allows. The lint that pays is "requires a comment". |
| TABS-01 | `role="tab(list)?"` or a `tab`/`tabs` class in a view or area helper | 7 | 6 | The mailbox folder tabs and the photo upload page's source tabs. |
| MODAL-01 | `<dialog[\s>]` | 3 | 10 | The three raw dialogs (mega menu, search, HQ site registration) are real. The rest are `modal` blocks with no `m.title`, or with their buttons inside `m.body`; those need a reader. |
| MODAL-02 | `turbo_confirm:\s*"`, `data-turbo-confirm=`, `window.confirm(`, `alert(` | 6 | 46 | Seven are browser dialogs, which this catches. Eighteen are a destructive `confirm_modal` without `variant: :error` (match `confirm_modal(` with `method: :delete` and no `variant:`); the rest are wording. |
| COPY-04 | a helper label starting `New`, `Create`, `Update`, `Submit`, `Trash`, `Destroy`, or `Remove` not followed by `from`; a label that is exactly `Back` | 14 | 46 | The regex sees only labels passed as the first string argument; hero titles ("New Badge Title") and block labels were found by reading. Extend it to `title:`. |
| COPY-03 | a `title:`, heading or button label string with a lowercase word of five or more letters after the first word | not run | 81 | Heuristic. Interpolated strings and proper names need an allowlist. |
| COPY-02 | `status…\.titleize`, `\.status\.humanize` | 2 | 0 | Neither hit is a person's status. Keep as a tripwire. |
| COPY-01 | `\b(work\|working\|job\|employee\|staff)\b` in visible text, skipping "Work History" and "Staff Credential" | 42 | 2 | Mostly background jobs and paid-position pages. Needs a per-file allowlist to be worth running. |
| TYPE-02 / TYPE-03 | a `text-xs` or `text-sm` token | 137 view files | 104 | Too many legitimate uses for a hard rule. A ratchet (no new ones without a comment) would stop the growth. |
| TYPE-06 | `font-mono` | 40 | 2 | Nearly all are IDs, codes and plates, which the rule allows. |
| EMPTY-02 | `\|\| "-"`, `: "-"`, `"N/A"`, `"None"`, `<em>None</em>` as a cell or value | not run | 64 | Found by reading. Worth adding: the fix is always `value_or_dash`. |
| EMPTY-01 | a `<p>` or `<div>` whose text starts "No " inside an `else` or `empty?` branch | not run | 59 | Heuristic; would shortlist, not decide. |
| HERO-01 | a routed HTML template with no `hero_panel` in itself or its partials | 49 | 1 | 48 are sign-in, kiosk, print and wrapper templates; write the exemption first (section 4). |
| TABLE-05 | a file with `filter_bar` and an export control on a line without `actions:` | 6 | 0 | All six are a second export for a different table, which the rule allows. |
| MOTION-01 | `animate-` other than `spin`/`pulse`; `hover:(scale\|translate\|shadow)-`; in CSS, an `animation` or `transition` in a file with no `prefers-reduced-motion` block | 5 | 7 | The real cases are CSS and JS without a reduced-motion guard (toast slide-in, copy-success bounce, autocomplete spinner). |
