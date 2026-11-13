# UI inventory (Phase 1)

What the Clubhouse 3 UI does today, described without reference to the design guidelines. Phase 2
(`report.md`, `findings.json`) compares this inventory with `docs/DESIGN-GUIDE.md`.

This file is generated: `ruby docs/design-audit/tools/pattern_census.rb --helpers`, then
`ruby docs/design-audit/tools/build_inventory.rb`. The introduction is `data/inventory-intro.md`.

## How it was built

1. **Mechanical census** (`tools/pattern_census.rb` → `data/census.tsv`). A regex pass over every
   file in `app/views` (1,133 files) and `app/helpers` (192 files). It records each shared-helper
   call with the options it could read, each Rails form/link helper, each raw HTML tag that
   implements a pattern, and each class token inside a `class` attribute: daisyUI component classes,
   the app's own CSS classes, palette colours, colour tokens, type and spacing utilities, arbitrary
   values, inline styles and literal colour values. 12,296 rows of (file, pattern, variant, lines).
2. **Nineteen subagents** (`data/phase1-brief.md`, output in `data/inventory/*.txt`) each read every
   file in one area in full and recorded what a regex cannot see: one-off markup, empty and loading
   states, error display, shared helpers called with overriding classes, hand-made headings, colour
   carrying status, icon-only controls, and the same job done two ways. Fifteen covered the view
   areas and their area helpers; four documented the shared layer (component helpers, the form
   builder, the stylesheets and tokens, the Stimulus controllers). They were told not to open the
   guidelines. 3,257 `ADD` rows, 343 "same job, two ways" notes, 406 component records, 89 tokens.
3. **Merge** (`tools/build_inventory.rb`). Census rows the agents flagged as false positives were
   dropped (116). Each page's rows are the rows of its own file plus every partial it reaches
   through a static `render` call or an agent-reported edge.

Routes come from `bin/rails routes` (`data/routes.txt`), matched to templates by controller and
action. A template with no route of its own (a shared template under `common/`, a turbo-stream
response, a dashboard task partial) shows the controllers that render it instead.

## Scope

| | Count |
|---|---|
| Templates and fragments inventoried | 629 |
| Full pages (HTML template with a route, or a shared template rendered as a page) | 450 |
| Fragments (modal or frame bodies, dashboard task partials) | 119 |
| Layouts | 27 |
| Print sheets | 9 |
| Turbo-stream responses | 12 |
| Other (static error pages, PWA manifest and service worker, mail layout, fixtures) | 12 |
| Inventory rows (file, pattern, variant) | 14,757 |

Patterns: buttons, links, forms, validation, modals, tables-lists, navigation, cards,
toasts-alerts, empty-loading, typography, color, spacing, icons, and `other` (badges, progress,
stats, photos, charts, print sheets, Stimulus behaviours).

`impl` says how a variant is implemented: `shared-helper` (a helper in `app/helpers/ui_components`
or one of the top-level UI helpers), `shared-partial`, `form-builder` (`AppFormBuilder`),
`rails-helper`, `area-helper` (a helper in `app/helpers/<area>/`), `daisyui-class`,
`custom-css(<file>)`, `raw-html`, `one-off-markup`, `inline-style`, `hard-coded`, `utility`
(Tailwind scale utilities), `token` (semantic or bridge colour token), `attribute`.

## What the UI is made of

The UI is built almost entirely from shared helpers. The ten most widely used, by files that call
them: `hero_panel` (402), `button_row` (314), `ui_section` (293), `ui_callout_box` (284),
`ui_empty_state` (281), `ui_table` (242), `fa_icon` (206), `ui_badge` (195), `button_link` (195),
`ui_form` (157). Raw component markup is rare: 8 files hold a raw `<table>`, 5 a raw `<input>`,
18 use the `btn` class directly, 12 the `card` class.

Hard-coded values are few. Outside the print sheets and the mail layout the census found two
palette colours (`profile_photos/crop.html.erb:95,97`), 11 files with an arbitrary Tailwind value,
and 8 files with an inline `style` (seven set a computed width, height or anchor name).

## Where one job is done more than one way

The agents recorded 343 cases; the full list is under "Same pattern, more than one implementation"
below. The ones that recur across areas:

- **Empty value in a table cell or field.** `value_or_dash` (65 files), a literal "-", a literal
  "—", `&mdash;` in a muted span, "— none —", `none_stated`, an italic `<i>`, plain words ("Never",
  "not yet"), a dash with screen-reader text, a blank cell.
- **Empty collection.** `ui_empty_state` (281 files) is the usual form. Alongside it: a muted or
  italic `<p>`, red text in a `div`, a table row wrapping `ui_empty_state`, a callout box, a
  hand-made dashed box, the `.empty-state` class on a `div`, and collections with no empty branch.
- **Muted text.** `text-stone-muted` (226 files), `text-stone-subtle` (49), `me-muted` (23),
  `text-base-content/70`, `text-body-subtle`.
- **Destructive confirmation.** `delete_button confirm_modal:` with and without `variant: :error`,
  `delete_button confirm_message:`, `button_link data: confirm_modal(...)`,
  `turbo_confirm: confirm_modal_dialog(...)` on `f.submit`, and `window.confirm` / `alert()` in
  three Stimulus controllers.
- **Cancel.** `cancel_link` (69 files), `cancel_button` (15), a hand-built "Cancel" `button_link`.
- **Dialogs.** `modal_dialog` (47 files), the `modal` builder (28), a raw `<dialog class="modal">`
  (HQ site registration); footers from `modal_form_footer` or a hand-built `button_row` with
  `modal_close_button`; four ways of opening a dialog from JavaScript.
- **Label and value display.** `ui_label_value`, a header-less `ui_table`, a raw `<dl>` grid,
  stacked `dt`/`dd`, flex `div`s, helper-built lines.
- **Bordered container.** `ui_card`, `card-standard`, `box` + `box-*`, `box-accent`,
  `table-container`, and utility-only `div`s with their own border, radius and padding.
- **Filter and picker forms.** `filter_bar` with builder fields (88 files), `form_with` /
  `form_tag` with `select_tag` and `AppFormBuilder` class constants, and an auto-submitting select.
- **CSV export placement.** In `filter_bar` actions, in a `button_row` under the stats, in a bare
  `div`, in a toolbar beside a badge, right-aligned in its own row.
- **Loading indicator.** `shared/_frame_spinner`, the same markup copied inline, a `border-[3px]`
  spinner, `fa_icon` spinners, and plain "Loading…" paragraphs.
- **Status display.** `ui_badge`, area badge helpers (56 files call one), icon plus coloured text,
  a badge beside muted text; some status-to-colour maps disagree between helpers.
- **Warnings inside dashboard tasks.** Red bold `<p>` lines in about 14 task partials,
  `ui_callout_box` in 3.

