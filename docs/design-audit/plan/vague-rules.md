# Vague rules: the wording Phase 1 gives them

Every rule `report.md` section 4 lists under "Rules too vague to judge against", with the 512 `ambiguous`
cases from `plan/*.ambiguous.tsv`. "New wording" is a one-line digest; the full text is in the guide and its
skills. The effect sorts each rule's cases into those the new wording makes compliant and those it makes a
finding to fix. Totals: **343 now compliant, 169 now to fix.**

| Rule | Cases | New wording in one line | Effect | Reading chosen, and why |
|---|---|---|---|---|
| BTN-07 | 91 | Every page or form action sits in a `button_row`, a lone button included; exempt: one row's or card's record actions, a button in a callout, a title-row button, a toolbar shared with a pager, count or field. | now compliant: 39, now to fix: 52 (a lone page button, a bare `f.submit`, or two or more page buttons in a hand-made div; a cancel that is not `cancel_link`: R13041, R13067, R12014; a submit from `button_action`: R14124). The six sign-in cases fall under R9 | About 212 `button_row`s hold one button against some 30 lone buttons in bare divs; row and callout actions are already grouped by hand everywhere. |
| EMPTY-01 | 42 | A list, table or section the reader came for, and a search's results, show `ui_empty_state`; one that cannot be empty where drawn, a fixed catalogue, or a supplementary list may render nothing. | now compliant: 36, now to fix: 6 (R11763, R11827, R11829, R12040, R12410, R13521) | Most cases are guarded by caller or link; the fixes are the ones that draw a header-only table, an empty box or a silent search. |
| ALERT-01 | 41 | A notice in the page body is a callout; inside a card, step, cell, label/value row or dialog body a one-line status message may be status-coloured text led by its status icon, sentence case. | now compliant: 19, now to fix: 22 (a status line with no status icon, or in capitals; a notice standing alone in a page body as a `<p>` or heading; a callout that frames a control, R12893) | Fifteen dashboard steps already use the red line with an icon; text with no icon fails colour-alone (A11Y-01). |
| EMPTY-02 | 40 | An empty value prints "—" (`value_or_dash`), a profile label/value may say "None stated" (`none_stated`); a word stating a recorded fact is a value, plain or muted, never italic or bracketed; a zero prints as a number. | now compliant: 12, now to fix: 28 (worded empties: "None given", "No comments yet.", "(not set)", "(blank)", "No phone", "not stated", a "Not set" badge; fact words in italics or wrapped: "\*imported\*", "— imported —", "- Clubhouse -", `<i>never</i>`; a zero printed as "—": R13344, R14063) | Follows R6 for empty values; "Never", "Self", "Anonymous" carry information a dash would lose, so they stay as values. |
| HERO-01 | 31 | Every page inside the app shell heads with `hero_panel`; sign-in, print, kiosk, bookmark and wall-display pages, `public/` error pages and the test harness head themselves. | now compliant: 31, now to fix: 0 | Writes R9 and R10 down; every case is one of those page kinds, or a title holding a status beside it. |
| ICON-01 | 22 | Typographic glyphs in text (·, —, → for "then" or before/after, × naming a close) are punctuation; a glyph standing for a word on its own is an icon via `fa_icon`. | now compliant: 22, now to fix: 0 | Every case is an arrow or × inside a sentence that still reads with it; a screen reader says the glyph. |
| LAYOUT-02 | 21 | Page columns fold at `lg` with `gap-4` (a fixed rail may be a track list), never `md:`; item grids inside a section pick their own scale gap and may use `columns-*`, `xl:` or a content wrap. | now compliant: 18, now to fix: 3 (R11906, R11997, R13512) | Most cases are item grids, not page columns; the guide already prefers content-driven wraps; `md:` folds break BP-01. |
| HERO-04 | 16 | The hero's back link is the page's one way back, never repeated at the foot; a body link back only for a step back, a re-post or an empty result's one action; print sheets use the area's print nav. | now compliant: 8, now to fix: 8 (R12201, R12692, R12750, R12863, R12884, R13028, R13107, R14578) | The repeats duplicate the hero exactly; step-back, re-post and print-nav cases do what a hero link cannot. |
| FORM-07 | 15 | In a filter panel or `form_row` each field fills its share (`w-full` + `flex-1`); a width goes through `width:` at `sm:` on a scale step, never `lg:`, an arbitrary value or the input's `class:`. | now compliant: 8, now to fix: 7 (R12155, R12177, R12185, R12216, R12218, R12224, R13842) | Filter panels all fill their share already; `lg:` widths contradict the sanctioned `sm:` use (BP-01). |
| TABLE-01 | 15 | `class:` on `ui_table` and its cells carries layout only; a grouped header may be built inside `ui_table`; blank print grids, card lists and roster grids are not data tables. | now compliant: 15, now to fix: 0 | Every override is nowrap, a width cap, a divider or a total's weight, which is how the code uses it throughout. |
| FORM-06 | 14 | A form with no model, or one acting on many records, reports a refusal in an error callout naming the failed rows; a flash alone is not enough. | now compliant: 11, now to fix: 3 (R12823, R13592, R13604) | Grids, bulk tools and review flows already report in a callout or review table; flash-only refusals vanish with the toast. |
| HERO-02 | 14 | Every hero has a one-sentence description in the panel's own style, except a new or edit form page. | now compliant: 9, now to fix: 5 (F0007, F0138, F0140, F0145, R14580) | Roughly 288 heroes have one against 83 without; the guide's own Form pattern omits it, so new/edit pages may. |
| SPACE-01 | 14 | Spacing comes from the scale, no arbitrary value without a comment; defaults include `p-3` for a dense repeated card and the button row's own gap. | now compliant: 11, now to fix: 3 (R04576, R07367, R13575) | `p-3` cards and scale gaps are common and harmless; the fixes are uncommented arbitrary values and a gap forced onto `button_row`. |
| FORM-08 | 13 | Hero (back link where the reader came from a page; description optional on new/edit), optional callouts, `ui_form`, button row last; sections inside or around the form are optional. | now compliant: 13, now to fix: 0 | Fixes the order, frees what the guide's own hybrid example already varies; menu-entry tools have no page to go back to. |
| BTN-05 | 10 | The main action is `:primary`, a positive one included; `:success` is a positive non-main action; Apply Filters follows R7; a view toggle marks the current view `:primary`. | now compliant: 8, now to fix: 2 (R12699, R12704) | Only 8 buttons in the views use `:success`; main actions are `:primary` almost everywhere. |
| TYPE-04 | 9 | The `<h1>` is the hero's; a page outside the app shell styles its own `<h1>` from its own stylesheet or masthead. | now compliant: 9, now to fix: 0 | Every case is a sign-in, print or fixture page, the surfaces `design-foundations` already lets keep their own styles. |
| HELP-02 | 8 | A form page may keep its Q&A open in a `ui_section` above the form; the steps of one action may sit in an info callout beside it. | now compliant: 8, now to fix: 0 | Matches the guide's existing allowance for operated pages; all eight cases are forms or operated pages. |
| TYPE-03 | 6 | `text-sm` also for a footnote marker, an image-placeholder caption and a list line's metadata; never for a disclosure summary label. | now compliant: 5, now to fix: 1 (R14624) | These are fine print or metadata by nature; a summary label is a control label, like a tab label. |
| FORM-01 | 6 | A fieldless carrier form and a browser-only filter input are not forms that need the builder; the autocomplete builds its input from `INPUT_CLASSES`. | now compliant: 6, now to fix: 0 | None of the six collects submitted input through a form; the autocomplete already borrows the builder's classes. |
| LAYOUT-03 | 5 | Any list of drill-down rows or roster of one-line rows may use `lg:w-3/4`; two level-2 empty states only where both can occur. | now compliant: 5, now to fix: 0 | Four rosters borrow the width sensibly; an unreachable empty state helps no one. |
| COLOR-06 | 5 | `me-muted` is a legacy alias; new or touched markup writes `text-stone-muted`. | now compliant: 0, now to fix: 5 (R02779, R02857, R02870, R11852, R11855) | `text-stone-muted` is in 233 files against 24 for `me-muted`. |
| CARD-03 | 5 | A section is titled unless it boxes a whole page body or form; sibling sections all carry an icon or none do; `ui_section_title` may head a group of rows. | now compliant: 4, now to fix: 1 (R12962) | Untitled body boxes and bare group titles are deliberate; one icon missing among siblings reads as a mistake. |
| TYPE-02 | 4 | `text-xs` also for icon sizing beside text and keyboard-shortcut hints. | now compliant: 4, now to fix: 0 | Shortcut hints repeat what a control does, so they are non-essential; an icon's size is not text a reader reads. |
| TOAST-01 | 4 | A streamed (`ui_toast_render`, `ui_toast_stream`) or template-cloned toast is the same toast, same types, timing and roles. | now compliant: 4, now to fix: 0 | All four already use the toast markup; only the delivery differs. |
| TABLE-05 | 4 | With no filter bar, the export sits in the page's `button_row` above the table. | now compliant: 4, now to fix: 0 | All four training reports already do this. |
| TABS-01 | 3 | A switch that loads another view of the page is a button group with its current one announced, not tabs. | now compliant: 3, now to fix: 0 | The mode switches reload the page; tab roles would promise in-place panes. |
| STYLE-01 | 3 | `base.css` holds element base styles; a one-page component gets its own `components/` file; `style=` may carry a computed custom property. | now compliant: 3, now to fix: 0 | Matches AGENTS.md (a dynamic number travels as a custom property) and the Key Files list. |
| STAT-01 | 3 | A tile's value is a short figure or word; `class:` sets width or margin only. | now compliant: 3, now to fix: 0 | A status word or a channel phrase reads as a tile value; a width class is layout. |
| ICON-04 | 3 | Every meaningful icon with no word beside it takes `fa_icon … label:`, wherever its explanation lives. | now compliant: 0, now to fix: 3 (R12189, R12239, R13085) | An `sr-only` name leaves sighted readers with a bare icon; `label:` already gives both. |
| DISC-01 | 3 | `summary_class:` sets the summary text's weight, size and ink only, never its focus ring or layout; a title's icon goes inside it. | now compliant: 2, now to fix: 1 (R11726) | Restyling the text is harmless; rewriting the focus ring risks the keyboard floor. |
| COPY-03 | 3 | Badge text keeps its casing; checkbox and radio labels are sentence case. | now compliant: 3, now to fix: 0 | Ruling C6 (2026-10-23 copy rulings). |
| BTN-02 | 3 | `class:` on a button carries width and margin only: never `btn-link`, padding or a text size. | now compliant: 0, now to fix: 3 (R04274, R12296, R14266) | `link_to` and `size:` already do these jobs; overrides drift from the 36px button scale. |
| BTN-01 | 3 | Ruled raw buttons: the sort heading, `clipboard_button`'s icon, `dropdown_button`. | now compliant: 3, now to fix: 0 | Each is a helper's own markup, the case the sort-heading ruling already covers. |
| BADGE-01 | 3 | `class:` on `ui_badge` is layout only (never opacity or colour); every state of a badge set is a badge. | now compliant: 1, now to fix: 2 (R12440, R12905) | Opacity hurts contrast; a set that is a badge in every state but one reads as two components. |
| SPACE-02 | 2 | Lines that each start with a typed marker are a list. | now compliant: 0, now to fix: 2 (R12755, R12818) | A list gives the marker and indent the guide already defines; typed dashes are a hand-drawn list. |
| MODAL-02 | 2 | A confirm that destroys nothing asks with its action, says what follows, and keeps its action's variant. | now compliant: 2, now to fix: 0 | Both already ask with the action; undoability matters only where something is destroyed. |
| MODAL-01 | 2 | The `dialog` controller's on-demand dialogs and the HQ wizard open themselves; a new dialog uses `ModalHelper`. | now compliant: 2, now to fix: 0 | Both are shared infrastructure that predates the rule; documenting them closes the gap. |
| LIST-01 | 2 | Every `<dt>` of an `instruction-list` is a question. | now compliant: 0, now to fix: 2 (R03202, R12011) | The drawn "Q:" prefix makes a value-as-question read wrongly. |
| FORM-10 | 2 | A card's footer row uses the same divider, with `mt-3` allowed. | now compliant: 2, now to fix: 0 | Both card footers already use it. |
| COPY-04 | 2 | A save names what it saves, never a bare "Save" or "Save Changes"; one action, one label everywhere. | now compliant: 0, now to fix: 2 (R12710, R13547) | "Save [Entity]" labels number about 76 against 11 bare "Save" and "Save Changes". |
| COLOR-02 | 2 | A stat tile takes a status variant only when its value is a status, and `:secondary` at zero. | now compliant: 0, now to fix: 2 (R14379, R14528) | A warning or success colour on a zero count signals a status that is not there. |
| BTN-06 | 2 | A table's id or name link to the record's page is a row link, not an edit control, and never reads "Edit". | now compliant: 1, now to fix: 1 (R14574) | A link labelled "Edit" that opens the read view misleads. |
| TYPE-08 | 1 | `font-semibold` also for a total row or grand-total cell. | now compliant: 1, now to fix: 0 | Totals are headings of a kind; the weight marks the row a reader looks for. |
| SHADOW-01 | 1 | A panel floating over the page casts the shadow the table gives it. | now compliant: 1, now to fix: 0 | The shadow table already lists `shadow-lg` for popovers and menus. |
| RADIUS-01 | 1 | A full profile photo is `rounded-2xl`; `rounded-full` is for small avatars. | now compliant: 1, now to fix: 0 | The one profile photo already uses it. |
| NAV-04 | 1 | A jump list's lead-in sits in its own element, never a bare text node. | now compliant: 0, now to fix: 1 (R13792) | A bare text node cannot be styled or named; this is the only case. |
| NAV-01 | 1 | An open dropdown closes on Escape, an outside click and a choice. | now compliant: 0, now to fix: 1 (C0423) | Keyboard users need Escape (A11Y-02); the other two are what the code already does. |
| LAYOUT-04 | 1 | The mailbox's three-line review rows are the exception to one line per record. | now compliant: 1, now to fix: 0 | `design-layouts` already documents the mailbox as an adaptation of the pattern. |
| LAYOUT-01 | 1 | Pages outside the app shell are exempt from the layout patterns. | now compliant: 1, now to fix: 0 | R10. |
| FORM-09 | 1 | Unchanged: saved rich text renders through `rich_text`. | now compliant: 0, now to fix: 1 (R12085, once it is confirmed the column holds Lexxy HTML) | The rule was firm; the case needed the data checked, not new wording. |
| FORM-04 | 1 | A character counter line is help text, tied to the field by `aria-describedby`. | now compliant: 0, now to fix: 1 (C0454) | Otherwise a screen reader never hears the limit. |
| FORM-02 | 1 | In a grid of rows the column heading is the visible label; each field takes `hide_label:` and an `aria-label`. | now compliant: 1, now to fix: 0 | The one grid does exactly this; a repeated visible label per cell would defeat the grid. |
| COPY-02 | 1 | A status prints bare: no brackets, quotes or italics. | now compliant: 0, now to fix: 1 (R11804) | "As stored" means the value, not decorated. |
| COLOR-03 | 1 | Unchanged; the case is the sign-in page. | now compliant: 1, now to fix: 0 | R9 exempts sign-in's look. |
| CARD-01 | 1 | Unchanged; the case is the sign-in page. | now compliant: 1, now to fix: 0 | R9: the login panels are `login.css`'s. |
| BTN-04 | 1 | The same action may repeat above and below a long table. | now compliant: 1, now to fix: 0 | It is one action in two places, not two primaries. |

## Needs the maintainer

None.

## Sidebar code Phase 2 deletes

C4 approved ("delete code and docs"). The docs entries are gone (guide Sidebar, `docs/UI-COMPONENTS.md`,
`design-components`); Phase 2 (`shared-helpers`, `shared-css`) deletes the code below, which no code path renders.

- `sidebar_item`'s `icon:`, `icon_type:`, `badge:` and `badge_variant:`: accepted and dropped. The method ends in
  `link_to title, url, html_options` (`app/helpers/sidebar_helper.rb:159`); `render_sidebar_content` (255) and
  `sidebar_badge` (240), which would draw them, are never called.
- `SIDEBAR_BADGE_VARIANTS` (41-47) and the `sidebar-badge` utility (`components/sidebar.css:18`) serve only
  `sidebar_badge`.
- `sidebar_item`'s `use_turbo:`: no view, helper or menu definition passes it.
- `sidebar_submenu_item` (163): no caller.
- `sidebar_submenu`'s `icon:` and `icon_type:`: its only callers, inside `sidebar_render_section`, pass neither.
- `sidebar_section` and `sidebar_submenu` are called only from `sidebar_render_menu`; no layout calls them
  directly as the guide's Basic Usage example does (every layout calls `sidebar_render_menu(Menus::…)`).

## Code to fix in Phase 2

Places where the code, not the guide, is wrong. The guide was left saying the right thing.

- `app/assets/tailwind/application.css:107`: `--font-mono` quotes the generic keywords (`"ui-monospace"`,
  `"monospace"`), which makes them family names, so the generic fallback never applies. The guide's stack writes
  them bare. (`shared-css`, already in its list.)
- Remove the `required_label:` option (`app/helpers/form_helper.rb`: `SELECT_FIELD_OPTION_KEYS` line 37, the option read at
  568, the asterisk branch of `required_marker` at 789-790) and every caller, so all forms show the visible
  "(required)". Callers that pass `""`: `app/views/register/_form.html.erb` (35, 60, 64, 69, 81, 91, 101, 112),
  `app/views/sessions/new.html.erb` (85), `app/views/sessions/_password_form.html.erb` (10, 37),
  `app/views/sessions/forgot.html.erb` (17), `app/views/sessions/reset_token.html.erb` (32, 50). Partials that pass
  it through (local `required_label:`, default `nil`): `app/views/common/_legal_name_fields.html.erb` (8, 11, 16)
  and `app/views/common/_mailing_address_fields.html.erb` (13, 16, 19, 27, 32, 34).
- `app/helpers/form_helper.rb:792`: the "(required)" marker is `text-xs`; R3 raises it to `text-sm`. `check_box`
  does not honour `required:` (R3). Both already in `shared-forms`.
- `app/helpers/ui_components/ui_section_helper.rb:7,55-57`: `border: false` cannot remove the padding, because
  `BODY_BASE` already carries `px-4 pb-2`; the option only adds or leaves out a `pb-1`. Either make `false` drop
  the body padding or retire the option (callers that pass it would need checking first).
- Stale comments: `app/helpers/sidebar_helper.rb:52` gives the default width as `w-65 lg:w-55` (the signature
  says `lg:w-50`); `app/helpers/form_helper.rb:356` says the chips field's placeholder, less its ellipsis, is the
  input's accessible name, but `shared/_callsign_chips` passes `aria_label: nil` and the label names it.
