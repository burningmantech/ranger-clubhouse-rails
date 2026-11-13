# Phase 1 brief: UI pattern inventory (shared by every inventory subagent)

You are one of ~19 subagents building a **descriptive inventory** of the UI in this Rails app
(Clubhouse 3: ERB views, Hotwire, Tailwind 4, daisyUI 5, custom helpers). A later phase compares the
inventory with the written design guidelines. **Your job is to describe what the code does, not to
judge it.**

Worktree root (every path below is relative to it; never read or search outside it):
`/Users/lion/rangers/src/clubhouse3/.claude/worktrees/ui-design-audit-5712b7`

## Hard constraints

- Read-only. Change no application code. The only file you write is your own output file
  (`docs/design-audit/data/inventory/<your-group>.txt`), created with the Write tool.
- **Do not open the design guidelines.** Off limits in this phase: `docs/DESIGN-GUIDE.md`,
  `docs/UI-COMPONENTS.md`, `docs/form_helper.md`, `docs/css-dry-rules.md`, `docs/ui-duplication.md`,
  `docs/css-refactor/`, `docs/MENUS.md`, `ai/skills/`, `.claude/skills/`. Do not invoke any skill
  (the "Frontend Change Protocol" in AGENTS.md is for people editing views; you are not).
  The inventory must describe the UI as it is, not as the guidelines expect it.
- No servers, no tests, no `bin/rails` commands, no database access, no network requests, no git
  commands. Never touch the beta server (`clubhouse3.dev`): no docker, no ssh, no requests.
- Report only what you saw in a file you opened. Give `file:line` for everything. If you could not
  inspect something (built at runtime, rendered by a helper you could not trace), say so in a
  `PAGE` row with `audited` = `partial` or `no` and the reason. Do not infer.

## What already exists (do not redo it)

`docs/design-audit/tools/pattern_census.rb` has already scanned every file in `app/views` and
`app/helpers` with regexes and written `docs/design-audit/data/census.tsv`
(columns: file, pattern, variant, impl, count, lines, detail). It records, with line numbers:

- every call to a shared helper: `button_action button_link cancel_button edit_link export_csv_link
  delete_button submit_button button_row clipboard_button dropdown_button modal_close_button
  nav_link_to callsign_link email_link_or_dash person_display_link ui_form form_row filter_bar
  filter_chips bulk_select* year_selector* form_error_summary ui_flash_submit_error modal modal_dialog
  modal_form_footer confirm_modal confirm_modal_dialog ui_table ui_table_rows ui_label_value
  ui_data_block ui_drill_down_row ui_stat_row tab_navigation dropdown_menu dropdown_item ui_pager
  ui_match_stepper ui_card* ui_accent_card ui_section action_box ui_stat_box ui_stat_link ui_icon_item
  ui_accordion ui_disclosure inline_disclosure card_disclosure ui_callout_box ui_alert_banner
  ui_toast_render ui_toast_stream ui_flash_successful ui_success_text ui_empty_state hero_panel
  ui_section_title ui_subheading page_title fa_icon ui_badge ui_progress_bar ui_progress_box`
  (with the `variant:/size:/class:/icon:` options it could read);
- Rails helpers: `link_to mail_to button_to button_tag form_with form_for form_tag *_field_tag
  select_tag turbo_frame_tag image_tag`, and form-builder calls (`f.text_field`, `f.select`, `f.submit` ...);
- raw HTML tags: `<button> <a> <form> <input> <select> <textarea> <label> <fieldset> <dialog> <table>
  <ul> <ol> <dl> <nav> <details> <svg> <img> <i class> <h1>-<h6> <strong> <b> <em> <small> <hr> <br>`;
- class tokens inside `class=` / `class:`: daisyUI component classes (`btn card badge alert modal table
  tabs menu dropdown loading ...`), custom CSS classes defined in `app/assets/stylesheets`, Tailwind
  palette colours, semantic/bridge colour tokens, text-size and font utilities, spacing-scale
  utilities, arbitrary values (`w-[13px]`), inline `style=`, literal colour values, `data-controller`.

You may grep the census for your files (`grep '^app/views/<dir>/' docs/design-audit/data/census.tsv`)
to see what it caught, but do not copy its rows into your output. `docs/design-audit/data/pages.tsv`
lists each page template with its route(s) and the partials it reaches through static `render` calls.

## What you add

Open and read **every file in your scope, in full**. For each one, record what a regex cannot see:

1. **One-off markup** that implements a UI pattern without a shared helper or component class: a
   `div` with border/rounded/padding acting as a card, a link styled as a button with utilities
   only, a `span` acting as a badge, a table built from grid/flex divs, hand-rolled tabs, dialogs,
   progress bars, list rows, definition grids, notice boxes, and so on.
2. **Empty states**: for every list, table or collection, how the "nothing to show" case is
   presented (shared helper, plain text in a `<p>`, a table row, a callout, or not handled in the
   view at all). **Loading/busy states**: spinners, skeletons, lazy frames, disabled-while-submitting.
3. **Validation and error display**: where errors appear and through what (form builder inline
   errors, an error summary, a flash, a callout, custom markup).
4. **Shared helpers bent out of shape**: a shared helper called with `class:` (or similar) that
   changes its colour, size, spacing or typography; a helper used for a job other than its own.
5. **Typography, colour and spacing done by hand**: headings made from non-heading tags plus
   utilities; raw heading tags with their own size/weight classes; colour used to carry status;
   page-level wrappers (max widths, grids, column layouts); spacing that differs from the
   neighbouring pages in your scope.
6. **Icons**: icon-only controls (and whether they carry an accessible name), emoji or glyph
   characters used as icons, icons not produced by `fa_icon`.
7. **Navigation**: how the page is reached and left (back link, tabs, breadcrumbs, pager,
   year selector, in-page anchors).
8. **Census mistakes** you notice (a false positive, or a row filed under the wrong pattern).
9. **The same thing done two ways** inside your scope.

Pattern names (use exactly these): `buttons`, `links`, `forms`, `validation`, `modals`,
`tables-lists`, `navigation`, `cards`, `toasts-alerts`, `empty-loading`, `typography`, `color`,
`spacing`, `icons`, `other` (badges, progress, stats, avatars/photos, charts, print sheets,
anything else).

## Output format

Write plain text, one record per line, fields separated by ` || ` (space, two pipes, space). Never
put `||` inside a field. No header, no blank-line-separated prose, no markdown tables.

```
PAGE || <template path> || <route(s) or "rendered by <controller#action>" or "-"> || <kind> || <layout file or "-"> || <audited: yes|partial|no> || <purpose in a few words, then the page's skeleton, e.g. "hero_panel > filter_bar > ui_table > ui_pager">
ADD || <file> || <pattern> || <variant key> || <impl> || <line numbers, comma separated> || <what it is, in under 30 words, quoting the key classes>
DROP || <file> || <pattern> || <census variant> || <why the census row is wrong>
EDGE || <template or partial> || <partial or helper it renders that pages.tsv does not list> || <how: helper call / dynamic name / collection render>
VARIANTS || <pattern> || <the same UI job done in 2+ ways in your scope: each way with file:line>
OBS || <anything else a design auditor should know; description only>
```

- One `PAGE` row for **every non-partial template** in your scope (`kind`: `page`, `turbo-stream`,
  `print`, `fragment` (frame/modal body fetched on its own), `layout`, `fixture`, `mail`, `other`).
  Take routes from `pages.tsv`; if its route column is empty, find the controller that renders the
  template (grep `app/controllers`) and `docs/design-audit/data/routes.txt`. The layout comes from
  the controller (`layout "..."`) or the controller's namespace default.
- `ADD` rows are keyed by the **file that contains the code** (page or partial), not by the page.
- `impl` is one of: `one-off-markup`, `raw-html`, `inline-style`, `hard-coded-value`,
  `shared-helper`, `shared-partial`, `rails-helper`, `daisyui-class`, `custom-css`, `attribute`,
  `area-helper` (a helper in `app/helpers/<area>/`), `not-handled`.
- Variant keys: where the thing is a known helper/tag/class, use its name (`ui_table`, `<table>`,
  `class:btn`). For one-offs, use `oneoff:<slug>` and prefer these slugs so groups line up:
  `div-card`, `utility-button`, `utility-badge`, `grid-table`, `plain-text-empty`, `table-row-empty`,
  `plain-text-alert`, `utility-heading`, `raw-heading-with-utilities`, `custom-tabs`, `custom-dialog`,
  `custom-progress`, `custom-list-row`, `definition-grid`, `icon-only-control`, `status-by-color`,
  `page-width-wrapper`, `grid-layout`, `inline-error-text`, `plain-text-loading`. Coin a new slug
  when none fits. Other fixed keys: `helper-class-override` (item 4), `empty-not-handled`,
  `errors-via-form-builder`, `errors-via-flash`.
- Be exhaustive on items 1-4 and 6; for item 5 record each distinct treatment once per file with
  all its lines.

## When you finish

Reply with a summary of at most 150 words: how many files you read, how many PAGE/ADD rows you
wrote, anything you could not audit and why, and the two or three most notable "same thing done two
ways" cases. Do not paste the data into your reply.
