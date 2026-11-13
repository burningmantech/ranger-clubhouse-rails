# Rule IDs for `docs/DESIGN-GUIDE.md`

The guide line ranges below refer to the guide as of commit d94bda8; the rule text follows the guide as Phase 1 rewrote it.

The guide has no rule IDs, so this audit assigns them. Each ID names one statement in the guide;
`Lines` is where it is written (guide as of 2026-11-12, 4,137 lines). `Priority` is the guide's own
marker where it gives one (CRITICAL, PREFERRED, AVOID); a dash means the guide states the rule
without a marker. `Judged` says how this audit could test it: **M** a grep settles it, **R** it
needs a reader to open the code, **V** it needs a rendered page, **P** it is a process rule that
code cannot show to be kept or broken.

Keep the IDs stable: add new ones at the end of a family, and retire an ID rather than reuse it.

| ID | Priority | Lines | Judged | Rule |
|---|---|---|---|---|
| PROC-01 | CRITICAL | 197-225 | P | A UI component pattern not documented in the guide needs the owner's approval first, is built as a helper, and is then documented in the guide. The search bar's segmented radio control and the profile photo dropzone are approved one-offs; each becomes a helper on its second use. |
| PROC-02 | CRITICAL | 244-271 | P | Colour styling outside the semantic tokens and documented utilities needs approval first, is put in a component CSS file, and is then documented. |
| DENS-01 | CRITICAL | 96-106 | V | Interfaces are as compact as readability allows: minimal vertical scrolling, no decorative whitespace. |
| HELP-01 | CRITICAL | 117-144 | R | A help or FAQ section further down a page is announced and linked from the top of the page (callout with an anchor link). |
| HELP-02 | CRITICAL | 340-361 | R | A rule, legend or how-to goes in one collapsed `ui_disclosure variant: :card` per page ("About This Report" / "How This Page Works") holding an `instruction-list`, under the stat row and above the filter bar, never inside a `ui_section`. On a report or log nothing of reference stays visible; a form page may keep its Q&A open in a `ui_section` above the form. |
| COLOR-01 | CRITICAL | 379-380, 1012-1014, 4013 | M | Semantic colour tokens only; never a Tailwind palette value (`text-gray-700`, `bg-white`) or a `dark:` pair on a raw colour in markup. Printed paper is `bg-paper` / `print:bg-paper` (`--color-paper`), white whatever the theme. |
| COLOR-02 | CRITICAL | 148-178, 3915-3921 | R | Colour carries meaning (status, warning, success), never decoration: no coloured backgrounds, borders or gradients without a semantic purpose. A stat tile takes a status variant only when its value is a status, and `:secondary` at zero. The red "live data" callout on the mentoring Shift Report and Alpha Sign-Out pages is an approved use of `:error`. |
| COLOR-03 | AVOID | 176, 3920 | R | No coloured text for emphasis; use weight and size. |
| COLOR-04 | CRITICAL | 156-158 | R | Primary (Signal Blue) is for primary actions and key elements only. |
| COLOR-05 | PREFERRED | 171, 635-637 | R | Icons are neutral (`text-stone-muted`, `text-stone-icon`) unless they convey status; a status icon takes `icon-success`, `icon-warning`, `icon-error` or `icon-info`. The hero's look is the exception: its icon and `action_box`'s are gold (`icon-warning`), and the hero stats' award gold and flame gradient stay. |
| COLOR-06 | CRITICAL | 983 | R | The same neutral text utility is used for the same purpose across pages (ladder: `text-heading`, `text-body`/`text-stone-emphasis`, `text-stone-muted`, `text-stone-subtle`, `text-stone-icon`); `me-muted` is a legacy alias, and new or touched markup writes `text-stone-muted`. |
| COLOR-07 | AVOID | 745-760 | R | The progress gradients are used only in progress components; the form fieldset's primary rule and `from-primary/5` gradient (`components/forms.css`) is the theme's one other gradient, besides the hero stats' flame, which is the hero's own look. |
| COLOR-08 | AVOID | 3888-3889 | M | No hand-picked blue CTA (`bg-blue-600`, `btn-info`); use `btn-primary`. |
| DARK-01 | CRITICAL | 1012 | V | Every user-facing element renders correctly in dark mode. |
| TYPE-01 | CRITICAL | 459, 3201 | R | Body content is `text-base`; never a smaller size for primary content. |
| TYPE-02 | AVOID / CRITICAL | 476-496 | R | `text-xs` only for `btn-xs`, badges, mobile-only table labels, icon sizing beside text, decorative footer text, labels inside a progress bar, keyboard-shortcut hints. Never for content, warnings, errors, instructions, labels, list items or notes a reader needs. |
| TYPE-03 | PREFERRED / CRITICAL | 498-519 | R | `text-sm` only for secondary content (compact navigation, `btn-sm`, badges and pills, help and error text, metadata including a list line's state words, fine print, footnote markers, a caption in an image placeholder, a muted second line under a cell's or card's main value). Never for body text, a cell's main value, tab or disclosure summary labels, form labels, label/value displays, primary card information, empty-state messages or paragraphs. |
| TYPE-04 | - | 530-535 | R | One style per heading level: `<h2>` takes `heading-section`, `<h3>` and `<h4>` take `heading-title`; nothing inside a section outweighs its title. The `<h1>` is the hero's; a page outside the app shell styles its own. |
| TYPE-05 | CRITICAL | 3185 | R | Heading hierarchy is clear and consistent (h1 > h2 > h3). |
| TYPE-06 | CRITICAL | 439-450 | M | No new fonts. `font-mono` only where a value is a literal string or cells must line up (code, document tags, client IDs, licence plates, log output, format examples); not for prose, headings or ordinary table text. |
| TYPE-08 | - | 521-528 | R | Weights by role: `font-normal` body, `font-medium` labels, `font-semibold` headings, buttons and totals, `font-bold` strong emphasis. |
| TYPE-07 | - | 452-455 | R | Digits that stack outside a table take `tabular-nums`, not the mono face. |
| SPACE-01 | - | 537-554 | R | Spacing follows the Tailwind scale, no arbitrary value without a comment; defaults: card padding `p-4` or `p-2 lg:p-4` (`p-3` for a dense repeated card), section margin `mb-4`, button-row gap the row's own, form field spacing `mb-3`. |
| SPACE-02 | - | 556-568 | M | A bulleted list is `list-bulleted`, a numbered one `list-numbered`; never `list-disc`/`list-decimal` on their own, a numeric indent (`ms-5`, `pl-4`) or `list-inside`; lines led by a typed marker are a list. |
| SPACE-03 | - | 668-672 | M | No classes on the `<dt>` or `<dd>` of an `instruction-list`. |
| LIST-01 | - | 655-697, 2762-2774, 3626-3633 | R | Instructional or explanatory content is a Q&A `dl.instruction-list`, not paragraphs; every `<dt>` is a question. |
| RADIUS-01 | - | 584-592 | R | Radius by role: `rounded-field` (8px, daisyUI `--radius-field`) buttons and inputs, `rounded-base` (12px) cards, `rounded-lg` modals and panels that are not cards, `rounded-2xl` a full profile photo, `rounded-full` badges, small avatars and pills. |
| SHADOW-01 | - | 594-611 | R | Flat by default: a new component gets no shadow (lift belongs to `.box`, the hero, `ui_card`'s default `shadow-xs`, floating panels, and `shadow-lg` on a pinned bar content scrolls beneath, the HQ window's checklist strip); hover is a colour change, never a lift. |
| STYLE-01 | CRITICAL | 365-371, 4026 | M | No inline `style=` attribute except a computed CSS custom property set by a helper or controller, no scoped or per-view CSS, no CSS outside `components/` except element base styles in `base.css`; a one-page component still gets its own `components/` file. |
| STYLE-02 | CRITICAL | 365-369 | R | Tailwind and daisyUI utilities in markup first; an `@utility` only when the same 3+ classes recur in 3+ places. |
| STYLE-04 | - | 613-653, 924-925 | R | The documented custom utilities (`flex-center`, `flex-center-gap-2`, `inline-flex-center-gap-2`, the `icon-*` four, `card-standard`, `toast-*`, `sidebar-*`, `table-*`, `ac-*`) are the vocabulary; reach them through their helper where one exists. |
| STYLE-03 | AVOID | 924-925, 3893-3895, 3930 | R | Use the helper where one exists: no raw HTML, inline utility markup or ad-hoc wrapper doing a helper's job. |
| TOUCH-01 | CRITICAL | 570-582, 3210, 4017 | R | Interactive elements have a 36px minimum target (`min-h-9` where nothing else floors it); never `min-h-[36px]`, `min-h-11` or a raw `min-height`. `LinkHelper::TABLE_LINK_CLASSES` is the one standing exception; any other is commented. |
| TOUCH-02 | - | 577-579 | R | An icon-only `ButtonHelper` button takes `btn-square`. |
| BTN-01 | CRITICAL | 1071, 934-935, 4014 | R | Buttons come from `ButtonHelper` methods; never raw button HTML or the `btn` classes written by hand. Ruled exceptions, each a helper's own raw button: the client-side sort heading, `clipboard_button`'s icon, `dropdown_button`; and the roll call roster row, one whole-row `button_to`. A link in a list row that reads as a button is a real `button_link`, never `btn` classes on a span. |
| BTN-02 | - | 1101-1103 | R | No hand-applied `bg-*` or `ring-*` utilities on a button, nor `btn-link`, padding or a text size; `class:` carries width and margin, colour comes from the variant and size from `size:`. |
| BTN-03 | CRITICAL | 1157-1174 | R | `xs` buttons only for icon-only actions in dense table rows, compact navigation, constrained secondary actions, debug buttons; never for a primary call to action, a form submit, a button with text to read, navigation, or an action in a card or section. |
| BTN-04 | CRITICAL | 3186-3187 | R | One clear primary action per form, dialog or section; no row of several primaries and no primary on every table row. The same action may repeat above and below a long table. |
| BTN-05 | - | 1088-1097 | R | Variants by role: `:primary` the main action (a positive one included), `:secondary` secondary (Apply Filters when the page has its own primary), `:error` destructive, `:success` a positive action that is not the main one, `:warning` warning, `:ghost` minimal, `:dark` dark chrome only. |
| BTN-06 | - | 1129 | R | `edit_link` is the one edit control; a table row's id or name link to the record's page is a row link, never labelled "Edit". |
| BTN-07 | - | 1132-1136, 2844-2889 | R | Every page or form action sits in a `button_row`, a lone button included; a form's save and cancel are `f.submit` + `cancel_link` in one; a sticky row holds controls only. Exempt: one row's or card's record actions, a button in a callout, a title-row button, a toolbar shared with a pager, count or field. |
| BTN-08 | - | 3141-3145 | R | No margin option on an icon inside a button; `.btn` already has the gap. |
| CARD-01 | - | 699-715, 1192-1214 | R | One card utility: `card-standard`, rendered by `ui_card`; not `card-border`; `ui_card` adds `shadow-xs` by default (`shadow: :none` drops it); padding set at the call site. |
| CARD-02 | - | 1216-1296 | R | A left-border accent card is `ui_accent_card`, with a variant that matches the status and a `heading_level:` when its title labels its content. |
| CARD-03 | - | 1919-1976 | R | Related content is grouped in `ui_section` (titled, except one boxing a whole page body or form; sibling sections all carry an icon or none do); two columns come from a `flex flex-col lg:flex-row gap-4` wrapper. |
| STAT-01 | - | 1320, 1360-1366 | R | A page's summary tiles are `ui_stat_box` inside `ui_stat_row`; never a hand-rolled div or grid. A value is a short figure or word; `class:` sets width or margin only. |
| STAT-02 | CRITICAL | 313-328, 1833-1847 | R | No stats in the hero (`hero_stats`, `stat_badge`) outside the /me dashboard welcome banner. |
| HERO-01 | - | 3025-3037 | R | Every page inside the app shell heads with a `hero_panel`; sign-in pages, print sheets, kiosk, bookmark and wall-display pages, `public/` error pages and the test harness head themselves. |
| HERO-02 | CRITICAL | 332-338, 1849-1855 | R | The hero description is one sentence saying what the page does, in the panel's own style; every hero has one except a new or edit form page. The person page's hero is an identity strip: its description holds badges, name and pronouns instead. |
| HERO-03 | - | 3039-3055 | R | A year selector lives in the hero panel (`panel.year_selector`). |
| HERO-04 | - | 3057-3075 | R | Back navigation lives in the hero panel (`panel.back_to` with `back_to`), never repeated at the foot; a body link back only for a step back, a re-post or an empty result's one action; a print sheet's sits `print:hidden` above it. |
| TABLE-01 | - | 1368-1394 | R | Data tables are `ui_table`; `class:` on the table and its cells carries layout only. Blank print grids, card lists and roster grids are not data tables. |
| TABLE-02 | CRITICAL | 1490-1519 | R | `ui_table` stays responsive. `responsive: false` only for a deliberate matrix or sorted ledger (with a comment at the call site), a print sheet, or a table of about four columns or fewer. The Shift Lead roster keeps its hand-built phone list in place of the fold. |
| TABLE-03 | CRITICAL | 514 | R | A table cell's main value is `text-base`; a muted second line under it may be `text-sm`. |
| TABLE-04 | PREFERRED | 1559-1570 | R | A table page's filters use `filter_bar`; no ad-hoc filter form, accordion or chip row. |
| TABLE-05 | - | 1572-1580, 4024 | R | On a page with a filter bar the CSV export sits in `filter_bar actions:`, not in a `button_row` above or below it; with no filter bar it sits in the page's `button_row` above the table. |
| TABLE-06 | - | 1533-1557 | R | Sort on the server; sort in the browser only when the server cannot reproduce the rows, with the documented `table-sort` markup. |
| MODAL-01 | - | 1584-1603 | R | Modals come from `ModalHelper` (`modal` with `m.title`, `m.body`, `m.footer`), with a `button_row` footer and `modal_close_button`; opened through the `modal` Stimulus controller, except the `dialog` controller's on-demand dialogs and the HQ wizard. |
| MODAL-02 | - | 3822-3827 | R | A confirm dialog asks with the action (`Delete this note?`) and says what follows (whether a destructive one can be undone); a destructive confirm is red (`delete_button`, which confirms by default, or `confirm_modal ... variant: :error`). Never "Are you sure…", never `window.confirm`. |
| DISC-01 | - | 1605-1624, 3635 | R | Collapsible content is `ui_accordion` or `ui_disclosure` (native `<details>`); `summary_class:` sets the summary text's weight, size and ink only; `unstyled: true` only for a custom shell with its own CSS component; long text uses the `read-more` controller. The HQ window's guided-flow sections and pinned checklist strip are purpose-built and keep their own markup. |
| TABS-01 | - | 1657-1674 | R | Tabs come from `tab_navigation`; the `tabs` markup is not hand-written. A switch that loads another view of the page is a button group, not tabs (the mega menu's panel switch included); the mailbox's folder switch keeps its tabs look. |
| TOAST-01 | - | 1680-1704 | R | Flash messages are set in the controller and rendered by the layout as toasts; type decides duration and ARIA role. A streamed (`ui_toast_render`) or template-cloned toast is the same toast. |
| TOAST-02 | - | 1716-1719 | R | Something the server pushes updates a persistent indicator; it does not pop a toast. |
| TOAST-03 | - | 1755-1776 | R | A copy is confirmed by a "Copied" tip at the control (`clipboard_button`), not a toast. |
| ALERT-01 | - | 1721-1753 | R | Inline notices in the page body are `ui_callout_box` or `ui_alert_banner`; inside a card, step, cell, label/value row or dialog body a one-line status message may be status-coloured text led by its status icon, sentence case. `class:` on a callout is margin and width. |
| EMPTY-01 | - | 2306-2324, 3094-3101 | R | A list, table or section the reader came for, and a search's results, show `ui_empty_state` when empty (never a hand-rolled box or header-only table); one that cannot be empty where drawn, a fixed catalogue, or a supplementary list may render nothing. |
| EMPTY-02 | - | 3853 | R | An empty value prints "—" (`value_or_dash`); a profile label/value display may say "None stated" through `none_stated`. A word stating a fact the data records is a value, printed plain or muted, never italic or bracketed. A zero is a value and prints as a number, in a grid cell as in a total. |
| BADGE-01 | - | 881-895, 1978-2006 | R | Badges come from `ui_badge` (variants primary, secondary, success, warning, error); `class:` is layout only, and every state of a badge set is a badge. |
| PROG-01 | - | 1898-1917 | R | Progress bars come from `ui_progress_bar`. |
| NAV-01 | - | 2326-2343 | R | A dropdown menu is `dropdown_menu` with `dropdown_item` (`dropdown_button` for a row that acts on the page); it closes on Escape, an outside click and a choice. |
| NAV-02 | - | 2008-2304 | R | Primary navigation is the sidebar built by `SidebarHelper`: each layout calls `sidebar_menu` with `sidebar_render_menu(Menus::…)`; items carry no icon or badge. |
| NAV-03 | - | 1626-1655 | R | Stepping through search matches uses `ui_match_stepper`, pinned on its own row and drawn only when there is a match. |
| NAV-04 | - | 3285-3305 | R | A directory's quick navigation is `dropdown_scroll_list`, with plain fragment links (`data-turbo="false"`); a lead-in sits in its own element. |
| MSG-01 | - | 762-795 | R | A search match is `<mark class="search-hit">`; a conversation is drawn as two-sided bubbles by `common/messages/_message_card`. |
| AC-01 | - | 2345-2360 | R | Autocomplete dropdowns use the `ac-*` classes. |
| TOUR-01 | - | 2362-2384 | R | The driver.js tour exists only on /me; a second tour needs approval. |
| FORM-01 | CRITICAL | 2390-2423, 4015 | R | Forms that collect input use `AppFormBuilder` through `ui_form` (or `form_with ... builder: AppFormBuilder`); a fieldless carrier form and a browser-only filter input are not such forms. |
| FORM-02 | - | 2398, 2461, 2709 | R | Every field has a visible label; never placeholder-only. In a grid of rows the column heading is the visible label, with `hide_label:` and an `aria-label`. |
| FORM-03 | - | 2400, 2462, 2710 | R | A required field is marked through `required:` (every field, `check_box` included): the visible word "(required)" at `text-sm` in the error colour, on every form, sign-in and register included; there is no asterisk form. |
| FORM-04 | - | 2463-2464, 2711 | R | Help text is the field's `help_text:`, tied to it by `aria-describedby`; a character counter line is help text too. |
| FORM-05 | - | 2579-2674, 3196 | R | Fields are grouped with `f.fieldset` (radio and checkbox groups, compact forms) or `ui_section` (profile-style forms with explanations). The People Search criteria panel is not a fieldset. |
| FORM-06 | - | 2676-2703 | R | Errors show through the builder: `input-error` on the field, a message with `role="alert"` under it, and `ui_form`'s summary at the top. A form with no model or many records reports a refusal in an error callout naming the failed rows, never a flash alone. |
| FORM-07 | - | 2785-2813 | R | Field widths fit their content and are responsive (`w-full sm:w-48` and friends) through `width:`, at `sm:` on a scale step; in a filter panel or `form_row` each field fills its share. |
| FORM-08 | - | 2722-2747, 3329-3355 | R | A form page is hero (back link where the reader came from a page; description optional on new/edit), optional callouts, `ui_form`, then the button row last; sections inside or around the form are optional. |
| FORM-09 | - | 2529-2556 | R | Rich text is for formatted body copy only; saved rich text renders inside `.lexxy-content` through `rich_text`. |
| FORM-10 | - | 2833-2842 | R | A sub-group inside a section is divided with `mt-4 pt-3 border-t border-line`; a card's footer row uses the same divider, with `mt-3` allowed. |
| BP-01 | PREFERRED / AVOID | 2907-2968, 4011 | M | Mobile first with `lg:` as the one structural fold; `xl:` for optional refinement; `md:` only for `.button-row` stacking and its spacer; `sm:` only in a form field's `width:`. The date picker's 768px swap to the native control is a touch-device swap, not a fold. |
| BP-02 | - | 2924-2927 | M | The `lg` fold in CSS is written `(width < theme(--breakpoint-lg))`, never `max-width: 1024px`. |
| BP-03 | - | 2970-2988 | R | The HQ shared-display tier (1800px, 2400px) lives in `hq-window.css` only and is `@media screen`. |
| LAYOUT-01 | PREFERRED | 3236-3253 | R | A page inside the app shell follows one of the seven layout patterns (dashboard, directory, detail, form, special, records management, review pane); pages outside the shell are exempt. |
| LAYOUT-02 | - | 3077-3092, 3617-3624 | R | Page columns are `flex flex-col lg:flex-row gap-4` or `grid grid-cols-1 lg:grid-cols-N gap-4` (a fixed rail may be a track list), never `md:`; item grids inside a section pick their own scale gap and may use `columns-*`, `xl:` or a content wrap. |
| LAYOUT-03 | - | 3469-3491 | R | Records management: level 1 has no table, and no filter bar but one that sets what every row counts (site, year, type, status), a `text-lg` count line and rows in `lg:w-3/4` (which any drill-row list may borrow); a row badges only the exception count or a count marking the rows a reader hunts for (`N on duty`) (`size: "base"`); level 2 has no category filter or column, a body `ui_stat_row`, and two different empty states where both can occur. |
| LAYOUT-04 | - | 3549-3576 | R | Review pane: one line per record (the mailbox's three-line rows excepted), the pane in its own `uf-pane` frame, selection by `?person=`, the legend in the page's card. |
| ICON-01 | CRITICAL | 3111 | R | Icons are FontAwesome Free 7.1, drawn by `fa_icon`; typographic glyphs in text (·, —, →, ×) are punctuation, and a glyph standing for a word on its own is an icon. |
| ICON-02 | AVOID | 3118-3126 | M | No custom SVG icon, inline SVG markup in a view, Pro icon, or data-URI SVG (except a CSS background-image built from FontAwesome paths). |
| ICON-03 | CRITICAL | 3113-3116 | M | The regular style only for icons on the regular list; `fa_icon` raises otherwise in development and test. |
| ICON-04 | - | 356-358 | R | An icon that carries meaning with no word beside it takes `fa_icon … label:`, wherever its explanation lives. |
| MOTION-01 | CRITICAL | 3218-3225 | R | Motion is functional only (loading spinner, progress pulse, `animate-pulse` on urgent badges, sidebar slide, toast slide and countdown, copy bounce; login ambience excepted) and stops under `prefers-reduced-motion`. |
| A11Y-01 | CRITICAL | 3229-3230, 3637, 3922 | R | Status is never carried by colour alone: pair it with an icon or text. |
| A11Y-02 | CRITICAL | 3211, 3897 | R | Everything works from the keyboard, and interactive elements carry their ARIA attributes (an icon-only control has an accessible name). |
| A11Y-03 | CRITICAL | 3202, 3231 | V | Text meets WCAG AA contrast in both themes. |
| COPY-01 | CRITICAL | 3651-3712 | M | Never "work", "working", "job", "employee" or "staff" for volunteering (exceptions: payroll and Paycom surfaces, proper names, the Work History page name). |
| COPY-02 | CRITICAL | 3714-3731 | M | A person's status prints as stored, bare; never `.titleize`, brackets, quotes or italics. |
| COPY-03 | CRITICAL | 3741-3787 | R | Every heading and button label is Title Case; a heading is a label, not a question. Badge text keeps its casing; checkbox and radio labels are sentence case. |
| COPY-04 | CRITICAL | 3789-3804 | M | One verb per action: "Add X" opens a create form, "Save X" submits (never a bare "Save" or "Save Changes"), "Delete X" destroys, "Remove from X" takes out of a group, "Back to X" leaves; one action, one label everywhere; never "New", "Create", "Update", "Submit" or a bare "Back". |
| COPY-05 | CRITICAL | 3806-3820 | R | A flash's type matches the outcome; a success reads `<Thing> <past participle>.` with no "successfully", "has been" or exclamation mark. |
| COPY-06 | - | 3829-3846 | R | Validation messages are whole sentences in the reader's words, ending in a period. |
| COPY-07 | - | 3848-3854 | M | Ellipsis is "…"; "sign-up" and "check-in" as nouns, "sign up" and "check in" as verbs; "un-submit"; no exclamation marks in flash or error messages; an empty value per EMPTY-02. |
| COPY-08 | CRITICAL | 3856-3872 | M | Dates and times come from `DateTimeHelper`, never `strftime` in a view; 24-hour clock, no zero-padded day; admin logs to the second, CSV and chips to the minute. |
| COPY-09 | - | 3874-3875 | M | Prices print through `dollars(amount)`; never `"%g"` or a `$` glued to `number_with_delimiter`. |
| COPY-10 | CRITICAL / PREFERRED | 3193-3197, 2891-2899 | R | Lead with the key point; paragraphs of two or three sentences at most; specific button labels, not "Click here" or "Submit". |
