# UI Design Audit

Read-only audit of the Clubhouse 3 UI against `docs/DESIGN-GUIDE.md`, 2026-11-12, at commit `d94bda8`. No application code was changed.

- [inventory.md](inventory.md): Phase 1, what the UI does, written before the guide was read. Per-page detail is in [inventory/](inventory/).
- [rules.md](rules.md): the rule IDs this audit assigned to the guide.
- [findings.json](findings.json): one object per classified variant (`page`, `pattern`, `variant`, `classification`, `rule_id`, `severity`, `file`, `line`, `note`), sorted by file and line so a later audit can be diffed against it.
- `tools/` and `data/`: the scripts and intermediate data that produced all of the above. To re-run: `pattern_census.rb --helpers`, `build_inventory.rb`, `rule_checks.rb`, `classify.rb`, `build_report.rb`. The two reading passes (`data/inventory/*.txt`, `data/phase2/*.txt`) were done by subagents and are inputs, not regenerated.

**How a verdict was reached.** Each inventory row (a file, a pattern, a variant) got one verdict. 9,948 rows took the verdict of their variant (a call to `ui_table` is compliant with TABLE-01 wherever it appears). The other 5,157 were opened and judged one at a time by a reviewer holding the rule list: every one-off the inventory recorded, every grep hit a rule might ban, and every page checked top to bottom for the rules a row cannot show (a hero with two sentences, two primary buttons, an export in the wrong place). I then read the reviewers' verdicts against the guide's wording and reclassified 204 of them as UNCOVERED where my rule ID said more than the guide does; those are marked `lead ruling` in `findings.json` and listed under "Rules too vague to judge against" in section 4.

**How far to trust it.** I opened the code behind 36 divergent findings and 8 shared-layer claims myself: 8 from the high-severity list, 14 drawn at random from the rest, all 14 MODAL-01 findings, and the largest shared-layer claims. Thirty-nine described the code accurately. Five were wrong, all the same mistake: a reviewer reported a modal as having no footer (or a bare button in it) without tracing `modal_helper.rb`, which adds the footer and wraps it in a `button_row` itself. Those are corrected. Expect a few more of that kind among findings that say something is *missing* from a call to a shared helper; check the helper before acting on one. Separately, accuracy of description is not agreement on the reading of a rule, which is what the 204 rulings above were for. Nothing here was verified on a rendered page; section 6 lists what needs one.

## Rule IDs

The guide has no rule IDs, so the audit assigned them. `Judged`: **M** a grep settles it, **R** a reader
must open the code, **V** it needs a rendered page, **P** a process rule code cannot show. The same
table, with notes on keeping the IDs stable, is in [rules.md](rules.md).

<details><summary>All 111 rules</summary>

| ID | Priority | Guide lines | Judged | Rule |
|---|---|---|---|---|
| PROC-01 | CRITICAL | 197-225 | P | A UI component pattern not documented in the guide needs the owner's approval first, is built as a helper, and is then documented in the guide. |
| PROC-02 | CRITICAL | 244-271 | P | Colour styling outside the semantic tokens and documented utilities needs approval first, is put in a component CSS file, and is then documented. |
| DENS-01 | CRITICAL | 96-106 | V | Interfaces are as compact as readability allows: minimal vertical scrolling, no decorative whitespace. |
| HELP-01 | CRITICAL | 117-144 | R | A help or FAQ section further down a page is announced and linked from the top of the page (callout with an anchor link). |
| HELP-02 | CRITICAL | 340-361 | R | A rule, legend or how-to goes in one collapsed `ui_disclosure variant: :card` per page ("About This Report" / "How This Page Works") holding an `instruction-list`, under the stat row and above the filter bar, never inside a `ui_section`. On a report or log no Q&A list, explanatory paragraph or reference info-callout stays visible in the body. |
| COLOR-01 | CRITICAL | 379-380, 1012-1014, 4013 | M | Semantic colour tokens only; never a Tailwind palette value (`text-gray-700`, `bg-white`) or a `dark:` pair on a raw colour in markup. |
| COLOR-02 | CRITICAL | 148-178, 3915-3921 | R | Colour carries meaning (status, warning, success), never decoration: no coloured backgrounds, borders or gradients without a semantic purpose. |
| COLOR-03 | AVOID | 176, 3920 | R | No coloured text for emphasis; use weight and size. |
| COLOR-04 | CRITICAL | 156-158 | R | Primary (Signal Blue) is for primary actions and key elements only. |
| COLOR-05 | PREFERRED | 171, 635-637 | R | Icons are neutral (`text-stone-muted`, `text-stone-icon`) unless they convey status; a status icon takes `icon-success`, `icon-warning`, `icon-error` or `icon-info`. |
| COLOR-06 | CRITICAL | 983 | R | The same neutral text utility is used for the same purpose across pages (ladder: `text-heading`, `text-body`/`text-stone-emphasis`, `text-stone-muted`, `text-stone-subtle`, `text-stone-icon`). |
| COLOR-07 | AVOID | 745-760 | R | The progress gradients are used only in progress components. |
| COLOR-08 | AVOID | 3888-3889 | M | No hand-picked blue CTA (`bg-blue-600`, `btn-info`); use `btn-primary`. |
| DARK-01 | CRITICAL | 1012 | V | Every user-facing element renders correctly in dark mode. |
| TYPE-01 | CRITICAL | 459, 3201 | R | Body content is `text-base`; never a smaller size for primary content. |
| TYPE-02 | AVOID / CRITICAL | 476-496 | R | `text-xs` only for `btn-xs`, badges, mobile-only table labels, icon sizing in links, decorative footer text, labels inside a progress bar. Never for content, warnings, errors, instructions, labels, list items or notes a reader needs. |
| TYPE-03 | PREFERRED / CRITICAL | 498-519 | R | `text-sm` only for secondary content (compact navigation, `btn-sm`, badges and pills, help and error text, metadata, fine print). Never for body text, table content, tab labels, form labels, primary card information, empty-state messages or paragraphs. |
| TYPE-04 | - | 530-535 | R | One style per heading level: `<h2>` takes `heading-section`, `<h3>` and `<h4>` take `heading-title`; nothing inside a section outweighs its title. |
| TYPE-05 | CRITICAL | 3185 | R | Heading hierarchy is clear and consistent (h1 > h2 > h3). |
| TYPE-06 | CRITICAL | 439-450 | M | No new fonts. `font-mono` only where a value is a literal string or cells must line up (code, document tags, client IDs, licence plates, log output, format examples); not for prose, headings or ordinary table text. |
| TYPE-08 | - | 521-528 | R | Weights by role: `font-normal` body, `font-medium` labels, `font-semibold` headings and buttons, `font-bold` strong emphasis. |
| TYPE-07 | - | 452-455 | R | Digits that stack outside a table take `tabular-nums`, not the mono face. |
| SPACE-01 | - | 537-554 | R | Spacing follows the Tailwind scale; card padding `p-4` or `p-2 lg:p-4`, section margin `mb-4`, button-row gaps `gap-2` or `gap-4`, form field spacing `mb-3`. |
| SPACE-02 | - | 556-568 | M | A bulleted list is `list-bulleted`, a numbered one `list-numbered`; never `list-disc`/`list-decimal` on their own, a numeric indent (`ms-5`, `pl-4`) or `list-inside`. |
| SPACE-03 | - | 668-672 | M | No classes on the `<dt>` or `<dd>` of an `instruction-list`. |
| LIST-01 | - | 655-697, 2762-2774, 3626-3633 | R | Instructional or explanatory content is a Q&A `dl.instruction-list`, not paragraphs. |
| RADIUS-01 | - | 584-592 | R | Radius by role: `rounded-base` buttons and inputs, `rounded-lg` modals and panels that are not cards, `rounded-full` badges, avatars and pills. |
| SHADOW-01 | - | 594-611 | R | Flat by default: a new component gets no shadow; hover is a colour change, never a lift. |
| STYLE-01 | CRITICAL | 365-371, 4026 | M | No inline `style=` attribute, no scoped or per-view CSS, no CSS outside `components/`. |
| STYLE-02 | CRITICAL | 365-369 | R | Tailwind and daisyUI utilities in markup first; an `@utility` only when the same 3+ classes recur in 3+ places. |
| STYLE-04 | - | 613-653, 924-925 | R | The documented custom utilities (`flex-center`, `flex-center-gap-2`, `inline-flex-center`, `inline-flex-center-gap-2`, the `icon-*` four, `card-standard`, `toast-*`, `sidebar-*`, `table-*`, `ac-*`) are the vocabulary; reach them through their helper where one exists. |
| STYLE-03 | AVOID | 924-925, 3893-3895, 3930 | R | Use the helper where one exists: no raw HTML, inline utility markup or ad-hoc wrapper doing a helper's job. |
| TOUCH-01 | CRITICAL | 570-582, 3210, 4017 | R | Interactive elements have a 36px minimum target (`min-h-9` where nothing else floors it); never `min-h-[36px]`, `min-h-11` or a raw `min-height`. `LinkHelper::TABLE_LINK_CLASSES` is the one standing exception; any other is commented. |
| TOUCH-02 | - | 577-579 | R | An icon-only `ButtonHelper` button takes `btn-square`. |
| BTN-01 | CRITICAL | 1071, 934-935, 4014 | R | Buttons come from `ButtonHelper` methods; never raw button HTML or the `btn` classes written by hand. The client-side sort heading button is the one ruled exception (1543). |
| BTN-02 | - | 1101-1103 | R | No hand-applied `bg-*` or `ring-*` utilities on a button; colour, hover and focus come from the variant. |
| BTN-03 | CRITICAL | 1157-1174 | R | `xs` buttons only for icon-only actions in dense table rows, compact navigation, constrained secondary actions, debug buttons; never for a primary call to action, a form submit, a button with text to read, navigation, or an action in a card or section. |
| BTN-04 | CRITICAL | 3186-3187 | R | One clear primary action per view. |
| BTN-05 | - | 1088-1097 | R | Variants by role: `:primary` primary actions, `:secondary` secondary, `:error` destructive, `:success` positive, `:warning` warning, `:ghost` minimal, `:dark` dark chrome only. |
| BTN-06 | - | 1129 | R | `edit_link` is the one edit control. |
| BTN-07 | - | 1132-1136, 2844-2889 | R | Buttons sit in a `button_row`; a form's save and cancel are `f.submit` + `cancel_link` in one; a sticky row holds controls only. |
| BTN-08 | - | 3141-3145 | R | No margin option on an icon inside a button; `.btn` already has the gap. |
| CARD-01 | - | 699-715, 1192-1214 | R | One card utility: `card-standard`, rendered by `ui_card`; not `card-border`; no shadow by default; padding set at the call site. |
| CARD-02 | - | 1216-1296 | R | A left-border accent card is `ui_accent_card`, with a variant that matches the status and a `heading_level:` when its title labels its content. |
| CARD-03 | - | 1919-1976 | R | Related content is grouped in `ui_section`; two columns come from a `flex flex-col lg:flex-row gap-4` wrapper. |
| STAT-01 | - | 1320, 1360-1366 | R | A page's summary tiles are `ui_stat_box` inside `ui_stat_row`; never a hand-rolled div or grid. |
| STAT-02 | CRITICAL | 313-328, 1833-1847 | R | No stats in the hero (`hero_stats`, `stat_badge`) outside the /me dashboard welcome banner. |
| HERO-01 | - | 3025-3037 | R | Every page's header is a `hero_panel`. |
| HERO-02 | CRITICAL | 332-338, 1849-1855 | R | The hero description is one sentence saying what the page does. |
| HERO-03 | - | 3039-3055 | R | A year selector lives in the hero panel (`panel.year_selector`). |
| HERO-04 | - | 3057-3075 | R | Back navigation lives in the hero panel (`panel.back_to` with `back_to`). |
| TABLE-01 | - | 1368-1394 | R | Data tables are `ui_table`. |
| TABLE-02 | CRITICAL | 1490-1519 | R | `ui_table` stays responsive. `responsive: false` only for a deliberate matrix or sorted ledger (with a comment at the call site), a print sheet, or a table of about four columns or fewer. |
| TABLE-03 | CRITICAL | 514 | R | Table content is `text-base`. |
| TABLE-04 | PREFERRED | 1559-1570 | R | A table page's filters use `filter_bar`; no ad-hoc filter form, accordion or chip row. |
| TABLE-05 | - | 1572-1580, 4024 | R | On a page with a filter bar the CSV export sits in `filter_bar actions:`, not in a `button_row` above or below it. |
| TABLE-06 | - | 1533-1557 | R | Sort on the server; sort in the browser only when the server cannot reproduce the rows, with the documented `table-sort` markup. |
| MODAL-01 | - | 1584-1603 | R | Modals come from `ModalHelper` (`modal` with `m.title`, `m.body`, `m.footer`), with a `button_row` footer and `modal_close_button`; opened through the `modal` Stimulus controller. |
| MODAL-02 | - | 3822-3827 | R | A confirm dialog asks with the action (`Delete this note?`) and says whether it can be undone; a destructive confirm is red (`delete_button`, or `confirm_modal ... variant: :error`). Not "Are you sure…". |
| DISC-01 | - | 1605-1624, 3635 | R | Collapsible content is `ui_accordion` or `ui_disclosure` (native `<details>`); `unstyled: true` only for a custom shell with its own CSS component; long text uses the `read-more` controller. |
| TABS-01 | - | 1657-1674 | R | Tabs come from `tab_navigation`; the `tabs` markup is not hand-written. |
| TOAST-01 | - | 1680-1704 | R | Flash messages are set in the controller and rendered by the layout as toasts; type decides duration and ARIA role. |
| TOAST-02 | - | 1716-1719 | R | Something the server pushes updates a persistent indicator; it does not pop a toast. |
| TOAST-03 | - | 1755-1776 | R | A copy is confirmed by a "Copied" tip at the control (`clipboard_button`), not a toast. |
| ALERT-01 | - | 1721-1753 | R | Inline notices are `ui_callout_box` (`:success`, `:info`, `:warning`, `:error`, `:secondary`) or `ui_alert_banner`. |
| EMPTY-01 | - | 2306-2324, 3094-3101 | R | An empty state is always `ui_empty_state`; never a hand-rolled box. |
| EMPTY-02 | - | 3853 | R | An empty value prints "—". |
| BADGE-01 | - | 881-895, 1978-2006 | R | Badges come from `ui_badge` (variants primary, secondary, success, warning, error). |
| PROG-01 | - | 1898-1917 | R | Progress bars come from `ui_progress_bar`. |
| NAV-01 | - | 2326-2343 | R | A dropdown menu is `dropdown_menu` with `dropdown_item`. |
| NAV-02 | - | 2008-2304 | R | Primary navigation is the sidebar built by `SidebarHelper`. |
| NAV-03 | - | 1626-1655 | R | Stepping through search matches uses `ui_match_stepper`, pinned on its own row and drawn only when there is a match. |
| NAV-04 | - | 3285-3305 | R | A directory's quick navigation is `dropdown_scroll_list`, with plain fragment links (`data-turbo="false"`). |
| MSG-01 | - | 762-795 | R | A search match is `<mark class="search-hit">`; a conversation is drawn as two-sided bubbles by `common/messages/_message_card`. |
| AC-01 | - | 2345-2360 | R | Autocomplete dropdowns use the `ac-*` classes. |
| TOUR-01 | - | 2362-2384 | R | The driver.js tour exists only on /me; a second tour needs approval. |
| FORM-01 | CRITICAL | 2390-2423, 4015 | R | Forms use `AppFormBuilder` through `ui_form` (or `form_with ... builder: AppFormBuilder`); never a raw form without the builder. |
| FORM-02 | - | 2398, 2461, 2709 | R | Every field has a visible label; never placeholder-only. |
| FORM-03 | - | 2400, 2462, 2710 | R | A required field is marked through `required:` (asterisk plus screen-reader text). |
| FORM-04 | - | 2463-2464, 2711 | R | Help text is the field's `help_text:`, tied to it by `aria-describedby`. |
| FORM-05 | - | 2579-2674, 3196 | R | Fields are grouped with `f.fieldset` (radio and checkbox groups, compact forms) or `ui_section` (profile-style forms with explanations). |
| FORM-06 | - | 2676-2703 | R | Errors show through the builder: `input-error` on the field, a message with `role="alert"` under it, and `ui_form`'s summary at the top. |
| FORM-07 | - | 2785-2813 | R | Field widths fit their content and are responsive (`w-full sm:w-48` and friends) rather than full width. |
| FORM-08 | - | 2722-2747, 3329-3355 | R | A form page is hero panel (with back link), optional callouts, `ui_form` with sections, then the button row. |
| FORM-09 | - | 2529-2556 | R | Rich text is for formatted body copy only; saved rich text renders inside `.lexxy-content` through `rich_text`. |
| FORM-10 | - | 2833-2842 | R | A sub-group inside a section is divided with `mt-4 pt-3 border-t border-line`. |
| BP-01 | PREFERRED / AVOID | 2907-2968, 4011 | M | Mobile first with `lg:` as the one structural fold; `xl:` for optional refinement; `md:` only for `.button-row` stacking and its spacer; `sm:` only in a form field's `width:`. |
| BP-02 | - | 2924-2927 | M | The `lg` fold in CSS is written `(width < theme(--breakpoint-lg))`, never `max-width: 1024px`. |
| BP-03 | - | 2970-2988 | R | The HQ shared-display tier (1800px, 2400px) lives in `hq-window.css` only and is `@media screen`. |
| LAYOUT-01 | PREFERRED | 3236-3253 | R | A page follows one of the seven layout patterns (dashboard, directory, detail, form, special, records management, review pane). |
| LAYOUT-02 | - | 3077-3092, 3617-3624 | R | Columns are `flex flex-col lg:flex-row gap-4` or `grid grid-cols-1 lg:grid-cols-N gap-4`. |
| LAYOUT-03 | - | 3469-3491 | R | Records management: level 1 has no filter bar or table, a `text-lg` count line and rows in `lg:w-3/4`; a row badges only the exception count (`size: "base"`); level 2 has no category filter or column, a body `ui_stat_row`, and two different empty states. |
| LAYOUT-04 | - | 3549-3576 | R | Review pane: one line per record, the pane in its own `uf-pane` frame, selection by `?person=`, the legend in the page's card. |
| ICON-01 | CRITICAL | 3111 | R | Icons are FontAwesome Free 7.1, drawn by `fa_icon`. |
| ICON-02 | AVOID | 3118-3126 | M | No custom SVG icon, inline SVG markup in a view, Pro icon, or data-URI SVG (except a CSS background-image built from FontAwesome paths). |
| ICON-03 | CRITICAL | 3113-3116 | M | The regular style only for icons on the regular list; `fa_icon` raises otherwise in development and test. |
| ICON-04 | - | 356-358 | R | An icon whose meaning is explained only in the page's card carries `fa_icon … label:`. |
| MOTION-01 | CRITICAL | 3218-3225 | R | Motion is functional only (loading spinner, progress pulse, `animate-pulse` on urgent badges, sidebar slide; login ambience excepted) and honours `prefers-reduced-motion`. |
| A11Y-01 | CRITICAL | 3229-3230, 3637, 3922 | R | Status is never carried by colour alone: pair it with an icon or text. |
| A11Y-02 | CRITICAL | 3211, 3897 | R | Everything works from the keyboard, and interactive elements carry their ARIA attributes (an icon-only control has an accessible name). |
| A11Y-03 | CRITICAL | 3202, 3231 | V | Text meets WCAG AA contrast in both themes. |
| COPY-01 | CRITICAL | 3651-3712 | M | Never "work", "working", "job", "employee" or "staff" for volunteering (exceptions: payroll and Paycom surfaces, proper names, the Work History page name). |
| COPY-02 | CRITICAL | 3714-3731 | M | A person's status prints as stored; never `.titleize`. |
| COPY-03 | CRITICAL | 3741-3787 | R | Every heading and button label is Title Case; a heading is a label, not a question. |
| COPY-04 | CRITICAL | 3789-3804 | M | One verb per action: "Add X" opens a create form, "Save X" submits, "Delete X" destroys, "Remove from X" takes out of a group, "Back to X" leaves; never "New", "Create", "Update", "Submit" or a bare "Back". |
| COPY-05 | CRITICAL | 3806-3820 | R | A flash's type matches the outcome; a success reads `<Thing> <past participle>.` with no "successfully", "has been" or exclamation mark. |
| COPY-06 | - | 3829-3846 | R | Validation messages are whole sentences in the reader's words, ending in a period. |
| COPY-07 | - | 3848-3854 | M | Ellipsis is "…"; "sign-up" and "check-in" as nouns, "sign up" and "check in" as verbs; "un-submit"; no exclamation marks in flash or error messages. |
| COPY-08 | CRITICAL | 3856-3872 | M | Dates and times come from `DateTimeHelper`, never `strftime` in a view; 24-hour clock, no zero-padded day. |
| COPY-09 | - | 3874-3875 | M | Prices print through `dollars(amount)`; never `"%g"` or a `$` glued to `number_with_delimiter`. |
| COPY-10 | CRITICAL / PREFERRED | 3193-3197, 2891-2899 | R | Lead with the key point; paragraphs of two or three sentences at most; specific button labels, not "Click here" or "Submit". |

</details>

## 1. Summary

| | |
|---|---|
| Templates audited | 578 (450 pages, 119 fragments, 9 print sheets) |
| Also inventoried | 27 layouts, 12 turbo-stream responses, 12 others; 496 shared helpers, classes, tokens and controllers |
| Pattern variants classified | 15105 (after merging 312 duplicate records of the same departure) |
| COMPLIANT | 11004 |
| DIVERGENT | 1129 (52 high, 558 medium, 519 low) |
| UNCOVERED | 2972 |
| Templates with no divergent finding | 174 of 578 |

**The UI is consistent where a helper exists and drifts where one does not.** 73% of what was classified is a shared helper, builder field or token used as the guide documents it. The 1,129 departures cluster in a few places:

- **The shared layer itself (90).** The form builder, the modal and tab helpers and the stylesheets depart from what the guide documents for them, and every page inherits it. The ones that matter: the required-field marker is a visible `text-xs` "(required)" where the guide documents an asterisk with screen-reader text; `help_mode: :tooltip` leaves `aria-describedby` pointing at an id that is never rendered; a radio button sits outside its 36px label; inactive tabs get `tabindex="-1"` and no key handler reaches them; the `modal` dialog has no accessible name; `delete_button` with no confirm option deletes without asking, though the guide says it "includes confirmation". These are in section 3.3 and are the cheapest fixes per page affected.
- **Shared templates under `common/` (145 there; 309 across all shared partials and area helpers).** The schedule, timesheet, shift check-in and messages screens are rendered for /me, /person and /hq, so each departure shows three times. They carry most of the `md:` layout tiers, hand-made cards and red-text notices.
- **Type size (104).** `text-sm` on table cells, paragraphs and labels (92, the most-broken rule) and `text-xs` on text a reader needs (12, all high).
- **Forms built outside the builder (66).** Pickers and bulk tools made from `form_tag`, `select_tag` and `check_box_tag`, most borrowing the builder's class constants so they look the same.
- **Empty states and empty values (123).** Plain or red text instead of `ui_empty_state` (59), and "-", "None", italics or blanks instead of "—" (64).
- **Confirmation (46).** Destructive confirms that are not red, browser `confirm()` dialogs, and wording that does not say whether the action can be undone.
- **Copy (163, all low).** Sentence-case headings and labels (81), "New"/"Create"/"Update" verbs (46), `strftime` in views (21).

**What no rule covers is mostly the unglamorous half of the system:** links, dialog shells other than `modal`, loading states, pagination, label/value blocks, bulk selection, where a button sits, print sheets. 2,972 variants are UNCOVERED; 512 of them are cases where a rule exists but does not settle the case. Section 4 ranks them.

**By area** (divergent findings in files under each `app/views` area): common 145, person 87, me 86, mentoring 72, vc 70, training 56, scheduling 53, shift_operations 42, communication 41, admin 41, teams_positions 30, hq 29, profile_photos 25, bmid 20, dashboard_tasks 19, timesheets 19, ticketing 18. The cleanest: quartermaster (4), layouts (3), asset_management (3), pogs (1). 174 of 578 templates have no divergent finding at all, counting the partials they render.

### The five pages furthest out of sync

Ranked by weighted divergent findings on the page and the partials it renders (high 3, medium 2, low 1).
"Own file" counts only the page's own template, so a page is not ranked high merely for rendering a
shared partial that has findings.

| # | Page | Route | Score | High | Medium | Low | Own-file score | Main departures |
|---|---|---|---|---|---|---|---|---|
| 1 | `common/schedule/index.html.erb` | /me/schedule, /person/:person_id/schedule, /hq/:person_id/schedule | 33 | 0 | 13 | 7 | 14 | BP-01 ×6, BTN-01 ×2, COLOR-02 ×2, SPACE-03 ×2 |
| 2 | `hq/shift_manage/index.html.erb` | /hq/:person_id/shift-manage | 33 | 0 | 13 | 7 | 3 | BTN-04 ×4, ICON-01 ×3, COPY-04 ×3, MODAL-02 ×1 |
| 3 | `scheduling/shift_lead/index.html.erb` | /scheduling/shift-lead | 33 | 1 | 11 | 8 | 1 | FORM-01 ×4, TYPE-03 ×3, COPY-03 ×3, TABLE-02 ×2 |
| 4 | `common/timesheet/index.html.erb` | /me/timesheet, /me/timesheet/manage, /hq/:person_id/timesheets | 31 | 0 | 12 | 7 | 14 | BP-01 ×4, CARD-01 ×3, COPY-03 ×3, COLOR-06 ×2 |
| 5 | `person/memberships/edit.html.erb` | /person/:person_id/membership/edit | 28 | 0 | 13 | 2 | 5 | FORM-01 ×5, TYPE-03 ×4, NAV-01 ×2, EMPTY-01 ×1 |

The next fifteen:

| # | Page | Score | Own-file score |
|---|---|---|---|
| 6 | `profile_photos/new.html.erb` | 25 | 25 |
| 7 | `profile_photos/crop.html.erb` | 24 | 24 |
| 8 | `communication/rbs_broadcasts/new.html.erb` | 22 | 0 |
| 9 | `vc/applications/show.html.erb` | 21 | 2 |
| 10 | `vc/handle_checker/index.html.erb` | 19 | 6 |
| 11 | `mentoring/alpha_mentor_assignments/index.html.erb` | 17 | 17 |
| 12 | `hq/site_registration/show.html.erb` | 17 | 10 |
| 13 | `profile/show.html.erb` | 17 | 3 |
| 14 | `shift_operations/rollcall/sign_in.html.erb` | 17 | 3 |
| 15 | `alerts/edit.html.erb` | 16 | 8 |
| 16 | `people/people_by_location/index.html.erb` | 16 | 2 |
| 17 | `communication/rbs_messages/index.html.erb` | 15 | 7 |
| 18 | `vc/thank_you_cards/index.html.erb` | 15 | 5 |
| 19 | `shift_operations/rollcall/sign_out.html.erb` | 15 | 1 |
| 20 | `common/messages/index.html.erb` | 15 | 0 |

### Rules departed from most

| Rule | Findings | High | Medium | Low | Templates touched | Rule |
|---|---|---|---|---|---|---|
| TYPE-03 | 92 | 0 | 92 | 0 | 98 | `text-sm` only for secondary content (compact navigation, `btn-sm`, badges and pills, help and error text, metadata, fine print). Never for body text, |
| COPY-03 | 81 | 0 | 0 | 81 | 80 | Every heading and button label is Title Case; a heading is a label, not a question. |
| FORM-01 | 66 | 4 | 61 | 1 | 43 | Forms use `AppFormBuilder` through `ui_form` (or `form_with ... builder: AppFormBuilder`); never a raw form without the builder. |
| EMPTY-02 | 64 | 0 | 0 | 64 | 57 | An empty value prints "—". |
| EMPTY-01 | 59 | 0 | 18 | 41 | 74 | An empty state is always `ui_empty_state`; never a hand-rolled box. |
| COPY-04 | 46 | 0 | 0 | 46 | 66 | One verb per action: "Add X" opens a create form, "Save X" submits, "Delete X" destroys, "Remove from X" takes out of a group, "Back to X" leaves; nev |
| MODAL-02 | 46 | 0 | 17 | 29 | 47 | A confirm dialog asks with the action (`Delete this note?`) and says whether it can be undone; a destructive confirm is red (`delete_button`, or `conf |
| BP-01 | 41 | 0 | 23 | 18 | 48 | Mobile first with `lg:` as the one structural fold; `xl:` for optional refinement; `md:` only for `.button-row` stacking and its spacer; `sm:` only in |
| STYLE-01 | 37 | 0 | 6 | 31 | 26 | No inline `style=` attribute, no scoped or per-view CSS, no CSS outside `components/`. |
| BTN-04 | 35 | 0 | 31 | 4 | 37 | One clear primary action per view. |
| HELP-02 | 31 | 4 | 17 | 10 | 37 | A rule, legend or how-to goes in one collapsed `ui_disclosure variant: :card` per page ("About This Report" / "How This Page Works") holding an `instr |
| CARD-01 | 26 | 0 | 25 | 1 | 53 | One card utility: `card-standard`, rendered by `ui_card`; not `card-border`; no shadow by default; padding set at the call site. |
| BTN-05 | 24 | 4 | 20 | 0 | 22 | Variants by role: `:primary` primary actions, `:secondary` secondary, `:error` destructive, `:success` positive, `:warning` warning, `:ghost` minimal, |
| TYPE-04 | 22 | 0 | 11 | 11 | 22 | One style per heading level: `<h2>` takes `heading-section`, `<h3>` and `<h4>` take `heading-title`; nothing inside a section outweighs its title. |
| COPY-08 | 21 | 0 | 0 | 21 | 28 | Dates and times come from `DateTimeHelper`, never `strftime` in a view; 24-hour clock, no zero-padded day. |
| STYLE-03 | 20 | 0 | 18 | 2 | 18 | Use the helper where one exists: no raw HTML, inline utility markup or ad-hoc wrapper doing a helper's job. |
| COLOR-05 | 19 | 0 | 4 | 15 | 25 | Icons are neutral (`text-stone-muted`, `text-stone-icon`) unless they convey status; a status icon takes `icon-success`, `icon-warning`, `icon-error`  |
| COLOR-02 | 19 | 0 | 16 | 3 | 15 | Colour carries meaning (status, warning, success), never decoration: no coloured backgrounds, borders or gradients without a semantic purpose. |
| COLOR-03 | 18 | 0 | 18 | 0 | 19 | No coloured text for emphasis; use weight and size. |
| TYPE-05 | 18 | 0 | 11 | 7 | 24 | Heading hierarchy is clear and consistent (h1 > h2 > h3). |
| FORM-07 | 17 | 0 | 4 | 13 | 20 | Field widths fit their content and are responsive (`w-full sm:w-48` and friends) rather than full width. |
| FORM-06 | 16 | 0 | 15 | 1 | 10 | Errors show through the builder: `input-error` on the field, a message with `role="alert"` under it, and `ui_form`'s summary at the top. |
| STAT-01 | 15 | 3 | 12 | 0 | 17 | A page's summary tiles are `ui_stat_box` inside `ui_stat_row`; never a hand-rolled div or grid. |
| COLOR-01 | 15 | 0 | 3 | 12 | 6 | Semantic colour tokens only; never a Tailwind palette value (`text-gray-700`, `bg-white`) or a `dark:` pair on a raw colour in markup. |
| BTN-01 | 14 | 2 | 12 | 0 | 23 | Buttons come from `ButtonHelper` methods; never raw button HTML or the `btn` classes written by hand. The client-side sort heading button is the one r |

## 2. Page-by-pattern matrix

One row per audited template, one column per pattern. `D`*n*: at least one divergent variant (*n* of them);
`U`: no divergence, at least one variant no rule covers; `C`: every variant found is covered and compliant;
`·`: the pattern does not occur. A cell reflects the template and every partial it renders.

<details><summary><strong>admin</strong> (43 templates, own-file divergence score 40)</summary>

| Template | Btn | Link | Form | Valid | Modal | Table | Nav | Card | Alert | Empty | Type | Color | Space | Icon | Other |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `action_logs/index.html.erb` | C | U | **D3** | U | · | U | U | C | C | C | **D4** | C | U | U | U |
| `bug_reports/index.html.erb` | U | U | · | · | · | U | · | C | · | C | **D1** | C | C | C | · |
| `documents/body.html.erb` | C | U | · | · | · | · | · | **D1** | · | U | C | **D1** | C | · | **D1** |
| `documents/edit.html.erb` | C | · | C | U | · | · | C | · | C | · | C | · | · | C | · |
| `documents/index.html.erb` | C | U | · | · | · | U | · | **D1** | C | U | U | **D1** | U | C | **D1** |
| `documents/new.html.erb` | C | · | C | U | · | · | C | · | C | · | C | · | · | C | · |
| `error_logs/index.html.erb` | U | U | C | U | · | U | U | C | · | C | **D1** | C | C | U | U |
| `event_dates/edit.html.erb` | C | · | C | C | · | · | C | · | · | · | **D2** | · | C | C | · |
| `event_dates/index.html.erb` | C | · | · | · | · | C | · | C | C | C | C | · | C | C | · |
| `event_dates/new.html.erb` | C | · | C | C | · | · | C | · | · | · | **D2** | · | C | C | · |
| `jobs/index.html.erb` | **D1** | · | C | U | C | U | U | U | · | C | U | C | U | U | U |
| `legacy_log/index.html.erb` | C | U | **D3** | U | · | U | U | C | · | C | **D2** | C | U | U | · |
| `mail_log/index.html.erb` | C | U | C | U | · | C | U | C | · | **D1** | U | C | U | **D1** | · |
| `oauth_clients/edit.html.erb` | C | · | C | C | **D1** | C | C | C | · | · | **D1** | · | C | C | · |
| `oauth_clients/index.html.erb` | C | · | · | · | · | C | · | C | C | C | C | · | C | C | U |
| `oauth_clients/new.html.erb` | C | · | C | C | **D1** | C | C | C | · | · | **D1** | · | C | C | · |
| `online_courses/edit.html.erb` | U | · | C | U | · | · | C | · | · | C | U | C | C | C | C |
| `online_courses/enrollment.html.erb` | · | · | · | · | · | · | C | · | · | U | C | C | C | C | C |
| `online_courses/enrollment_roster.html.erb` | · | U | · | · | · | C | · | C | C | U | U | C | · | · | C |
| `online_courses/index.html.erb` | C | · | · | · | · | U | C | · | C | C | U | · | C | C | C |
| `online_courses/moodle_catalog.html.erb` | · | · | · | · | · | · | C | · | · | U | C | C | C | C | C |
| `online_courses/moodle_catalog_courses.html.erb` | **D1** | · | · | · | · | U | · | · | C | U | **D1** | C | · | U | C |
| `online_courses/new.html.erb` | C | · | C | U | · | · | C | · | · | · | C | · | · | C | C |
| `passkeys/index.html.erb` | C | U | **D1** | · | · | **D1** | U | C | · | C | U | · | C | C | C |
| `permissions/edit.html.erb` | C | · | C | U | · | U | C | U | · | · | C | · | · | U | · |
| `permissions/index.html.erb` | **D1** | · | · | · | · | C | · | C | C | C | **D2** | C | C | U | C |
| `permissions/new_art.html.erb` | **D1** | · | C | C | · | U | C | U | · | · | **D1** | · | · | U | · |
| `rbs_alerts/edit.html.erb` | C | · | **D1** | U | · | U | C | U | · | · | C | · | C | C | C |
| `rbs_alerts/index.html.erb` | C | · | · | · | · | C | · | C | C | C | U | C | C | C | U |
| `request_logs/index.html.erb` | U | U | C | U | **D1** | **D1** | U | C | C | C | **D4** | C | C | U | U |
| `salesforce_query/index.html.erb` | C | · | C | C | · | U | · | C | C | U | C | C | U | C | C |
| `settings/edit.html.erb` | C | · | **D2** | U | · | · | C | U | C | · | U | · | C | C | U |
| `settings/index.html.erb` | U | · | **D2** | · | · | C | · | C | C | C | U | C | C | C | C |
| `shift_coverage_groups/edit.html.erb` | C | · | **D1** | C | · | · | C | · | · | · | C | C | C | C | · |
| `shift_coverage_groups/index.html.erb` | C | U | · | · | · | C | · | C | · | C | C | · | C | C | · |
| `shift_coverage_groups/new.html.erb` | C | · | **D1** | C | · | · | C | · | · | · | C | C | C | C | · |
| `shift_coverage_groups/show.html.erb` | C | · | · | · | · | U | C | C | · | C | C | · | C | C | U |
| `shift_coverage_positions/edit.html.erb` | C | · | **D4** | **D3** | · | · | C | · | · | · | C | · | U | C | · |
| `shift_coverage_positions/new.html.erb` | C | · | **D4** | **D3** | · | · | C | · | · | · | C | · | U | C | · |
| `sms_management/index.html.erb` | **D1** | U | C | U | **D1** | U | · | C | **D1** | U | U | C | U | U | C |
| `sms_management/lookup.html.erb` | C | U | C | U | · | U | · | · | C | U | U | · | U | U | C |
| `sms_management/messages.html.erb` | · | U | C | · | · | C | U | · | C | U | U | · | C | U | C |
| `sms_management/twilio.html.erb` | U | U | C | U | **D1** | U | · | · | **D1** | U | U | · | C | U | C |

</details>

<details><summary><strong>alerts</strong> (1 templates, own-file divergence score 8)</summary>

| Template | Btn | Link | Form | Valid | Modal | Table | Nav | Card | Alert | Empty | Type | Color | Space | Icon | Other |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `edit.html.erb` | **D1** | U | **D3** | U | · | U | C | **D1** | U | · | **D2** | C | **D1** | C | **D1** |

</details>

<details><summary><strong>asset_management</strong> (10 templates, own-file divergence score 3)</summary>

| Template | Btn | Link | Form | Valid | Modal | Table | Nav | Card | Alert | Empty | Type | Color | Space | Icon | Other |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `asset_history/index.html.erb` | U | U | C | · | · | U | U | C | · | C | C | C | C | C | C |
| `assets_outstanding/index.html.erb` | U | U | C | · | · | U | C | C | · | C | C | C | · | C | C |
| `radio_assets/index.html.erb` | U | U | C | · | · | C | **D1** | C | C | C | C | · | C | C | · |
| `radio_checkout/index.html.erb` | U | U | · | · | · | U | U | C | C | C | U | C | C | C | C |
| `records/edit.html.erb` | C | · | **D1** | U | · | · | C | C | · | · | C | · | · | C | U |
| `records/index.html.erb` | U | · | C | · | · | C | C | · | · | C | C | · | U | C | C |
| `records/new.html.erb` | C | · | **D1** | U | · | · | C | C | · | · | **D1** | · | · | C | U |
| `records/show.html.erb` | C | U | C | · | · | U | C | C | C | C | C | · | U | C | C |
| `records/type.html.erb` | U | · | C | · | · | C | C | C | · | C | C | · | U | C | C |
| `search/index.html.erb` | C | U | C | U | · | U | C | C | C | C | C | · | C | C | C |

</details>

<details><summary><strong>bmid</strong> (14 templates, own-file divergence score 19)</summary>

| Template | Btn | Link | Form | Valid | Modal | Table | Nav | Card | Alert | Empty | Type | Color | Space | Icon | Other |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `badges/edit.html.erb` | C | · | **D1** | U | · | U | C | C | C | · | **D3** | C | C | C | U |
| `export/create.html.erb` | U | U | C | · | · | C | C | C | C | C | U | · | C | C | U |
| `export/index.html.erb` | U | U | U | · | **D2** | U | U | C | C | U | C | C | U | C | U |
| `export/unsubmit.html.erb` | U | U | C | · | · | C | C | C | C | **D1** | C | · | C | C | U |
| `manage/index.html.erb` | **D1** | **D1** | U | U | U | U | C | C | C | U | C | C | C | C | U |
| `provisions/edit.html.erb` | **D1** | · | **D3** | U | **D1** | C | · | C | · | U | **D1** | U | C | C | · |
| `provisions/index.html.erb` | C | · | · | · | C | C | · | · | · | C | C | C | **D1** | C | · |
| `provisions/new.html.erb` | **D1** | · | **D3** | U | **D1** | C | · | C | · | U | **D1** | U | C | C | · |
| `sanity_check/index.html.erb` | C | U | C | · | · | **D1** | · | U | **D1** | C | C | C | C | C | **D1** |
| `titles/apply.html.erb` | C | U | · | · | · | **D1** | C | C | · | C | C | C | U | C | U |
| `titles/edit.html.erb` | **D1** | · | **D2** | C | · | C | C | · | · | · | C | · | C | C | · |
| `titles/index.html.erb` | U | · | · | · | · | **D1** | · | C | · | C | C | · | C | C | · |
| `titles/new.html.erb` | **D1** | · | **D2** | C | · | C | C | · | · | · | **D1** | · | C | C | · |
| `titles/set.html.erb` | C | U | **D2** | U | · | **D1** | C | C | C | C | U | C | C | C | U |

</details>

<details><summary><strong>bookmarks</strong> (3 templates, own-file divergence score 1)</summary>

| Template | Btn | Link | Form | Valid | Modal | Table | Nav | Card | Alert | Empty | Type | Color | Space | Icon | Other |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `document.html.erb` | · | · | · | · | · | · | · | · | · | U | U | **D1** | **D1** | · | **D1** |
| `not_found.html.erb` | · | · | · | · | · | · | · | · | · | C | U | · | U | C | · |
| `show.html.erb` | · | · | · | · | · | · | **D1** | · | · | U | U | **D1** | **D1** | · | **D1** |

</details>

<details><summary><strong>bug_reports</strong> (1 templates, own-file divergence score 0)</summary>

| Template | Btn | Link | Form | Valid | Modal | Table | Nav | Card | Alert | Empty | Type | Color | Space | Icon | Other |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `new.html.erb` | C | U | C | C | U | · | · | · | · | · | C | · | C | · | · |

</details>

<details><summary><strong>certificates</strong> (2 templates, own-file divergence score 0)</summary>

| Template | Btn | Link | Form | Valid | Modal | Table | Nav | Card | Alert | Empty | Type | Color | Space | Icon | Other |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `certificates_report/index.html.erb` | U | · | C | · | · | C | · | C | · | C | C | · | C | C | · |
| `certificates_report/show.html.erb` | U | U | C | · | · | U | C | C | · | U | C | · | · | C | · |

</details>

<details><summary><strong>common</strong> (27 templates, own-file divergence score 71)</summary>

| Template | Btn | Link | Form | Valid | Modal | Table | Nav | Card | Alert | Empty | Type | Color | Space | Icon | Other |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `available_sign_ups/index.html.erb` | · | · | · | · | · | C | C | · | U | **D1** | C | C | C | C | C |
| `available_sign_ups/show.html.erb` | **D1** | U | · | · | **D1** | U | C | **D1** | U | **D1** | U | C | U | U | **D2** |
| `bulk_upload/index.html.erb` | C | U | **D1** | U | · | C | · | C | C | C | **D1** | · | **D1** | C | U |
| `bulk_upload/preview.html.erb` | C | U | C | · | **D1** | C | · | C | **D1** | · | C | · | C | C | U |
| `mail_log/body.html.erb` | · | · | · | · | · | · | · | · | · | U | · | C | C | C | U |
| `mentoring/index.html.erb` | C | U | U | · | · | · | C | **D1** | · | U | U | C | U | C | **D1** |
| `messages/index.html.erb` | **D1** | U | **D2** | U | · | U | **D1** | **D1** | C | U | **D2** | U | U | C | **D1** |
| `messages/new.html.erb` | **D1** | · | C | U | · | · | C | **D1** | · | · | C | C | U | C | U |
| `messages/show.html.erb` | **D1** | U | **D2** | U | · | U | **D1** | **D1** | C | U | **D2** | U | U | C | **D1** |
| `missing_requests/edit.html.erb` | **D1** | · | C | U | · | · | C | **D1** | C | U | **D1** | C | C | C | · |
| `missing_requests/index.html.erb` | **D2** | · | · | · | C | U | C | **D2** | C | **D1** | U | C | **D1** | C | U |
| `missing_requests/new.html.erb` | **D2** | · | C | U | · | · | C | **D1** | C | U | **D1** | C | C | C | U |
| `provisions/edit.html.erb` | **D1** | · | **D3** | U | C | C | C | C | · | U | **D1** | U | C | C | · |
| `provisions/new.html.erb` | **D2** | · | **D3** | U | C | C | C | C | · | U | **D1** | U | C | C | · |
| `qualifications/index.html.erb` | C | · | · | · | · | U | C | C | **D1** | · | **D1** | **D1** | U | C | **D1** |
| `resource_documents/edit.html.erb` | **D1** | · | C | C | · | · | C | C | · | · | U | U | C | C | · |
| `schedule/index.html.erb` | **D2** | **D1** | · | · | **D1** | **D1** | C | **D1** | **D1** | U | **D3** | **D1** | **D8** | U | **D1** |
| `schedule/signup_summary.html.erb` | · | · | · | · | · | **D1** | C | C | C | · | U | C | C | **D1** | **D2** |
| `surveys/report.html.erb` | U | U | · | · | · | U | **D1** | C | · | **D1** | U | C | C | C | · |
| `surveys/trainer.html.erb` | U | U | · | · | · | U | C | C | · | **D1** | U | C | C | C | · |
| `timesheet/edit.html.erb` | **D1** | · | U | U | · | U | C | **D1** | **D1** | U | C | C | C | C | · |
| `timesheet/index.html.erb` | **D2** | · | · | C | · | **D1** | C | **D4** | C | U | **D3** | **D2** | **D4** | **D1** | **D2** |
| `unified_flagging/detail.html.erb` | U | · | · | · | · | U | · | C | · | **D1** | **D2** | C | C | C | U |
| `unified_flagging/index.html.erb` | U | U | C | · | · | U | C | U | C | **D1** | **D3** | C | U | C | U |
| `work_history/entire_year.html.erb` | · | · | · | · | · | C | C | C | · | U | **D1** | C | C | C | **D1** |
| `work_history/position_all.html.erb` | · | · | · | · | · | C | C | C | · | U | **D2** | C | C | C | **D1** |
| `work_history/position_summary.html.erb` | · | · | · | · | · | C | C | C | · | U | **D1** | C | C | C | **D1** |

</details>

<details><summary><strong>communication</strong> (23 templates, own-file divergence score 38)</summary>

| Template | Btn | Link | Form | Valid | Modal | Table | Nav | Card | Alert | Empty | Type | Color | Space | Icon | Other |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `announcements/edit.html.erb` | C | · | C | U | · | C | C | · | · | · | **D1** | · | C | C | C |
| `announcements/index.html.erb` | **D1** | U | U | · | C | · | · | **D1** | · | C | C | C | U | C | U |
| `announcements/new.html.erb` | C | · | C | U | · | C | C | · | · | · | **D2** | · | C | C | C |
| `mail_templates/edit.html.erb` | C | · | C | C | · | C | C | · | C | · | **D1** | · | C | C | C |
| `mail_templates/index.html.erb` | U | U | · | · | · | U | · | C | C | C | **D1** | · | U | C | C |
| `person_banners/index.html.erb` | C | U | U | · | · | · | · | U | C | C | C | C | U | C | **D1** |
| `rbs/index.html.erb` | **D2** | U | C | · | · | C | · | C | C | C | U | C | U | U | C |
| `rbs_broadcasts/new.html.erb` | C | · | **D8** | C | · | U | C | **D1** | **D1** | C | **D1** | C | **D1** | C | U |
| `rbs_broadcasts/review.html.erb` | **D1** | · | C | · | · | U | C | **D1** | C | U | **D1** | C | U | C | U |
| `rbs_broadcasts/sent.html.erb` | C | U | · | · | · | C | C | C | C | U | U | · | C | C | U |
| `rbs_history/index.html.erb` | C | U | U | · | · | C | C | C | **D1** | C | C | · | · | U | · |
| `rbs_history/retried.html.erb` | C | U | · | · | · | C | U | C | C | U | U | · | C | C | U |
| `rbs_history/show.html.erb` | **D1** | U | · | · | C | **D1** | C | **D1** | C | C | **D1** | C | U | C | C |
| `rbs_messages/index.html.erb` | C | U | **D5** | U | · | U | U | **D1** | · | C | **D1** | C | C | **D1** | · |
| `rbs_phone_numbers/index.html.erb` | · | U | · | · | · | C | C | C | C | C | U | · | U | C | **D1** |
| `survey_groups/edit.html.erb` | **D1** | · | C | U | · | C | C | · | · | · | **D1** | · | C | C | C |
| `survey_groups/new.html.erb` | **D1** | · | C | U | · | C | C | · | · | · | **D1** | · | C | C | C |
| `survey_questions/edit.html.erb` | **D1** | · | U | C | · | C | C | · | · | · | **D1** | · | C | C | C |
| `survey_questions/new.html.erb` | **D1** | · | U | C | · | C | C | · | · | · | **D1** | · | C | C | C |
| `surveys/edit.html.erb` | **D1** | · | U | U | C | C | C | · | · | · | **D1** | · | C | C | C |
| `surveys/index.html.erb` | **D1** | U | · | · | C | C | C | C | C | C | **D1** | C | U | C | C |
| `surveys/new.html.erb` | **D1** | · | U | U | C | C | C | · | · | · | **D2** | · | C | C | C |
| `surveys/show.html.erb` | **D1** | · | · | · | C | U | C | **D1** | C | **D1** | U | C | U | C | U |

</details>

<details><summary><strong>dashboard_tasks</strong> (69 templates, own-file divergence score 34)</summary>

| Template | Btn | Link | Form | Valid | Modal | Table | Nav | Card | Alert | Empty | Type | Color | Space | Icon | Other |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `_after_event_no_more_things.html.erb` | · | · | · | · | · | · | · | · | · | · | U | · | C | · | · |
| `_after_event_status_advisory.html.erb` | · | · | · | · | · | C | · | · | · | · | **D1** | C | C | C | · |
| `_attend_alpha_shift_bonked.html.erb` | · | · | · | · | · | · | · | · | U | · | U | C | · | C | · |
| `_attend_alpha_shift_missed.html.erb` | · | · | · | · | · | · | · | · | U | · | U | C | · | C | · |
| `_attend_alpha_shift_not_available.html.erb` | · | · | · | · | · | · | · | · | · | · | U | · | · | · | · |
| `_attend_alpha_shift_pending.html.erb` | · | U | · | · | · | C | · | **D1** | U | · | U | C | U | C | · |
| `_attend_alpha_shift_sign_up.html.erb` | · | · | · | · | · | · | · | · | · | · | U | · | · | C | · |
| `_attend_cheetah_cub_shift_pending.html.erb` | · | · | · | · | · | · | · | **D1** | U | · | **D1** | C | C | C | **D1** |
| `_attend_green_dot_mentee_shift_waiting.html.erb` | · | U | · | · | · | · | · | · | · | · | **D1** | C | C | C | · |
| `_attend_training_art.html.erb` | · | · | · | · | · | · | · | · | · | · | U | C | C | · | · |
| `_attend_training_cheetah.html.erb` | · | · | · | · | · | · | · | · | · | · | U | · | · | U | · |
| `_attend_training_fail.html.erb` | · | U | · | · | · | · | · | · | U | · | U | C | U | C | · |
| `_attend_training_no_show.html.erb` | · | · | · | · | · | C | · | · | U | · | U | C | · | C | · |
| `_attend_training_pending.html.erb` | · | U | · | · | · | · | · | **D1** | U | · | U | C | U | C | · |
| `_attend_training_signup.html.erb` | · | · | · | · | · | · | · | · | · | · | U | · | · | C | · |
| `_bmid_will_not_be_printed.html.erb` | · | U | · | · | · | **D1** | · | · | · | · | U | · | C | · | · |
| `_burn_weekend_shift_completed.html.erb` | · | · | · | · | · | · | · | · | · | · | U | · | · | · | · |
| `_burn_weekend_shift_needed.html.erb` | · | U | · | · | · | · | · | · | · | · | U | · | C | C | · |
| `_cheetah_cub_shift_needed.html.erb` | · | U | · | · | · | · | · | · | · | · | U | · | C | C | · |
| `_dashboard_arts.html.erb` | · | U | · | · | · | C | · | · | · | C | U | · | U | · | U |
| `_dashboard_survey.html.erb` | · | U | · | · | · | · | · | · | · | · | U | · | C | C | · |
| `_dashboard_tickets.html.erb` | · | U | · | · | · | C | · | · | U | **D1** | U | C | C | C | · |
| `_green_dot_mentee_shift_needed.html.erb` | · | U | · | · | · | C | · | · | · | · | U | · | C | **D1** | · |
| `_missing_bpguid.html.erb` | · | U | · | · | · | C | · | · | U | · | U | C | C | C | · |
| `_mvr_request_approved.html.erb` | · | · | · | · | · | · | · | · | · | · | U | · | · | · | · |
| `_mvr_request_eligible.html.erb` | · | U | · | · | · | · | · | · | · | · | U | · | C | C | · |
| `_mvr_request_muted.html.erb` | · | · | · | · | · | · | · | · | · | · | · | C | · | C | · |
| `_no_things_at_the_moment.html.erb` | · | · | · | · | · | · | · | · | · | **D1** | U | · | · | · | · |
| `_online_course_blocked.html.erb` | · | · | · | · | · | · | · | · | · | · | U | · | · | U | · |
| `_online_course_completed.html.erb` | · | U | · | · | · | · | · | · | · | · | U | · | C | · | · |
| `_online_course_needed.html.erb` | · | U | · | · | · | · | · | · | · | · | **D1** | C | C | C | U |
| `_online_course_waiting.html.erb` | · | U | · | · | · | · | · | · | · | · | **D1** | C | C | · | · |
| `_photo_approval_missing.html.erb` | · | · | · | · | · | · | · | · | · | · | U | · | · | C | · |
| `_photo_approval_review.html.erb` | · | · | · | · | · | · | · | · | · | · | U | · | · | · | · |
| `_ranger_interest_signup.html.erb` | · | U | · | · | · | · | · | · | · | · | U | · | C | C | · |
| `_sandman_affidavit_needed.html.erb` | · | U | · | · | · | · | · | · | · | · | U | · | C | C | · |
| `_sign_behavioral_agreement_optional.html.erb` | · | U | · | · | · | · | · | · | · | · | U | · | C | C | · |
| `_sign_motor_pool_protocol_blocked.html.erb` | · | · | · | · | · | · | · | · | · | · | U | · | · | U | · |
| `_sign_motor_pool_protocol_needed.html.erb` | · | U | · | C | · | C | · | · | · | · | **D1** | C | C | C | · |
| `_sign_nda_needed.html.erb` | · | U | · | · | · | · | · | · | U | · | C | C | C | U | · |
| `_sign_radio_checkout_agreement_blocked.html.erb` | · | · | · | · | · | · | · | · | · | · | U | · | · | U | · |
| `_sign_radio_checkout_agreement_needed.html.erb` | · | U | · | · | · | · | · | · | · | · | U | C | C | C | · |
| `_sign_radio_checkout_agreement_not_available.html.erb` | · | · | · | · | · | · | · | · | · | · | U | · | · | · | · |
| `_sign_up_for_alpha_shift_blocked.html.erb` | · | · | · | · | · | · | · | · | · | · | **D1** | C | C | U | · |
| `_sign_up_for_alpha_shift_needed.html.erb` | · | U | · | · | · | · | · | · | C | · | U | · | C | · | · |
| `_sign_up_for_alpha_shift_waiting.html.erb` | · | · | · | · | · | · | · | · | · | · | U | U | U | C | · |
| `_sign_up_for_shifts_blocked.html.erb` | · | · | · | · | · | · | · | · | · | · | U | · | · | U | · |
| `_sign_up_for_shifts_completed.html.erb` | · | U | · | · | · | · | · | · | · | · | U | · | C | U | · |
| `_sign_up_for_shifts_needed.html.erb` | · | U | · | · | · | · | · | · | · | · | U | · | C | C | · |
| `_sign_up_for_shifts_schedule_pending.html.erb` | · | · | · | · | · | · | · | · | · | · | **D1** | C | C | · | · |
| `_sign_up_for_training_blocked.html.erb` | · | · | · | · | · | · | · | · | · | · | U | C | C | U | · |
| `_sign_up_for_training_needed.html.erb` | · | U | · | · | · | · | · | · | · | · | U | · | C | U | · |
| `_sign_up_for_training_waiting.html.erb` | · | · | · | · | · | · | · | · | · | · | U | · | · | · | · |
| `_take_alpha_survey.html.erb` | · | U | · | · | · | · | · | · | · | · | U | · | · | C | · |
| `_take_student_survey.html.erb` | · | U | · | · | · | C | · | · | · | U | U | · | C | C | · |
| `_trainer_survey.html.erb` | · | U | · | · | · | C | · | · | · | U | U | · | C | C | · |
| `_troubleshooter_mentor_survey.html.erb` | · | U | · | · | · | · | · | · | · | · | U | · | · | C | · |
| `_upload_photo_action.html.erb` | · | U | · | · | · | · | · | · | · | · | U | · | C | C | · |
| `_upload_photo_disabled.html.erb` | · | U | · | · | · | · | · | · | · | · | U | · | C | · | · |
| `_upload_photo_error.html.erb` | · | · | · | · | · | · | · | · | U | · | U | C | · | C | · |
| `_upload_photo_rejected.html.erb` | · | U | · | · | · | C | · | · | U | U | U | C | C | C | · |
| `_vehicle_requests_approved.html.erb` | · | U | · | · | · | · | · | · | · | · | U | · | · | · | · |
| `_vehicle_requests_denied.html.erb` | · | U | · | · | · | · | · | · | U | · | U | C | · | C | · |
| `_vehicle_requests_eligible.html.erb` | · | U | · | · | · | · | · | · | · | · | U | · | C | C | · |
| `_vehicle_requests_muted.html.erb` | · | · | · | · | · | · | · | · | · | · | · | C | · | C | · |
| `_vehicle_requests_pending.html.erb` | · | U | · | · | · | · | · | · | · | · | U | · | · | · | · |
| `_verify_personal_info.html.erb` | · | U | · | · | · | C | · | · | · | · | **D1** | **D1** | C | C | · |
| `_verify_timesheets.html.erb` | · | U | · | · | · | · | · | · | C | · | **D1** | · | · | C | · |
| `_verify_timesheets_finished.html.erb` | · | · | · | · | · | · | · | · | · | · | U | · | · | · | · |

</details>

<details><summary><strong>hq</strong> (19 templates, own-file divergence score 13)</summary>

| Template | Btn | Link | Form | Valid | Modal | Table | Nav | Card | Alert | Empty | Type | Color | Space | Icon | Other |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `assets/index.html.erb` | **D1** | U | **D1** | U | · | U | C | C | C | U | C | C | C | C | C |
| `available_sign_ups/index.html.erb` | · | · | · | · | · | C | C | · | U | **D1** | C | C | C | C | C |
| `available_sign_ups/show.html.erb` | **D1** | U | · | · | **D1** | U | C | **D1** | U | **D1** | U | C | U | U | **D2** |
| `messages/index.html.erb` | **D1** | U | **D2** | U | · | U | **D1** | **D1** | C | U | **D2** | U | U | C | **D1** |
| `messages/new.html.erb` | **D1** | · | C | U | · | · | C | **D1** | · | · | C | C | U | C | U |
| `messages/show.html.erb` | **D1** | U | **D2** | U | · | U | **D1** | **D1** | C | U | **D2** | U | U | C | **D1** |
| `missing_requests/edit.html.erb` | **D1** | · | C | U | · | · | C | **D1** | C | U | **D1** | C | C | C | C |
| `missing_requests/index.html.erb` | **D2** | · | · | · | C | U | C | **D2** | C | **D1** | U | C | **D1** | C | U |
| `missing_requests/new.html.erb` | **D2** | · | C | U | · | · | C | **D1** | C | U | **D1** | C | C | C | U |
| `scheduling/index.html.erb` | **D2** | **D1** | · | · | **D1** | **D1** | C | **D1** | **D1** | U | **D3** | **D1** | **D8** | U | **D1** |
| `scheduling/signup_summary.html.erb` | · | · | · | · | · | **D1** | C | C | C | · | U | C | C | **D1** | **D2** |
| `shift_manage/index.html.erb` | **D6** | U | **D2** | U | **D1** | U | · | **D2** | C | U | **D3** | **D1** | **D1** | **D3** | **D1** |
| `site_registration/show.html.erb` | **D2** | U | **D1** | U | **D3** | U | · | C | **D1** | U | **D2** | C | **D1** | C | U |
| `tickets_provisions/progress.html.erb` | · | · | · | · | · | C | · | · | C | U | U | C | U | C | C |
| `tickets_provisions/show.html.erb` | · | · | · | · | · | · | · | · | · | U | · | C | C | C | C |
| `timesheets/edit.html.erb` | **D1** | · | U | U | · | U | C | **D1** | **D1** | U | C | C | C | C | C |
| `timesheets/event_summary.html.erb` | · | · | · | · | · | **D2** | C | C | C | C | **D1** | C | C | U | C |
| `timesheets/index.html.erb` | **D2** | · | · | C | · | **D1** | C | **D4** | C | U | **D3** | **D2** | **D4** | **D1** | **D2** |
| `training/index.html.erb` | · | · | · | C | · | U | C | C | C | U | U | C | U | C | C |

</details>

<details><summary><strong>me</strong> (45 templates, own-file divergence score 64)</summary>

| Template | Btn | Link | Form | Valid | Modal | Table | Nav | Card | Alert | Empty | Type | Color | Space | Icon | Other |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `agreements/index.html.erb` | C | · | · | C | · | U | C | **D1** | · | **D1** | **D2** | C | **D1** | U | C |
| `agreements/show.html.erb` | **D1** | · | · | · | · | · | C | · | · | · | C | C | C | C | **D1** |
| `announcements/index.html.erb` | C | · | · | · | · | U | C | **D1** | · | **D1** | **D1** | C | U | C | **D1** |
| `available_sign_ups/index.html.erb` | · | · | · | · | · | C | C | · | U | **D1** | C | C | C | C | C |
| `available_sign_ups/show.html.erb` | **D1** | U | · | · | **D1** | U | C | **D1** | U | **D1** | U | C | U | U | **D2** |
| `awards/index.html.erb` | · | · | · | · | · | C | C | **D1** | C | **D2** | **D2** | C | U | **D2** | · |
| `dashboard/index.html.erb` | **D1** | U | · | · | **D1** | U | · | **D2** | U | U | **D1** | **D1** | U | U | **D1** |
| `directory/index.html.erb` | · | U | · | · | · | · | C | **D1** | · | **D1** | **D2** | C | **D1** | U | **D2** |
| `event_info.html.erb` | · | · | · | · | · | · | **D1** | · | · | · | C | · | · | C | · |
| `event_summary/index.html.erb` | · | · | · | · | · | **D2** | C | C | C | C | **D1** | C | C | U | **D1** |
| `feedback/index.html.erb` | C | U | · | · | · | U | U | C | · | **D1** | U | C | C | U | C |
| `mentoring/index.html.erb` | C | U | U | · | · | · | C | **D1** | · | U | U | C | U | C | **D1** |
| `menu/show.html.erb` | **D2** | U | **D1** | · | · | U | **D1** | · | · | U | **D2** | · | C | U | · |
| `messages/index.html.erb` | **D1** | U | **D2** | U | · | U | **D1** | **D1** | C | U | **D2** | U | U | C | **D1** |
| `messages/new.html.erb` | **D1** | · | C | U | · | · | C | **D1** | · | · | C | C | U | C | U |
| `messages/show.html.erb` | **D1** | U | **D2** | U | · | U | **D1** | **D1** | C | U | **D2** | U | U | C | **D1** |
| `missing_requests/edit.html.erb` | **D1** | · | C | U | · | · | C | **D1** | C | U | **D1** | C | C | C | · |
| `missing_requests/index.html.erb` | **D2** | · | · | · | C | U | C | **D2** | C | **D1** | U | C | **D1** | C | U |
| `missing_requests/new.html.erb` | **D2** | · | C | U | · | · | C | **D1** | C | U | **D1** | C | C | C | U |
| `online_course/index.html.erb` | C | · | C | · | · | C | C | C | · | · | C | **D1** | C | C | · |
| `operational_summary/index.html.erb` | C | U | · | C | · | U | C | **D1** | C | C | **D5** | C | U | C | C |
| `passkeys/index.html.erb` | U | U | · | · | · | C | C | C | C | C | C | C | C | C | · |
| `passkeys/new.html.erb` | C | · | C | C | · | C | C | C | C | U | C | · | C | C | U |
| `password/edit.html.erb` | **D1** | · | **D1** | U | · | · | C | C | · | · | C | · | · | C | · |
| `personal_vehicles/edit.html.erb` | **D1** | · | **D1** | **D1** | · | · | C | C | C | · | C | · | · | C | · |
| `personal_vehicles/new.html.erb` | **D1** | · | **D1** | **D1** | · | · | C | C | C | · | C | · | · | C | **D1** |
| `schedule/index.html.erb` | **D2** | **D1** | · | · | **D1** | **D1** | C | **D1** | **D1** | U | **D3** | **D1** | **D8** | U | **D1** |
| `schedule/signup_summary.html.erb` | · | · | · | · | · | **D1** | C | C | C | · | U | C | C | **D1** | **D2** |
| `shift_manage/index.html.erb` | **D2** | · | **D1** | C | C | U | C | C | C | C | C | **D1** | U | C | · |
| `surveys/show.html.erb` | **D1** | · | C | **D2** | · | · | C | C | U | U | **D1** | C | C | U | U |
| `team_documents/show.html.erb` | · | · | · | · | · | · | C | C | · | C | C | · | · | C | · |
| `tickets/gift.html.erb` | **D2** | U | · | · | · | C | U | **D1** | C | **D1** | **D1** | C | C | C | C |
| `tickets/index.html.erb` | **D1** | U | · | · | · | U | C | **D3** | U | C | **D1** | C | U | C | U |
| `tickets/provisions.html.erb` | **D1** | · | · | · | · | **D1** | U | C | C | **D1** | C | C | C | C | C |
| `tickets/review.html.erb` | **D1** | · | · | · | · | C | U | U | C | **D1** | U | C | C | C | · |
| `tickets/sap.html.erb` | **D1** | U | · | · | · | C | U | C | C | · | C | C | C | C | C |
| `tickets/sap_so.html.erb` | **D1** | U | C | U | · | C | U | C | C | · | C | **D1** | C | C | · |
| `tickets/ticket.html.erb` | **D1** | U | · | · | · | C | U | **D1** | C | · | C | C | C | C | U |
| `tickets/vehicle_pass.html.erb` | **D1** | · | · | · | · | · | U | C | C | · | C | C | C | C | C |
| `timesheet/edit.html.erb` | **D1** | · | U | U | · | U | C | **D1** | **D1** | U | C | C | C | C | · |
| `timesheet/final_confirmation.html.erb` | C | · | · | · | · | · | C | C | · | · | C | U | C | C | · |
| `timesheet/index.html.erb` | **D2** | · | · | C | · | **D1** | C | **D4** | C | U | **D3** | **D2** | **D4** | **D1** | **D2** |
| `vehicles_dashboard/index.html.erb` | **D2** | · | · | · | · | · | C | **D1** | C | · | **D1** | C | **D1** | U | U |
| `vehicles_dashboard/mvr_submit.html.erb` | · | · | · | · | · | · | C | C | U | · | C | C | C | C | · |
| `work_history/index.html.erb` | · | U | · | · | · | **D1** | C | C | · | C | C | C | C | C | **D1** |

</details>

<details><summary><strong>mentoring</strong> (25 templates, own-file divergence score 91)</summary>

| Template | Btn | Link | Form | Valid | Modal | Table | Nav | Card | Alert | Empty | Type | Color | Space | Icon | Other |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `alpha_acceptance_sheets/index.html.erb` | U | U | U | · | · | C | · | C | · | **D1** | U | C | U | C | · |
| `alpha_acceptance_sheets/print_sheets.html.erb` | · | · | C | · | · | **D1** | U | · | · | **D1** | **D1** | C | U | U | U |
| `alpha_mentor_assignments/index.html.erb` | U | U | **D4** | **D2** | · | C | · | C | C | **D1** | **D1** | C | U | C | **D1** |
| `alpha_mentor_assignments/print_sheet.html.erb` | · | · | C | · | · | C | U | · | · | C | U | C | U | · | U |
| `alpha_pods/index.html.erb` | C | · | · | · | · | · | C | C | · | C | **D1** | C | U | U | U |
| `alpha_pods/people/edit.html.erb` | **D1** | · | **D2** | · | U | · | · | · | · | · | **D1** | C | C | U | **D1** |
| `alpha_pods/people/new.html.erb` | C | · | **D1** | · | U | · | · | U | C | **D1** | **D2** | C | **D1** | U | · |
| `alpha_pods/print_sheet.html.erb` | · | · | · | · | · | **D1** | U | · | · | **D2** | U | **D1** | C | U | **D2** |
| `alpha_pods/show.html.erb` | **D1** | **D1** | · | · | · | C | C | **D1** | C | **D1** | **D1** | C | C | U | U |
| `alpha_pods/unavailable.html.erb` | C | · | · | · | U | · | · | · | · | · | **D1** | C | C | U | · |
| `alpha_schedule/apparel.html.erb` | · | · | · | · | · | **D2** | U | · | · | **D2** | U | C | C | U | U |
| `alpha_schedule/index.html.erb` | C | · | · | · | · | · | C | C | · | C | **D1** | C | U | C | U |
| `alpha_schedule/info_sheet.html.erb` | · | · | · | · | · | **D1** | U | · | · | **D2** | U | **D1** | C | U | **D1** |
| `alpha_schedule/no_alphas.html.erb` | C | · | · | · | U | · | · | · | · | · | C | · | C | C | · |
| `alpha_schedule/rosters/new.html.erb` | **D1** | · | **D1** | **D1** | U | C | · | · | · | U | **D1** | C | C | · | · |
| `alpha_schedule/show.html.erb` | **D1** | U | · | · | **D1** | C | C | C | C | **D1** | **D2** | C | C | C | U |
| `alpha_schedule/signup_sheet.html.erb` | · | · | · | · | · | **D1** | U | · | · | **D1** | U | C | U | **D1** | U |
| `alpha_signout/index.html.erb` | C | U | U | · | **D1** | C | C | C | C | C | **D1** | **D2** | U | C | U |
| `alpha_status/index.html.erb` | U | U | C | · | · | U | · | C | C | **D2** | **D3** | C | U | C | U |
| `alphas_convert/index.html.erb` | C | U | U | · | **D1** | C | · | C | C | U | **D1** | C | C | C | U |
| `convert_prospectives/index.html.erb` | C | U | U | · | **D1** | C | · | C | C | U | **D1** | C | C | C | U |
| `post_season_summary/index.html.erb` | U | U | C | · | · | U | C | U | C | **D2** | **D3** | C | U | C | U |
| `potential_alphas/index.html.erb` | U | U | C | · | · | U | · | C | C | **D2** | **D3** | C | U | C | U |
| `shift_report/index.html.erb` | **D1** | U | · | · | · | C | C | C | C | **D1** | **D1** | **D2** | U | U | **D1** |
| `surveys/index.html.erb` | · | U | · | · | · | C | · | C | · | U | U | C | C | C | **D1** |

</details>

<details><summary><strong>people</strong> (13 templates, own-file divergence score 17)</summary>

| Template | Btn | Link | Form | Valid | Modal | Table | Nav | Card | Alert | Empty | Type | Color | Space | Icon | Other |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `bulk_lookup/index.html.erb` | C | U | C | C | · | U | · | C | **D1** | C | U | · | U | C | U |
| `create_account/new.html.erb` | C | · | C | U | · | C | C | C | · | · | C | · | C | C | C |
| `languages_known/index.html.erb` | C | · | **D3** | · | · | C | **D1** | · | · | C | **D1** | **D1** | U | C | **D1** |
| `languages_known/show.html.erb` | C | U | C | · | · | C | C | C | · | C | **D1** | **D1** | U | C | **D1** |
| `people_by_location/country.html.erb` | U | U | **D4** | · | · | C | C | · | **D2** | C | **D1** | C | C | C | U |
| `people_by_location/index.html.erb` | U | · | **D4** | · | · | C | **D1** | · | **D2** | C | **D1** | C | C | C | · |
| `people_by_status/index.html.erb` | · | · | · | · | · | C | · | · | · | U | C | · | C | C | · |
| `people_by_status/show.html.erb` | · | U | · | · | · | U | C | C | · | U | **D1** | · | C | C | · |
| `retention_report/index.html.erb` | U | U | C | · | · | C | · | C | · | C | C | C | C | C | C |
| `search/index.html.erb` | U | U | **D3** | U | · | U | U | C | U | C | **D2** | C | U | U | · |
| `status_change_recommendations/index.html.erb` | C | · | C | · | · | U | **D1** | C | · | C | C | C | C | C | C |
| `status_change_recommendations/show.html.erb` | **D1** | U | U | U | · | C | C | C | C | C | C | C | C | C | U |
| `unified_flagging/index.html.erb` | U | U | C | · | · | U | U | U | C | **D1** | **D3** | C | U | C | U |

</details>

<details><summary><strong>person</strong> (68 templates, own-file divergence score 66)</summary>

| Template | Btn | Link | Form | Valid | Modal | Table | Nav | Card | Alert | Empty | Type | Color | Space | Icon | Other |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `access_documents/edit.html.erb` | U | · | **D5** | · | · | · | C | C | C | · | U | C | C | U | · |
| `access_documents/history.html.erb` | · | · | · | · | · | U | C | C | · | C | U | C | C | U | · |
| `access_documents/new.html.erb` | C | · | **D5** | · | · | · | C | C | C | · | U | C | C | U | · |
| `agreements/index.html.erb` | C | · | C | · | · | · | C | C | C | C | **D2** | C | C | C | C |
| `applications/index.html.erb` | · | U | · | · | · | C | C | U | C | C | C | C | C | C | U |
| `assets/index.html.erb` | **D1** | U | **D1** | U | C | U | C | U | C | U | C | C | C | C | C |
| `available_sign_ups/index.html.erb` | · | · | · | · | · | C | C | · | U | **D1** | C | C | C | C | C |
| `available_sign_ups/show.html.erb` | **D1** | U | · | · | **D1** | U | C | **D1** | U | **D1** | U | C | U | U | **D2** |
| `awards/edit.html.erb` | C | · | C | C | · | C | C | C | · | · | C | · | C | C | C |
| `awards/index.html.erb` | **D3** | · | · | · | **D1** | C | C | C | **D1** | C | C | · | C | C | C |
| `awards/new.html.erb` | C | · | C | C | · | C | C | C | · | · | C | · | C | C | C |
| `banners/edit.html.erb` | **D1** | · | C | C | · | · | C | C | C | · | C | · | · | C | · |
| `banners/index.html.erb` | U | · | · | · | · | C | C | C | C | C | C | C | C | C | C |
| `banners/new.html.erb` | **D1** | · | C | C | · | · | C | C | C | · | C | · | · | C | · |
| `bmids/show.html.erb` | **D1** | · | **D1** | U | · | C | C | C | C | C | **D1** | C | C | U | **D1** |
| `callsigns/edit.html.erb` | **D1** | · | **D1** | C | **D1** | C | C | U | U | **D1** | C | C | C | C | C |
| `certifications/edit.html.erb` | **D1** | · | C | U | · | · | C | C | · | · | C | · | · | C | · |
| `certifications/index.html.erb` | U | · | · | · | · | C | C | C | C | C | C | C | C | C | · |
| `certifications/new.html.erb` | **D1** | · | C | U | · | · | C | C | · | · | C | · | · | C | · |
| `certifications/show.html.erb` | C | U | · | · | · | U | C | C | · | U | C | C | U | C | **D1** |
| `dashboard/show.html.erb` | · | U | · | · | · | C | C | **D1** | C | U | U | **D1** | U | U | C |
| `external_ids/show.html.erb` | C | · | C | U | · | · | C | C | · | · | C | · | · | C | · |
| `fka/edit.html.erb` | C | · | C | U | · | · | C | C | · | · | C | · | · | C | · |
| `fka/new.html.erb` | C | · | C | U | · | · | C | C | · | · | C | · | · | C | · |
| `intake_notes/edit.html.erb` | C | · | U | C | · | · | C | · | C | · | C | · | · | C | U |
| `intake_notes/new.html.erb` | **D1** | · | C | C | · | U | C | C | · | **D1** | **D2** | C | C | C | U |
| `mail_log/index.html.erb` | · | **D1** | · | · | · | C | U | C | · | **D1** | U | C | U | **D1** | · |
| `membership_history/show.html.erb` | · | · | · | · | · | C | C | C | · | C | C | C | C | C | C |
| `memberships/edit.html.erb` | **D1** | · | **D5** | · | · | · | **D2** | C | U | **D1** | **D5** | C | U | U | **D1** |
| `mentoring/index.html.erb` | C | U | U | · | · | · | C | **D1** | · | U | U | C | U | C | **D1** |
| `messages/index.html.erb` | **D1** | U | **D2** | U | · | U | **D1** | **D1** | C | U | **D2** | U | U | C | **D1** |
| `messages/new.html.erb` | **D1** | · | C | U | · | · | C | **D1** | · | · | C | C | U | C | U |
| `messages/show.html.erb` | **D1** | U | **D2** | U | · | U | **D1** | **D1** | C | U | **D2** | U | U | C | **D1** |
| `missing_requests/edit.html.erb` | **D1** | · | C | · | C | U | C | **D1** | U | U | C | **D1** | C | C | **D1** |
| `missing_requests/new.html.erb` | C | · | C | U | · | · | C | C | · | · | C | · | C | C | · |
| `missing_requests/show.html.erb` | C | · | · | · | · | C | U | **D1** | · | **D1** | C | C | C | C | U |
| `passkeys/index.html.erb` | U | U | · | · | C | C | C | C | C | C | C | · | C | C | **D1** |
| `passkeys/new.html.erb` | C | · | C | C | · | C | C | C | C | U | C | · | · | C | U |
| `passwords/edit.html.erb` | C | · | C | U | · | · | C | C | · | · | C | · | · | C | · |
| `permissions/edit.html.erb` | C | · | **D2** | · | · | U | C | U | C | **D1** | C | C | U | C | U |
| `pogs/edit.html.erb` | U | · | U | C | · | · | C | · | · | · | C | · | · | C | U |
| `pogs/index.html.erb` | U | · | · | · | · | C | C | C | · | C | **D2** | C | C | C | U |
| `pogs/new.html.erb` | U | · | U | C | · | · | C | · | · | · | C | · | · | C | U |
| `provisions/edit.html.erb` | **D1** | · | **D3** | U | C | C | C | C | · | U | **D1** | U | C | C | · |
| `provisions/new.html.erb` | **D2** | · | **D3** | U | C | C | C | C | · | U | **D1** | U | C | C | · |
| `scheduling/index.html.erb` | **D2** | **D1** | · | · | **D1** | **D1** | C | **D1** | **D1** | U | **D3** | **D1** | **D8** | U | **D1** |
| `scheduling/log.html.erb` | · | U | · | · | · | **D1** | C | C | · | U | **D1** | C | C | C | C |
| `scheduling/signup_summary.html.erb` | · | · | · | · | · | **D1** | C | C | C | · | U | C | C | **D1** | **D2** |
| `sessions/index.html.erb` | C | · | · | · | **D1** | C | C | C | · | C | C | · | C | C | C |
| `show.html.erb` | C | **D1** | · | · | C | **D1** | U | C | U | **D2** | **D1** | C | U | C | **D3** |
| `site_log/index.html.erb` | C | U | C | · | · | C | C | C | · | C | C | · | C | C | C |
| `status_history/index.html.erb` | · | U | · | · | · | C | C | C | · | U | C | C | C | C | · |
| `statuses/edit.html.erb` | C | · | C | · | C | · | C | C | · | · | C | · | C | C | U |
| `swag/edit.html.erb` | U | · | U | U | · | · | C | · | C | **D1** | C | · | · | C | U |
| `swag/index.html.erb` | **D1** | · | · | · | · | C | C | C | C | **D2** | **D1** | C | C | U | C |
| `swag/new.html.erb` | U | · | U | U | · | · | C | · | C | **D1** | C | · | · | C | U |
| `tickets_provisions/dashboard.html.erb` | **D1** | U | · | · | · | U | C | **D3** | U | C | **D1** | C | U | C | U |
| `tickets_provisions/show.html.erb` | **D2** | · | · | · | · | U | U | C | C | C | C | C | U | C | **D2** |
| `timesheets/backfill.html.erb` | C | · | **D2** | · | · | C | C | C | · | · | C | C | U | U | C |
| `timesheets/breakdown.html.erb` | · | · | C | · | · | **D2** | C | C | C | C | **D1** | C | C | U | C |
| `timesheets/edit.html.erb` | U | **D1** | **D1** | C | **D1** | U | U | **D1** | **D1** | **D1** | U | **D1** | U | U | U |
| `timesheets/index.html.erb` | **D1** | U | C | · | **D1** | **D1** | C | C | C | C | **D1** | C | U | **D1** | **D1** |
| `timesheets/log.html.erb` | · | **D1** | C | · | · | U | C | C | **D1** | C | U | C | U | U | C |
| `timesheets/shift_manage.html.erb` | **D2** | · | **D1** | C | C | U | C | C | C | C | C | **D1** | U | U | C |
| `training/index.html.erb` | C | · | C | C | **D1** | U | C | C | C | U | U | C | U | C | C |
| `unified_flagging/show.html.erb` | **D1** | · | C | U | · | U | C | C | C | **D3** | **D2** | C | C | U | **D1** |
| `vehicles/index.html.erb` | **D1** | · | C | · | · | C | C | C | C | **D1** | U | C | **D2** | C | C |
| `work_history/index.html.erb` | · | U | · | · | · | C | C | C | C | C | U | C | U | C | · |

</details>

<details><summary><strong>pogs</strong> (3 templates, own-file divergence score 1)</summary>

| Template | Btn | Link | Form | Valid | Modal | Table | Nav | Card | Alert | Empty | Type | Color | Space | Icon | Other |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `administration/edit.html.erb` | C | · | C | C | C | · | C | · | · | · | **D1** | · | · | C | · |
| `administration/index.html.erb` | C | U | C | U | C | C | U | C | · | C | C | · | · | C | C |
| `dashboard/index.html.erb` | · | U | · | · | · | C | C | C | · | C | C | · | U | C | C |

</details>

<details><summary><strong>profile</strong> (6 templates, own-file divergence score 4)</summary>

| Template | Btn | Link | Form | Valid | Modal | Table | Nav | Card | Alert | Empty | Type | Color | Space | Icon | Other |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `camp_edit.html.erb` | U | · | U | U | · | C | C | C | C | · | **D1** | · | C | C | · |
| `clothing_edit.html.erb` | C | · | U | · | · | C | C | C | U | · | C | · | C | C | · |
| `emergency_contact_edit.html.erb` | C | · | U | U | · | C | C | C | C | · | C | · | C | C | · |
| `identity_info_edit.html.erb` | C | U | C | C | · | C | C | C | C | · | U | C | C | U | C |
| `mailing_address_edit.html.erb` | C | · | C | U | · | C | C | C | · | · | C | · | C | C | · |
| `show.html.erb` | **D2** | U | · | · | C | **D1** | C | C | U | **D6** | **D2** | **D1** | U | C | **D1** |

</details>

<details><summary><strong>profile_languages</strong> (3 templates, own-file divergence score 3)</summary>

| Template | Btn | Link | Form | Valid | Modal | Table | Nav | Card | Alert | Empty | Type | Color | Space | Icon | Other |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `edit.html.erb` | C | · | C | C | · | · | C | U | · | · | C | · | · | C | C |
| `index.html.erb` | **D1** | · | · | · | C | U | **D1** | C | C | C | C | · | C | C | · |
| `new.html.erb` | C | · | C | C | · | · | C | U | · | · | C | · | · | C | C |

</details>

<details><summary><strong>profile_photos</strong> (2 templates, own-file divergence score 49)</summary>

| Template | Btn | Link | Form | Valid | Modal | Table | Nav | Card | Alert | Empty | Type | Color | Space | Icon | Other |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `crop.html.erb` | **D2** | · | **D1** | · | C | U | C | **D2** | C | · | **D2** | **D3** | **D1** | **D1** | **D2** |
| `new.html.erb` | **D1** | · | **D3** | C | · | U | **D3** | **D1** | **D1** | U | **D2** | C | U | U | U |

</details>

<details><summary><strong>quartermaster</strong> (11 templates, own-file divergence score 7)</summary>

| Template | Btn | Link | Form | Valid | Modal | Table | Nav | Card | Alert | Empty | Type | Color | Space | Icon | Other |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `alpha_shirts/index.html.erb` | U | U | C | · | · | U | · | C | · | **D1** | **D1** | C | U | C | C |
| `events_rangered/index.html.erb` | U | U | C | · | · | C | · | C | · | C | C | · | C | C | U |
| `freaking_years/index.html.erb` | U | · | · | · | · | C | · | C | · | C | C | · | U | C | · |
| `freaking_years/show.html.erb` | U | U | · | · | · | C | C | C | · | U | C | · | U | C | · |
| `potential_shirts/index.html.erb` | U | U | C | · | · | C | C | C | · | U | C | · | U | C | C |
| `potential_swag/index.html.erb` | U | U | C | · | · | C | · | C | · | C | C | · | C | C | U |
| `swag/edit.html.erb` | C | · | U | U | · | C | C | C | · | · | C | · | C | C | C |
| `swag/index.html.erb` | C | · | · | · | · | C | · | C | · | U | C | · | U | C | **D1** |
| `swag/new.html.erb` | C | · | C | U | · | C | C | · | · | · | **D1** | · | C | C | C |
| `swag/type.html.erb` | C | · | · | · | · | C | C | C | · | C | C | · | U | C | C |
| `swag_distribution/index.html.erb` | U | U | C | · | · | U | C | U | · | C | C | C | C | C | C |

</details>

<details><summary><strong>register</strong> (1 templates, own-file divergence score 0)</summary>

| Template | Btn | Link | Form | Valid | Modal | Table | Nav | Card | Alert | Empty | Type | Color | Space | Icon | Other |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `show.html.erb` | C | U | U | · | · | · | U | C | C | · | U | C | U | C | U |

</details>

<details><summary><strong>scheduling</strong> (35 templates, own-file divergence score 49)</summary>

| Template | Btn | Link | Form | Valid | Modal | Table | Nav | Card | Alert | Empty | Type | Color | Space | Icon | Other |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `early_arrivals/index.html.erb` | U | U | U | · | · | C | C | C | C | C | **D2** | C | C | C | C |
| `event_stats/index.html.erb` | · | · | · | · | · | C | C | **D1** | · | C | **D1** | C | U | C | U |
| `flake_report/index.html.erb` | · | U | · | · | · | C | C | C | · | C | U | · | C | U | C |
| `flake_report/position.html.erb` | · | U | · | · | · | U | C | C | · | C | U | C | C | U | C |
| `hq_forecast/burn_perimeters.html.erb` | C | U | C | · | · | C | C | C | · | C | **D2** | C | **D1** | C | U |
| `hq_forecast/index.html.erb` | U | U | C | · | · | C | U | C | · | C | **D2** | C | **D1** | C | U |
| `hq_forecast/people.html.erb` | C | U | C | · | U | U | · | · | · | C | **D4** | C | **D1** | C | U |
| `hq_forecast/shift.html.erb` | C | U | C | · | U | U | · | · | · | C | **D3** | C | **D1** | C | U |
| `no_shows_report/index.html.erb` | · | U | · | · | · | C | C | C | · | C | C | · | C | U | C |
| `no_shows_report/position.html.erb` | U | U | · | · | · | U | C | C | · | C | U | C | C | U | C |
| `position_credit_copies/new.html.erb` | C | · | U | **D1** | · | C | C | C | C | C | **D2** | C | C | **D1** | · |
| `position_credits/edit.html.erb` | C | · | U | U | · | · | C | · | · | · | **D4** | C | C | U | **D5** |
| `position_credits/index.html.erb` | U | · | C | · | · | C | C | · | · | C | **D3** | C | C | U | **D5** |
| `position_credits/new.html.erb` | C | · | U | U | · | · | C | · | C | · | **D4** | C | C | U | **D5** |
| `position_credits/position.html.erb` | U | · | U | · | C | C | C | C | C | C | **D4** | C | C | U | **D5** |
| `position_credits/timeline.html.erb` | U | · | C | · | · | C | C | C | C | C | **D4** | C | C | U | **D5** |
| `sandman_qualified/index.html.erb` | U | U | U | · | · | C | C | **D1** | · | C | U | C | **D1** | U | U |
| `schedule_by_callsign/index.html.erb` | U | · | U | · | · | U | **D1** | · | · | C | **D1** | · | U | U | U |
| `schedule_by_callsign/person.html.erb` | U | · | C | · | · | C | C | C | · | C | **D1** | **D1** | C | U | C |
| `schedule_by_position/index.html.erb` | · | U | · | · | · | U | **D1** | · | · | C | **D1** | C | U | U | U |
| `schedule_by_position/position.html.erb` | U | U | · | · | · | U | C | C | · | C | **D2** | C | C | U | C |
| `shift_coverage/index.html.erb` | U | U | U | · | · | U | C | C | · | C | **D1** | C | C | C | · |
| `shift_drop_report/index.html.erb` | U | · | U | · | · | C | C | C | · | C | C | · | U | U | C |
| `shift_drop_report/position.html.erb` | C | U | U | · | · | U | C | C | · | C | U | C | C | U | C |
| `shift_lead/index.html.erb` | C | U | **D4** | · | · | **D2** | C | **D2** | · | C | **D8** | **D1** | **D1** | **D2** | C |
| `shift_lead/print_sheet.html.erb` | · | · | U | · | · | **D2** | U | · | · | **D1** | **D3** | **D2** | C | U | **D2** |
| `shift_signups/index.html.erb` | U | U | C | · | · | C | C | C | · | C | U | C | C | U | U |
| `shift_signups/position.html.erb` | U | · | C | · | · | C | C | C | · | C | U | C | C | C | U |
| `slot_bulk_edits/new.html.erb` | **D1** | · | U | **D1** | · | C | C | C | · | C | **D1** | C | C | C | C |
| `slot_copies/new.html.erb` | C | · | U | **D1** | · | C | C | C | C | C | **D3** | C | C | **D1** | · |
| `slots/edit.html.erb` | C | · | C | U | · | · | C | · | U | U | **D1** | C | C | C | U |
| `slots/index.html.erb` | C | · | C | · | · | C | C | · | C | C | U | · | C | C | U |
| `slots/link_options.html.erb` | · | · | C | · | · | · | · | · | U | U | U | C | C | C | U |
| `slots/new.html.erb` | C | · | C | U | · | · | C | · | U | U | **D2** | C | C | C | U |
| `slots/position.html.erb` | **D1** | · | U | · | C | C | C | C | · | C | **D1** | C | C | U | U |

</details>

<details><summary><strong>sessions</strong> (4 templates, own-file divergence score 11)</summary>

| Template | Btn | Link | Form | Valid | Modal | Table | Nav | Card | Alert | Empty | Type | Color | Space | Icon | Other |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `forgot.html.erb` | **D1** | U | **D1** | U | · | · | · | U | · | · | **D1** | C | C | **D1** | U |
| `new.html.erb` | **D2** | U | **D1** | U | · | U | U | U | C | · | **D2** | C | U | **D2** | U |
| `reset_password_confirmation.html.erb` | · | U | · | · | · | · | · | · | · | · | **D1** | C | C | · | U |
| `reset_token.html.erb` | **D1** | U | **D1** | U | · | · | · | · | · | · | **D1** | C | C | **D1** | U |

</details>

<details><summary><strong>shift_operations</strong> (16 templates, own-file divergence score 29)</summary>

| Template | Btn | Link | Form | Valid | Modal | Table | Nav | Card | Alert | Empty | Type | Color | Space | Icon | Other |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `bulk_sign_in_out/index.html.erb` | C | · | C | U | · | C | · | C | C | · | C | · | C | C | **D1** |
| `bulk_sign_in_out/preview.html.erb` | **D1** | U | C | U | **D2** | U | U | C | C | C | C | C | C | C | U |
| `cruise_direction/index.html.erb` | U | U | **D2** | · | · | U | C | C | U | **D2** | C | C | U | U | **D1** |
| `cruise_direction/people/edit.html.erb` | **D2** | · | **D1** | · | U | · | · | · | · | U | C | C | **D2** | C | C |
| `cruise_direction/people/new.html.erb` | C | · | U | · | U | · | · | C | · | **D1** | **D1** | C | **D1** | C | C |
| `cruise_direction/pods/edit.html.erb` | **D1** | · | U | U | U | · | · | · | · | · | C | C | **D1** | C | C |
| `cruise_direction/pods/new.html.erb` | · | · | U | U | **D1** | · | · | · | · | · | C | · | · | C | C |
| `cruise_direction/unavailable.html.erb` | C | · | U | · | U | · | · | · | · | · | **D1** | C | C | C | C |
| `mass_signout/index.html.erb` | **D1** | U | U | · | C | C | · | C | U | C | C | C | C | **D1** | U |
| `payroll_export/index.html.erb` | **D1** | U | **D3** | C | C | U | · | **D1** | C | U | **D2** | C | C | C | U |
| `payroll_missing_id/index.html.erb` | U | U | · | · | · | C | C | C | · | C | U | · | C | C | C |
| `roc_photo_board/board.html.erb` | · | · | · | · | · | U | U | **D1** | · | **D1** | **D1** | · | · | C | **D1** |
| `roc_photo_board/index.html.erb` | · | · | · | · | · | U | U | **D1** | · | **D1** | **D1** | · | · | C | **D1** |
| `rollcall/index.html.erb` | U | · | · | · | **D1** | C | · | C | · | C | U | C | U | C | C |
| `rollcall/sign_in.html.erb` | **D1** | U | **D5** | · | **D2** | C | C | **D1** | C | U | U | U | C | C | U |
| `rollcall/sign_out.html.erb` | **D1** | · | **D5** | · | **D1** | C | C | **D1** | · | U | U | C | C | C | U |

</details>

<details><summary><strong>sso</strong> (2 templates, own-file divergence score 2)</summary>

| Template | Btn | Link | Form | Valid | Modal | Table | Nav | Card | Alert | Empty | Type | Color | Space | Icon | Other |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `hand_back.html.erb` | **D1** | · | · | · | · | · | · | · | · | U | **D1** | C | C | C | U |
| `invalid_request.html.erb` | · | U | · | · | · | · | · | · | · | · | **D1** | C | C | · | U |

</details>

<details><summary><strong>teams_positions</strong> (26 templates, own-file divergence score 41)</summary>

| Template | Btn | Link | Form | Valid | Modal | Table | Nav | Card | Alert | Empty | Type | Color | Space | Icon | Other |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `bulk_positions/index.html.erb` | C | U | U | U | · | · | · | · | C | C | **D1** | · | C | C | U |
| `bulk_positions/preview.html.erb` | C | U | C | · | **D1** | C | **D1** | C | C | C | C | · | U | C | U |
| `bulk_teams/index.html.erb` | C | U | U | U | · | · | · | · | C | C | **D1** | · | C | C | U |
| `bulk_teams/preview.html.erb` | C | U | C | · | **D1** | C | **D1** | C | C | C | C | C | U | C | U |
| `membership_report/index.html.erb` | C | · | C | · | · | C | **D1** | C | · | C | C | · | C | C | C |
| `membership_report/show.html.erb` | · | U | C | · | · | C | C | C | C | U | C | C | C | C | C |
| `position_grants/index.html.erb` | C | · | C | · | · | C | **D1** | C | · | C | C | · | C | C | C |
| `position_grants/show.html.erb` | U | U | C | · | · | U | C | **D1** | C | C | C | C | C | C | C |
| `position_lineups/edit.html.erb` | C | · | **D1** | C | · | C | C | C | · | · | **D1** | C | C | C | · |
| `position_lineups/index.html.erb` | C | · | · | · | · | **D1** | C | · | **D1** | C | U | **D1** | C | C | · |
| `position_lineups/new.html.erb` | C | · | **D1** | C | · | C | C | C | · | · | **D1** | C | C | C | · |
| `position_records/edit.html.erb` | C | · | **D1** | U | · | U | C | C | C | **D1** | C | C | C | C | C |
| `position_records/index.html.erb` | C | · | C | · | · | C | C | C | · | C | U | **D1** | C | C | C |
| `position_records/new.html.erb` | C | · | **D1** | U | · | U | C | C | C | **D1** | C | C | C | C | C |
| `position_sanity_checker/check.html.erb` | **D1** | U | U | U | · | **D1** | **D1** | C | **D1** | C | **D2** | C | U | **D1** | U |
| `position_sanity_checker/index.html.erb` | **D1** | · | · | · | · | **D1** | · | **D1** | · | U | **D2** | C | C | U | U |
| `roster_management/index.html.erb` | · | · | C | · | · | C | · | · | · | C | C | C | C | C | C |
| `roster_management/preview.html.erb` | C | · | C | · | **D1** | U | C | C | C | C | C | **D1** | C | **D1** | U |
| `roster_management/show.html.erb` | C | U | U | U | · | U | C | U | C | C | **D2** | C | C | C | **D1** |
| `special_teams_hours/index.html.erb` | U | U | **D1** | C | · | U | · | C | **D1** | C | U | C | U | C | U |
| `team_documents/edit.html.erb` | **D1** | · | C | C | · | C | C | C | · | · | U | U | C | C | C |
| `team_documents/index.html.erb` | · | · | · | · | · | C | · | · | · | C | C | · | C | C | C |
| `team_documents/show.html.erb` | C | U | · | · | · | C | C | C | C | C | U | U | C | C | C |
| `team_records/edit.html.erb` | C | · | **D1** | C | · | C | C | C | C | **D1** | C | C | C | C | C |
| `team_records/index.html.erb` | C | U | C | · | · | C | C | C | · | C | C | **D1** | C | C | C |
| `team_records/new.html.erb` | C | · | **D1** | C | · | C | C | C | C | **D1** | C | C | C | C | C |

</details>

<details><summary><strong>ticketing</strong> (17 templates, own-file divergence score 18)</summary>

| Template | Btn | Link | Form | Valid | Modal | Table | Nav | Card | Alert | Empty | Type | Color | Space | Icon | Other |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `access_documents/index.html.erb` | C | U | C | U | · | U | · | C | · | C | **D1** | C | **D1** | C | C |
| `access_documents/records.html.erb` | U | U | C | · | · | C | · | C | · | C | **D1** | C | C | C | · |
| `claimed_with_no_signups/index.html.erb` | U | U | C | · | · | U | · | C | · | C | C | C | C | C | U |
| `expiring/index.html.erb` | **D1** | U | C | · | · | U | · | C | · | C | C | C | C | C | C |
| `maintenance/index.html.erb` | **D1** | · | · | · | · | · | · | C | U | U | U | C | U | C | C |
| `maintenance/preview.html.erb` | C | U | C | **D1** | · | C | C | · | C | **D1** | U | C | C | C | · |
| `maintenance/results.html.erb` | · | U | · | C | · | C | C | · | C | **D1** | U | C | C | C | U |
| `provisions/edit.html.erb` | **D1** | · | **D3** | U | C | C | C | C | · | U | **D1** | U | C | C | · |
| `provisions/index.html.erb` | U | U | C | · | · | C | · | C | · | C | C | · | C | C | U |
| `sap_candidates/index.html.erb` | U | U | · | · | · | U | · | C | · | C | C | C | C | C | U |
| `statistics/index.html.erb` | · | · | · | · | · | C | · | **D1** | · | U | C | C | U | C | **D2** |
| `trs_export/export.html.erb` | **D1** | U | U | U | **D1** | C | C | C | C | C | C | C | C | **D1** | U |
| `trs_export/index.html.erb` | **D1** | U | **D1** | U | **D1** | C | · | C | U | C | C | C | C | **D1** | U |
| `trs_export/mark_submitted.html.erb` | C | U | · | C | · | C | C | · | C | **D1** | U | C | C | C | U |
| `unclaimed_with_signups/index.html.erb` | U | U | C | · | · | C | · | C | · | C | C | · | C | C | U |
| `unsubmit_provisions/index.html.erb` | **D1** | U | U | · | C | U | C | C | C | C | **D1** | · | C | C | U |
| `unsubmit_provisions/results.html.erb` | C | U | · | C | · | C | C | · | C | **D1** | U | C | C | C | U |

</details>

<details><summary><strong>timesheets</strong> (17 templates, own-file divergence score 20)</summary>

| Template | Btn | Link | Form | Valid | Modal | Table | Nav | Card | Alert | Empty | Type | Color | Space | Icon | Other |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `correction_requests/index.html.erb` | U | U | U | · | · | U | C | C | · | U | C | C | C | C | C |
| `correction_stats/index.html.erb` | · | U | · | · | · | C | C | U | · | **D2** | U | C | U | C | **D2** |
| `early_late_checkins/index.html.erb` | U | U | U | · | · | U | C | C | · | **D1** | U | C | U | C | C |
| `forced_shift_start/index.html.erb` | U | U | U | · | · | U | C | C | · | U | U | C | C | C | **D1** |
| `hours_credits/index.html.erb` | U | U | U | · | · | **D1** | C | C | C | C | U | · | C | C | C |
| `on_duty/index.html.erb` | C | U | C | · | · | U | · | **D1** | C | C | U | C | **D1** | C | U |
| `sanity_checker/check.html.erb` | U | U | · | · | · | **D1** | C | **D1** | C | C | U | C | U | C | C |
| `sanity_checker/index.html.erb` | · | · | · | · | · | C | C | C | · | · | **D2** | C | U | C | U |
| `timesheet_by_position/index.html.erb` | U | · | C | · | · | C | C | · | C | C | U | C | U | C | C |
| `timesheet_by_position/position.html.erb` | U | U | C | · | · | C | C | C | C | C | U | C | U | C | C |
| `timesheet_slot_repair/index.html.erb` | U | U | U | C | **D1** | U | **D1** | C | C | C | **D2** | C | C | **D1** | U |
| `timesheet_totals_report/index.html.erb` | U | · | C | · | · | C | C | · | · | C | U | · | U | C | C |
| `timesheet_totals_report/person.html.erb` | · | · | C | · | · | C | C | C | · | C | U | C | · | C | U |
| `timesheet_unconfirmed/index.html.erb` | U | U | · | · | · | U | C | C | · | U | C | **D1** | C | C | C |
| `timesheets_by_callsign/index.html.erb` | U | · | C | · | · | C | U | · | C | C | U | · | U | C | · |
| `timesheets_by_callsign/person.html.erb` | U | · | C | · | · | C | C | C | · | C | U | C | C | C | · |
| `top_hour_earners/index.html.erb` | U | U | C | · | · | U | · | C | · | C | U | C | C | C | · |

</details>

<details><summary><strong>training</strong> (30 templates, own-file divergence score 37)</summary>

| Template | Btn | Link | Form | Valid | Modal | Table | Nav | Card | Alert | Empty | Type | Color | Space | Icon | Other |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `all_notes/index.html.erb` | U | U | U | · | · | U | C | C | · | **D1** | **D1** | C | C | C | U |
| `capacity/index.html.erb` | U | · | · | · | · | U | C | C | · | C | U | C | U | C | C |
| `completed_training/index.html.erb` | U | U | · | · | · | C | C | C | · | C | C | · | U | C | C |
| `completed_training/show.html.erb` | C | U | · | · | · | C | U | C | · | C | C | C | C | C | **D1** |
| `mentees/index.html.erb` | **D1** | U | C | · | · | U | C | C | C | U | C | C | C | C | C |
| `mentoring/assignments/index.html.erb` | C | · | U | · | · | C | C | U | C | U | **D1** | C | U | C | **D1** |
| `mentoring/assignments/show.html.erb` | U | U | **D4** | **D2** | C | U | C | C | C | U | U | C | U | C | **D2** |
| `mentoring/general_notes/edit.html.erb` | · | · | U | C | U | · | · | C | · | U | U | C | C | C | **D1** |
| `mentoring/landing/index.html.erb` | · | U | U | · | · | C | C | C | C | **D1** | U | C | C | C | **D1** |
| `mentoring/multiple_shifts/index.html.erb` | U | U | U | · | · | C | C | C | C | U | U | U | C | C | **D1** |
| `mentoring/verdicts/index.html.erb` | U | U | U | · | · | U | C | C | C | U | U | C | C | C | **D1** |
| `multiple_enrollments/index.html.erb` | U | U | · | · | · | U | C | C | · | C | C | C | U | C | C |
| `online_course_progress/index.html.erb` | U | U | C | · | · | C | C | C | · | **D1** | C | · | C | C | C |
| `resources/edit.html.erb` | **D1** | · | C | C | · | · | C | C | · | · | U | U | C | C | · |
| `resources/show.html.erb` | C | U | · | · | · | · | C | C | C | C | U | U | C | C | · |
| `sessions/graduations/show.html.erb` | C | · | **D1** | C | U | C | · | C | C | **D1** | C | C | C | C | U |
| `sessions/index.html.erb` | · | **D1** | · | · | · | C | C | C | **D1** | **D1** | U | C | C | C | U |
| `sessions/notes/edit.html.erb` | · | · | C | C | U | · | · | C | C | U | C | C | C | C | U |
| `sessions/rosters/new.html.erb` | C | · | **D3** | · | U | C | · | C | C | **D1** | C | C | C | C | U |
| `sessions/scores/edit.html.erb` | U | · | C | C | U | C | · | C | C | **D1** | U | C | C | C | U |
| `sessions/show.html.erb` | **D2** | U | **D3** | U | · | C | C | U | U | **D1** | **D2** | C | U | C | **D1** |
| `sessions/signup_sheet.html.erb` | · | · | · | · | · | **D2** | U | C | · | **D1** | **D2** | **D1** | C | C | **D1** |
| `sessions/trainers_report.html.erb` | · | · | · | · | · | **D1** | U | C | **D1** | **D2** | **D1** | **D1** | C | **D1** | **D3** |
| `sessions/work_histories/show.html.erb` | C | **D1** | · | · | U | **D1** | · | C | C | U | U | **D1** | C | C | U |
| `surveys/index.html.erb` | · | U | · | · | · | C | C | C | · | U | U | C | C | C | C |
| `surveys/report.html.erb` | U | U | · | · | · | U | **D1** | C | · | **D1** | U | C | C | C | · |
| `surveys/trainer.html.erb` | U | U | · | · | · | U | C | C | · | **D1** | U | C | C | C | · |
| `trained_no_work/index.html.erb` | U | U | C | · | · | U | C | C | C | C | C | C | C | C | **D1** |
| `trainer_attendance/index.html.erb` | U | U | · | · | · | C | C | C | · | C | U | C | U | C | U |
| `untrained_people/index.html.erb` | **D1** | U | C | · | · | U | C | C | C | C | C | C | C | C | U |

</details>

<details><summary><strong>vc</strong> (37 templates, own-file divergence score 64)</summary>

| Template | Btn | Link | Form | Valid | Modal | Table | Nav | Card | Alert | Empty | Type | Color | Space | Icon | Other |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `application_import/index.html.erb` | U | U | C | · | **D1** | C | · | **D1** | C | U | C | C | C | C | **D2** |
| `applications/dialogs/adjust_status.html.erb` | · | U | C | · | U | · | · | · | C | · | C | C | · | C | **D2** |
| `applications/dialogs/approve_callsign.html.erb` | · | U | C | C | U | · | · | · | C | · | C | C | C | C | **D2** |
| `applications/dialogs/assign.html.erb` | · | U | C | · | U | · | · | · | · | · | C | C | · | C | **D2** |
| `applications/dialogs/edit_approved_handle.html.erb` | · | U | C | C | U | · | · | · | C | · | C | C | C | C | **D2** |
| `applications/dialogs/edit_handles.html.erb` | · | U | C | C | U | · | · | · | C | · | C | C | · | C | **D2** |
| `applications/dialogs/more_handles.html.erb` | C | U | C | C | U | · | · | · | C | · | C | C | C | C | **D2** |
| `applications/dialogs/note_delete.html.erb` | · | U | C | · | U | · | · | · | C | · | C | C | C | C | **D2** |
| `applications/dialogs/note_form.html.erb` | · | U | C | C | U | · | · | · | C | · | C | C | C | C | **D2** |
| `applications/dialogs/problem_review.html.erb` | · | U | C | C | U | · | · | · | · | · | C | C | C | C | **D2** |
| `applications/dialogs/send_email.html.erb` | C | U | **D1** | C | U | · | · | · | · | · | C | C | C | C | **D2** |
| `applications/dialogs/status_message.html.erb` | C | U | C | C | U | · | · | · | C | · | **D1** | C | C | C | **D2** |
| `applications/edit_details.html.erb` | C | U | **D3** | C | · | C | C | C | · | · | **D1** | C | C | C | **D2** |
| `applications/edit_personal_info.html.erb` | C | U | **D1** | C | · | · | C | C | · | · | C | C | · | C | **D2** |
| `applications/extract_handles.html.erb` | · | U | C | C | U | C | · | **D1** | C | · | C | C | U | C | **D2** |
| `applications/index.html.erb` | U | U | **D1** | · | · | C | **D1** | **D1** | C | **D1** | U | C | C | C | **D2** |
| `applications/search.html.erb` | C | U | U | · | · | C | C | C | · | C | **D1** | C | C | C | **D2** |
| `applications/show.html.erb` | **D3** | U | · | · | · | U | U | **D2** | C | **D2** | **D5** | C | U | U | **D2** |
| `bpguid/index.html.erb` | **D1** | · | C | U | **D1** | U | · | C | C | **D1** | U | C | U | **D1** | **D2** |
| `create_prospectives/index.html.erb` | C | U | C | · | **D1** | U | · | **D1** | C | U | C | C | C | C | **D1** |
| `handle_checker/index.html.erb` | C | U | **D5** | U | · | C | · | C | · | **D1** | **D4** | C | U | C | U |
| `maintenance/index.html.erb` | **D1** | · | · | · | · | · | · | C | C | · | C | · | C | C | · |
| `maintenance/preview_past_prospectives.html.erb` | C | U | C | C | · | C | U | · | C | C | U | C | C | C | · |
| `maintenance/preview_pnvs.html.erb` | C | U | C | C | · | C | U | · | C | C | U | C | C | C | · |
| `maintenance/reset_past_prospectives.html.erb` | · | U | · | C | · | C | C | · | · | C | U | C | C | C | U |
| `maintenance/reset_pnvs.html.erb` | · | U | · | C | · | C | C | · | · | C | U | C | C | C | U |
| `photos/index.html.erb` | · | U | · | · | · | C | U | C | · | C | **D1** | · | U | C | C |
| `photos_review/index.html.erb` | C | U | · | · | **D1** | U | · | C | C | **D2** | **D3** | C | U | C | U |
| `photos_review/info.html.erb` | · | U | · | · | C | U | · | · | · | **D1** | **D1** | C | U | C | C |
| `photos_review/reject_dialog.html.erb` | C | · | C | **D1** | U | · | · | · | · | · | **D1** | · | U | C | C |
| `reserved_handles/edit.html.erb` | C | · | C | U | · | C | C | C | · | · | **D1** | · | C | C | **D1** |
| `reserved_handles/index.html.erb` | **D1** | · | **D1** | · | **D1** | C | · | C | · | C | **D1** | · | C | C | · |
| `reserved_handles/new.html.erb` | C | · | C | U | · | C | C | · | · | · | **D2** | · | C | C | C |
| `reserved_handles/upload.html.erb` | C | · | C | U | · | C | C | C | C | C | **D2** | C | C | C | U |
| `shiny_penny_report/index.html.erb` | U | U | · | · | · | C | C | C | · | C | U | · | C | C | · |
| `spigot_flow_report/index.html.erb` | U | U | · | · | · | **D1** | C | C | · | C | U | C | U | C | **D1** |
| `thank_you_cards/index.html.erb` | U | U | **D3** | · | · | C | C | C | **D1** | C | **D3** | **D1** | C | U | C |

</details>

<details><summary><strong>vehicles</strong> (5 templates, own-file divergence score 7)</summary>

| Template | Btn | Link | Form | Valid | Modal | Table | Nav | Card | Alert | Empty | Type | Color | Space | Icon | Other |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `paperwork/index.html.erb` | U | U | C | · | · | U | C | C | C | **D1** | **D2** | C | C | C | U |
| `registry/edit.html.erb` | **D2** | U | **D2** | U | · | C | C | C | C | **D2** | **D2** | C | **D2** | C | C |
| `registry/index.html.erb` | U | U | C | · | · | U | C | C | C | **D1** | **D3** | C | U | C | C |
| `registry/new.html.erb` | **D2** | U | **D2** | U | · | C | C | C | C | **D2** | **D1** | C | **D2** | C | C |
| `registry/permit.html.erb` | C | U | C | · | · | U | C | C | C | **D1** | **D3** | C | C | C | C |

</details>

## 3. Divergent findings

Each line: severity, rule, `file:line`, pattern, then what the rule says and what the code does. **high** is a visible inconsistency or an accessibility problem; **medium** is the wrong component or token that renders about the same; **low** is cosmetic or internal. Where one departure repeats in a file, the note lists the lines. Pages are grouped by area and ordered by weight within it; findings in a file that several pages render are in 3.2, and departures in the shared helpers, stylesheets and controllers are in 3.3.

Severity was judged from code. A "medium" that turns out to look different on screen is a "high"; section 6 lists the ones the reviewers flagged as needing a look.

### 3.1 Pages

#### admin (25)

**`admin/documents/body.html.erb`** (GET /admin/documents/:id/body (render layout: false))

- **medium** `CARD-01` `admin/documents/body.html.erb:4` cards: Rule: card containers are card-standard via ui_card. Code: preview box is a hand-made div "border border-line rounded-base p-4 my-2".
- **medium** `COLOR-06` `admin/documents/body.html.erb:6` color: Rule: the same neutral text utility for the same purpose. Code: .me-muted (a hero-panel class) instead of text-stone-muted; same departure as R11520.
- **medium** `FORM-09` `admin/documents/body.html.erb:16` other: Rule: saved rich text renders inside .lexxy-content through rich_text. Code: @document.body.html_safe inside a hand-written div.lexxy-content.

**`admin/request_logs/index.html.erb`** (GET /admin/request-logs (also ?mode=live))

- **medium** `TYPE-03` `admin/request_logs/index.html.erb:168` typography: Rule: paragraph content is not text-sm. Code: the no-payload note is p "text-sm text-stone-muted" (same departure as R01381).
- **low** `COPY-03` `admin/request_logs/index.html.erb:157` typography: Rule: every string read as a label is Title Case. Code: detail block labels "What was sent" and "What came back" (lines 157, 163).
- **low** `EMPTY-02` `admin/request_logs/index.html.erb:144` typography: Rule: an empty value prints "—". Code: a missing address chain prints "-" in the detail row.
- **low** `MODAL-02` `admin/request_logs/index.html.erb:185` modals: Rule: a confirm says whether the action can be undone. Code: "Delete every request recorded more than N days ago? A nightly task does this on its own." says nothing about undo.

**`admin/settings/edit.html.erb`** (GET /admin/settings/:id/edit)

- **high** `FORM-02` `admin/settings/edit.html.erb:38` forms: Rule: every field has a visible label. Code: f.text_field :value with no label:; the builder renders no label, leaving the input unnamed.
- **medium** `FORM-02` `admin/settings/edit.html.erb:16` forms: Rule: every field has a visible label. Code: the boolean collection_radio_buttons has no label:, so the group renders without a legend.

**`admin/settings/index.html.erb`** (GET /admin/settings)

- **high** `TABLE-04` `admin/settings/index.html.erb:14` forms: Rule: a table page's filters use filter_bar. Code: a ui_form GET with a horizontal field and inline submit, no chips or count, unlike sibling admin lists.
- **low** `FORM-07` `admin/settings/index.html.erb:16` forms: Rule: field widths are responsive width classes. Code: text_field uses size: 40 with layout: :horizontal instead of a width: class.

**`admin/sms_management/twilio.html.erb`** (GET /admin/sms-management/twilio (render layout: false))

- **high** `TOAST-01` `admin/sms_management/twilio.html.erb:4` toasts-alerts: Rule: flash renders as a layout toast. Code: flash[:success]/[:error] read in the view and drawn as callouts inside the frame (commented reason).
- **low** `MODAL-02` `admin/sms_management/twilio.html.erb:103` modals: Rule: ask with the action and say whether it can be undone. Code: the dialog states what Twilio will do; no question, no undo note.

**`admin/online_courses/moodle_catalog_courses.html.erb`** (GET /admin/online-course/moodle-catalog-courses (render layout: false))

- **medium** `BTN-04` `admin/online_courses/moodle_catalog_courses.html.erb:29` buttons: Rule: one clear primary action per view. Code: every catalog row carries a :primary "Add Course" button, so the table shows one primary per course.
- **low** `EMPTY-02` `admin/online_courses/moodle_catalog_courses.html.erb:25` typography: Rule: an empty value prints "—". Code: "— none —" in text-stone-subtle.

**`admin/error_logs/index.html.erb`** (GET /admin/error-log)

- **medium** `TYPE-03` `admin/error_logs/index.html.erb:66` typography: Rule: table content is text-base. Code: Type cell spells "align-middle text-sm leading-snug" by hand (and drops text-body that log_text_class adds).

**`admin/passkeys/index.html.erb`** (GET /admin/passkeys)

- **low** `BP-01` `admin/passkeys/index.html.erb:28` forms: Rule: sm: belongs in a field's width:. Code: f.select gets class: "w-full sm:w-48" in html options (same departure as M0002).
- **low** `EMPTY-02` `admin/passkeys/index.html.erb:58` tables-lists: Rule: an empty value prints "—". Code: deleted account's Status cell is t.cell "" (blank).

**`admin/permissions/new_art.html.erb`** (GET /admin/permissions/art)

- **low** `COPY-03` `admin/permissions/new_art.html.erb:24` typography: Rule: every heading is Title Case. Code: fieldset legend "Training position".
- **low** `COPY-04` `admin/permissions/new_art.html.erb:30` buttons: pattern=buttons Rule: a form submit says "Save [Entity]", never "Create". Code: f.submit "Create Permissions".

**`admin/rbs_alerts/edit.html.erb`** (GET /admin/rbs-alerts/:id/edit)

- **medium** `FORM-04` `admin/rbs_alerts/edit.html.erb:41` forms: Rule: help text is the field's help_text:, tied by aria-describedby. Code: raw p#on-playa-note "text-sm mt-1" wired to the checkbox by hand.

**`admin/sms_management/index.html.erb`** (GET /admin/sms-management)

- **medium** `BTN-04` `admin/sms_management/index.html.erb:104` buttons: Rule: one primary per view. Code: Look Up Number (_lookup.html.erb:36), Apply Filters (line 125) and Update Incoming Address (twilio.html.erb:102) are all :primary on one page.

**`admin/bug_reports/index.html.erb`** (GET /admin/bug-reports)

- **low** `EMPTY-02` `admin/bug_reports/index.html.erb:36` typography: Rule: an empty value prints "—". Code: person blank "-", browser or "-", url/ip/user_agent presence or "-" (lines 36, 43, 58, 61, 64).

**`admin/jobs/index.html.erb`** (GET /admin/jobs)

- **low** `BTN-04` `admin/jobs/index.html.erb:39` buttons: Rule: one primary per view. Code: "Retry All Failed" :primary in filter_bar actions beside the Apply Filters primary submit (jobs_helper.rb:71, line 55).

**`admin/permissions/index.html.erb`** (GET /admin/permissions)

- **low** `COPY-04` `admin/permissions/index.html.erb:25` buttons: pattern=buttons Rule: a button opening a create form says "Add [Entity]". Code: "Create ART Permissions".

#### alerts (5)

**`alerts/edit.html.erb`** (GET /me/alerts/edit (me/alerts#edit, layout me))

- **medium** `BTN-04` `alerts/edit.html.erb:110` buttons: One primary action per view; f.submit defaults to :primary, so Save Phone Number (110), Verify Code (138) and Save Preferences (206) are three primaries (admin: 64, 206).
- **medium** `TYPE-03` `alerts/edit.html.erb:156` typography: text-sm is never for paragraph content; the stopped-number callout's contact sentence is text-sm, among divs with ad-hoc strong/font-semibold emphasis.
- **medium** `TYPE-03` `alerts/edit.html.erb:163` cards: text-sm not for paragraph content; ui_disclosure "Why It's Stopped" shrinks its summary and its explanation to text-sm via summary_class/content_class.
- **low** `EMPTY-02` `alerts/edit.html.erb:70` typography: An empty value prints "—"; the missing phone number prints italic content_tag(:em, "none on file").
- **low** `FORM-07` `alerts/edit.html.erb:54` forms: Phone fields are w-full sm:w-44; the SMS number fields use w-full sm:w-32 (54) and w-full sm:w-80 (108).

#### asset_management (2)

**`asset_management/radio_assets/index.html.erb`** (GET /asset-management/radio-assets)

- **medium** `BTN-05` `asset_management/radio_assets/index.html.erb:68` navigation: :primary is for primary actions; a view switch (Full Roster / Summarized View) is navigation styled primary, and the sibling Radio Checkout page uses a two-button toggle instead.

**`asset_management/records/new.html.erb`** (GET /asset-management/records/new)

- **low** `COPY-04` `asset_management/records/new.html.erb:2` typography: The create form is named Add X, never New X; hero title reads New Asset.

#### bmid (11)

**`bmid/sanity_check/index.html.erb`** (GET /bmid/sanity-check)

- **medium** `HELP-02` `bmid/sanity_check/index.html.erb:5` toasts-alerts: Rule: on a report no reference info callout stays visible in the body. Code: an always-shown ui_callout_box :info explains the page covers only the current year.
- **medium** `STAT-01` `bmid/sanity_check/index.html.erb:10` other: Rule: summary tiles are ui_stat_box inside ui_stat_row; a grid needs approval. Code: hand grid "grid grid-cols-2 lg:grid-cols-4" of ui_stat_link-wrapped tiles.
- **medium** `TYPE-03` `bmid/sanity_check/index.html.erb:90` tables-lists: Rule: table content is never text-sm. Code: identity subline (name, status, email) div "text-sm text-stone-muted" inside the Person cell.

**`bmid/badges/edit.html.erb`** (GET /bmid/manage/badges/:person_id/edit (re-rendered at 422 by update))

- **medium** `TYPE-03` `bmid/badges/edit.html.erb:64` typography: Rule: text-sm never for labels. Code: field labels Meals/Showers/Motor Vehicle Record and "(Read-only)" note are text-sm (64,71,78,81); line 85 is text-base and fine.
- **low** `COLOR-06` `bmid/badges/edit.html.erb:109` typography: Rule: same neutral utility for same purpose (text-stone-muted). Code: timestamp line uses hero-panel class me-muted, which maps to text-stone-muted; line 85 uses text-stone-muted directly.

**`bmid/export/unsubmit.html.erb`** (DELETE /bmid/export/:id (rendered by bmid/export#unsubmit at 422))

- **medium** `EMPTY-01` `bmid/export/unsubmit.html.erb:34` empty-loading: Rule: an empty state is always ui_empty_state. Code: when no badges were reverted the page shows a ui_callout_box :warning accent and skips the table.

**`bmid/titles/apply.html.erb`** (POST /bmid/titles/set (rendered by bmid/titles#apply at 422))

- **medium** `TYPE-03` `bmid/titles/apply.html.erb:43` tables-lists: Rule: table content is never text-sm. Code: status subline under callsign is text-sm; the identity column is also a t.cell, not row_header.

**`bmid/titles/index.html.erb`** (GET /bmid/titles)

- **medium** `HELP-02` `bmid/titles/index.html.erb:7` tables-lists: Rule: a rule or how-to goes in one collapsed ui_disclosure card. Code: a bare visible dl.instruction-list sits in the page body under the hero.

**`bmid/titles/set.html.erb`** (GET /bmid/titles/set)

- **medium** `TYPE-03` `bmid/titles/set.html.erb:57` tables-lists: Rule: table content is never text-sm. Code: div "text-sm text-stone-muted" status and positions under callsign; identity column is t.cell, not row_header.

**`bmid/export/index.html.erb`** (GET /bmid/export)

- **low** `MODAL-02` `bmid/export/index.html.erb:87` modals: Rule: a confirm asks with the action and says whether it can be undone. Code: export confirm states consequences but not whether it can be undone (it can, via Un-Submit).

**`bmid/titles/new.html.erb`** (GET /bmid/titles/new (re-rendered at 422 by create))

- **low** `COPY-04` `bmid/titles/new.html.erb:4` typography: Rule: creating says "Add [Entity]", never "New". Code: hero title "New Badge Title" on the create form page.

#### bookmarks (1)

**`bookmarks/show.html.erb`** (GET /bookmark/:tag)

- **low** `STYLE-01` `bookmarks/show.html.erb:15` navigation: No CSS outside components/; bookmark-page is defined in app/assets/stylesheets/bookmark.css, outside components/.

#### common (42)

**`common/schedule/index.html.erb`** (GET /me/schedule (via me/schedule/index))

- **medium** `BP-01` `common/schedule/index.html.erb:52` spacing: pattern=spacing md: only for button-row stacking and its spacer; md:hidden here shows the phone action stack only below md.
- **medium** `BP-01` `common/schedule/index.html.erb:80` spacing: pattern=spacing md:hidden on the export wrapper is show/hide by md, which the guide forbids.
- **medium** `BP-01` `common/schedule/index.html.erb:102` spacing: pattern=spacing md:flex-row md:gap-6 makes md the two-column fold; lg is the one structural fold.
- **medium** `BP-01` `common/schedule/index.html.erb:140` spacing: pattern=spacing md:w-60 md:sticky md:top-4 sizes and pins the rail at md, a layout tier.
- **medium** `BP-01` `common/schedule/index.html.erb:145` spacing: pattern=spacing hidden md:flex shows the desktop action rail by md breakpoint.
- **medium** `BTN-01` `common/schedule/index.html.erb:47` buttons: Buttons come from ButtonHelper, not btn classes by hand; the ui_disclosure summary is styled with button_classes(:primary) plus py-3 my-4 and a marker-hiding variant.
- **medium** `COLOR-02` `common/schedule/index.html.erb:170` cards: Colour carries meaning, never decoration; action_box gets ring-2 ring-warning to highlight the Sign-Ups box, with no warning to signal.

**`common/timesheet/index.html.erb`** (GET /me/timesheet)

- **medium** `BP-01` `common/timesheet/index.html.erb:50` spacing: pattern=spacing md:hidden shows the phone quick-action stack below md; md is not for show/hide.
- **medium** `BP-01` `common/timesheet/index.html.erb:87` spacing: pattern=spacing md:flex-row md:gap-4 makes md the two-column fold.
- **medium** `BP-01` `common/timesheet/index.html.erb:117` spacing: pattern=spacing md:w-60 md:sticky sizes and pins the rail at md.
- **medium** `BP-01` `common/timesheet/index.html.erb:122` spacing: pattern=spacing hidden md:flex shows the desktop rail by md.
- **medium** `BTN-04` `common/timesheet/index.html.erb:135` buttons: One primary per view; action_box defaults to :primary, so the desktop rail shows up to four primary buttons (124, 135, 145, 154).
- **medium** `COLOR-02` `common/timesheet/index.html.erb:131` cards: Colour carries meaning, never decoration; action_box gets ring-2 ring-warning for highlight. Descriptions also inject <br> via html_safe (147, 156).
- **low** `COPY-03` `common/timesheet/index.html.erb:24` other: Labels are Title Case; stat labels are written in capitals ("ENTRIES", "VERIFIED", "UNVERIFIED", "PENDING").
- **low** `COPY-03` `common/timesheet/index.html.erb:93` typography: Title Case lowercases coordinating conjunctions; the section title reads "Action Required Or Pending Correction Review".

**`common/qualifications/index.html.erb`** (GET /me/schedule/qualifications)

- **medium** `ALERT-01` `common/qualifications/index.html.erb:91` toasts-alerts: Inline notices are ui_callout_box; the Shiny Penny notice is a hand-made div "p-4 bg-warning/10 rounded-lg text-warning" with its own h4 and star icon.
- **medium** `COLOR-03` `common/qualifications/index.html.erb:25` color: No coloured text for emphasis; the Non-transferable rule li is text-error while its sibling rules are plain, so red only emphasises.
- **medium** `HELP-02` `common/qualifications/index.html.erb:14` other: On a report, reference info lives in one collapsed About This Report card; the always-open accent card lists reference rules (estimates, verification) beside the one warning.
- **medium** `TYPE-05` `common/qualifications/index.html.erb:92` typography: Hierarchy goes h1 > h2 > h3; the Shiny Penny h4 sits directly under a level-2 section title, skipping h3.

**`common/schedule/signup_summary.html.erb`** (GET /me/schedule/signup-summary)

- **medium** `HELP-02` `common/schedule/signup_summary.html.erb:28` other: On a report the legend lives in one collapsed About This Report card; the Earned/Scheduled legend is a visible muted line under the stats.
- **medium** `STAT-01` `common/schedule/signup_summary.html.erb:8` other: Summary tiles are ui_stat_box inside ui_stat_row, never a hand-rolled grid; here three stat boxes sit in "grid grid-cols-3 gap-2 lg:gap-4 my-4".
- **low** `COLOR-05` `common/schedule/signup_summary.html.erb:29` icons: Icons are neutral unless they carry status; the legend's circle-info icon is text-primary.
- **low** `TABLE-02` `common/schedule/signup_summary.html.erb:49` tables-lists: pattern=tables-lists responsive: false fits ~4 columns or fewer, or a matrix with a call-site comment; this 5-column period matrix has no comment.

**`common/work_history/position_all.html.erb`** (GET /me/timesheet/work-history/position-all)

- **medium** `STAT-01` `common/work_history/position_all.html.erb:7` other: Summary numbers are ui_stat_box in ui_stat_row; year count and total hours are ui_badge in a flex div (mb-4, siblings mb-3).
- **medium** `TYPE-03` `common/work_history/position_all.html.erb:33` typography: Table content is text-base; the Echelon note in a cell is text-sm (33); 17 is a muted text-sm hours aside next to the year heading.
- **medium** `TYPE-04` `common/work_history/position_all.html.erb:15` typography: Nothing in a section outweighs its title; the per-year div is text-lg font-semibold, heavier than the base-size section title below lg.

**`common/work_history/entire_year.html.erb`** (GET /me/timesheet/work-history/entire-year)

- **medium** `STAT-01` `common/work_history/entire_year.html.erb:10` other: Summary numbers are ui_stat_box in ui_stat_row; entry count, total hours and credits are a row of ui_badge in a flex div.
- **medium** `TYPE-03` `common/work_history/entire_year.html.erb:29` typography: Table content is text-base; the "(as Echelon volunteer)" note in a cell is text-sm.

**`common/work_history/position_summary.html.erb`** (GET /me/timesheet/work-history/position-summary)

- **medium** `STAT-01` `common/work_history/position_summary.html.erb:10` other: Summary numbers are ui_stat_box in ui_stat_row; entries, hours, credits are a ui_badge row in a flex div.
- **medium** `TYPE-03` `common/work_history/position_summary.html.erb:28` typography: Table content is text-base; the Echelon note in a cell is text-sm.

**`common/available_sign_ups/index.html.erb`** (GET /me/schedule/sign-ups)

- **medium** `EMPTY-01` `common/available_sign_ups/index.html.erb:33` empty-loading: An empty state is always ui_empty_state; the no-positions case is a div "mt-4 text-error", red text for an empty list.

**`common/available_sign_ups/show.html.erb`** (GET /me/schedule/sign-ups/position/:position_id)

- **medium** `EMPTY-01` `common/available_sign_ups/show.html.erb:75` empty-loading: An empty state is always ui_empty_state; "No more upcoming shifts" (75) and "No past shifts" (90) are div "text-error px-4", red text.

**`common/surveys/report.html.erb`** (GET /training/:slug/surveys/:survey_id/reports/:report_id (training/surveys#report via training/surveys/report.html.erb), GET /mentoring/surveys/:survey_id/reports/:report_id (mentoring/surveys#report via mentoring/surveys/report.html.erb))

- **medium** `BTN-05` `common/surveys/report.html.erb:20` navigation: Rule: :primary is for primary actions. The sibling-report switcher paints the current report's link :primary (aria-current page) as a selected-tab marker.

**`common/timesheet/edit.html.erb`** (GET /me/timesheet/manage/:id/edit (via me/timesheet/edit))

- **low** `COPY-04` `common/timesheet/edit.html.erb:85` buttons: pattern=buttons Submitting a form says "Save [Entity]", never "Submit"; the submit reads "Submit Correction" (hero title 4 too).
- **low** `FORM-10` `common/timesheet/edit.html.erb:80` toasts-alerts: A sub-group divider is mt-4 pt-3 border-t border-line; the callout's footer line uses mt-3 pt-3 border-t border-warning.

**`common/bulk_upload/index.html.erb`** (GET and POST .../edit for: /agreements/bulk-signature, /people/bulk-status, /certificates/bulk-record, /vehicles/bulk-paperwork, /teams-positions/bulk-positions, /teams-positions/bulk-teams, /teams-positions/bulk-membership-history, /shift-operations/bulk-sign-in-out, /ticketing/bulk-provisions, /ticketing/bulk-access-documents, /ticketing/bulk-bmid (each <ctrl>#index)

- **low** `BP-01` `common/bulk_upload/index.html.erb:58` forms: Rule: sm: only in a field's width:. The action select's width is passed as an html class `w-full sm:w-96`, not width:.

**`common/bulk_upload/preview.html.erb`** (POST .../preview for the same eleven bulk controllers (<ctrl>#preview, 422))

- **low** `MODAL-02` `common/bulk_upload/preview.html.erb:99` modals: Rule: ask with the action and say whether it can be undone. Dialog is titled "Final Confirmation" and its message states the consequence but not whether it can be undone.

**`common/messages/new.html.erb`** (GET /me/messages/new, GET /person/:person_id/messages/new, GET /hq/:person_id/messages/new)

- **low** `COPY-04` `common/messages/new.html.erb:22` buttons: Rule: never "New [Entity]". The /me hero title is "New Message".

**`common/missing_requests/index.html.erb`** (GET /me/timesheet/missing-request (me/missing_requests#index via me/missing_requests/index.html.erb), GET /hq/:person_id/timesheets/missing-requests (hq/missing_requests#index via hq stub))

- **low** `EMPTY-01` `common/missing_requests/index.html.erb:31` empty-loading: Rule: always ui_empty_state. No requests shows a plain `mt-4` div of text.

**`common/missing_requests/new.html.erb`** (GET /me/timesheet/missing-request/new, GET /hq/:person_id/timesheets/missing-requests/new)

- **low** `COPY-04` `common/missing_requests/new.html.erb:2` buttons: Rule: creating is "Add [Entity]", never "New". Hero title "New Missing Timesheet Request".

**`common/provisions/new.html.erb`** (GET /person/:person_id/tickets-provisions/provisions/new (person/provisions#new via person/provisions/new.html.erb))

- **low** `COPY-04` `common/provisions/new.html.erb:5` buttons: Rule: never "New [Entity]". Hero title "New Provision — <callsign>".

**`common/resource_documents/edit.html.erb`** (GET /training/:slug/resources/edit (training/resources#edit via training/resources/edit.html.erb), GET /teams-positions/team-documents/:team_id/edit (teams_positions/team_documents#edit via its edit.html.erb))

- **low** `COPY-04` `common/resource_documents/edit.html.erb:1` buttons: Rule: never "New [Entity]". The browser title reads "New Document" for an unsaved document.

#### communication (23)

**`communication/rbs_messages/index.html.erb`** (GET /communication/rbs/messages)

- **medium** `FORM-01` `communication/rbs_messages/index.html.erb:41` forms: Labels come from the builder; raw <label> elements (41,53) label checkbox grids they are not associated with.
- **medium** `FORM-05` `communication/rbs_messages/index.html.erb:41` forms: Checkbox groups are grouped with f.fieldset; Outcome and Email Failure Reason use raw <label> with LABEL_CLASSES plus role=group (41,53).
- **medium** `STYLE-03` `communication/rbs_messages/index.html.erb:112` cards: No ad-hoc wrapper doing a helper's job; message text in the detail row is a hand-made bordered, rounded, tinted, padded box.
- **low** `EMPTY-02` `communication/rbs_messages/index.html.erb:113` icons: pattern=empty-loading not an icon: an empty message prints italic tag.i("empty message") instead of "—".

**`communication/rbs_history/show.html.erb`** (GET /communication/rbs/history/:id)

- **medium** `BTN-05` `communication/rbs_history/show.html.erb:32` buttons: :error is for destructive actions; the non-destructive retry "Send Failed Messages Again" is a red :error button_link.
- **medium** `STYLE-03` `communication/rbs_history/show.html.erb:70` cards: No ad-hoc wrapper doing a helper's job; message bodies sit in hand-made bordered, rounded, tinted, padded boxes (70,74).
- **low** `COPY-03` `communication/rbs_history/show.html.erb:73` typography: Headings are Title Case; the h3 reads "Email and Clubhouse message".
- **low** `STYLE-04` `communication/rbs_history/show.html.erb:66` tables-lists: The documented utilities are the vocabulary; stack-to-row-lg is an undocumented @utility equal to the documented flex flex-col lg:flex-row gap-4 wrapper.

**`communication/rbs_broadcasts/review.html.erb`** (POST /communication/rbs/broadcasts/:type/review)

- **medium** `BTN-05` `communication/rbs_broadcasts/review.html.erb:81` buttons: :error is for destructive actions; the emergency Send is red :error though sending is not destructive (Edit Message :secondary and cancel_link fine).
- **medium** `STYLE-03` `communication/rbs_broadcasts/review.html.erb:36` cards: No ad-hoc wrapper doing a helper's job; message previews sit in hand-made bordered, rounded, tinted, padded boxes (36,46).
- **low** `COPY-03` `communication/rbs_broadcasts/review.html.erb:44` typography: Headings and button labels are Title Case; h3 reads "Email and Clubhouse message" (44) and the submit "Send to N people" (80).

**`communication/announcements/index.html.erb`** (GET /communication/announcements)

- **high** `BTN-05` `communication/announcements/index.html.erb:21` buttons: Destructive actions take :error (delete_button); "Delete Expired" is a grey :secondary button_link, unlike the red delete buttons elsewhere.

**`communication/rbs_history/index.html.erb`** (GET /communication/rbs/history)

- **high** `HELP-02` `communication/rbs_history/index.html.erb:22` toasts-alerts: On a log no reference info callout stays visible; the "Most rows are message alerts" explanation is an always-open info callout, not the collapsed About This Report card.

**`communication/rbs_phone_numbers/index.html.erb`** (GET /communication/rbs/phone-numbers)

- **high** `HELP-02` `communication/rbs_phone_numbers/index.html.erb:24` other: On a report, explanations go in one collapsed About card; this page keeps a visible info callout holding a Q&A instruction-list under the stat row.

**`communication/surveys/index.html.erb`** (GET /communication/survey-management)

- **medium** `BTN-04` `communication/surveys/index.html.erb:63` buttons: One clear primary action per view; every table row has a :primary "Manage" button besides the page's :primary "Add Survey".
- **low** `COPY-03` `communication/surveys/index.html.erb:36` typography: Section titles are Title Case; the table section reads "3 surveys in 2026".

**`communication/surveys/show.html.erb`** (GET /communication/survey-management/:id)

- **medium** `STYLE-03` `communication/surveys/show.html.erb:45` cards: No ad-hoc wrapper doing a helper's job; prologue and epilogue sit in hand-made bordered, rounded, tinted, padded scroll boxes (45,51).
- **low** `EMPTY-02` `communication/surveys/show.html.erb:46` empty-loading: An empty value prints "—"; missing prologue/epilogue print italic muted "None given." (46,52).

**`communication/announcements/new.html.erb`** (GET /communication/announcements/new)

- **low** `COPY-04` `communication/announcements/new.html.erb:2` typography: The create form is "Add [Entity]", never "New"; the hero title reads "New Announcement" (survey_groups/new uses "Add Group").

**`communication/mail_templates/edit.html.erb`** (GET /communication/mail-templates/:id/edit)

- **low** `COPY-03` `communication/mail_templates/edit.html.erb:36` typography: Headings are Title Case; fieldset legends read "Subject line" and "Template text" (36,43).

**`communication/mail_templates/index.html.erb`** (GET /communication/mail-templates)

- **low** `COPY-03` `communication/mail_templates/index.html.erb:13` typography: Section titles are Title Case; pluralize(n, "template") prints "3 templates".

**`communication/person_banners/index.html.erb`** (GET /communication/person-banners)

- **low** `COPY-10` `communication/person_banners/index.html.erb:18` other: Paragraphs are two or three sentences at most; the Who Sees Banners callout is four sentences and opens by repeating its title as a question.

**`communication/surveys/new.html.erb`** (GET /communication/survey-management/new)

- **low** `COPY-04` `communication/surveys/new.html.erb:4` typography: The create form is "Add [Entity]", never "New"; the hero title reads "New Survey".

#### dashboard_tasks (19)

**`dashboard_tasks/_attend_cheetah_cub_shift_pending.html.erb`** (rendered by common/_dashboard_step on GET /me)

- **medium** `STYLE-03` `dashboard_tasks/_attend_cheetah_cub_shift_pending.html.erb:4` cards: Use the helper where one exists; hand-made bg-default rounded p-2 date box (alpha pending uses p-3)
- **medium** `TYPE-03` `dashboard_tasks/_attend_cheetah_cub_shift_pending.html.erb:8` typography: text-sm is for secondary content; the "Can't make it? Email Mentor Cadre" instruction is text-sm
- **low** `COPY-08` `dashboard_tasks/_attend_cheetah_cub_shift_pending.html.erb:5` other: Dates come from DateTimeHelper methods, never strftime in a view; prints with strftime where siblings use datetime_format tz:

**`dashboard_tasks/_verify_personal_info.html.erb`** (rendered by common/_dashboard_step on GET /me)

- **medium** `COLOR-03` `dashboard_tasks/_verify_personal_info.html.erb:4` color: No coloured text for emphasis; the same sentence is red text-error in one branch and plain in the other, colour alone marking urgency in the line
- **medium** `TYPE-04` `dashboard_tasks/_verify_personal_info.html.erb:12` typography: Nothing inside a section outweighs its title; p font-semibold text-lg shirt line is larger than the step card title (assumed heading-title)

**`dashboard_tasks/_after_event_status_advisory.html.erb`** (rendered by common/_dashboard_step on GET /me)

- **medium** `TYPE-03` `dashboard_tasks/_after_event_status_advisory.html.erb:9` typography: text-sm is for secondary content only; lines 9 and 21 set reactivation rules the reader needs in text-sm

**`dashboard_tasks/_attend_alpha_shift_pending.html.erb`** (rendered by common/_dashboard_step on GET /me)

- **medium** `STYLE-03` `dashboard_tasks/_attend_alpha_shift_pending.html.erb:4` cards: Use the helper where one exists; a hand-made bg-default rounded padded box does a callout/card job

**`dashboard_tasks/_attend_green_dot_mentee_shift_waiting.html.erb`** (rendered by common/_dashboard_step on GET /me)

- **medium** `TYPE-03` `dashboard_tasks/_attend_green_dot_mentee_shift_waiting.html.erb:7` typography: text-sm is for secondary content; the "Can't make it?" instruction and its link are text-sm

**`dashboard_tasks/_attend_training_pending.html.erb`** (rendered by common/_dashboard_step on GET /me)

- **medium** `STYLE-03` `dashboard_tasks/_attend_training_pending.html.erb:27` cards: Use the helper where one exists; hand-made bg-default rounded slot box with icons and <br>

**`dashboard_tasks/_dashboard_tickets.html.erb`** (rendered by common/_dashboard_step on GET /me (payload.tickets, payload.ticketing_open))

- **medium** `EMPTY-01` `dashboard_tasks/_dashboard_tickets.html.erb:30` empty-loading: An empty state is always ui_empty_state; "No tickets claimed yet." is red bold-ish alert text with an error icon

**`dashboard_tasks/_online_course_needed.html.erb`** (rendered by common/_dashboard_step on GET /me)

- **medium** `TYPE-03` `dashboard_tasks/_online_course_needed.html.erb:16` typography: text-sm is for secondary content; the radio-protocol advice (4) and the completion/contact instruction (16) are text-sm

**`dashboard_tasks/_online_course_waiting.html.erb`** (rendered by common/_dashboard_step on GET /me)

- **medium** `TYPE-03` `dashboard_tasks/_online_course_waiting.html.erb:4` typography: text-sm is for secondary content; "Questions? email" and "Watch the Announce mailing list" instructions are text-sm

**`dashboard_tasks/_sign_motor_pool_protocol_needed.html.erb`** (rendered by common/_dashboard_step on GET /me)

- **medium** `TYPE-03` `dashboard_tasks/_sign_motor_pool_protocol_needed.html.erb:10` typography: text-sm is for secondary content; for applicants the step's only message ("Alphas don't drive Ranger vehicles.") is text-sm

**`dashboard_tasks/_sign_up_for_alpha_shift_blocked.html.erb`** (rendered by common/_dashboard_step on GET /me)

- **medium** `TYPE-03` `dashboard_tasks/_sign_up_for_alpha_shift_blocked.html.erb:2` typography: text-sm is for secondary content; the "Sat–Tue only, no exceptions" requirement is text-sm

**`dashboard_tasks/_sign_up_for_shifts_schedule_pending.html.erb`** (rendered by common/_dashboard_step on GET /me)

- **medium** `TYPE-03` `dashboard_tasks/_sign_up_for_shifts_schedule_pending.html.erb:2` typography: text-sm is for secondary content; the "Watch the Announce mailing list" instruction is text-sm

**`dashboard_tasks/_verify_timesheets.html.erb`** (rendered by common/_dashboard_step on GET /me)

- **medium** `TYPE-03` `dashboard_tasks/_verify_timesheets.html.erb:14` typography: text-sm is for secondary content; the warning "your ranger hours won't count" is text-sm

**`dashboard_tasks/_bmid_will_not_be_printed.html.erb`** (rendered by common/_dashboard_step on GET /me)

- **low** `SPACE-02` `dashboard_tasks/_bmid_will_not_be_printed.html.erb:5` tables-lists: A bulleted list is list-bulleted; code builds bullets from literal &bullet; glyphs in divs with an ms-5 "OR" divider

**`dashboard_tasks/_green_dot_mentee_shift_needed.html.erb`** (rendered by common/_dashboard_step on GET /me)

- **low** `COLOR-05` `dashboard_tasks/_green_dot_mentee_shift_needed.html.erb:2` icons: Icons are neutral unless they convey status; solid circle tinted icon-success draws a green dot as decoration (check at 4 is neutral)

**`dashboard_tasks/_no_things_at_the_moment.html.erb`** (rendered by common/_dashboard_step on GET /me)

- **low** `EMPTY-01` `dashboard_tasks/_no_things_at_the_moment.html.erb:1` empty-loading: An empty state is always ui_empty_state; the nothing-to-do state is bare bold text

#### hq (8)

**`hq/site_registration/show.html.erb`** (GET /hq/:person_id/site-registration)

- **medium** `BTN-04` `hq/site_registration/show.html.erb:17` buttons: One primary per view; when on site the callout's :primary Start Shift Check-In (17) shows with a disabled :primary Begin On-Site Registration (54).
- **medium** `MODAL-01` `hq/site_registration/show.html.erb:70` modals: Hand-built dialog driven by hq-wizard rather than ModalHelper modal with m.title/m.body/m.footer.
- **medium** `MODAL-01` `hq/site_registration/show.html.erb:77` modals: modal-header-bar copied from ModalHelper output instead of calling m.title.
- **medium** `MODAL-01` `hq/site_registration/show.html.erb:82` modals: modal-body-content hand-written instead of m.body.
- **low** `COPY-03` `hq/site_registration/show.html.erb:27` typography: Headings are Title Case labels; h3s at lines 27 and 31 are full sentences about the Vehicle Use Protocol.
- **low** `FORM-10` `hq/site_registration/show.html.erb:46` spacing: A sub-group divider is mt-4 pt-3 border-t border-line; section uses hr.my-4.border-base-300.

**`hq/shift_manage/index.html.erb`** (GET /hq/:person_id/shift-manage)

- **medium** `BTN-04` `hq/shift_manage/index.html.erb:39` buttons: One primary per view; page-level callouts add :primary Begin On-Site Registration (39) and Read Messages (61) above sections that hold their own primaries.
- **low** `COPY-03` `hq/shift_manage/index.html.erb:68` typography: Articles stay lowercase inside Title Case; section titles read End The Shift and Start A Shift.

#### me (41)

**`me/directory/index.html.erb`** (GET /me/directory)

- **medium** `CARD-01` `me/directory/index.html.erb:41` cards: One card utility via ui_card, no shadow; member tiles are hand-made divs with border, rounded-lg and shadow-sm
- **medium** `TYPE-03` `me/directory/index.html.erb:64` typography: text-sm never for primary card information; position titles in member tiles (64) and the No Photo label (53) are text-sm
- **medium** `TYPE-04` `me/directory/index.html.erb:59` typography: Nothing inside a section outweighs its title; callsign div is text-xl font-semibold inside a ui_section with a text-base/lg title
- **low** `EMPTY-02` `me/directory/index.html.erb:32` empty-loading: An empty value prints an em dash; missing email shows italic words "No contact email on file."; member grid has no empty branch
- **low** `SHADOW-01` `me/directory/index.html.erb:41` spacing: Flat by default and hover is a colour change; tile has shadow-sm plus hover:shadow-md
- **low** `STYLE-01` `me/directory/index.html.erb:45` other: pattern=other No inline style attribute; image height set by style: from PersonPhoto::AVATAR_HEIGHT
- **low** `STYLE-01` `me/directory/index.html.erb:50` other: pattern=other No inline style attribute; placeholder div sets height by style attribute from a constant

**`me/agreements/index.html.erb`** (GET /me/agreements)

- **medium** `CARD-02` `me/agreements/index.html.erb:30` cards: A left-border accent card is ui_accent_card; hand-made <article> with border-l-4 and status border/bg colours from agreement_* helpers
- **medium** `EMPTY-01` `me/agreements/index.html.erb:57` empty-loading: An empty state is always ui_empty_state, never a hand-rolled dashed box; code draws a dashed bordered box with medallion and h3
- **low** `SHADOW-01` `me/agreements/index.html.erb:30` spacing: Hover is a colour change, never a lift; hover:shadow-sm on the agreement article (57 is only rounded-lg on the empty box)
- **low** `TYPE-04` `me/agreements/index.html.erb:32` typography: <h3> takes heading-title; line 32 h3 carries text-base font-semibold instead (59 is correct)
- **low** `TYPE-05` `me/agreements/index.html.erb:32` typography: Heading hierarchy runs h1 > h2 > h3; agreement article titles are h3 directly under the hero h1 with no h2

**`me/vehicles_dashboard/index.html.erb`** (GET /me/vehicles)

- **medium** `ALERT-01` `me/vehicles_dashboard/index.html.erb:30` cards: Inline notices are ui_callout_box or ui_alert_banner; hand-made bg-error/10 bordered rounded-xl panel with medallion, h2 and lg button
- **medium** `BTN-04` `me/vehicles_dashboard/index.html.erb:21` buttons: One clear primary action per view; the side-by-side MVR and PVR sections each end in a full-width :primary button (_mvr_status_eligible:36, _pvr_status_eligible:9 or _pvr_status_potential:18)
- **medium** `BTN-05` `me/vehicles_dashboard/index.html.erb:44` buttons: :error is for destructive actions; "Review and Sign Agreement" is an :error lg button
- **low** `SHADOW-01` `me/vehicles_dashboard/index.html.erb:30` spacing: Flat by default; the agreement-required panel has shadow-sm (and rounded-xl)

**`me/announcements/index.html.erb`** (GET /me/announcements)

- **medium** `ALERT-01` `me/announcements/index.html.erb:11` other: Inline notices are ui_callout_box; the hand-made box renders as an empty bordered div for anyone neither ranger nor applicant
- **medium** `EMPTY-01` `me/announcements/index.html.erb:46` empty-loading: An empty state is always ui_empty_state, never a dashed box; code draws a dashed bordered box with inbox icon and p heading
- **low** `TYPE-05` `me/announcements/index.html.erb:13` typography: Hierarchy runs h1 > h2 > h3; notice box and announcement titles (_announcement:27) are h3 directly under the hero h1

**`me/tickets/gift.html.erb`** (GET /me/tickets/gift)

- **medium** `BTN-04` `me/tickets/gift.html.erb:114` buttons: One clear primary action per view; every claim, delivery and release button is :secondary, so the gift page has none (claim_buttons makes Will Call primary)
- **medium** `EMPTY-01` `me/tickets/gift.html.erb:23` empty-loading: An empty state is ui_empty_state; no gift tickets shown as a secondary callout box with a back button
- **low** `COPY-03` `me/tickets/gift.html.erb:56` typography: A heading is a Title Case label, not prose; h3s are sentences ("Claimed — pick up at Will Call (free).")

**`me/agreements/show.html.erb`** (GET /me/agreements/:id)

- **medium** `BTN-01` `me/agreements/show.html.erb:21` buttons: Buttons come from ButtonHelper; code uses button_to with class button_classes({}, :primary) and an fa_icon block
- **medium** `FORM-09` `me/agreements/show.html.erb:13` other: Saved rich text renders in .lexxy-content through rich_text; the agreement document body is printed with @document.body.html_safe

**`me/surveys/show.html.erb`** (GET /me/surveys)

- **medium** `FORM-06` `me/surveys/show.html.erb:40` validation: Errors show in ui_form's summary at the top as well as on fields; survey form passes no_error_summary: true
- **low** `COPY-04` `me/surveys/show.html.erb:82` buttons: pattern=buttons Never "Submit" as a submit label; the survey button reads "Submit Feedback"
- **low** `HERO-02` `me/surveys/show.html.erb:5` typography: Description is one sentence saying what the page does; it is a slot label plus a date span with class text-lg and ml-4

**`me/dashboard/index.html.erb`** (GET /me)

- **high** `HERO-01` `me/dashboard/index.html.erb:4` typography: Every page header is hero_panel; applicant branch prints raw <h1> text-2xl font-bold while ranger and other branches use hero_panel

**`me/password/edit.html.erb`** (GET /me/profile/password)

- **medium** `FORM-03` `me/password/edit.html.erb:7` forms: Required fields are marked through required:; the three password fields (7-9) carry no required: marker
- **low** `COPY-04` `me/password/edit.html.erb:13` buttons: A form submit says "Save [Entity]"; the password form's submit reads "Change Password"

**`me/tickets/provisions.html.erb`** (GET /me/tickets/provisions)

- **medium** `EMPTY-01` `me/tickets/provisions.html.erb:27` empty-loading: An empty state is ui_empty_state; no provisions shown as a secondary callout with a back button
- **low** `STYLE-03` `me/tickets/provisions.html.erb:48` tables-lists: Use the helper where one exists; li flex + fa_icon rows hand-build what ui_icon_item renders

**`me/work_history/index.html.erb`** (GET /me/timesheet/work-history)

- **medium** `HELP-02` `me/work_history/index.html.erb:12` tables-lists: On a report the explanation lives only in one collapsed card; Work History keeps a visible Q&A dl inside a ui_section
- **low** `COPY-03` `me/work_history/index.html.erb:6` other: Labels a reader scans are Title Case; stat labels are ALL CAPS ("TOTAL HOURS", "YEARS", "POSITIONS")

**`me/online_course/index.html.erb`** (GET /me/online-course)

- **medium** `COLOR-03` `me/online_course/index.html.erb:13` color: No coloured text for emphasis; "MUST complete In-Person Training" is strong text-warning

**`me/tickets/sap_so.html.erb`** (GET /me/tickets/sap-so)

- **medium** `COLOR-03` `me/tickets/sap_so.html.erb:69` color: No coloured text for emphasis; "NO EXCEPTIONS!" is span text-error inside a Q&A answer

**`me/tickets/ticket.html.erb`** (GET /me/tickets/ticket)

- **medium** `CARD-01` `me/tickets/ticket.html.erb:62` cards: Cards are card-standard via ui_card; ticket cards are hand-made rounded-lg bordered p-4 divs

**`me/event_info.html.erb`** (- (MeController#event_info exists)

- **low** `COPY-03` `me/event_info.html.erb:4` navigation: Tab labels are Title Case; tab_navigation panes are titled "event" and "training" (lines 4, 7)

**`me/event_summary/index.html.erb`** (GET /me/timesheet/event-summary)

- **low** `COPY-03` `me/event_summary/index.html.erb:7` other: Labels a reader scans are Title Case; stat labels are ALL CAPS ("TOTAL HOURS", "CREDITS", "POSITIONS")

**`me/personal_vehicles/new.html.erb`** (GET /me/vehicles/personal/new)

- **low** `COPY-04` `me/personal_vehicles/new.html.erb:2` other: Opening the create form says "Add [Entity]", never "New"/"Submit"; hero title is "Submit New Personal Vehicle Request"

**`me/tickets/review.html.erb`** (GET /me/tickets/review)

- **low** `EMPTY-01` `me/tickets/review.html.erb:45` empty-loading: An empty state is ui_empty_state; "Nothing claimed." is plain text in a p

#### mentoring (58)

**`mentoring/alpha_mentor_assignments/index.html.erb`** (GET /mentoring/alpha-mentor-assignments (POST, pod-prefill POST re-render))

- **high** `TYPE-02` `mentoring/alpha_mentor_assignments/index.html.erb:211` typography: text-xs never for content a reader needs; prior years' results and mentors print as "block text-xs text-stone-muted", built from interpolated <br> strings.
- **medium** `FORM-01` `mentoring/alpha_mentor_assignments/index.html.erb:172` forms: Forms use builder fields; the pod shift picker is a raw select_tag borrowing SELECT_CLASSES, aria-label only, beside f.submit in a flex div.
- **medium** `FORM-01` `mentoring/alpha_mentor_assignments/index.html.erb:249` forms: Forms use builder fields; each row's three mentor selects and result select are raw select_tag with SELECT_CLASSES, aria labels and explicit ids.
- **medium** `FORM-01` `mentoring/alpha_mentor_assignments/index.html.erb:258` forms: pattern=forms Per-row result select is select_tag with SELECT_CLASSES, not a builder field.
- **medium** `FORM-02` `mentoring/alpha_mentor_assignments/index.html.erb:172` forms: Every field has a visible label; the pod shift select has only an aria-label.
- **medium** `FORM-06` `mentoring/alpha_mentor_assignments/index.html.erb:41` validation: Errors show through the builder with ui_form's summary on top; the form passes no_error_summary and hand-writes an error callout "Nothing Was Recorded" with a row count.
- **medium** `FORM-06` `mentoring/alpha_mentor_assignments/index.html.erb:270` validation: A field error is a role=alert message under the field; row errors are an extra error-tinted table row with a "text-error font-semibold" span and icon, no role=alert.
- **low** `COPY-10` `mentoring/alpha_mentor_assignments/index.html.erb:34` other: Paragraphs are two or three sentences; the no-bonks callout body is five sentences and opens by repeating its title as a question.
- **low** `EMPTY-02` `mentoring/alpha_mentor_assignments/index.html.erb:221` empty-loading: An empty value prints "—"; no shift sign-up prints muted "None".

**`mentoring/alpha_pods/people/edit.html.erb`** (GET /mentoring/alpha-pods/:slot_id/pods/:pod_id/people/:person_id/edit)

- **medium** `FORM-01` `mentoring/alpha_pods/people/edit.html.erb:16` forms: Fields come from the builder; lead is check_box_tag in a hand label, pod is select_tag with a raw label and hand help paragraph, all borrowing builder classes.
- **medium** `FORM-01` `mentoring/alpha_pods/people/edit.html.erb:23` forms: Raw <label> elements (15, 23) stand in for builder field labels.
- **medium** `TYPE-03` `mentoring/alpha_pods/people/edit.html.erb:36` typography: text-sm never for paragraph content; the walk-order paragraph is text-sm (36); line 26 is field help text, an allowed use.
- **low** `COPY-04` `mentoring/alpha_pods/people/edit.html.erb:49` buttons: Taking something out of a group is "Remove from [Group]"; the button reads "Take out of Pod N".
- **low** `FORM-10` `mentoring/alpha_pods/people/edit.html.erb:35` other: A sub-group divider is "mt-4 pt-3 border-t border-line"; the dialog uses "border-t border-base-300 mt-4 pt-3".

**`mentoring/alpha_pods/print_sheet.html.erb`** (GET /mentoring/alpha-pods/:slot_id/print)

- **medium** `STYLE-01` `mentoring/alpha_pods/print_sheet.html.erb:19` other: No per-view CSS; the view injects a <style> block (named @page with a page-counter margin box) through content_for :page_rules.
- **medium** `TABLE-01` `mentoring/alpha_pods/print_sheet.html.erb:64` tables-lists: Data tables are ui_table; the pod columns are a raw table styled by alpha-pod-table CSS.
- **low** `COLOR-01` `mentoring/alpha_pods/print_sheet.html.erb:25` color: Semantic colour tokens only; the page-counter margin box hard-codes color: #444 in the view's <style>.
- **low** `EMPTY-01` `mentoring/alpha_pods/print_sheet.html.erb:107` empty-loading: An empty state uses ui_empty_state; no pods prints a plain p.mt-4 sentence.
- **low** `EMPTY-02` `mentoring/alpha_pods/print_sheet.html.erb:85` empty-loading: An empty value prints "—"; an empty pod group cell prints span.alpha-pod-empty "None" (the no-pods sentence at 107 is logged as F).
- **low** `STYLE-01` `mentoring/alpha_pods/print_sheet.html.erb:68` other: No inline style= without a reason; th width is an inline style holding a computed percentage.

**`mentoring/alpha_schedule/show.html.erb`** (GET /mentoring/alpha-schedule/:slot_id)

- **high** `TYPE-02` `mentoring/alpha_schedule/show.html.erb:82` typography: text-xs never for content a reader needs; the flag year beside each rank badge is in a text-xs span (text-sm trainings at 104 logged as F).
- **medium** `TYPE-03` `mentoring/alpha_schedule/show.html.erb:104` typography: text-sm never for table content; each training line in the Training cell is a text-sm div.
- **low** `COPY-04` `mentoring/alpha_schedule/show.html.erb:112` buttons: Taking someone out of a group reads "Remove from [Group]"; the row button is a bare "Remove".
- **low** `EMPTY-02` `mentoring/alpha_schedule/show.html.erb:101` empty-loading: An empty value prints "—"; no training prints muted "None" (101); the muted "No" at 96 answers the Yes badge.
- **low** `MODAL-02` `mentoring/alpha_schedule/show.html.erb:116` modals: A confirm says whether it can be undone; "Remove X from Y?" stops at the question.

**`mentoring/alpha_schedule/info_sheet.html.erb`** (GET /mentoring/alpha-schedule/:slot_id/info-sheet)

- **medium** `STYLE-01` `mentoring/alpha_schedule/info_sheet.html.erb:19` other: No per-view CSS; the view injects a <style> block (@page alpha-info margin box with page counter) through content_for :page_rules.
- **medium** `TABLE-01` `mentoring/alpha_schedule/info_sheet.html.erb:44` tables-lists: Data tables are ui_table; the per-Alpha information blocks are a raw table.
- **low** `COLOR-01` `mentoring/alpha_schedule/info_sheet.html.erb:24` color: Semantic colour tokens only; the page-counter margin box hard-codes color: #444 in the view's <style>.
- **low** `EMPTY-02` `mentoring/alpha_schedule/info_sheet.html.erb:89` empty-loading: An empty value prints "—"; known rangers, known Alphas and trainings print nothing at all when empty (73-78, 89, 93).
- **low** `EMPTY-02` `mentoring/alpha_schedule/info_sheet.html.erb:101` empty-loading: An empty value prints "—"; prior mentors and mentor notes print <em>None</em>, a missing note source <em>Unknown</em> (101, 116, 126).

**`mentoring/shift_report/index.html.erb`** (GET /mentoring/shift-report)

- **medium** `COLOR-02` `mentoring/shift_report/index.html.erb:54` color: Colour carries meaning; the :error callout flags "On duty now" live data, which the comment says is not an error state.
- **medium** `COLOR-02` `mentoring/shift_report/index.html.erb:59` color: Colour carries meaning; a :success callout states the scheduled shift and window, which is neutral information, not a success.
- **medium** `HELP-02` `mentoring/shift_report/index.html.erb:62` other: On a report the card is the only home for counting rules; the visible banner says shifts 1 hour before and 2 hours after are included.
- **low** `COPY-03` `mentoring/shift_report/index.html.erb:30` buttons: Prepositions of four letters or fewer stay lower case; "Currently On Duty" capitalises "On" (the sign-out page writes "Still on Duty").

**`mentoring/alpha_schedule/apparel.html.erb`** (GET /mentoring/alpha-schedule/:slot_id/apparel)

- **medium** `TABLE-01` `mentoring/alpha_schedule/apparel.html.erb:30` tables-lists: Data tables are ui_table; apparel rows and captioned totals tables are raw HTML styled by .alpha-sheet.
- **medium** `TABLE-01` `mentoring/alpha_schedule/apparel.html.erb:75` tables-lists: pattern=tables-lists Data tables are ui_table; each size-totals table is a raw table with a caption.
- **low** `EMPTY-01` `mentoring/alpha_schedule/apparel.html.erb:23` empty-loading: An empty state uses ui_empty_state; an empty apparel group prints a plain p.mt-4 sentence.
- **low** `EMPTY-01` `mentoring/alpha_schedule/apparel.html.erb:85` empty-loading: An empty state uses ui_empty_state; an empty totals table prints a bare row "None" (colspan 2).

**`mentoring/alpha_signout/index.html.erb`** (GET /mentoring/alpha-signout (POST re-renders))

- **medium** `COLOR-02` `mentoring/alpha_signout/index.html.erb:97` color: Colour carries meaning; the :error callout marks live data that ignores the schedule, which the comment says is not an error state.
- **medium** `COLOR-02` `mentoring/alpha_signout/index.html.erb:102` color: Colour carries meaning; a :success callout states the chosen shift and its sign-out window, which is neutral information, not a success.
- **medium** `MODAL-02` `mentoring/alpha_signout/index.html.erb:157` modals: A destructive confirm is red (variant: :error); the irreversible sign-out confirm_modal_dialog passes no variant, so its confirm button is primary under an :error submit.

**`mentoring/alpha_schedule/signup_sheet.html.erb`** (GET /mentoring/alpha-schedule/:slot_id/signup-sheet)

- **medium** `ICON-01` `mentoring/alpha_schedule/signup_sheet.html.erb:48` icons: Icons are FontAwesome via fa_icon; a flagged person is a literal "⚑" character, where the information sheet uses fa_icon flag.
- **medium** `TABLE-01` `mentoring/alpha_schedule/signup_sheet.html.erb:30` tables-lists: Data tables are ui_table; roster blocks are raw tbody groups with alpha-write-row rows and a repeating running head.
- **low** `EMPTY-01` `mentoring/alpha_schedule/signup_sheet.html.erb:28` empty-loading: An empty state uses ui_empty_state; an empty roster prints a plain p.mt-4 sentence (the dash for no trainings at 61 is correct).

**`mentoring/alpha_pods/people/new.html.erb`** (GET /mentoring/alpha-pods/:slot_id/pods/:pod_id/people/new)

- **medium** `FORM-01` `mentoring/alpha_pods/people/new.html.erb:23` forms: check_box_tag with CHECKBOX_CLASSES in place of a builder checkbox.
- **medium** `TYPE-03` `mentoring/alpha_pods/people/new.html.erb:49` typography: text-sm never for paragraph content; the Not Checked In explanation is p "text-sm text-stone-muted".

**`mentoring/alpha_acceptance_sheets/print_sheets.html.erb`** (GET /mentoring/alpha-acceptance-sheets/print)

- **low** `COPY-03` `mentoring/alpha_acceptance_sheets/print_sheets.html.erb:169` tables-lists: Table headings are Title Case; the sign-off grid headings are all caps ("MENTOR NAME", "ACCEPT W/RESERV.", "REJECT") (169-172).
- **low** `EMPTY-01` `mentoring/alpha_acceptance_sheets/print_sheets.html.erb:211` empty-loading: Empty states use ui_empty_state; notes boxes print plain "None", "No VC notes", "No notes given.", "No prior mentor notes" (148, 211, 242, 255).
- **low** `TYPE-05` `mentoring/alpha_acceptance_sheets/print_sheets.html.erb:32` typography: Heading hierarchy is clear (h1 > h2 > h3); the form title and section bands are plain divs, so the document has no headings at all.

**`mentoring/convert_prospectives/index.html.erb`** (GET /mentoring/convert-prospectives (POST re-renders))

- **medium** `TYPE-03` `mentoring/convert_prospectives/index.html.erb:115` typography: text-sm never for table content; "<status>" in literal angle brackets and the FKA line are text-sm muted divs in table cells.
- **low** `MODAL-02` `mentoring/convert_prospectives/index.html.erb:175` modals: A confirm says whether it can be undone; "Convert the selected Prospectives to Alpha status?" omits it (the callout above says it).

**`mentoring/alpha_pods/unavailable.html.erb`** (rendered by Mentoring::AlphaPods::BaseController#render_refusal (frame GET, 422))

- **medium** `TYPE-03` `mentoring/alpha_pods/unavailable.html.erb:11` typography: text-sm never for paragraph content; p "text-sm text-stone-muted mb-3" explains what to do next in the dialog.

**`mentoring/surveys/index.html.erb`** (GET /mentoring/surveys)

- **medium** `COLOR-02` `mentoring/surveys/index.html.erb:25` other: Colour carries meaning; the survey count badge is :success with a pluralized word, where sibling sections show a bare number without a success colour.

**`mentoring/alpha_acceptance_sheets/index.html.erb`** (GET /mentoring/alpha-acceptance-sheets)

- **low** `EMPTY-02` `mentoring/alpha_acceptance_sheets/index.html.erb:111` empty-loading: An empty value prints "—"; Training and Mentor Shift cells print muted "None" instead (111, 120).

**`mentoring/alpha_status/index.html.erb`** (GET /mentoring/alpha-status)

- **low** `EMPTY-01` `mentoring/alpha_status/index.html.erb:97` empty-loading: An empty state uses ui_empty_state; an empty section prints a muted p with a filter-aware sentence.

**`mentoring/alphas_convert/index.html.erb`** (GET /mentoring/alphas-convert (POST re-renders))

- **low** `COPY-03` `mentoring/alphas_convert/index.html.erb:76` typography: Section titles are Title Case; pluralize builds "N Shiny Penny candidates" with lower-case "candidates".

**`mentoring/post_season_summary/index.html.erb`** (GET /mentoring/post-season-summary)

- **low** `EMPTY-01` `mentoring/post_season_summary/index.html.erb:100` empty-loading: An empty state uses ui_empty_state; an empty section prints a muted p with post_season_empty_message.

**`mentoring/potential_alphas/index.html.erb`** (GET /mentoring/potential-alphas)

- **low** `EMPTY-01` `mentoring/potential_alphas/index.html.erb:84` empty-loading: An empty state uses ui_empty_state; an empty cohort section prints a muted p, while the page-level empties (17, 72) use the helper.

#### people (9)

**`people/languages_known/index.html.erb`** (GET /people/languages-known)

- **medium** `FORM-01` `people/languages_known/index.html.erb:13` forms: Rule says AppFormBuilder; code is raw form_with with f.search_field styled by hand (input w-full max-w-sm min-h-9) beside the page's filter_bar, an ad-hoc second filter form (TABLE-04).
- **medium** `FORM-01` `people/languages_known/index.html.erb:18` forms: Rule says field classes come from the builder; the search field writes daisyUI input classes by hand.
- **medium** `FORM-02` `people/languages_known/index.html.erb:16` forms: Rule says every field has a visible label, never placeholder-only; the search field's label is sr-only and only the placeholder "Search languages" shows.
- **medium** `LAYOUT-03` `people/languages_known/index.html.erb:36` navigation: Rule says level 1 of a drill-down gets no filter bar; the language index (rows open per-language pages) carries a filter_bar plus a search form.

**`people/people_by_location/index.html.erb`** (GET /people/people-by-location)

- **medium** `LAYOUT-03` `people/people_by_location/index.html.erb:22` navigation: Rule says level 1 gets no filter bar and counts as a text-lg line; the country index has a filter_bar whose count slot replaces the text-lg line.

**`people/search/index.html.erb`** (GET /people/search)

- **medium** `FORM-05` `people/search/index.html.erb:80` typography: Rule says a checkbox group is grouped with f.fieldset; the group label is a styled p and common/checkbox_grid adds no fieldset, so the checkboxes have no programmatic group name.

**`people/status_change_recommendations/index.html.erb`** (GET /people/status-change-recommendations)

- **medium** `BTN-05` `people/status_change_recommendations/index.html.erb:14` navigation: Rule reserves :primary for primary actions; the period switch paints the current choice :primary and the other :secondary, using a button variant as a selected-state toggle.

**`people/status_change_recommendations/show.html.erb`** (GET /people/status-change-recommendations/:group)

- **medium** `MODAL-02` `people/status_change_recommendations/show.html.erb:106` buttons: Rule says a destructive confirm is red; the :error submit opens confirm_modal_dialog with no variant: :error (primary confirm button), and the message does not say the change cannot be undone.

**`people/people_by_status/show.html.erb`** (GET /people/people-by-status/:status)

- **low** `LAYOUT-03` `people/people_by_status/show.html.erb:12` typography: Rule gives level 2 a body ui_stat_row for totals; this level-2 page repeats the level-1 text-lg count line, which the section badge also states.

#### person (47)

**`person/callsigns/edit.html.erb`** (GET /person/:person_id/callsign/edit)

- **medium** `FORM-04` `person/callsigns/edit.html.erb:54` forms: FORM-04 says help text is the field's help_text:; notes under the checkboxes are hand-made div/p "text-sm text-stone-muted ml-8 -mt-1 mb-2" (54, 60, 67, 76)
- **medium** `MODAL-02` `person/callsigns/edit.html.erb:31` modals: MODAL-02 says a destructive confirm is red (confirm_modal variant: :error); the Release Callsign confirm_modal (renames and unapproves the callsign) passes no variant
- **low** `BTN-04` `person/callsigns/edit.html.erb:95` buttons: BTN-04 wants one primary action per view; "Save Callsign" (84) and "Add FKA" (95) are both primary
- **low** `EMPTY-02` `person/callsigns/edit.html.erb:113` empty-loading: EMPTY-02 says an empty value prints "—"; a missing FKA date prints italic muted "unknown"

**`person/awards/index.html.erb`** (GET /person/:person_id/awards)

- **medium** `HELP-02` `person/awards/index.html.erb:18` toasts-alerts: HELP-02 puts background and rules in one collapsed ui_disclosure :card; "What These Awards Recognize" is a visible info callout of reference text under the stat row
- **low** `COPY-03` `person/awards/index.html.erb:55` buttons: COPY-03 says button labels are Title Case; "Grant team award", "Grant special award", "Grant position award" (55, 64, 73)
- **low** `COPY-04` `person/awards/index.html.erb:55` buttons: COPY-04 says the control opening a create form is "Add [Entity]"; the award buttons say "Grant ... award" (55, 64, 73)
- **low** `MODAL-02` `person/awards/index.html.erb:37` modals: MODAL-02 says a confirm asks with the action ("Rebuild awards?"); the Rebuild message is a statement ("Rebuild re-checks ... history and grants ...") with no question

**`person/memberships/edit.html.erb`** (GET /person/:person_id/membership/edit)

- **medium** `HELP-02` `person/memberships/edit.html.erb:11` other: HELP-02 puts a legend in one collapsed ui_disclosure :card; the icon legend is inline in the intro paragraph, icons and italic terms separated by middots
- **medium** `TYPE-03` `person/memberships/edit.html.erb:5` typography: TYPE-03 bans text-sm on paragraph content; the intro and legend paragraph is p "mb-2 text-sm text-stone-muted" with text-xs icons
- **low** `TYPE-05` `person/memberships/edit.html.erb:35` typography: TYPE-05 wants h1 > h2 > h3; the General Positions card title is an h3 directly under the hero's h1 with no h2 between

**`person/permissions/edit.html.erb`** (GET /person/:person_id/permissions)

- **medium** `FORM-01` `person/permissions/edit.html.erb:30` forms: FORM-01: per-role raw check_box_tag in a table cell (CHECKBOX_CLASSES, disabled when not editable) stands in for a builder field
- **medium** `FORM-01` `person/permissions/edit.html.erb:45` forms: FORM-01: raw label "inline-flex items-center min-h-9 cursor-pointer font-medium text-heading" built by hand
- **low** `EMPTY-02` `person/permissions/edit.html.erb:59` empty-loading: EMPTY-02 says an empty value prints "—"; empty team/position cells print italic muted "None"

**`person/timesheets/edit.html.erb`** (GET /person/:person_id/timesheets/:id/edit)

- **medium** `EMPTY-01` `person/timesheets/edit.html.erb:131` toasts-alerts: EMPTY-01 says an empty state is always ui_empty_state; no desired changes shows as div "text-error font-semibold mb-3" red text
- **low** `EMPTY-02` `person/timesheets/edit.html.erb:19` empty-loading: EMPTY-02 says an empty value prints "—"; a missing verifier (19) and review status (57) print "-"
- **low** `FORM-02` `person/timesheets/edit.html.erb:165` forms: FORM-02 says every field has a visible label; the review_status collection_radio_buttons passes no label: (only the section title names it)
- **low** `MODAL-02` `person/timesheets/edit.html.erb:184` modals: MODAL-02 says ask with the action ("Delete this entry?"), not "Are you sure…"; the message reads "Are you certain you want to permanently delete this entry?"

**`person/timesheets/index.html.erb`** (GET /person/:person_id/timesheets)

- **medium** `HELP-02` `person/timesheets/index.html.erb:142` icons: HELP-02 puts a legend in one collapsed ui_disclosure :card; the ban-icon legend is a visible div "mb-2 text-body" above the table
- **medium** `TYPE-03` `person/timesheets/index.html.erb:124` typography: TYPE-03 bans text-sm on main content; the Credits / Appreciation Hours / Total hours rollup line is div "mb-3 text-sm" (text-base at 59-87 is on buttons)
- **low** `COPY-03` `person/timesheets/index.html.erb:11` other: COPY-03 asks for Title Case labels; the stat labels are all caps (ENTRIES, VERIFIED, UNVERIFIED, PENDING) where sibling stat rows use Title Case

**`person/swag/index.html.erb`** (GET /person/:person_id/swag)

- **medium** `BTN-04` `person/swag/index.html.erb:29` buttons: BTN-04 wants one primary action per view; seven :primary button_links (T-Shirt ... Other Swag) sit in a hand-made div "my-3 flex flex-wrap gap-2" role=group, not a button_row
- **low** `COLOR-06` `person/swag/index.html.erb:36` typography: COLOR-06 wants one neutral utility per purpose; the count is div "text-base-content/80" while other counts use me-muted
- **low** `EMPTY-02` `person/swag/index.html.erb:56` empty-loading: EMPTY-02 says an empty value prints "—"; missing year and notes print "-" (56, 58)

**`person/tickets_provisions/show.html.erb`** (GET /person/:person_id/tickets-provisions)

- **high** `STAT-01` `person/tickets_provisions/show.html.erb:21` other: STAT-01 says summary tiles are ui_stat_box in ui_stat_row; four hand-rolled "border rounded px-2 py-1" boxes with a font-semibold label sit in "flex justify-start gap-2" (no wrap)
- **low** `COPY-03` `person/tickets_provisions/show.html.erb:108` buttons: COPY-03 says button labels are Title Case; the toggle reads "Show current documents" / "Show all documents"

**`person/agreements/index.html.erb`** (GET /person/:person_id/agreements)

- **medium** `TYPE-03` `person/agreements/index.html.erb:31` typography: TYPE-03 bans text-sm for paragraph content; the Lifetime Agreements intro paragraph is p "text-sm"
- **low** `COLOR-06` `person/agreements/index.html.erb:31` typography: COLOR-06 wants one neutral utility per purpose (muted = text-stone-muted/me-muted); this section intro uses text-base-content/70, off the ladder

**`person/scheduling/log.html.erb`** (GET /person/:person_id/schedule/log)

- **medium** `CARD-03` `person/scheduling/log.html.erb:51` tables-lists: CARD-03 says related content is grouped in ui_section; the log table sits directly on the page while its empty state (96) is wrapped in ui_section, and sibling logs put tables in sections
- **low** `COLOR-06` `person/scheduling/log.html.erb:47` typography: COLOR-06 wants one neutral utility per purpose; sibling logs set their count line in me-muted, this one is p "my-3 text-body"

**`person/unified_flagging/show.html.erb`** (GET /person/:person_id/unified-flagging)

- **medium** `LIST-01` `person/unified_flagging/show.html.erb:93` other: LIST-01: instruction-list is for Q&A; Known Rangers / Known Fellow Applicants values are shown in one, drawing "Q:" before a field name and "A:" before its value
- **low** `EMPTY-02` `person/unified_flagging/show.html.erb:95` empty-loading: EMPTY-02 says an empty value prints "—"; empty Known Rangers / Applicants print "None" (95, 97)

**`person/vehicles/index.html.erb`** (GET /person/:person_id/vehicles)

- **medium** `BTN-04` `person/vehicles/index.html.erb:61` buttons: BTN-04 wants one primary action per view; four separate forms each end in a primary f.submit (61, 87, 114, 142)
- **low** `FORM-10` `person/vehicles/index.html.erb:35` spacing: FORM-10 divides a sub-group with "mt-4 pt-3 border-t border-line"; the MVR/PVR split is a raw <hr class="my-4 border-base-300">

**`person/missing_requests/edit.html.erb`** (GET /person/:person_id/timesheets/missing-requests/:id/edit)

- **low** `BTN-04` `person/missing_requests/edit.html.erb:136` buttons: BTN-04 wants one primary action per view; "Save Request" and "Save & Review Next" are both primary f.submit buttons in one row
- **low** `HERO-02` `person/missing_requests/edit.html.erb:4` other: HERO-02 wants a sentence saying what the page does; the description is the position title and shift time joined by a comma

**`person/pogs/index.html.erb`** (GET /person/:person_id/pogs)

- **low** `COLOR-06` `person/pogs/index.html.erb:20` typography: COLOR-06 wants one neutral utility per purpose (counts use me-muted/text-stone-muted elsewhere); the count is div "text-base-content/80", off the ladder
- **low** `HELP-02` `person/pogs/index.html.erb:9` typography: HELP-02 says a sentence on an operated page joins a fitting list, callout or section (or the card); the 2023-and-later scope note is a bare p "text-body mb-4" between hero and button

**`person/timesheets/backfill.html.erb`** (GET /person/:person_id/timesheets/backfill)

- **medium** `FORM-01` `person/timesheets/backfill.html.erb:24` forms: FORM-01: raw check_box_tag "years[]" with CHECKBOX_CLASSES + shrink-0 inside common/_checkbox_tile; the tile's span is the only label

**`person/timesheets/log.html.erb`** (GET /person/:person_id/timesheets/log)

- **medium** `EMPTY-01` `person/timesheets/log.html.erb:15` toasts-alerts: EMPTY-01 says an empty state is always ui_empty_state; a year before 2018 with no logs shows a ui_callout_box :warning instead

**`person/certifications/show.html.erb`** (GET /person/:person_id/certifications/:id)

- **low** `HERO-02` `person/certifications/show.html.erb:2` other: HERO-02 wants one sentence saying what the page does; the description is the fragment "Certification details."

**`person/intake_notes/new.html.erb`** (GET /person/:person_id/unified-flagging/notes/new)

- **low** `HELP-02` `person/intake_notes/new.html.erb:16` typography: HELP-02 says a consequence of the page's action stays visible as a callout beside the action; "Your note will be timestamped, and appended..." is a whole-bold p inside the section

**`person/mail_log/index.html.erb`** (GET /person/:person_id/mail-log)

- **low** `EMPTY-02` `person/mail_log/index.html.erb:53` links: EMPTY-02 says an empty value prints "—"; Changed By passes blank: "-" (hyphen)

**`person/missing_requests/show.html.erb`** (GET /person/:person_id/timesheets/missing-requests/:id)

- **low** `EMPTY-02` `person/missing_requests/show.html.erb:25` empty-loading: EMPTY-02 says an empty value prints "—"; a blank partner prints "-" (hyphen)

**`person/passkeys/index.html.erb`** (GET /person/:person_id/passkeys)

- **low** `COPY-04` `person/passkeys/index.html.erb:10` other: COPY-04 says getting rid of a record is "Delete"; the callout says "Remove its passkey here" and "Removing a passkey" while the button says Delete

**`person/sessions/index.html.erb`** (GET /person/:person_id/login-sessions)

- **low** `MODAL-02` `person/sessions/index.html.erb:52` modals: MODAL-02 says a confirm asks with the action ("Revoke your own session?"); the own-session message ends "...Continue?" (the other branch, "Revoke this login session?", follows the rule)

**`person/training/index.html.erb`** (GET /person/:person_id/training)

- **low** `MODAL-02` `person/training/index.html.erb:59` modals: MODAL-02 wants "<Verb> <thing>?"; Force Completion's confirm opens "Are you absolutely sure..." (the Generate Password one at 76 follows the rule); mechanism is the app modal via turbo_confirm

#### pogs (1)

**`pogs/administration/edit.html.erb`** (GET /pogs/administration/:id/edit)

- **low** `HERO-02` `pogs/administration/edit.html.erb:8` typography: Description says what the page does; this one states when and by whom the pog was issued.

#### profile (3)

**`profile/show.html.erb`** (GET /me/profile (me/profile#index), GET /person/:person_id/profile (person/profiles#show))

- **medium** `COLOR-03` `profile/show.html.erb:80` color: No coloured text for emphasis; "Pay special attention to" dt/dd set text-error inside a warning callout.
- **low** `SPACE-03` `profile/show.html.erb:80` typography: pattern=typography No classes on instruction-list dt/dd; <dt class="text-error">.

**`profile/camp_edit.html.erb`** (GET /me/profile/camp/edit, /person/:id/profile/camp/edit (profile#edit via ProfileSubjectConcern))

- **low** `SPACE-03` `profile/camp_edit.html.erb:21` typography: pattern=typography No classes on instruction-list <dt>/<dd>; <dd class="italic"> on the example format.

#### profile_languages (2)

**`profile_languages/index.html.erb`** (GET /me/profile/languages, /person/:id/profile/languages (me/languages#index, person/languages#index))

- **medium** `BTN-05` `profile_languages/index.html.erb:39` buttons: :error is the destructive variant; row Delete is a :secondary button_link (confirm uses variant :error).
- **low** `COPY-04` `profile_languages/index.html.erb:57` navigation: Leaving a page reads "Back to [Page]"; a list page with no form ends in cancel_link "Cancel" to the profile.

#### profile_photos (25)

**`profile_photos/new.html.erb`** (GET /me/profile/photos/new, /person/:id/photos/new (PhotoUploadConcern#new))

- **high** `BTN-01` `profile_photos/new.html.erb:292` buttons: Buttons from ButtonHelper; capture is a raw <button class="camera-capture-btn">, a round primary disc unlike any helper button. 87/98 are tabs (TABS-01).
- **high** `FORM-01` `profile_photos/new.html.erb:131` forms: Fields through AppFormBuilder; file field is a raw label dropzone (dashed border, bg-base-200, h-48) wrapping a hidden raw <input type=file>.
- **high** `FORM-01` `profile_photos/new.html.erb:150` forms: Raw hidden <input type=file> instead of a builder field.
- **high** `FORM-01` `profile_photos/new.html.erb:269` forms: Fields via builder; camera picker is raw <label> + <select class="camera-select"> (custom @utility: rounded-lg border p-2), unlike builder selects.
- **medium** `ALERT-01` `profile_photos/new.html.erb:161` toasts-alerts: Inline notices are ui_callout_box; selected-file notice is a hand-made "rounded-lg border border-success/30 bg-success/10 p-3 text-success" box.
- **medium** `CARD-01` `profile_photos/new.html.erb:24` cards: Cards render through ui_card; Photo Requirements is a hand-made "mb-4 card-standard p-4" div with a raw h2.
- **medium** `TABS-01` `profile_photos/new.html.erb:86` navigation: Rule: tabs from tab_navigation. Code: raw <button class="tab"> pair with ARIA tablist driven by camera controller.
- **medium** `TABS-01` `profile_photos/new.html.erb:90` navigation: pattern=navigation role="tab" on a hand-written tab button.
- **medium** `TABS-01` `profile_photos/new.html.erb:98` navigation: pattern=navigation Second raw <button class="tab">; hand-written tab.
- **medium** `TYPE-03` `profile_photos/new.html.erb:300` typography: text-sm barred for paragraphs/labels; file info (175-178), callout instructions (224, 229), camera label (266) and capture hint (300) are text-sm; file size (177) is text-xs.
- **low** `TYPE-04` `profile_photos/new.html.erb:138` typography: Nothing in a section outweighs its title; "Click to upload" line is text-lg with font-semibold in the Photo Upload section (title text-base below lg).

**`profile_photos/crop.html.erb`** (GET /me/profile/photos/:id/crop, /person/:id/photos/:id/crop, /vc/photos-review/:id/crop (PhotoUploadConcern#crop))

- **medium** `BP-01` `profile_photos/crop.html.erb:139` spacing: pattern=spacing sm: only in a field width:; button_row class uses sm:flex-row and sm:justify-between, a stacking tier.
- **medium** `CARD-01` `profile_photos/crop.html.erb:27` cards: Cards are card-standard rendered by ui_card; desktop Quick Guide is a hand-made div.card-standard p-4 with its own h2.
- **medium** `COLOR-01` `profile_photos/crop.html.erb:95` color: Semantic tokens only; bg-gray-800/bg-gray-500 classes and literal #ffffff/#fbbf24/#f59e0b checkerboard (202). Guide records no exception.
- **medium** `COLOR-01` `profile_photos/crop.html.erb:202` color: Semantic tokens only; checkerboard uses literal #ffffff, #fbbf24, #f59e0b.
- **medium** `COLOR-02` `profile_photos/crop.html.erb:21` color: Colour carries meaning, never decoration; "fills the outline completely" gets a bg-primary/10 highlight for emphasis.
- **medium** `FORM-01` `profile_photos/crop.html.erb:62` forms: Raw form_with without builder: AppFormBuilder; holds only buttons and the cropper, so it renders like a builder form.
- **medium** `HELP-02` `profile_photos/crop.html.erb:27` cards: A how-to or legend goes in one collapsed ui_disclosure variant :card; crop's Quick Guide (task how-to plus button legend) is an always-open card from lg up.
- **medium** `STYLE-01` `profile_photos/crop.html.erb:161` other: No scoped/per-view CSS; page carries an 80-line <style> block (wrapper, zoom, cropper elements) with !important at 216, 217, 222, 232.
- **medium** `TYPE-03` `profile_photos/crop.html.erb:38` typography: text-sm barred for paragraphs and instructions; button legend list (38), review reminder (52) and mobile tip (134) are text-sm.
- **medium** `TYPE-03` `profile_photos/crop.html.erb:134` typography: text-sm barred for instructions; mobile tip "No orange checkerboard…" is text-sm centred.
- **low** `COLOR-05` `profile_photos/crop.html.erb:29` icons: Icons are neutral unless they convey status; Quick Guide lightbulb is text-primary.
- **low** `COPY-04` `profile_photos/crop.html.erb:152` buttons: pattern=buttons Never "Submit" as a submit label; button reads "Submit Photo".
- **low** `STYLE-01` `profile_photos/crop.html.erb:98` other: pattern=other No inline style=; cropper-canvas style holds computed width/height from PersonPhoto constants.
- **low** `TOUCH-02` `profile_photos/crop.html.erb:86` buttons: Icon-only ButtonHelper buttons take btn-square; crop tools are icon-only below lg without btn-square (aria-label/title set).

#### quartermaster (4)

**`quartermaster/alpha_shirts/index.html.erb`** (GET /quartermaster/alpha-shirts)

- **medium** `TYPE-03` `quartermaster/alpha_shirts/index.html.erb:124` typography: text-sm never for table content; the roster's email line is text-sm.
- **low** `EMPTY-01` `quartermaster/alpha_shirts/index.html.erb:53` empty-loading: An empty state is always ui_empty_state; an empty size run prints a plain text-body p.

**`quartermaster/swag/index.html.erb`** (GET /quartermaster/swag)

- **high** `LAYOUT-03` `quartermaster/swag/index.html.erb:7` other: Level 1 counts are one text-lg line, not stat boxes; Swag level 1 shows a ui_stat_row Items box and no count line, unlike Asset Inventory and Freaking Years.

**`quartermaster/swag/new.html.erb`** (GET /quartermaster/swag/new)

- **low** `COPY-04` `quartermaster/swag/new.html.erb:4` typography: The create form is named Add X, never New X; hero title reads New Swag.

#### scheduling (35)

**`scheduling/shift_lead/print_sheet.html.erb`** (GET /scheduling/shift-lead/print)

- **medium** `TABLE-01` `scheduling/shift_lead/print_sheet.html.erb:109` tables-lists: Raw <table> elements instead of ui_table on the print sheet (109, 171).
- **medium** `TABLE-01` `scheduling/shift_lead/print_sheet.html.erb:171` tables-lists: Data tables are ui_table; raw tables with colgroup sheet-col-* and sheet-num cells.
- **low** `BADGE-01` `scheduling/shift_lead/print_sheet.html.erb:215` other: Badges come from ui_badge; print chips are span.sheet-chip / sheet-chip-solid and span.sheet-none.
- **low** `COLOR-01` `scheduling/shift_lead/print_sheet.html.erb:41` color: Semantic tokens only; page-footer margin boxes use literal color #444 (41, 47).
- **low** `COPY-03` `scheduling/shift_lead/print_sheet.html.erb:103` typography: Headings are Title Case; bands "Below minimum staffing" (103, 106), all-caps roster titles (151-153), "Decoder ring" (252), column headings "On duty"/"Signed up"/"Start" (118, 147).
- **low** `EMPTY-01` `scheduling/shift_lead/print_sheet.html.erb:104` empty-loading: Empty states always use ui_empty_state; print sheet uses plain <p> for fully staffed and empty rosters (104, 163-169).
- **low** `EMPTY-02` `scheduling/shift_lead/print_sheet.html.erb:221` typography: An empty value prints "—"; print roster prints "-" for missing pronouns, gender and positions (221, 222, 227).
- **low** `STYLE-01` `scheduling/shift_lead/print_sheet.html.erb:34` other: No per-view CSS; an inline <style> named @page rule with literal font-size, colour and font family is emitted from the view.

**`scheduling/slot_copies/new.html.erb`** (GET /scheduling/slots/copy)

- **medium** `FORM-06` `scheduling/slot_copies/new.html.erb:54` validation: Errors show through ui_form's summary; copy failures arrive as flash.now[:error] (slot_copies_controller.rb:31).
- **low** `COPY-08` `scheduling/slot_copies/new.html.erb:44` typography: pattern=typography Never strftime in a view; option labels formatted inline.
- **low** `COPY-08` `scheduling/slot_copies/new.html.erb:124` typography: pattern=typography Never strftime in a view; adjusted begins formatted inline.
- **low** `COPY-08` `scheduling/slot_copies/new.html.erb:130` typography: pattern=typography Never strftime in a view; adjusted ends formatted inline.
- **low** `ICON-01` `scheduling/slot_copies/new.html.erb:124` icons: Icons come from fa_icon; &rarr; glyph marks the shifted times (124, 130).

**`scheduling/position_credit_copies/new.html.erb`** (GET /scheduling/position-credits/copy)

- **medium** `FORM-06` `scheduling/position_credit_copies/new.html.erb:27` validation: Errors show through the builder and ui_form's summary; copy failures arrive as flash.now[:error] toasts (position_credit_copies_controller.rb:28).
- **low** `COPY-08` `scheduling/position_credit_copies/new.html.erb:83` typography: pattern=typography Never strftime in a view; adjusted start time formatted inline.
- **low** `COPY-08` `scheduling/position_credit_copies/new.html.erb:89` typography: pattern=typography Never strftime in a view; adjusted end time formatted inline.
- **low** `ICON-01` `scheduling/position_credit_copies/new.html.erb:83` icons: Icons come from fa_icon; &rarr; glyphs used as arrow markers (lines 83, 89).

**`scheduling/event_stats/index.html.erb`** (GET /scheduling/event-stats)

- **medium** `STAT-01` `scheduling/event_stats/index.html.erb:102` cards: Summary tiles go in ui_stat_row, never a hand-rolled grid; paired tiles sit in grid grid-cols-2 gap-2 (lines 102, 137).
- **low** `EMPTY-02` `scheduling/event_stats/index.html.erb:101` typography: An empty value prints "—"; the Still Marked On Site tile prints "n/a".

**`scheduling/sandman_qualified/index.html.erb`** (GET /scheduling/sandman-qualified)

- **high** `STAT-01` `scheduling/sandman_qualified/index.html.erb:33` cards: Summary tiles go in ui_stat_row, never a hand-rolled grid; scoreboard is grid grid-cols-2 lg:grid-cols-N gap-2 lg:gap-3 of linked tiles.

**`scheduling/slot_bulk_edits/new.html.erb`** (GET /scheduling/slots/position/:position_id/bulk-edit)

- **medium** `FORM-06` `scheduling/slot_bulk_edits/new.html.erb:51` validation: Errors show through ui_form's summary; bulk-edit validation failures are flash.now[:error] toasts (slot_bulk_edits_controller.rb:23,28,35).
- **low** `COPY-08` `scheduling/slot_bulk_edits/new.html.erb:40` typography: pattern=typography Never strftime in a view; option labels formatted with strftime(MONTH_DAY_TIME).

**`scheduling/slots/position.html.erb`** (GET /scheduling/slots/position/:position_id)

- **high** `TYPE-02` `scheduling/slots/position.html.erb:116` typography: text-xs never for text a reader needs; the "+24h" that tells the two Repeat buttons apart is text-xs.

**`scheduling/early_arrivals/index.html.erb`** (GET /scheduling/early-arrivals)

- **medium** `TYPE-03` `scheduling/early_arrivals/index.html.erb:190` typography: text-sm is never for table content; shift time and description in the cell are text-sm.

**`scheduling/position_credits/timeline.html.erb`** (GET /scheduling/position-credits/position/:position_id/timeline)

- **medium** `HELP-02` `scheduling/position_credits/timeline.html.erb:22` typography: On a report, how-tos go in the collapsed card; the timeline keeps a visible how-to paragraph ("Hover a step...") in the section body (22-25).

**`scheduling/schedule_by_callsign/person.html.erb`** (GET /scheduling/schedule-by-callsign/person/:person_id)

- **medium** `COLOR-02` `scheduling/schedule_by_callsign/person.html.erb:25` color: Colour carries meaning only; the neutral Positions count is painted :success with no status behind it.

**`scheduling/schedule_by_position/position.html.erb`** (GET /scheduling/schedule-by-position/position/:position_id)

- **medium** `TYPE-03` `scheduling/schedule_by_position/position.html.erb:58` typography: text-sm never for table content; description line in the row header is text-sm text-stone-subtle.

**`scheduling/slots/new.html.erb`** (GET /scheduling/slots/new)

- **low** `COPY-04` `scheduling/slots/new.html.erb:4` typography: The create form is "Add [Entity]", never "Create"; the hero title reads "Create Slot for <year>".
- **low** `HERO-02` `scheduling/slots/new.html.erb:2` typography: Description is one sentence saying what the page does; it states a caveat ("The slot's year is set by its start time...") instead.

**`scheduling/hq_forecast/people.html.erb`** (GET /scheduling/hq-forecast/people (opened into turbo-frame "modal" from a staffing count))

- **low** `COPY-08` `scheduling/hq_forecast/people.html.erb:2` typography: pattern=typography Never strftime in a view; dialog title formats @period with strftime(MONTH_DAY_TIME).

**`scheduling/position_credits/edit.html.erb`** (GET /scheduling/position-credits/:id/edit)

- **low** `HERO-02` `scheduling/position_credits/edit.html.erb:2` typography: Description is one sentence saying what the page does; it is the fragment "<position> - <description>".

**`scheduling/position_credits/new.html.erb`** (GET /scheduling/position-credits/new)

- **low** `COPY-04` `scheduling/position_credits/new.html.erb:4` typography: The create form is "Add [Entity]", never "Create"; the hero title reads "Create Position Credit for <year>".

**`scheduling/position_credits/position.html.erb`** (GET /scheduling/position-credits/position/:position_id)

- **low** `COPY-08` `scheduling/position_credits/position.html.erb:89` typography: Never strftime in a view; From/To cells call strftime with DateTimeHelper constants (89-90).

**`scheduling/shift_lead/index.html.erb`** (GET /scheduling/shift-lead)

- **low** `COPY-03` `scheduling/shift_lead/index.html.erb:47` typography: Section titles are Title Case; roster ui_section titles are all caps "DIRT / GREEN DOTS", "COMMAND STAFF", "SPECIAL TEAMS" (47-51).

**`scheduling/slots/edit.html.erb`** (GET /scheduling/slots/:id/edit)

- **low** `HERO-02` `scheduling/slots/edit.html.erb:2` typography: Description is one sentence saying what the page does; it is the fragment "<position> - <description>".

#### sessions (9)

**`sessions/forgot.html.erb`** (GET /forgot (sessions#forgot), POST /reset-password re-render)

- **medium** `BTN-05` `sessions/forgot.html.erb:34` buttons: Primary action takes :primary; "Send Reset Link" is submit_button :warning lg.
- **low** `COLOR-05` `sessions/forgot.html.erb:24` icons: Icons are neutral unless status; envelope field icon is text-warning.
- **low** `FORM-07` `sessions/forgot.html.erb:14` forms: Email field should be w-full sm:w-72; it takes the full column width (login-input, no width:).

**`sessions/reset_token.html.erb`** (GET /reset-token (sessions#reset_token))

- **medium** `BTN-05` `sessions/reset_token.html.erb:64` buttons: Primary action takes :primary; "Set Password"/"Reset Password" is submit_button :warning lg.
- **low** `COLOR-05` `sessions/reset_token.html.erb:40` icons: Icons are neutral unless status; key field icons are text-warning (40, 57).
- **low** `FORM-07` `sessions/reset_token.html.erb:29` forms: Field widths fit content (short text w-full sm:w-64); password fields at 29 and 47 fill the column.

**`sessions/new.html.erb`** (GET / (sessions#new))

- **low** `COLOR-05` `sessions/new.html.erb:18` icons: Icons are neutral unless status; the days-to-burn flame is text-warning (decorative).
- **low** `COPY-03` `sessions/new.html.erb:45` typography: A heading is a label, not a question; h2 and nav label read "Audit Training? Want to be a Ranger?".
- **low** `TYPE-04` `sessions/new.html.erb:45` typography: <h2> takes heading-section; "Audit Training? Want to be a Ranger?" is h2.login-doors-title styled in login.css.

#### shift_operations (21)

**`shift_operations/payroll_export/index.html.erb`** (GET /shift-operations/payroll-export)

- **medium** `BTN-04` `shift_operations/payroll_export/index.html.erb:157` buttons: One clear primary per view; "Run Report" (80, default primary) and "Export payroll with meal breaks" (157, style: :primary) are both primary on the same page.
- **medium** `CARD-01` `shift_operations/payroll_export/index.html.erb:168` cards: Card containers are card-standard via ui_card; grand total is a hand-made div with bg-base-100, border-line, rounded-base and padding.
- **medium** `FORM-01` `shift_operations/payroll_export/index.html.erb:141` forms: Forms use AppFormBuilder and table filters use filter_bar; person filter is form_tag with raw <label> and select_tag (SELECT_CLASSES), auto-submitting.
- **medium** `FORM-01` `shift_operations/payroll_export/index.html.erb:146` forms: select_tag in place of f.select.
- **low** `COPY-03` `shift_operations/payroll_export/index.html.erb:125` typography: Button labels and headings are Title Case; export labels "Export payroll with meal breaks", "Export unadjusted payroll", "Export this table" (125-127), "Export these without IDs" (116) and fieldset "Positions to export" (44) are sentence case.
- **low** `FORM-04` `shift_operations/payroll_export/index.html.erb:75` typography: Help text is a field's help_text:; this note is a standalone muted <p> between fieldset and submit.

**`shift_operations/cruise_direction/people/edit.html.erb`** (GET /shift-operations/cruise-direction/pods/:pod_id/people/:person_id/edit)

- **medium** `FORM-01` `shift_operations/cruise_direction/people/edit.html.erb:19` forms: Fields come from the builder; inside a builder form the Pod field is raw <label>, select_tag with SELECT_CLASSES, and a hand-made help <p>.
- **low** `BP-01` `shift_operations/cruise_direction/people/edit.html.erb:21` spacing: pattern=spacing sm: belongs in a field's width: option; here sm:w-44 rides the class: of a raw select_tag (a field width, outside the builder).
- **low** `COPY-03` `shift_operations/cruise_direction/people/edit.html.erb:38` buttons: Button labels are Title Case; the button reads "Take out of Pod N".
- **low** `COPY-04` `shift_operations/cruise_direction/people/edit.html.erb:38` buttons: "Remove from X" takes out of a group; the button reads "Take out of Pod N".
- **low** `FORM-10` `shift_operations/cruise_direction/people/edit.html.erb:35` spacing: Sub-section divider is mt-4 pt-3 border-t border-line; this uses border-base-300.

**`shift_operations/bulk_sign_in_out/preview.html.erb`** (POST /shift-operations/bulk-sign-in-out/preview (422))

- **low** `COPY-03` `shift_operations/bulk_sign_in_out/preview.html.erb:141` modals: Button labels are Title Case; confirm labels "Create it"/"Create them" (141) and the submit "Create N timesheet entries" (135) are not.
- **low** `COPY-04` `shift_operations/bulk_sign_in_out/preview.html.erb:135` buttons: pattern=buttons Rule bans "Create" as a verb; submit reads "Create N timesheet entries" and confirm labels "Create it"/"Create them" (141).
- **low** `MODAL-02` `shift_operations/bulk_sign_in_out/preview.html.erb:138` modals: Rule: ask with the action and say whether it can be undone; title "Final Confirmation" and a statement message, no question, no undo sentence.

**`shift_operations/rollcall/sign_in.html.erb`** (GET /shift-operations/rollcall/sign-in)

- **medium** `MODAL-01` `shift_operations/rollcall/sign_in.html.erb:80` modals: Modals open through the modal Stimulus controller; this one is rendered on a full page load when ?set_time=1 is present.
- **low** `HELP-02` `shift_operations/rollcall/sign_in.html.erb:64` cards: The card goes above the form (directly under the hero with no stat row); here it sits below the Shift picker section, just above the roster.

**`shift_operations/bulk_sign_in_out/index.html.erb`** (GET /shift-operations/bulk-sign-in-out)

- **medium** `HELP-02` `shift_operations/bulk_sign_in_out/index.html.erb:37` other: Reference/how-to belongs in a collapsed ui_disclosure variant: :card; the line-format reference uses the default inline disclosure inside the form.

**`shift_operations/cruise_direction/unavailable.html.erb`** (rendered by ShiftOperations::CruiseDirection::BaseController#render_refusal (turbo-frame GET, 422))

- **medium** `TYPE-03` `shift_operations/cruise_direction/unavailable.html.erb:11` typography: text-sm never for paragraphs; the second explanatory paragraph is text-sm.

**`shift_operations/cruise_direction/pods/new.html.erb`** (GET /shift-operations/cruise-direction/pods/new)

- **low** `COPY-04` `shift_operations/cruise_direction/pods/new.html.erb:5` modals: "Add X" opens a create form and "Create" is never used; the add-pod dialog is titled "Create a Pod" while its opener reads "Add Pod".

**`shift_operations/mass_signout/index.html.erb`** (GET /shift-operations/mass-signout)

- **low** `MODAL-02` `shift_operations/mass_signout/index.html.erb:122` buttons: Rule: ask with the action and say whether it can be undone; title "Confirm Mass Sign-Out", statement message, no undo sentence.

**`shift_operations/rollcall/sign_out.html.erb`** (GET /shift-operations/rollcall/sign-out)

- **low** `HELP-02` `shift_operations/rollcall/sign_out.html.erb:38` cards: The card goes directly under the hero when there is no stat row; here it sits below the Position picker section.

#### sso (1)

**`sso/hand_back.html.erb`** (rendered by sso#authorize/callback (sso_controller.rb:38))

- **medium** `BTN-05` `sso/hand_back.html.erb:18` buttons: Primary action takes :primary; "Continue to <client>" is :warning lg.

#### teams_positions (25)

**`teams_positions/roster_management/preview.html.erb`** (POST /teams-positions/roster-management/:team_id/preview (rendered at 422))

- **high** `ALERT-01` `teams_positions/roster_management/preview.html.erb:21` icons: Rule lists callout variants success/info/warning/error/secondary; roster_action_variant passes :primary for a grant, which the helper renders as a plain untinted box with a warning triangle.
- **medium** `MODAL-02` `teams_positions/roster_management/preview.html.erb:80` modals: Rule says ask with the action, state undo, red when destructive; title "Final Confirmation", no undo sentence, no variant: :error though revoke and remove are destructive.
- **medium** `TYPE-03` `teams_positions/roster_management/preview.html.erb:47` color: Rule says text-sm never for table content; the cell's second line "and their X membership" (what the person loses) is text-sm muted.

**`teams_positions/roster_management/show.html.erb`** (GET /teams-positions/roster-management/:team_id)

- **medium** `HELP-02` `teams_positions/roster_management/show.html.erb:71` other: Rule says a legend goes in one collapsed card (samples in the dd); the grid legend with sample NS badges is a visible info callout in the body.
- **medium** `TYPE-03` `teams_positions/roster_management/show.html.erb:149` typography: Rule says text-sm never for table content; the status under each callsign in the grid is text-sm (line 25 card eyebrow is metadata and fine).
- **low** `HELP-02` `teams_positions/roster_management/show.html.erb:93` typography: Rule says a rule goes in the page's one collapsed card or joins a fitting list or callout; who the roster lists stands as a loose p.my-3 paragraph (line 18 is a figure caption, fine).

**`teams_positions/bulk_positions/preview.html.erb`** (POST /teams-positions/bulk-positions/preview (rendered at 422))

- **medium** `HERO-04` `teams_positions/bulk_positions/preview.html.erb:110` navigation: Rule says back navigation lives in the hero panel; preview has no back_to and returns via an f.submit "Go Back and Edit" with formaction (needed to re-post the list).
- **medium** `MODAL-02` `teams_positions/bulk_positions/preview.html.erb:100` modals: Rule says a confirm asks with the action, states undo, and is red when destructive; dialog titled "Final Confirmation", no undo sentence, no variant: :error even on revoke.

**`teams_positions/bulk_teams/preview.html.erb`** (POST /teams-positions/bulk-teams/preview (rendered at 422))

- **medium** `HERO-04` `teams_positions/bulk_teams/preview.html.erb:119` navigation: Rule says back navigation lives in the hero; no back_to here, back is an f.submit formaction "Go Back and Edit".
- **medium** `MODAL-02` `teams_positions/bulk_teams/preview.html.erb:109` modals: Rule says ask with the action, state undo, red when destructive; title "Final Confirmation", no undo sentence, no variant: :error on a revoke.

**`teams_positions/position_lineups/index.html.erb`** (GET /teams-positions/position-lineups)

- **medium** `STYLE-03` `teams_positions/position_lineups/index.html.erb:38` tables-lists: Rule says use the helper where one exists; positions cell is a hand-built div.flex-col of divs while sibling record tables use value_list for multi-value cells.
- **low** `EMPTY-02` `teams_positions/position_lineups/index.html.erb:49` color: Rule says an empty value prints "—"; an empty positions cell shows italic muted "No positions linked yet" (line 43 "(inactive)" is a status note, not a blank).
- **low** `HELP-02` `teams_positions/position_lineups/index.html.erb:6` toasts-alerts: Rule says a how-to goes in one collapsed card per page; how lineups drive the Sign-Ups button is a visible info callout above the list.

**`teams_positions/position_sanity_checker/check.html.erb`** (GET /teams-positions/position-sanity-checker/:check)

- **medium** `TYPE-05` `teams_positions/position_sanity_checker/check.html.erb:28` typography: Rule says clear heading hierarchy; the page-level truncation callout title "Showing the First N" renders as h4 directly under the h1.
- **low** `HERO-04` `teams_positions/position_sanity_checker/check.html.erb:67` navigation: Rule says back navigation lives in the hero panel; besides hero back_to the page adds a second "Back to the Board" button_link in the form's button row.

**`teams_positions/position_sanity_checker/index.html.erb`** (GET /teams-positions/position-sanity-checker)

- **medium** `CARD-03` `teams_positions/position_sanity_checker/index.html.erb:52` typography: Rule says related content is grouped in ui_section; each band is a raw <section> with a hand-built border-b title bar and h2, imitating ui_section.
- **low** `LAYOUT-03` `teams_positions/position_sanity_checker/index.html.erb:19` cards: Rule says level-1 counts are plain text, not stat boxes; the board opens with a ui_stat_row of totals and no text-lg line.

**`teams_positions/membership_report/index.html.erb`** (GET /teams-positions/membership-report)

- **medium** `LAYOUT-03` `teams_positions/membership_report/index.html.erb:28` navigation: Rule says level 1 gets no filter bar and one text-lg count line; the team index uses a filter_bar and puts the summary in its count slot.

**`teams_positions/position_grants/index.html.erb`** (GET /teams-positions/position-grants)

- **medium** `LAYOUT-03` `teams_positions/position_grants/index.html.erb:26` navigation: Rule says level 1 gets no filter bar and one text-lg count line; the position index uses a filter_bar with the summary in its count slot.

**`teams_positions/special_teams_hours/index.html.erb`** (GET /teams-positions/special-teams-hours)

- **medium** `TYPE-05` `teams_positions/special_teams_hours/index.html.erb:109` toasts-alerts: Rule says clear heading hierarchy; the page-level truncation callout title renders as h4 directly under the h1.

**`teams_positions/bulk_positions/index.html.erb`** (GET /teams-positions/bulk-positions)

- **low** `HELP-02` `teams_positions/bulk_positions/index.html.erb:54` typography: Rule says a consequence of the page's action stays visible as a callout beside the action; "Checking is always safe" is a plain p.mb-3 with a strong lead above the submit.

**`teams_positions/bulk_teams/index.html.erb`** (GET /teams-positions/bulk-teams)

- **low** `HELP-02` `teams_positions/bulk_teams/index.html.erb:62` typography: Rule says an action's consequence stays visible as a callout beside the action; "Checking is always safe." is a plain p.mb-3 above the submit.

**`teams_positions/position_grants/show.html.erb`** (GET /teams-positions/position-grants/:position_id)

- **low** `LAYOUT-03` `teams_positions/position_grants/show.html.erb:18` cards: Rule says level-2 totals describe the category, not the filtered view; the first stat box "Shown" counts the filtered roster.

**`teams_positions/position_records/index.html.erb`** (GET /teams-positions/position-records)

- **low** `EMPTY-02` `teams_positions/position_records/index.html.erb:97` color: Rule says an empty value prints "—"; the Team cell shows italic muted "No team".

**`teams_positions/team_records/index.html.erb`** (GET /teams-positions/team-records)

- **low** `EMPTY-02` `teams_positions/team_records/index.html.erb:97` color: Rule says an empty value prints "—"; missing email and document tag show italic muted "No email" / "No document tag" (101).

#### ticketing (11)

**`ticketing/trs_export/index.html.erb`** (GET /ticketing/trs-export)

- **medium** `BTN-04` `ticketing/trs_export/index.html.erb:78` buttons: Rule: one clear primary action per view. Code: filter_bar "Apply Filters" (78) and "Export Selected Items" (100) both render primary.
- **medium** `STYLE-03` `ticketing/trs_export/index.html.erb:89` forms: Rule: use the helper where one exists. Code: raw div data-controller="checkbox-select-all" instead of bulk_select, which the export page and siblings use.
- **low** `MODAL-02` `ticketing/trs_export/index.html.erb:102` modals: Rule: confirm says whether it can be undone. Code: export and mark-submitted confirms (102, 110) state the action but not whether it can be undone.

**`ticketing/trs_export/export.html.erb`** (POST /ticketing/trs-export/export)

- **medium** `BTN-04` `ticketing/trs_export/export.html.erb:33` buttons: Rule: one clear primary action per view. Code: the primary Download export_csv_link (33) and the default-primary "Mark Selected as Submitted" submit (53).
- **low** `MODAL-02` `ticketing/trs_export/export.html.erb:55` modals: Rule: confirm says whether it can be undone. Code: mark-submitted confirm gives a precondition but no undo statement.

**`ticketing/unsubmit_provisions/index.html.erb`** (GET /ticketing/unsubmit-provisions)

- **medium** `MODAL-02` `ticketing/unsubmit_provisions/index.html.erb:92` buttons: Rule: a destructive confirm is red (confirm_modal variant: :error). Code: error-variant submit opens confirm_modal_dialog with no variant, so its confirm button is primary blue.
- **low** `COPY-03` `ticketing/unsubmit_provisions/index.html.erb:55` typography: Rule: a heading is a label, not a question. Code: table column heading "#{@year} Sign-Ups?" ends in a question mark.

**`ticketing/maintenance/index.html.erb`** (GET /ticketing/maintenance)

- **medium** `BTN-04` `ticketing/maintenance/index.html.erb:45` buttons: Rule: one clear primary action per view. Code: every task card footer carries a full-width primary button_link, so the launcher shows many primaries.

**`ticketing/maintenance/preview.html.erb`** (GET /ticketing/maintenance/:task (also re-rendered at 422 by ticketing/maintenance#commit))

- **medium** `FORM-06` `ticketing/maintenance/preview.html.erb:49` validation: Rule: errors show through the builder (input-error, message under the field). Code: hand-built red p role=alert above f.text_area; the field itself is not flagged.

**`ticketing/statistics/index.html.erb`** (GET /ticketing/statistics)

- **medium** `STAT-01` `ticketing/statistics/index.html.erb:67` other: Rule: stat tiles live in ui_stat_row; a grid of stat boxes needs approval. Code: hand grids "grid grid-cols-3" (67) and "grid grid-cols-2 lg:grid-cols-4" (78) of ui_stat_box.

**`ticketing/expiring/index.html.erb`** (GET /ticketing/expiring)

- **low** `COPY-03` `ticketing/expiring/index.html.erb:52` buttons: Rule: button labels are Title Case. Code: clipboard_button reads "Copy N email addresses".

#### timesheets (11)

**`timesheets/on_duty/index.html.erb`** (GET /timesheets/on-duty)

- **medium** `BP-01` `timesheets/on_duty/index.html.erb:134` spacing: lg: is the structural fold; grid uses md:grid-cols-2 xl:grid-cols-3, adding an md tier.
- **medium** `STYLE-03` `timesheets/on_duty/index.html.erb:137` cards: Use the helper where one exists (ui_card_title); card header is a hand-built border-b px-4 py-3 bar with its own h2.

**`timesheets/sanity_checker/index.html.erb`** (GET /timesheets/sanity-checker)

- **medium** `CARD-03` `timesheets/sanity_checker/index.html.erb:55` typography: Related content is grouped in ui_section; band groups are hand-built <section> + border-b div + h2 (plus a text-sm subline).
- **medium** `TYPE-03` `timesheets/sanity_checker/index.html.erb:72` typography: text-sm not for content the reader needs; "Open to check — counted when you look" note is text-sm (86 is a count caption).

**`timesheets/timesheet_slot_repair/index.html.erb`** (GET /timesheets/timesheet-slot-repair (also re-rendered after POST apply with @results))

- **medium** `HERO-04` `timesheets/timesheet_slot_repair/index.html.erb:67` navigation: Back navigation lives in the hero panel; "Back to Timesheets" is a button_link in the form's button_row.
- **medium** `MODAL-02` `timesheets/timesheet_slot_repair/index.html.erb:65` modals: A destructive confirm is red; this one says it "cannot be undone" yet confirm_modal_dialog has no variant: :error.

**`timesheets/correction_stats/index.html.erb`** (GET /timesheets/correction-stats)

- **medium** `COLOR-02` `timesheets/correction_stats/index.html.erb:30` other: Colour carries meaning, never decoration; "Entries Deleted" is amber "not because it is bad" (comment 27-29), i.e. for emphasis.

**`timesheets/hours_credits/index.html.erb`** (GET /timesheets/hours-credits)

- **medium** `TABLE-01` `timesheets/hours_credits/index.html.erb:112` tables-lists: Data tables are ui_table built through its helpers; the thead and colgroup <th>s are hand-written with TableHelper constants.

**`timesheets/timesheet_unconfirmed/index.html.erb`** (GET /timesheets/timesheet-unconfirmed)

- **medium** `COLOR-04` `timesheets/timesheet_unconfirmed/index.html.erb:30` color: Primary is for primary actions and key elements; "One Click Away" stat tile is :primary, a non-status count coloured blue.

**`timesheets/forced_shift_start/index.html.erb`** (GET /timesheets/forced-shift-start)

- **low** `COPY-03` `timesheets/forced_shift_start/index.html.erb:76` other: Section titles are Title Case; ui_section title reads "N forced starts in YEAR".

**`timesheets/sanity_checker/check.html.erb`** (GET /timesheets/sanity-checker/:check)

- **low** `HELP-02` `timesheets/sanity_checker/check.html.erb:43` cards: With no stat row the card sits directly under the hero; here it follows the count badge and export toolbar (34-37).

#### training (26)

**`training/sessions/trainers_report.html.erb`** (GET /training/:slug/session/:slot_id/trainers-report)

- **medium** `ALERT-01` `training/sessions/trainers_report.html.erb:79` toasts-alerts: Rule: inline notices are ui_callout_box. The full-day notice is a custom div.report-callout with a <b> lead.
- **medium** `BADGE-01` `training/sessions/trainers_report.html.erb:123` other: Rule: badges come from ui_badge. Print pills are custom spans (report-years-pill, report-new "NEW", report-full-day, report-chip, report-status).
- **medium** `STAT-01` `training/sessions/trainers_report.html.erb:55` other: Rule: summary tiles are ui_stat_box in ui_stat_row. Print tiles are hand-built div.report-stat with <b> numbers and label spans.
- **medium** `STYLE-01` `training/sessions/trainers_report.html.erb:17` other: Rule: no per-view CSS. Inline <style> @page rule with escaped footer text, font size, #444 and font family; near-copy of the sign-up sheet's.
- **medium** `TABLE-01` `training/sessions/trainers_report.html.erb:90` tables-lists: Rule: data tables are ui_table. Raw table banded by tbody.report-band-body with rowspan number and pass cells.
- **low** `COLOR-01` `training/sessions/trainers_report.html.erb:22` color: Rule: semantic colour tokens only. Footer colour literal #444 at 22 and 28.
- **low** `COPY-03` `training/sessions/trainers_report.html.erb:55` typography: Rule: headings and scanned labels are Title Case. Print labels read "Signed up" (55), "Inact/Retired" (59) and the legend title "Teams legend" (160).
- **low** `EMPTY-01` `training/sessions/trainers_report.html.erb:70` empty-loading: Rule: empty states use ui_empty_state. Empty groups print italic "No trainers signed up." and "None signed up." (84).
- **low** `EMPTY-01` `training/sessions/trainers_report.html.erb:111` empty-loading: Rule: empty states use ui_empty_state. An empty band prints a tr.report-empty-row "None signed up.".
- **low** `ICON-01` `training/sessions/trainers_report.html.erb:94` icons: Rule: icons come from fa_icon. The pass column header is a bare "✔︎" glyph with no text alternative beyond the character.

**`training/sessions/signup_sheet.html.erb`** (GET /training/:slug/session/:slot_id/signup-sheet)

- **medium** `STYLE-01` `training/sessions/signup_sheet.html.erb:22` other: Rule: no scoped or per-view CSS. A <style> @page rule with font size, colour and font family is emitted per view via content_for :page_rules.
- **medium** `TABLE-01` `training/sessions/signup_sheet.html.erb:52` tables-lists: Rule: data tables are ui_table. Raw table, tbody per trainee, rowspan number cell and sr-only "Row" header for print.
- **medium** `TABLE-01` `training/sessions/signup_sheet.html.erb:95` tables-lists: pattern=tables-lists Rule: data tables are ui_table. Walk-ins table is raw <table>.
- **low** `COLOR-01` `training/sessions/signup_sheet.html.erb:27` color: Rule: semantic colour tokens only. The page footer colour is the literal #444 in per-view CSS.
- **low** `COPY-03` `training/sessions/signup_sheet.html.erb:55` typography: Rule: table column headers are Title Case. The running-head th reads "… · Sign-up sheet" (55), as does the doc label (12).
- **low** `EMPTY-01` `training/sessions/signup_sheet.html.erb:46` empty-loading: Rule: empty states use ui_empty_state. Empty roster prints <p class="mt-4">No one is signed up for this session yet.</p>.
- **low** `TYPE-04` `training/sessions/signup_sheet.html.erb:87` typography: Rule: <h2> takes heading-section. The walk-ins masthead <h2 class="signup-session"> uses the print class instead (h1 at 40 is the page title).

**`training/sessions/work_histories/show.html.erb`** (GET /training/:slug/session/:slot_id/work-history/:person_id)

- **medium** `COLOR-03` `training/sessions/work_histories/show.html.erb:77` color: Rule: no coloured text for emphasis. "includes Echelon volunteer entries" is <strong class="text-error"> in a summary line, not a status or callout.
- **medium** `TOUCH-01` `training/sessions/work_histories/show.html.erb:95` links: Rule: a bare link gets min-h-9 (TABLE_LINK_CLASSES the only table exception). Hour totals are classless link_to at 95, 104, 111.
- **low** `TABLE-02` `training/sessions/work_histories/show.html.erb:81` tables-lists: pattern=tables-lists Rule: a matrix may pass responsive: false with a comment at the call site. The year matrix opts out; only the file header calls it a matrix.

**`training/untrained_people/index.html.erb`** (GET /training/:slug/untrained-people)

- **medium** `TOAST-03` `training/untrained_people/index.html.erb:54` buttons: Rule: a copy is confirmed by clipboard_button. Copy Emails is button_action with the copy-to-clipboard controller wired by hand, in a button_row inside a my-4 div.

**`training/completed_training/show.html.erb`** (GET /training/:slug/completed-training/:slot_id)

- **low** `HERO-02` `training/completed_training/show.html.erb:9` other: Rule: the hero description is one sentence saying what the page does. Code prints "<location> · Completed <training>", a label line, not a sentence.

**`training/mentoring/landing/index.html.erb`** (GET /training/:slug/mentoring)

- **low** `EMPTY-02` `training/mentoring/landing/index.html.erb:127` empty-loading: Rule: an empty value prints "—". Mentee and mentor cells print bare "None yet" (127, 136).

**`training/online_course_progress/index.html.erb`** (GET /training/:slug/online-course-progress)

- **low** `EMPTY-02` `training/online_course_progress/index.html.erb:95` empty-loading: Rule: an empty value prints "—". Missing enrolled date prints italic "— direct enrollment —" (tag.i).

**`training/sessions/show.html.erb`** (GET /training/:slug/session/:slot_id)

- **low** `HERO-02` `training/sessions/show.html.erb:9` other: Rule: the hero description is one sentence saying what the page does. Code prints "<description> · <year>", a label line.

**`training/trained_no_work/index.html.erb`** (GET /training/:slug/trained-no-work)

- **low** `COPY-01` `training/trained_no_work/index.html.erb:18` other: pattern=other Rule: never "working" for volunteering. Callout says the training "has no working positions that require it".

#### vc (39)

**`vc/applications/edit_details.html.erb`** (GET /vc/applications/:id/edit-details)

- **high** `FORM-01` `vc/applications/edit_details.html.erb:25` forms: Fields come through AppFormBuilder; the year grid is raw labels and check_box_tag "checkbox checkbox-sm", missing the builder's checkbox-primary, so checked boxes look different from builder checkboxes.
- **medium** `FORM-05` `vc/applications/edit_details.html.erb:20` forms: Checkbox groups use f.fieldset; the event-year group is a raw <fieldset> with a hand-styled <legend class="font-medium mb-2">.
- **low** `COPY-03` `vc/applications/edit_details.html.erb:21` typography: Headings are Title Case; the legend reads "Events attended".
- **low** `FORM-07` `vc/applications/edit_details.html.erb:35` forms: Fields wider than w-32 take responsive widths (w-full sm:w-44); Experience Type select is a fixed "w-44".

**`vc/applications/index.html.erb`** (GET /vc/applications)

- **high** `A11Y-01` `vc/applications/index.html.erb:54` navigation: Status is never colour alone; the active workflow preset is shown only by switching button_link :primary vs :secondary, with no aria-current, text or icon change.
- **high** `TABLE-04` `vc/applications/index.html.erb:64` forms: A table page's filters use filter_bar; this page hand-rolls an auto-submitting row of selects in a flex div, with no chips, count or actions slot.
- **low** `HELP-02` `vc/applications/index.html.erb:17` cards: The one collapsed card sits under the stat row and above the filters; About This Report comes before the search form and the stat row (40).

**`vc/handle_checker/index.html.erb`** (GET /vc/handle-checker)

- **medium** `BP-01` `vc/handle_checker/index.html.erb:18` forms: Field and buttons switch from column to row at sm: (outside a field width), plus wrapper_class mb-0 and button_row mb-1 tweaks to align them.
- **medium** `FORM-01` `vc/handle_checker/index.html.erb:66` forms: Fields come through AppFormBuilder; the vintage checkbox is check_box_tag borrowing AppFormBuilder::CHECKBOX_CLASSES inside common/_checkbox_tile, so it looks the same.
- **medium** `TYPE-03` `vc/handle_checker/index.html.erb:69` typography: text-sm is never for form labels; the checkbox label "Always include vintage callsigns" is text-sm (the help line at 71 is fine).

**`vc/application_import/index.html.erb`** (GET /vc/application-import (also POST preview/commit re-render at 422))

- **medium** `HELP-01` `vc/application_import/index.html.erb:61` other: Help further down the page is announced and linked from the top; the "How the Import Behaves" card (id import-help) has no callout linking to it.
- **medium** `HELP-02` `vc/application_import/index.html.erb:61` cards: Help belongs in one collapsed ui_disclosure card or an announced foot ui_section; this page puts its Q&A in an always-open ui_accent_card at the foot (sister create_prospectives uses ui_section).
- **low** `MODAL-02` `vc/application_import/index.html.erb:47` modals: turbo_confirm carries the app's confirm_modal_dialog (not a browser string), but its wording neither asks with the action nor says whether the import can be undone.

**`vc/reserved_handles/index.html.erb`** (GET /vc/reserved-handles)

- **high** `BTN-05` `vc/reserved_handles/index.html.erb:38` modals: :error is for destructive actions; "Delete Expired Handles" is a :secondary button_link (its confirm button is red, the trigger is grey).
- **low** `BTN-04` `vc/reserved_handles/index.html.erb:33` buttons: One primary action per view; Add Reserved Handle (33) is :primary and the filter panel's Apply Filters f.submit (73) defaults to :primary too.
- **low** `FORM-07` `vc/reserved_handles/index.html.erb:62` forms: Field widths fit content and are responsive rather than full width; both filter selects are width "w-full" stretched with wrapper_class "flex-1".

**`vc/thank_you_cards/index.html.erb`** (GET /vc/thank-you-cards)

- **medium** `COLOR-06` `vc/thank_you_cards/index.html.erb:66` color: The same neutral utility serves the same purpose; "No address on file" uses text-base-content/70 where muted fallbacks elsewhere use text-stone-muted.
- **medium** `FORM-05` `vc/thank_you_cards/index.html.erb:32` typography: Raw <legend class="mb-2 text-base font-medium text-heading"> in place of f.fieldset's form-legend (edit_details hand-styles its legend differently again).
- **low** `COPY-03` `vc/thank_you_cards/index.html.erb:32` typography: Headings are Title Case; the filter legend reads "Also include people we do not normally mail".

**`vc/bpguid/index.html.erb`** (GET /vc/bpguid, GET /vc/bpguid/:person_id (bpguid#show renders :index))

- **medium** `BTN-04` `vc/bpguid/index.html.erb:11` buttons: One primary action per view; Look Up Callsign (11), Search Salesforce (27) and every row's Use This BPGUID (_results 109) are all primary.
- **low** `EMPTY-02` `vc/bpguid/index.html.erb:40` empty-loading: the rule: an empty value prints "—"; none_stated prints "None stated" in muted italics (application_helper.rb:80)
- **low** `EMPTY-02` `vc/bpguid/index.html.erb:67` icons: An empty value prints "—"; a missing BPGUID prints italic "None on file" via tag.i.

**`vc/create_prospectives/index.html.erb`** (GET /vc/create-prospectives (also POST preview/commit re-render at 422))

- **medium** `HELP-01` `vc/create_prospectives/index.html.erb:92` cards: Help at the foot of a page must be announced and linked from the top; the "How This Page Behaves" Q&A section has an id but no callout links to it.
- **low** `MODAL-02` `vc/create_prospectives/index.html.erb:76` modals: Confirm asks with the action and says whether it can be undone; this message describes effects and says "Preview first", with no question and no undo statement.

**`vc/maintenance/index.html.erb`** (GET /vc/maintenance)

- **high** `BTN-05` `vc/maintenance/index.html.erb:41` buttons: :error is for destructive actions; the two "Preview …" links change nothing and only open a preview, yet are red :error full-width buttons.

**`vc/photos_review/reject_dialog.html.erb`** (GET /vc/photos-review/:id/reject (layout false, into "modal" frame))

- **medium** `FORM-06` `vc/photos_review/reject_dialog.html.erb:3` validation: Errors show through the builder with ui_form's summary; the form sets no_error_summary and an empty reason list answers with an error toast stream (controller line 43), not a field error.
- **low** `COPY-03` `vc/photos_review/reject_dialog.html.erb:10` typography: Headings are Title Case; the fieldset legend reads "Rejection reasons".

**`vc/applications/dialogs/send_email.html.erb`** (GET /vc/applications/:id/dialog/:dialog (vc/applications#dialog, layout false))

- **medium** `FORM-07` `vc/applications/dialogs/send_email.html.erb:9` forms: Field widths fit content and are responsive (w-full sm:w-*); the Subject field sets size: 70 instead, a fixed width that can exceed a phone-width dialog.

**`vc/applications/extract_handles.html.erb`** (POST /vc/applications/:id/extract_handles (rendered layout: false into the "modal" turbo frame))

- **medium** `CARD-01` `vc/applications/extract_handles.html.erb:26` cards: Panels come from the card/section helpers; the original-handles box is a div with its own border, rounded-lg, p-3 and bg-base-200, with a div pseudo-label.

**`vc/applications/show.html.erb`** (GET /vc/applications/:id)

- **medium** `BTN-04` `vc/applications/show.html.erb:13` buttons: One clear primary action per view; the review page shows the next-stage jump (_action_bar 37), Assign Callsign (_callsign_stage 20), Mark Okay (_paragraph_stage 23) and Approve Application (_personal_info_stage 13) all as primary.

**`vc/photos_review/index.html.erb`** (GET /vc/photos-review)

- **medium** `EMPTY-01` `vc/photos_review/index.html.erb:8` empty-loading: An empty state is always ui_empty_state; the empty review queue is a ui_callout_box :success "Congratulations! All photos have been reviewed."

**`vc/applications/dialogs/status_message.html.erb`** (GET /vc/applications/:id/dialog/:dialog (vc/applications#dialog, layout false))

- **low** `COPY-04` `vc/applications/dialogs/status_message.html.erb:4` typography: One verb per action, never "Update"; the status dialog is titled "Update Status" while its button says "Save Status".

**`vc/applications/edit_personal_info.html.erb`** (GET /vc/applications/:id/edit-personal-info)

- **low** `FORM-07` `vc/applications/edit_personal_info.html.erb:25` forms: Fields wider than w-32 take responsive widths; Country (25) and State (29) are fixed "w-44" and City (28) fixed "w-48".

**`vc/applications/search.html.erb`** (GET /vc/applications/search)

- **low** `COPY-03` `vc/applications/search.html.erb:18` typography: Section titles are Title Case; the results ui_section is titled "Found N applications".

**`vc/photos_review/info.html.erb`** (GET /vc/photos-review/:id/info (layout false, into "modal" frame))

- **low** `EMPTY-02` `vc/photos_review/info.html.erb:23` empty-loading: An empty value prints "—"; missing dimensions, reasons and message print italic <i>unknown</i> / <i>none given</i> (lines 23, 38, 46).

**`vc/reserved_handles/edit.html.erb`** (GET /vc/reserved-handles/:id/edit (also PATCH re-render at 422))

- **low** `HERO-02` `vc/reserved_handles/edit.html.erb:2` other: The description is one sentence saying what the page does; "Reserved handle #N." only names the record.

**`vc/reserved_handles/new.html.erb`** (GET /vc/reserved-handles/new (also POST /vc/reserved-handles re-render at 422))

- **low** `COPY-04` `vc/reserved_handles/new.html.erb:4` typography: Creating a record is "Add [Entity]", never "New"; the page reached by Add Reserved Handle is titled "New Reserved Handle".

**`vc/reserved_handles/upload.html.erb`** (GET /vc/reserved-handles/upload (also POST re-render at 422))

- **low** `COPY-03` `vc/reserved_handles/upload.html.erb:18` typography: Section titles are Title Case; the results ui_section is titled "Commit results" or "Verified handles — not saved yet".

**`vc/spigot_flow_report/index.html.erb`** (GET /vc/spigot-flow-report)

- **low** `EMPTY-02` `vc/spigot_flow_report/index.html.erb:91` tables-lists: An empty value prints "—"; empty matrix cells print "-" (lines 83 and 91).

#### vehicles (6)

**`vehicles/registry/index.html.erb`** (GET /vehicles/registry)

- **medium** `TYPE-03` `vehicles/registry/index.html.erb:130` typography: text-sm never for table content; the vehicle class and licence plate line is text-sm text-stone-muted.
- **low** `COPY-03` `vehicles/registry/index.html.erb:150` typography: Headings are Title Case; detail-group h4 titles at 150, 153, 156 are sentence case.

**`vehicles/registry/permit.html.erb`** (GET /vehicles/registry/:id/permit)

- **low** `COPY-03` `vehicles/registry/permit.html.erb:49` typography: Section titles are Title Case; ui_section title is Approved items or Requested items.
- **low** `HERO-02` `vehicles/registry/permit.html.erb:5` typography: Description is one sentence of purpose; it is the bare registry_vehicle_title string.

**`vehicles/paperwork/index.html.erb`** (GET /vehicles/paperwork)

- **low** `COPY-03` `vehicles/paperwork/index.html.erb:175` typography: Headings are Title Case; detail-group h4 titles Record eligible via, Eligible sign-ups, Personal vehicle eligible via (175, 182, 185).

**`vehicles/registry/edit.html.erb`** (GET /vehicles/registry/:id/edit)

- **low** `HERO-02` `vehicles/registry/edit.html.erb:3` typography: Description is one sentence of purpose; it is the vehicle title and year joined by a dash.

### 3.2 Shared partials and area helpers

Findings in a file that several pages render. "Used by" counts the audited templates that reach it.

**`common/_timesheet_notes.html.erb`** (used by 18)

- **medium** `CARD-01` `common/_timesheet_notes.html.erb:9` cards: Rule: containers come from the card/section helpers. Each note body is a hand-made box `border border-body-subtle rounded p-2 mb-1`.

**`helpers/vc/applications_helper.rb`** (used by 17)

- **medium** `BADGE-01` `helpers/vc/applications_helper.rb:7` other: Badge variants are primary, secondary, success, warning, error; application_status_badge passes :info (Pending) and :neutral (Handle Check), which ui_badge silently renders as secondary.
- **medium** `BADGE-01` `helpers/vc/applications_helper.rb:95` other: Badge variants are primary, secondary, success, warning, error; STAGE_STATE_BADGES gives "To do" :info, which ui_badge falls back to secondary while tinting the icon icon-info.

**`common/_checkbox_row.html.erb`** (used by 11)

- **medium** `FORM-01` `common/_checkbox_row.html.erb:15` forms: Rule: forms use the builder. common/checkbox_row is a raw <label> around check_box_tag with CHECKBOX_CLASSES, matching the builder's look by hand.

**`common/_checkbox_tile.html.erb`** (used by 10)

- **medium** `FORM-01` `common/_checkbox_tile.html.erb:15` forms: Rule: forms use the builder. common/checkbox_tile is a raw bordered <label> tile (rounded-base border border-line bg-base-100) for callers' raw checkboxes.

**`common/scheduling/_slot_additional_info.html.erb`** (used by 10)

- **medium** `BTN-01` `common/scheduling/_slot_additional_info.html.erb:27` buttons: Btn classes are not written by hand; btn-link font-normal align-baseline is added over button_action :ghost to turn it into an inline text link.

**`common/_checkbox_grid.html.erb`** (used by 9)

- **medium** `BP-01` `common/_checkbox_grid.html.erb:10` forms: Same grid as M0012: `md:grid-cols-2` creates a two-column tier below lg.
- **medium** `FORM-01` `common/_checkbox_grid.html.erb:13` forms: Raw check_box_tag with copied CHECKBOX_CLASSES instead of a builder field; its label text is a text-sm span (see R02216).
- **medium** `TYPE-03` `common/_checkbox_grid.html.erb:17` typography: Rule: never text-sm for form labels. Each checkbox's label text in the grid is a `text-sm text-body` span.

**`common/messages/_conversation_list.html.erb`** (used by 8)

- **medium** `TYPE-03` `common/messages/_conversation_list.html.erb:8` typography: Rule: never text-sm for empty-state messages. The search status line is text-sm and is also the zero-hit message ("No conversations … in any folder").
- **low** `EMPTY-01` `common/messages/_conversation_list.html.erb:9` other: Rule: always ui_empty_state. A search with no hits shows only the muted status line, no empty state.

**`common/messages/_folder_selector.html.erb`** (used by 8)

- **high** `TABS-01` `common/messages/_folder_selector.html.erb:5` navigation: Same: folder tabs from messages_folder_tab in a hand-written tabs-lift row, not tab_navigation.

**`common/messages/_messages_panel_header.html.erb`** (used by 8)

- **medium** `BTN-01` `common/messages/_messages_panel_header.html.erb:59` buttons: Rule: buttons from ButtonHelper. Mark Read and Archive are button_to with button_classes({}, :ghost) (lines 59, 73).

**`common/messages/_reply_form.html.erb`** (used by 8)

- **medium** `FORM-02` `common/messages/_reply_form.html.erb:27` forms: Rule: every field has a visible label, never placeholder-only. Reply editor uses hide_label: true and placeholder "Type your reply…" (named only by aria-label).

**`common/messages/_search_field.html.erb`** (used by 8)

- **medium** `FORM-02` `common/messages/_search_field.html.erb:26` forms: Rule: every field has a visible label, never placeholder-only. The mailbox search has only placeholder "Search messages" and an aria_label.

**`common/messages/_workspace.html.erb`** (used by 8)

- **medium** `CARD-01` `common/messages/_workspace.html.erb:48` cards: Rule: containers come from the card/section helpers. Tabs and list sit in a hand-made `bg-default rounded-lg` panel.

**`shared/_autocomplete.html.erb`** (used by 8)

- **low** `COPY-07` `shared/_autocomplete.html.erb:1` typography: Ellipsis is "…"; the component's default placeholder is "Search..." (callers that pass none show it).

**`common/provisions/_form.html.erb`** (used by 7)

- **medium** `FORM-05` `common/provisions/_form.html.erb:39` typography: Rule: a checkbox group is grouped with f.fieldset. Meal periods use a hand-styled label <p> and a help <p> above three loose check_boxes.
- **low** `BP-01` `common/provisions/_form.html.erb:16` forms: Selects take sm: widths through html class (16, 18, 25, 30) while number_field uses width:.
- **low** `BP-01` `common/provisions/_form.html.erb:25` forms: pattern=forms sm:w-32 in a select's html class rather than width:.
- **low** `BP-01` `common/provisions/_form.html.erb:30` forms: pattern=forms sm:w-32 in a select's html class rather than width:.
- **low** `COPY-04` `common/provisions/_form.html.erb:95` buttons: Rule: "Delete [Entity]". The delete_button label is a bare "Delete".

**`me/tickets/_wizard_nav.html.erb`** (used by 7)

- **low** `COPY-03` `me/tickets/_wizard_nav.html.erb:25` buttons: Button labels are Title Case; "Continue to confirmation"

**`helpers/training/mentoring_helper.rb`** (used by 6)

- **low** `BADGE-01` `helpers/training/mentoring_helper.rb:167` other: Rule lists badge variants primary/secondary/success/warning/error; the signed-up chip uses ui_badge :info, outside the documented set (on-shift and rangered chips comply).

**`common/_photo_none.html.erb`** (used by 6)

- **low** `STYLE-01` `common/_photo_none.html.erb:2` other: pattern=other Rule: no inline style=. Placeholder width/height set inline from PersonPhoto constants (a computed number) rather than a custom property or utility.

**`common/missing_requests/_form.html.erb`** (used by 6)

- **medium** `TYPE-04` `common/missing_requests/_form.html.erb:3` typography: Rule: nothing outweighs the section title. Callout lead is a `text-xl font-semibold` div, heavier than the h2 section titles, instead of the callout's title:.
- **low** `COPY-04` `common/missing_requests/_form.html.erb:54` buttons: pattern=buttons Rule: the submit is "Save [Entity]", never "Submit". Button reads "Submit Request".

**`common/unified_flagging/_history.html.erb`** (used by 6)

- **medium** `TYPE-03` `common/unified_flagging/_history.html.erb:88` typography: Rule: never text-sm for paragraphs, list items or empty messages. text-sm on status words (29, 31), the feedback paragraph (88) and "No trainer notes." (102); 75 is metadata.
- **medium** `TYPE-05` `common/unified_flagging/_history.html.erb:46` typography: Rule: heading hierarchy h1 > h2 > h3. In the review pane the team headings are h4 (46, 112) with no h3 above them.
- **low** `EMPTY-01` `common/unified_flagging/_history.html.erb:50` empty-loading: Rule: always ui_empty_state. "No training sign-ups." (50), "No trainer notes." (102), "No notes." (130) and "No notes yet: …" (139) are plain text.

**`helpers/scheduling/position_credits_helper.rb`** (used by 5)

- **high** `TYPE-02` `helpers/scheduling/position_credits_helper.rb:71` typography: text-xs never for labels a reader needs; chart y-axis ticks, day numbers and month names are text-xs (legend is text-sm).
- **high** `TYPE-02` `helpers/scheduling/position_credits_helper.rb:111` typography: text-xs never for labels a reader needs; axis tick labels, day numbers and month labels use text-xs.
- **low** `COPY-08` `helpers/scheduling/position_credits_helper.rb:117` typography: pattern=typography Dates come from DateTimeHelper; month axis label uses a literal strftime("%B").
- **low** `STYLE-01` `helpers/scheduling/position_credits_helper.rb:32` other: pattern=other No inline style= attribute; chart root carries style "--ymax" holding a computed number.
- **low** `STYLE-01` `helpers/scheduling/position_credits_helper.rb:69` other: pattern=other No inline style=; each y tick carries style "--y" with a computed number.
- **low** `STYLE-01` `helpers/scheduling/position_credits_helper.rb:84` other: pattern=other No inline style=; each layer carries style "--h" with the credit rate.
- **low** `STYLE-01` `helpers/scheduling/position_credits_helper.rb:88` other: pattern=other No inline style=; each step carries style "--w" with its minutes.
- **low** `STYLE-01` `helpers/scheduling/position_credits_helper.rb:119` other: pattern=other No inline style=; month cells carry style "--w" with a day count.

**`common/mentoring/_shift_card.html.erb`** (used by 5)

- **medium** `TYPE-03` `common/mentoring/_shift_card.html.erb:20` typography: text-sm is never for primary card information; the shift's time line (20) and the Sign-Ups count row above the meter (26) are text-sm.

**`common/surveys/_session_label.html.erb`** (used by 5)

- **low** `EMPTY-02` `common/surveys/_session_label.html.erb:7` empty-loading: Rule: an empty value prints "—". A session with no description prints "(no description)".

**`common/unified_flagging/_list_row.html.erb`** (used by 5)

- **medium** `TYPE-03` `common/unified_flagging/_list_row.html.erb:35` typography: Rule: text-sm only for secondary content. The training-status word is the line's one exception (what stands out), drawn text-sm; the note stamp at 39 is metadata.

**`sessions/_heading.html.erb`** (used by 5)

- **low** `BP-01` `sessions/_heading.html.erb:6` typography: pattern=typography sm: only in a field width:; heading uses sm:text-4xl.

**`helpers/scheduling/hq_forecast_helper.rb`** (used by 4)

- **medium** `TYPE-03` `helpers/scheduling/hq_forecast_helper.rb:226` typography: text-sm is for secondary content only; the bar's signed-up count (the figure the chart exists for) is text-sm, as are the hour axis and legend.
- **low** `COPY-08` `helpers/scheduling/hq_forecast_helper.rb:9` typography: pattern=typography Dates come from DateTimeHelper; helper uses a literal strftime("%H:%M") where DateTimeHelper::HOUR_MINS exists.
- **low** `STYLE-01` `helpers/scheduling/hq_forecast_helper.rb:268` spacing: the rule: no inline style= attribute

**`helpers/vc/reserved_handles_helper.rb`** (used by 4)

- **low** `COPY-08` `helpers/vc/reserved_handles_helper.rb:39` typography: pattern=typography Dates come from DateTimeHelper, never strftime; reserved_handle_twii_default_date formats with strftime("%B %-d, %Y") and the result prints in help_text on two views.

**`helpers/vehicles/registry_helper.rb`** (used by 4)

- **medium** `TYPE-03` `helpers/vehicles/registry_helper.rb:173` typography: text-sm is for secondary content; line 173 sets the pending-row message No eligible teams, positions, or sign-ups in text-sm. Line 132 (DPW id) is metadata and fine.
- **low** `EMPTY-02` `helpers/vehicles/registry_helper.rb:189` empty-loading: An empty value prints the em dash; vehicle_eligibility_sources returns the word "none".

**`common/assets/_checkout_form.html.erb`** (used by 4)

- **medium** `FORM-03` `common/assets/_checkout_form.html.erb:15` forms: Rule: mark required fields through required:. The barcode label is hand-built with copied label classes and a hand-placed ui_badge "required", bypassing the builder (wrapper: false).

**`common/available_sign_ups/_slot.html.erb`** (used by 4)

- **medium** `CARD-02` `common/available_sign_ups/_slot.html.erb:6` cards: A left-border accent card is ui_accent_card; the slot card hand-builds box-accent box-accent-warning/success border-l-4 (or box box-default) on a content_tag div with its own p-3 mb-2.
- **low** `MODAL-02` `common/available_sign_ups/_slot.html.erb:122` modals: A confirm asks with the action and says whether it can be undone; this red confirm says "Please confirm you wish to remove this shift…" with no question or undo statement.

**`common/available_sign_ups/_training_months.html.erb`** (used by 4)

- **medium** `TYPE-05` `common/available_sign_ups/_training_months.html.erb:11` typography: Hierarchy goes h1 > h2 > h3; the month h3s render under schedule/index's h1 with no h2 between (the preview callout title is a div).
- **low** `COPY-08` `common/available_sign_ups/_training_months.html.erb:8` other: Dates come from DateTimeHelper, never strftime in a view; the month grouping key uses slot.begins.strftime("%B") and prints it as the card heading.

**`common/messages/_compose.html.erb`** (used by 4)

- **medium** `CARD-01` `common/messages/_compose.html.erb:7` cards: Rule: a container is card-standard via ui_card. The compose form sits in a hand-made `overflow-hidden rounded-lg border border-line` div.

**`common/schedule/_signed_up_row.html.erb`** (used by 4)

- **medium** `BP-01` `common/schedule/_signed_up_row.html.erb:31` spacing: pattern=spacing sm: is only for a field width; sm:grid-cols-2 creates a tablet column tier between the phone stack and lg:grid-cols-4.
- **low** `CARD-01` `common/schedule/_signed_up_row.html.erb:6` spacing: A card has no shadow by default and adds shadow-xs if it needs one; this card-standard div carries shadow-sm (the button/dropdown shadow).
- **low** `MODAL-02` `common/schedule/_signed_up_row.html.erb:81` modals: A confirm asks with the action and says whether it can be undone; the red confirm says "Please confirm you wish to remove this shift…", no question, no undo line.

**`common/scheduling/_alpha_shift_info.html.erb`** (used by 4)

- **medium** `HELP-02` `common/scheduling/_alpha_shift_info.html.erb:1` other: A how-to goes in the one collapsed card (or a footer ui_section announced from the top); six visible paragraphs of Alpha instructions sit open on available_sign_ups/show.
- **low** `COPY-10` `common/scheduling/_alpha_shift_info.html.erb:5` other: Paragraphs are two or three sentences at most; the shift-length paragraph runs to five sentences.

**`common/scheduling/_burn_weekend_shift_recommendation.html.erb`** (used by 4)

- **low** `SPACE-03` `common/scheduling/_burn_weekend_shift_recommendation.html.erb:5` tables-lists: No classes on an instruction-list dt; each dt carries font-bold (5, 12, 15), one with a trailing space.
- **low** `SPACE-03` `common/scheduling/_burn_weekend_shift_recommendation.html.erb:12` typography: pattern=typography instruction-list dt has class "font-bold".

**`common/scheduling/_signup_blockers.html.erb`** (used by 4)

- **medium** `COLOR-02` `common/scheduling/_signup_blockers.html.erb:60` links: Colour carries meaning, never decoration; the Contact Training Academy mail link is coloured with icon-warning, a status colour on a plain link.
- **medium** `COLOR-03` `common/scheduling/_signup_blockers.html.erb:49` color: No coloured text for emphasis; the requirement list is font-medium text-error inside an error banner that already signals the state.
- **medium** `TYPE-05` `common/scheduling/_signup_blockers.html.erb:13` typography: Hierarchy goes h1 > h2 > h3; these h4s (13, 24, 44) follow the schedule page's h1 directly, since the alert banner's title is a div.
- **low** `COLOR-05` `common/scheduling/_signup_blockers.html.erb:40` toasts-alerts: A status icon takes icon-error/icon-warning/icon-info; the ban icon wrapper uses text-error (40), while siblings use icon-error (9) and icon-warning (20).
- **low** `FORM-10` `common/scheduling/_signup_blockers.html.erb:58` spacing: A sub-group divider is mt-4 pt-3 border-t border-line; this one is mt-4 pt-4 border-t border-line.

**`common/ticketing_maintenance/_results_table.html.erb`** (used by 4)

- **low** `EMPTY-02` `common/ticketing_maintenance/_results_table.html.erb:33` empty-loading: Rule: an empty value prints "—". A missing person prints italic "unknown".

**`people/shared/_privacy_notice.html.erb`** (used by 4)

- **medium** `TYPE-05` `people/shared/_privacy_notice.html.erb:6` toasts-alerts: Rule says clear heading hierarchy; the page-level "Personal Information" callout title renders as h4 directly under the h1 (no heading_level: :h2).

**`helpers/person/swag_helper.rb`** (used by 3)

- **low** `EMPTY-02` `helpers/person/swag_helper.rb:13` empty-loading: EMPTY-02 says an empty value prints "—"; swag_type_label returns a hyphen "-" when swag is nil

**`helpers/shift_operations/rollcall_helper.rb`** (used by 3)

- **low** `MODAL-02` `helpers/shift_operations/rollcall_helper.rb:137` modals: Rule asks the action then says whether it can be undone; this sign-out confirm explains the effect but never says a second tap resumes the shift.

**`common/_event_summary_breakdown.html.erb`** (used by 3)

- **high** `HELP-02` `common/_event_summary_breakdown.html.erb:15` tables-lists: Rule: on a report, Q&A goes in one collapsed About This Report card, never inside a ui_section. Event-summary report shows two visible instruction-lists inside ui_sections (lines 15, 26).
- **high** `HELP-02` `common/_event_summary_breakdown.html.erb:26` tables-lists: Same as R02265: instruction-list Q&A left visible inside the report's ui_sections instead of the page's card.
- **medium** `TYPE-03` `common/_event_summary_breakdown.html.erb:51` typography: Rule: table content is never text-sm. "(hours excluded)" annotation in a table cell is `text-stone-muted text-sm`.

**`common/_timesheet_confirm.html.erb`** (used by 3)

- **medium** `COLOR-05` `common/_timesheet_confirm.html.erb:64` icons: Rule: a status icon takes icon-success. circle-check uses text-success.
- **medium** `LIST-01` `common/_timesheet_confirm.html.erb:41` tables-lists: Rule: explanatory Q&A is a classless dl.instruction-list. "Need help?" uses <dl class="space-y-2 text-sm"> with div-grouped dts styled font-semibold.
- **medium** `TYPE-03` `common/_timesheet_confirm.html.erb:80` typography: Rule: never text-sm for paragraphs. text-sm on the help dl (41) and paragraphs (80, 104, 111); text-base/text-lg uses (63, 102, 109) are fine.
- **low** `COPY-03` `common/_timesheet_confirm.html.erb:37` typography: Rule: a heading is a Title Case label, not a question. The accordion summary reads "Need help?".
- **low** `FORM-10` `common/_timesheet_confirm.html.erb:74` other: Rule: a sub-group divider is mt-4 pt-3 border-t border-line. Line 35 matches; line 74 uses mt-3 and border-success/30.

**`common/assets/_table.html.erb`** (used by 3)

- **medium** `BTN-04` `common/assets/_table.html.erb:68` buttons: Rule: one primary action per view. Every open row's "Check In" is :primary, so a table of checkouts shows many primaries.

**`common/mentoring/_mentee_card.html.erb`** (used by 3)

- **medium** `TYPE-03` `common/mentoring/_mentee_card.html.erb:24` cards: text-sm is never for primary information in cards; ui_card_body class "flex-grow text-sm" shrinks the whole body (Shift, Mentors, Last Rangered, FKAs).

**`common/missing_requests/_entry.html.erb`** (used by 3)

- **high** `BTN-05` `common/missing_requests/_entry.html.erb:58` buttons: Rule: destructive actions are :error (delete_button). Delete is button_link :secondary (outline) with an error confirm; siblings draw Delete red.
- **high** `SHADOW-01` `common/missing_requests/_entry.html.erb:3` spacing: Rule: flat by default; shadow-lg is for popovers and menus. Each missing-request entry is lifted with shadow-lg.
- **medium** `CARD-01` `common/missing_requests/_entry.html.erb:3` cards: Rule: a card is ui_card. Entry is a hand-made div (my-2 shadow-lg) with a callout on top and a p-3 body.
- **low** `COPY-04` `common/missing_requests/_entry.html.erb:47` buttons: Rule: never "Submit". Button "Submit Appeal" opens the edit form; the bare "Delete" at 58 also omits its entity.

**`common/shift_manage/_alerts.html.erb`** (used by 3)

- **medium** `COLOR-03` `common/shift_manage/_alerts.html.erb:82` color: No coloured text for emphasis; the no-privilege sentence is strong text-error while the parallel can-force sentence (77) is plain strong.

**`common/shift_manage/_on_duty.html.erb`** (used by 3)

- **low** `COPY-04` `common/shift_manage/_on_duty.html.erb:39` buttons: One verb per action, never "Submit"; the button reads "End Shift & Submit Correction".

**`common/shift_manage/_start_shift.html.erb`** (used by 3)

- **medium** `BTN-04` `common/shift_manage/_start_shift.html.erb:42` buttons: One clear primary action per view; every imminent-shift row has a :primary Start Shift (42) and the form adds a primary lg submit_button (78).
- **low** `FORM-07` `common/shift_manage/_start_shift.html.erb:75` forms: Field widths come through the responsive width: pattern (w-full sm:w-44 for selects); this select uses class "w-full lg:w-96".

**`common/timesheet/_entry_with_action.html.erb`** (used by 3)

- **low** `COLOR-06` `common/timesheet/_entry_with_action.html.erb:91` color: The same neutral text utility serves the same purpose (text-stone-muted); this line uses .me-muted, a hero-panel alias of it.
- **low** `COPY-04` `common/timesheet/_entry_with_action.html.erb:110` buttons: One verb per action, never "Submit"; the correction link reads "Submit Appeal" when rejected.

**`common/timesheet/_listing.html.erb`** (used by 3)

- **medium** `CARD-01` `common/timesheet/_listing.html.erb:4` cards: One card utility, card-standard via ui_card; the entry card is a div with the section box classes box box-default plus its own border, radius, padding.
- **low** `COLOR-06` `common/timesheet/_listing.html.erb:20` color: Neutral muted text is text-stone-muted; this note uses the hero-panel alias .me-muted.

**`common/timesheet/_listing_with_actions.html.erb`** (used by 3)

- **medium** `CARD-01` `common/timesheet/_listing_with_actions.html.erb:4` cards: Cards are card-standard via ui_card; turbo_frame_tag itself is the card: "box box-default mb-3 rounded-xl border border-line shadow-sm".

**`me/tickets/_ticket_gift_conditions.html.erb`** (used by 3)

- **medium** `STYLE-03` `me/tickets/_ticket_gift_conditions.html.erb:2` cards: Use the helper where one exists; hand-made bordered rounded p-2 box around ui_icon_item rows

**`person/vehicles/_eligibility_list.html.erb`** (used by 3)

- **medium** `BP-01` `person/vehicles/_eligibility_list.html.erb:34` spacing: BP-01: lg: is the one structural fold and sm: only for field widths; the team/position names use "grid grid-cols-2 sm:grid-cols-4 gap-2", a 640px layout tier
- **low** `EMPTY-01` `person/vehicles/_eligibility_list.html.erb:41` empty-loading: EMPTY-01 says an empty state is always ui_empty_state; an empty list prints bare text "No <title>s" in the wrapper div

**`vc/photos_review/_attribution.html.erb`** (used by 3)

- **low** `EMPTY-02` `vc/photos_review/_attribution.html.erb:4` typography: An empty value prints "—"; missing uploader and never-reviewed print italic <i>unknown</i> and <i>never</i>.

**`helpers/people/languages_known_helper.rb`** (used by 2)

- **medium** `TYPE-03` `helpers/people/languages_known_helper.rb:49` typography: Rule says text-sm never for table content; the shift position a speaker is on (Right Now cell) is drawn me-muted text-sm.
- **low** `COLOR-06` `helpers/people/languages_known_helper.rb:15` color: Rule says one neutral text utility per purpose (text-stone-muted for muted text); helper uses the /me hero-panel class me-muted outside /me, which renders the same colour.
- **low** `LAYOUT-03` `helpers/people/languages_known_helper.rb:79` other: Rule says badge only the exception count on a row; the index badges "N on duty" (a positive, ordinary state) beside the exception "Off site only".

**`helpers/scheduling/schedule_by_callsign_helper.rb`** (used by 2)

- **low** `COPY-08` `helpers/scheduling/schedule_by_callsign_helper.rb:89` typography: pattern=typography Dates come from DateTimeHelper; helper formats with literal strftime("%b %-d").

**`helpers/scheduling/schedule_by_position_helper.rb`** (used by 2)

- **low** `COPY-08` `helpers/scheduling/schedule_by_position_helper.rb:136` typography: pattern=typography Dates come from DateTimeHelper; helper uses literal "%b %-d" and "%b %-d, %Y".

**`helpers/scheduling/shift_lead_helper.rb`** (used by 2)

- **medium** `COLOR-03` `helpers/scheduling/shift_lead_helper.rb:247` color: No coloured text for emphasis; mode words "ON DUTY" (bold red) and "SCHEDULED" (bold green) are not statuses. The -BL- red text is a real status with words.
- **low** `EMPTY-02` `helpers/scheduling/shift_lead_helper.rb:190` typography: An empty value prints "—"; the GTR/Veh cell prints "-" when the Ranger has neither.

**`helpers/teams_positions/position_sanity_checker_helper.rb`** (used by 2)

- **low** `COPY-03` `helpers/teams_positions/position_sanity_checker_helper.rb:22` typography: Rule says hero titles are Title Case; CHECK_META labels used as check-page hero titles and row titles are sentence case ("Deactivated accounts with grants"), lines 22-99.
- **low** `COPY-03` `helpers/teams_positions/position_sanity_checker_helper.rb:30` buttons: Rule says button labels are Title Case; the repair button labels are sentence case ("Revoke everything", "Reset to the new-user set"), lines 30-106.
- **low** `COPY-03` `helpers/teams_positions/position_sanity_checker_helper.rb:131` tables-lists: Rule says table column headers are Title Case; COLUMNS headings are sentence case ("Still holds", "Missing positions", "Mentor year"), lines 131-139.

**`helpers/ticketing/access_documents_helper.rb`** (used by 2)

- **low** `COPY-08` `helpers/ticketing/access_documents_helper.rb:64` typography: pattern=typography Rule: dates come from DateTimeHelper. Code: arrival filter label formatted with Date#strftime and a presenter format constant in a helper.

**`admin/action_logs/_table.html.erb`** (used by 2)

- **medium** `TYPE-03` `admin/action_logs/_table.html.erb:26` typography: Rule: table content is text-base. Code: person, target, event and message cells take log_text_class (text-sm) (lines 26, 29, 32, 36).

**`admin/event_dates/_form.html.erb`** (used by 2)

- **low** `COPY-03` `admin/event_dates/_form.html.erb:3` typography: Rule: every heading is Title Case. Code: fieldset legends "Event window", "Credit period", "Pre-event slot window" (lines 3, 13, 24).
- **low** `LIST-01` `admin/event_dates/_form.html.erb:4` typography: Rule: explanatory content is a Q&A instruction-list, not paragraphs. Code: each fieldset opens with a raw p.my-2 explanation (lines 4, 14, 25).

**`admin/oauth_clients/_form.html.erb`** (used by 2)

- **low** `COPY-03` `admin/oauth_clients/_form.html.erb:5` typography: Rule: every heading is Title Case. Code: fieldset legend "Client details".
- **low** `MODAL-02` `admin/oauth_clients/_form.html.erb:42` modals: Rule: ask with the action ("<Verb> <thing>?") and say whether it can be undone. Code: the New Secret dialog states what happens, asks nothing and is silent on undo.

**`admin/shift_coverage_positions/_position_rows.html.erb`** (used by 2)

- **medium** `FORM-01` `admin/shift_coverage_positions/_position_rows.html.erb:22` forms: Rule: fields come from AppFormBuilder. Code: label_tag/select_tag/text_field_tag borrowing the builder's class constants; looks the same.
- **medium** `FORM-01` `admin/shift_coverage_positions/_position_rows.html.erb:28` forms: Rule: builder fields only. Code: select_tag stands in for f.select (same departure as M0294).
- **medium** `FORM-01` `admin/shift_coverage_positions/_position_rows.html.erb:38` forms: Rule: builder fields only. Code: text_field_tag stands in for f.text_field (same departure as M0295).
- **medium** `FORM-06` `admin/shift_coverage_positions/_position_rows.html.erb:10` validation: Rule: errors show through the builder (input-error on the field). Code: rows read errors.details and pick *_ERROR_CLASSES by hand.
- **medium** `FORM-06` `admin/shift_coverage_positions/_position_rows.html.erb:27` validation: Rule: field errors come from the builder. Code: per-row error classes and aria-invalid set by hand on raw tags (lines 10-11, 27, 31, 33, 37, 40-41).
- **medium** `FORM-06` `admin/shift_coverage_positions/_position_rows.html.erb:33` validation: Rule: the builder sets the error state. Code: aria-invalid written by hand on raw tags (lines 33, 41).
- **low** `BP-01` `admin/shift_coverage_positions/_position_rows.html.erb:24` forms: pattern=forms Rule: sm: only in a field's width:. Code: wrapper div "w-full sm:max-w-xs" (raw tag cannot take width:).

**`asset_management/records/_form.html.erb`** (used by 2)

- **medium** `FORM-07` `asset_management/records/_form.html.erb:24` forms: Field widths fit their content; barcode (25 chars), description, entity, group, expires and order number all take width: w-full (24, 29, 50, 57, 65, 71).

**`bmid/provisions/_modal.html.erb`** (used by 2)

- **medium** `MODAL-01` `bmid/provisions/_modal.html.erb:9` modals: Rule: modal buttons go in m.footer. Code: no m.footer; the shared form's button_row and modal_close_button "Cancel" render inside m.body (common/provisions/_form:86-89).

**`bmid/titles/_form.html.erb`** (used by 2)

- **low** `BP-01` `bmid/titles/_form.html.erb:22` forms: pattern=forms Rule: sm: only in a field's width:. Code: select width passed as html class "w-full sm:w-44" instead of width:.
- **low** `BP-01` `bmid/titles/_form.html.erb:29` forms: Rule: sm: only in a field's width:. Code: f.select and f.collection_select take widths through html class: (22, 29) while text and number fields use width: (17, 31).
- **low** `MODAL-02` `bmid/titles/_form.html.erb:43` buttons: Rule: confirm says whether it can be undone. Code: delete confirm (red via delete_button) explains effects but never says the deletion cannot be undone.

**`bookmarks/_document.html.erb`** (used by 2)

- **medium** `BP-01` `bookmarks/_document.html.erb:17` other: md: is reserved for button-row stacking; the bookmark status line becomes three columns at md:, a layout tier (text-sm here is metadata, allowed).
- **low** `BP-01` `bookmarks/_document.html.erb:22` spacing: pattern=spacing md: is not a sanctioned breakpoint here; md:text-right aligns the clock column.
- **low** `COLOR-06` `bookmarks/_document.html.erb:17` color: The same neutral text utility for the same purpose (text-stone-muted); the status line borrows me-muted, the /me hero panel's helper class.

**`common/_dropdown_scroll_list.html.erb`** (used by 2)

- **low** `NAV-04` `common/_dropdown_scroll_list.html.erb:20` navigation: Rule: dropdown_scroll_list links are plain fragments with data-turbo="false". dropdown_item "#id" links carry no data-turbo="false"; the partial relies on an application.js turbo:click handler instead.

**`common/_time_warnings.html.erb`** (used by 2)

- **medium** `COLOR-03` `common/_time_warnings.html.erb:12` color: Rule: no coloured text for emphasis; use weight and size. "is BEFORE/AFTER…" spans are text-error font-semibold with shouted capitals inside a warning callout (lines 12, 15).

**`common/bmids/_fields.html.erb`** (used by 2)

- **medium** `FORM-07` `common/bmids/_fields.html.erb:13` forms: Rule: widths fit content and are responsive, not full width. SAP Date select is html class w-full at every width; Status uses lg:w-60 via html class while text fields use width:.

**`common/bmids/_warnings.html.erb`** (used by 2)

- **low** `COPY-03` `common/bmids/_warnings.html.erb:17` typography: Rule: callout titles are Title Case. Titles "No sign-ups found" and "No claimed ticket or in-person training sign-up" are sentence case.

**`common/mail_log/_legend.html.erb`** (used by 2)

- **medium** `COLOR-05` `common/mail_log/_legend.html.erb:13` icons: Rule: a status icon takes icon-error / icon-warning. Mail log legend colours its icons text-error and text-warning.

**`common/mail_log/_table.html.erb`** (used by 2)

- **low** `EMPTY-02` `common/mail_log/_table.html.erb:39` empty-loading: Rule: an empty value prints "—". A missing recipient prints "-"; a blank subject prints "(no subject)" (20).

**`communication/announcements/_form.html.erb`** (used by 2)

- **low** `COPY-03` `communication/announcements/_form.html.erb:3` typography: Headings are Title Case; fieldset legends read "Who sees it", "What it says", "When it stops showing" (3,16,25).

**`communication/survey_groups/_form.html.erb`** (used by 2)

- **low** `COPY-03` `communication/survey_groups/_form.html.erb:4` typography: Headings are Title Case; legends read "What people see" and "How the answers are reported" (4,18).
- **low** `COPY-04` `communication/survey_groups/_form.html.erb:27` buttons: "Add" opens a create form and the submit says "Save [Entity]"; the new-group form's submit reads "Add Group".

**`communication/survey_questions/_form.html.erb`** (used by 2)

- **low** `COPY-03` `communication/survey_questions/_form.html.erb:9` typography: Headings are Title Case; legends read "The question" and "Settings for one type of question" (9,29).
- **low** `COPY-04` `communication/survey_questions/_form.html.erb:39` buttons: The submit says "Save [Entity]"; the new-question form's submit reads "Add Question".

**`communication/surveys/_form.html.erb`** (used by 2)

- **low** `COPY-03` `communication/surveys/_form.html.erb:5` typography: Headings are Title Case; legends read "Who answers, and about what", "What it says", "Whether it is shown" (5,38,50).
- **low** `COPY-04` `communication/surveys/_form.html.erb:64` buttons: A form submit says "Save [Entity]", never "Create"; the new-survey submit reads "Create Survey".

**`me/dashboard/_dashboard_bonked.html.erb`** (used by 2)

- **medium** `COLOR-03` `me/dashboard/_dashboard_bonked.html.erb:17` color: No coloured text for emphasis; a key sentence is <b class="text-error">

**`me/dashboard/_dashboard_document.html.erb`** (used by 2)

- **medium** `FORM-09` `me/dashboard/_dashboard_document.html.erb:6` cards: Saved rich text renders in .lexxy-content through rich_text; Milestones document body is printed with body.html_safe

**`me/personal_vehicles/_form.html.erb`** (used by 2)

- **medium** `FORM-03` `me/personal_vehicles/_form.html.erb:5` validation: A required field is marked through required:; the form says "All fields are required." in a warning callout and marks no field
- **low** `COPY-04` `me/personal_vehicles/_form.html.erb:72` buttons: Submitting a form says "Save [Entity]", never "Submit"; create branch label is "Submit Request"
- **low** `FORM-07` `me/personal_vehicles/_form.html.erb:15` forms: Widths fit content and are responsive (w-full sm:w-48); fixed w-24 and w-40 inputs and cols: 40 textarea

**`me/tickets/_item_details.html.erb`** (used by 2)

- **medium** `STYLE-03` `me/tickets/_item_details.html.erb:14` cards: Use the helper where one exists; hand-made bordered rounded p-2 box wraps the ui_icon_item list

**`me/tickets/_landing.html.erb`** (used by 2)

- **medium** `CARD-01` `me/tickets/_landing.html.erb:152` cards: Cards are card-standard via ui_card; checklist cards are hand-made divs with rounded-lg border border-line p-4
- **low** `COPY-03` `me/tickets/_landing.html.erb:37` typography: Headings are Title Case; section_meta titles "Gift tickets", "SAPs for significant others", "Confirm your choices" print as h3 and step titles (lines 37, 41, 42)
- **low** `COPY-03` `me/tickets/_landing.html.erb:188` buttons: Button labels are Title Case; "Start ticketing" / "Continue ticketing" are sentence case (button_link itself is compliant)

**`people/people_by_location/_filter_fields.html.erb`** (used by 2)

- **medium** `FORM-05` `people/people_by_location/_filter_fields.html.erb:10` forms: Rule says f.fieldset for checkbox groups; code uses raw fieldset, legend font-medium mb-2 and a p help line instead of the builder's fieldset and help text.

**`people/people_by_location/_status_notice.html.erb`** (used by 2)

- **medium** `TYPE-05` `people/people_by_location/_status_notice.html.erb:7` toasts-alerts: Rule says clear heading hierarchy; the page-level callout title "Who These Counts Include" renders as the helper default h4 directly under the h1 (no heading_level: :h2).

**`person/_photo.html.erb`** (used by 2)

- **high** `TYPE-02` `person/_photo.html.erb:15` other: TYPE-02 bans text-xs on text a reader needs; unknown photo status prints as span "text-xs text-body" instead of a badge

**`person/access_documents/_form.html.erb`** (used by 2)

- **low** `BP-01` `person/access_documents/_form.html.erb:17` forms: BP-01 sanctions sm: only through a field's width:; the selects carry sm:w-64/44/32/56 in html-options class (17, 19, 22, 27, 36), and 43 uses lg:w-40, while awards/_form uses width:
- **low** `BP-01` `person/access_documents/_form.html.erb:22` forms: pattern=forms sm:w-32 passed in the select's html class hash rather than width:
- **low** `BP-01` `person/access_documents/_form.html.erb:27` forms: pattern=forms sm:w-32 passed in the select's html class hash rather than width:
- **low** `BP-01` `person/access_documents/_form.html.erb:36` forms: pattern=forms sm:w-56 passed in the select's html class hash rather than width:
- **low** `FORM-07` `person/access_documents/_form.html.erb:45` forms: FORM-07 says widths fit their content and are responsive; "Name on Document" is width "w-full" at every size

**`person/banners/_form.html.erb`** (used by 2)

- **low** `COPY-03` `person/banners/_form.html.erb:39` buttons: COPY-03 says button labels are Title Case; the delete button reads "Delete banner"

**`person/certifications/_form.html.erb`** (used by 2)

- **low** `COPY-03` `person/certifications/_form.html.erb:27` buttons: COPY-03 says button labels are Title Case; the delete button reads "Delete certification"

**`person/provisions/_section.html.erb`** (used by 2)

- **medium** `DISC-01` `person/provisions/_section.html.erb:28` other: DISC-01 says collapsible content is ui_accordion or ui_disclosure; the provisions body is hidden with class "hidden hidden!" and aria-hidden and toggled by a button_action on the toggle controller
- **low** `COPY-03` `person/provisions/_section.html.erb:64` buttons: COPY-03 says button labels are Title Case; the toggle reads "Show current provisions" / "Show all provisions"

**`person/timesheets/_log_table.html.erb`** (used by 2)

- **low** `EMPTY-02` `person/timesheets/_log_table.html.erb:17` links: EMPTY-02 says an empty value prints "—"; a missing creator prints "-" (the creator link_to "underline" at 14 is a plain link, uncovered)

**`person/unified_flagging/_team_notes.html.erb`** (used by 2)

- **medium** `BTN-04` `person/unified_flagging/_team_notes.html.erb:56` buttons: BTN-04 wants one primary action per view; each team's section renders a :primary "Add Note / Rank", so the page shows one per writable team
- **medium** `TYPE-04` `person/unified_flagging/_team_notes.html.erb:14` typography: TYPE-04: nothing inside a section outweighs its title; the year is span "font-semibold text-heading text-lg", larger than the section title's text-base on phones
- **low** `EMPTY-01` `person/unified_flagging/_team_notes.html.erb:6` empty-loading: EMPTY-01 says an empty state is always ui_empty_state; "No <team> notes yet." (6) and "No notes." (25) are plain p "text-body"

**`scheduling/hq_forecast/_people_dialog.html.erb`** (used by 2)

- **low** `COPY-08` `scheduling/hq_forecast/_people_dialog.html.erb:25` typography: pattern=typography Never strftime in a view; cell formats signup.begins with strftime(MONTH_DAY_TIME).

**`shift_operations/roc_photo_board/_board.html.erb`** (used by 2)

- **medium** `BADGE-01` `shift_operations/roc_photo_board/_board.html.erb:20` other: Badges come from ui_badge; "Now showing" is a custom photo-board-badge span.
- **medium** `CARD-01` `shift_operations/roc_photo_board/_board.html.erb:28` cards: Cards are card-standard via ui_card; person cards are custom photo-board-card divs.
- **medium** `EMPTY-01` `shift_operations/roc_photo_board/_board.html.erb:38` empty-loading: Empty states use ui_empty_state; empty group and no-host are custom photo-board-empty/no-host boxes with a 3x icon.
- **medium** `TYPE-04` `shift_operations/roc_photo_board/_board.html.erb:21` typography: <h2> takes heading-section; board h2s use custom photo-board-group-title and photo-board-rail-heading classes.

**`shift_operations/rollcall/_pickers.html.erb`** (used by 2)

- **medium** `FORM-01` `shift_operations/rollcall/_pickers.html.erb:16` forms: Forms use AppFormBuilder; pickers use form_tag, label_tag and select_tag borrowing SELECT_CLASSES.
- **medium** `FORM-01` `shift_operations/rollcall/_pickers.html.erb:20` forms: select_tag in place of f.select (20, 31).
- **medium** `FORM-01` `shift_operations/rollcall/_pickers.html.erb:31` forms: pattern=forms select_tag for shift in place of f.select.

**`shift_operations/rollcall/_roster.html.erb`** (used by 2)

- **medium** `FORM-01` `shift_operations/rollcall/_roster.html.erb:20` forms: Fields come from the builder; the callsign filter is a raw <input type="search" class="input"> with an sr-only label.
- **medium** `FORM-02` `shift_operations/rollcall/_roster.html.erb:19` forms: Every field has a visible label, never placeholder-only; the label is sr-only and only the placeholder shows.

**`shift_operations/rollcall/_row.html.erb`** (used by 2)

- **high** `BTN-01` `shift_operations/rollcall/_row.html.erb:50` buttons: Buttons come from ButtonHelper; each roster row is button_to with a hand-built shell (border-s-4, tint, ring), looking unlike any btn.

**`teams_positions/position_lineups/_form.html.erb`** (used by 2)

- **low** `COPY-03` `teams_positions/position_lineups/_form.html.erb:11` typography: Rule says Title Case lowercases prepositions of four letters or fewer; section title reads "Positions In This Lineup".

**`teams_positions/position_records/_form.html.erb`** (used by 2)

- **low** `EMPTY-01` `teams_positions/position_records/_form.html.erb:168` empty-loading: Rule says empty states always use ui_empty_state; "This position grants no permissions." is a p.mt-3 in muted italic.

**`teams_positions/team_records/_form.html.erb`** (used by 2)

- **low** `EMPTY-01` `teams_positions/team_records/_form.html.erb:87` empty-loading: Rule says empty states always use ui_empty_state; "This team grants no permissions." is a p.mt-3 in muted italic.

**`ticketing/trs_export/_rows_table.html.erb`** (used by 2)

- **low** `COLOR-05` `ticketing/trs_export/_rows_table.html.erb:44` icons: Rule: a status icon takes icon-error. Code: problem icon coloured with raw text-error plus me-1; sr-only "Has problems:" is fine.

**`vehicles/registry/_form.html.erb`** (used by 2)

- **low** `BP-01` `vehicles/registry/_form.html.erb:50` forms: pattern=forms sm: only in a field's width:; the select passes w-full sm:w-56 through the html class option.
- **low** `BP-01` `vehicles/registry/_form.html.erb:63` forms: pattern=forms sm: belongs in width:; select passes w-full sm:w-56 via html class.
- **low** `COPY-03` `vehicles/registry/_form.html.erb:132` buttons: Button labels are Title Case; Save vehicle, Add vehicle and Delete vehicle (line 136) are sentence case.
- **low** `COPY-04` `vehicles/registry/_form.html.erb:132` buttons: Submit is Save X for new or edit; the create submit reads Add vehicle.
- **low** `FORM-10` `vehicles/registry/_form.html.erb:85` spacing: A sub-group divider is mt-4 pt-3 border-t border-line; disclosure uses hr.my-4.border-base-300.

**`helpers/admin/action_logs_helper.rb`** (used by 1)

- **low** `EMPTY-02` `helpers/admin/action_logs_helper.rb:60` typography: Rule: an empty value prints "—". Code: person_display_link blank: "-" and a blank message print a hyphen (lines 60, 131).

**`helpers/admin/request_logs_helper.rb`** (used by 1)

- **low** `EMPTY-02` `helpers/admin/request_logs_helper.rb:52` typography: Rule: an empty value prints "—". Code: a missing client IP prints "-".

**`helpers/bmid/manage_helper.rb`** (used by 1)

- **low** `COPY-04` `helpers/bmid/manage_helper.rb:309` buttons: Rule: opening a create form says "Add X". Code: Add case (no provisions, links to new form) still shows visible word "Manage"; only sr-only text and title say Add. Built via button_link (BTN-01 fine).

**`helpers/scheduling/early_arrivals_helper.rb`** (used by 1)

- **medium** `TYPE-03` `helpers/scheduling/early_arrivals_helper.rb:130` typography: text-sm is never for table content; radio lines in the Radios cell are text-sm (not text-xs, so TYPE-02 does not apply).

**`helpers/scheduling/sandman_qualified_helper.rb`** (used by 1)

- **high** `STAT-01` `helpers/scheduling/sandman_qualified_helper.rb:89` spacing: Summary tiles go in ui_stat_row; this lookup feeds the hand-rolled lg:grid-cols-4/5/6 scoreboard grid.

**`helpers/scheduling/shift_coverage_helper.rb`** (used by 1)

- **medium** `TYPE-03` `helpers/scheduling/shift_coverage_helper.rb:100` typography: text-sm is never for table content; the shift window time inside a coverage cell is text-sm.

**`helpers/shift_operations/mass_signout_helper.rb`** (used by 1)

- **low** `COLOR-05` `helpers/shift_operations/mass_signout_helper.rb:24` icons: A status icon takes icon-error; this one is coloured with text-error (the bulk preview uses icon-error for the same icon and meaning).

**`helpers/vehicles/paperwork_helper.rb`** (used by 1)

- **medium** `TYPE-03` `helpers/vehicles/paperwork_helper.rb:134` typography: text-sm only for secondary content; the detail-row body (teams, positions, sign-ups that explain eligibility) is primary content set in text-sm.
- **low** `EMPTY-02` `helpers/vehicles/paperwork_helper.rb:157` empty-loading: An empty value prints the em dash; helper prints italic "- none -" (lines 157, 178).

**`admin/action_logs/_live.html.erb`** (used by 1)

- **medium** `TYPE-03` `admin/action_logs/_live.html.erb:48` typography: Rule: table content is text-base. Code: t.body class: log_text_class sets the whole Live table body in text-sm.

**`admin/permissions/_row.html.erb`** (used by 1)

- **medium** `TYPE-03` `admin/permissions/_row.html.erb:7` typography: Rule: table content is text-base. Code: ID cell text-sm (line 7); lines 37, 41 text-sm block labels in the detail row.
- **low** `TYPE-06` `admin/permissions/_row.html.erb:7` typography: Rule: no mono for ordinary table text. Code: font-mono on the numeric ID cell; lines 37, 41 are font-semibold labels.

**`admin/request_logs/_live_rows.html.erb`** (used by 1)

- **medium** `TYPE-03` `admin/request_logs/_live_rows.html.erb:8` tables-lists: Rule: table content is text-base. Code: every Live cell takes log_text_class (text-sm) (lines 8, 9, 12).

**`alerts/_alert_group.html.erb`** (used by 1)

- **medium** `BP-01` `alerts/_alert_group.html.erb:10` spacing: pattern=spacing sm: is allowed only in a field width:; the legend switches from column to row at sm:, creating an extra layout tier.
- **medium** `FORM-01` `alerts/_alert_group.html.erb:53` forms: pattern=forms fields come from AppFormBuilder; the disabled SMS checkbox is a raw <input> borrowing CHECKBOX_CLASSES (32,71,90 are hidden fields, not judged).
- **medium** `FORM-01` `alerts/_alert_group.html.erb:73` forms: Forms use AppFormBuilder fields; per-alert SMS/Email checkboxes are tag.input + raw <label> with the builder's CHECKBOX_CLASSES, looking the same.
- **medium** `HELP-02` `alerts/_alert_group.html.erb:8` other: A legend goes in one collapsed ui_disclosure card per page, never inside a ui_section; the channel legend box sits inside each group's section, so it renders twice.

**`bmid/export/_previous_exports.html.erb`** (used by 1)

- **low** `MODAL-02` `bmid/export/_previous_exports.html.erb:48` modals: Rule: a confirm says whether it can be undone. Code: Un-Submit confirm lists effects (batch record and CSV removed) but never says whether the removal can be undone.

**`bmid/manage/_table.html.erb`** (used by 1)

- **high** `BTN-06` `bmid/manage/_table.html.erb:35` links: Rule: edit_link is the one edit control. Code: per-row "Edit" is a link_to with TABLE_LINK_CLASSES, a text link rather than the secondary pen-to-square button.

**`bmid/provisions/_list.html.erb`** (used by 1)

- **medium** `MODAL-01` `bmid/provisions/_list.html.erb:32` spacing: Rule: modals use m.footer with a button_row and modal_close_button. Code: Add and Close buttons sit in a div mt-4 button_row inside m.body; no m.footer.

**`bmid/titles/_cell.html.erb`** (used by 1)

- **medium** `FORM-01` `bmid/titles/_cell.html.erb:7` forms: Rule: builder fields only. Code: select_tag and text_field_tag with builder class constants, aria-label only and no visible label (FORM-02 also unmet).
- **medium** `FORM-01` `bmid/titles/_cell.html.erb:20` forms: Rule: builder fields only. Code: raw text_field_tag borrowing INPUT_CLASSES.

**`common/_trophies.html.erb`** (used by 1)

- **medium** `CARD-01` `common/_trophies.html.erb:15` cards: Rule: a card is card-standard via ui_card. Trophy card is a hand-made `border rounded p-2` div with no border colour token.
- **medium** `COLOR-02` `common/_trophies.html.erb:9` icons: Rule: no coloured backgrounds without semantic purpose. An award icon (not a status) sits on bg-warning/10 with a ring, drawn twice per trophy.
- **medium** `COLOR-05` `common/_trophies.html.erb:9` icons: Rule: icons are neutral unless they convey status. The decorative award icon takes icon-warning.
- **medium** `EMPTY-01` `common/_trophies.html.erb:4` empty-loading: Rule: always ui_empty_state. Trophies hand-write <div class="empty-state text-lg" role="status"> (the helper's class, applied by hand).
- **medium** `TYPE-03` `common/_trophies.html.erb:26` typography: Rule: never text-sm for labels or empty messages. "Service Years" label (26) and "no service years recorded" (29) are text-sm; text-lg uses are fine.
- **medium** `TYPE-04` `common/_trophies.html.erb:21` typography: Rule: nothing inside a section outweighs its title. Trophy years are text-lg font-bold text-heading under an h3.heading-title (text-base semibold); title text-lg too.
- **low** `EMPTY-02` `common/_trophies.html.erb:29` empty-loading: Rule: an empty value prints "—". Missing service years print italic "no service years recorded".

**`communication/announcements/_announcement.html.erb`** (used by 1)

- **medium** `STYLE-03` `communication/announcements/_announcement.html.erb:43` cards: No ad-hoc wrapper doing a helper's job; the message is a hand-made bordered, rounded, tinted, padded scroll box inside the card.

**`communication/rbs/_type_card.html.erb`** (used by 1)

- **medium** `BTN-04` `communication/rbs/_type_card.html.erb:13` buttons: One primary action per view; the launchpad gives every card a Start button, five of them :primary (secondary types mapped to :primary) beside :error and :warning ones.
- **medium** `BTN-05` `communication/rbs/_type_card.html.erb:13` buttons: :error is for destructive actions; "Start" (not destructive) takes the card's severity colour, red :error for emergency, amber :warning for on-shift.

**`communication/rbs_broadcasts/_audience_fields.html.erb`** (used by 1)

- **medium** `FORM-01` `communication/rbs_broadcasts/_audience_fields.html.erb:37` forms: Labels come from the builder; a raw <label> with LABEL_CLASSES titles a checkbox grid it is not associated with.
- **medium** `FORM-04` `communication/rbs_broadcasts/_audience_fields.html.erb:46` forms: Help text is the field's help_text: tied by aria-describedby; this help line is a hand-written <p> not linked to the checkbox group.
- **medium** `FORM-05` `communication/rbs_broadcasts/_audience_fields.html.erb:37` forms: Checkbox groups are grouped with f.fieldset; Account status and Attendance use a raw label/span with LABEL_CLASSES plus role=group (37,64).
- **low** `FORM-10` `communication/rbs_broadcasts/_audience_fields.html.erb:13` spacing: Sub-groups are divided with mt-4 pt-3 border-t border-line; 13 and 36 use mt-3 while 53 and 63 use mt-4.

**`communication/rbs_broadcasts/_notices.html.erb`** (used by 1)

- **low** `COPY-03` `communication/rbs_broadcasts/_notices.html.erb:7` toasts-alerts: Callout titles are Title Case; the emergency callout title reads "Use only in an emergency".

**`communication/rbs_broadcasts/_position_checkboxes.html.erb`** (used by 1)

- **medium** `FORM-05` `communication/rbs_broadcasts/_position_checkboxes.html.erb:7` forms: Checkbox groups are grouped with f.fieldset; the Positions group is labelled by a span with LABEL_CLASSES mb-0 and role=group.
- **medium** `STYLE-03` `communication/rbs_broadcasts/_position_checkboxes.html.erb:16` cards: No ad-hoc wrapper doing a helper's job; the checkbox list sits in a hand-made bordered, rounded, padded scroll box.

**`communication/surveys/_group_actions.html.erb`** (used by 1)

- **medium** `BTN-04` `communication/surveys/_group_actions.html.erb:3` buttons: One primary action per view; every group header has a :primary "Add Question", alongside the page's :primary "Add Group".

**`hq/shift_manage/_asset_table.html.erb`** (used by 1)

- **medium** `BTN-04` `hq/shift_manage/_asset_table.html.erb:36` buttons: One primary action per view; every checked-out row has a :primary Check In button beside the section's checkout form submit.

**`hq/shift_manage/_correction_modal.html.erb`** (used by 1)

- **low** `COPY-04` `hq/shift_manage/_correction_modal.html.erb:31` typography: Never Submit for a form submit; modal title Submit Timesheet Correction (line 7) and button Submit Correction (line 31).

**`hq/shift_manage/_other_entries.html.erb`** (used by 1)

- **low** `FORM-10` `hq/shift_manage/_other_entries.html.erb:11` cards: A sub-group divider is mt-4 pt-3 border-t border-line; this block uses mt-6 pt-4 border-t border-base-300.

**`hq/shift_manage/_pogs.html.erb`** (used by 1)

- **medium** `BTN-04` `hq/shift_manage/_pogs.html.erb:48` buttons: One primary action per view; three Record pog buttons are all :primary (48, 52, 57) plus a :primary Redeem in each eligible row (99).
- **low** `MODAL-02` `hq/shift_manage/_pogs.html.erb:104` modals: Confirm asks with the action and says whether it can be undone; message reads Confirm you want to redeem this 1/2 Meal Pog, no question or undo statement.

**`hq/shift_manage/_section.html.erb`** (used by 1)

- **medium** `DISC-01` `hq/shift_manage/_section.html.erb:30` cards: Collapsible content is ui_accordion or ui_disclosure; HQ sections hand-build details.collapse collapse-arrow with border, surface and open-state classes.
- **medium** `TYPE-05` `hq/shift_manage/_section.html.erb:31` typography: Heading hierarchy is h1 > h2 > h3; HQ section titles are summary text with no heading element, so h3s inside them (_other_entries, _provision_info) follow the h1 directly.

**`hq/shift_manage/_todo_chip.html.erb`** (used by 1)

- **medium** `ICON-01` `hq/shift_manage/_todo_chip.html.erb:20` icons: Icons are drawn by fa_icon; chip glyph classes are fa-solid/fa-regular literals rendered in a raw i tag (lines 20, 23, 26, 32).
- **medium** `ICON-01` `hq/shift_manage/_todo_chip.html.erb:32` icons: Raw i element with literal FontAwesome classes instead of fa_icon.

**`hq/shift_manage/_todo_list.html.erb`** (used by 1)

- **medium** `CARD-01` `hq/shift_manage/_todo_list.html.erb:23` other: Card-like container should be card-standard via ui_card; checklist panel is a hand-made div with p-5 bg-base-200 shadow-lg.
- **medium** `ICON-01` `hq/shift_manage/_todo_list.html.erb:65` icons: Raw i icon cloned by JS; fa_icon could render the same template markup.
- **medium** `SHADOW-01` `hq/shift_manage/_todo_list.html.erb:23` spacing: Flat by default, a new component gets no shadow; the sticky checklist panel carries shadow-lg.

**`hq/shift_manage/_verification.html.erb`** (used by 1)

- **low** `COPY-04` `hq/shift_manage/_verification.html.erb:92` buttons: Never Submit; the row button opening the correction dialog reads Submit Correction.

**`hq/site_registration/_radio_authorization_status.html.erb`** (used by 1)

- **low** `COPY-03` `hq/site_registration/_radio_authorization_status.html.erb:11` typography: Headings are Title Case labels, not sentences; h3s at lines 11, 15, 26, 30, 36 are sentences or sentence case (Shift radios only).

**`hq/site_registration/_radios_step.html.erb`** (used by 1)

- **medium** `TOAST-01` `hq/site_registration/_radios_step.html.erb:11` toasts-alerts: Action outcomes are flash toasts rendered by the layout; the radios step receives notice/notice_type locals and prints the outcome as an inline callout inside the wizard dialog.

**`me/announcements/_announcement.html.erb`** (used by 1)

- **medium** `CARD-01` `me/announcements/_announcement.html.erb:17` cards: One card utility rendered by ui_card; announcement is a hand-made div with rounded-lg p-4 bg-base-200 border and role article

**`me/dashboard/_announcements_section.html.erb`** (used by 1)

- **medium** `BADGE-01` `me/dashboard/_announcements_section.html.erb:15` other: Badges come from ui_badge; unread count is a hand-made rounded-full bg-warning span
- **medium** `BTN-01` `me/dashboard/_announcements_section.html.erb:56` buttons: Never the btn classes by hand; a span inside the row link wears button_classes btn-outline pointer-events-none to look like a button
- **medium** `CARD-01` `me/dashboard/_announcements_section.html.erb:9` cards: One card utility rendered by ui_card with p-4; code writes card-standard on a raw div with p-3

**`me/dashboard/_onboarding.html.erb`** (used by 1)

- **low** `COPY-03` `me/dashboard/_onboarding.html.erb:67` modals: Title Case lowercases articles; tour step title is "File A Bug Report"

**`me/menu/_content.html.erb`** (used by 1)

- **medium** `TABS-01` `me/menu/_content.html.erb:20` navigation: Tabs come from tab_navigation; mobile tab bar and desktop side nav are custom mega-menu-tabs/mega-menu-side switches
- **low** `COPY-03` `me/menu/_content.html.erb:22` buttons: Button labels are Title Case; mega_chrome_button "Recently visited" (lines 22, 30)
- **low** `COPY-04` `me/menu/_content.html.erb:90` buttons: Leaving goes "Back to X"; the mobile back control is labelled "Categories" with a chevron
- **low** `FORM-02` `me/menu/_content.html.erb:4` forms: Every field has a visible label, never placeholder-only; menu search has an sr-only label and a visible placeholder
- **low** `TYPE-04` `me/menu/_content.html.erb:40` typography: h3/h4 take heading-title; mega menu uses custom mega-menu-panel-title and mega-menu-section-title classes
- **low** `TYPE-04` `me/menu/_content.html.erb:66` typography: <h4> takes heading-title; uses custom mega-menu-section-title

**`me/operational_summary/_basic_driving.html.erb`** (used by 1)

- **medium** `TYPE-03` `me/operational_summary/_basic_driving.html.erb:15` typography: text-sm never for paragraph content; the permit requirement is a text-sm paragraph

**`me/operational_summary/_mvr.html.erb`** (used by 1)

- **medium** `TYPE-03` `me/operational_summary/_mvr.html.erb:7` typography: text-sm never for paragraph content; the "Required:" permit note (7) and the approval instruction (26) are text-sm paragraphs

**`me/operational_summary/_provisions_and_radios.html.erb`** (used by 1)

- **medium** `TYPE-03` `me/operational_summary/_provisions_and_radios.html.erb:30` typography: text-sm never for paragraph content; shower location and hours (primary info) are a text-sm paragraph
- **low** `COPY-01` `me/operational_summary/_provisions_and_radios.html.erb:26` typography: pattern=typography Never "work"/"working" for volunteering; copy says "every 40 hours worked during event week"

**`me/operational_summary/_teams_and_positions.html.erb`** (used by 1)

- **medium** `STYLE-03` `me/operational_summary/_teams_and_positions.html.erb:30` cards: Use the helper where one exists; hand-made rounded-box bg-base-200 padded bar holds a label and document buttons
- **medium** `TYPE-03` `me/operational_summary/_teams_and_positions.html.erb:31` typography: text-sm never for labels; the "Team documents" label is text-sm

**`me/surveys/_question.html.erb`** (used by 1)

- **medium** `FORM-03` `me/surveys/_question.html.erb:17` validation: Required fields are marked through required: (asterisk + sr text); radio groups append a red "required" ui_badge into the label instead

**`me/vehicles_dashboard/_mvr_status_eligible.html.erb`** (used by 1)

- **medium** `TYPE-03` `me/vehicles_dashboard/_mvr_status_eligible.html.erb:8` typography: text-sm never for labels or paragraphs; the "Deadline" label (8), "days left" label (21) and the Tip paragraph (30) are text-sm

**`mentoring/alpha_pods/_pod_card.html.erb`** (used by 1)

- **high** `TOUCH-01` `mentoring/alpha_pods/_pod_card.html.erb:54` links: Interactive elements have a 36px target (min-h-9); member links use min-h-8 (32px) and are not the TABLE_LINK_CLASSES exception.
- **medium** `BTN-05` `mentoring/alpha_pods/_pod_card.html.erb:94` buttons: Destructive actions take :error; "Delete Pod" delete_button is passed variant: :ghost (its confirm button stays red).
- **medium** `TYPE-03` `mentoring/alpha_pods/_pod_card.html.erb:41` typography: text-sm never for empty-state messages; the empty-group message is text-sm (41); line 50 sizes only the list marker.
- **low** `EMPTY-01` `mentoring/alpha_pods/_pod_card.html.erb:41` empty-loading: An empty state uses ui_empty_state; an empty group prints p "text-sm text-stone-muted" "No GROUP yet."
- **low** `FORM-10` `mentoring/alpha_pods/_pod_card.html.erb:24` cards: A sub-group divider is "mt-4 pt-3 border-t border-line"; pod groups use "border-t border-base-300 pt-2 mt-2" with first: resets.

**`mentoring/alpha_pods/people/_pool.html.erb`** (used by 1)

- **medium** `BP-01` `mentoring/alpha_pods/people/_pool.html.erb:19` spacing: pattern=spacing sm: only in a field width:; the candidate list uses "grid-cols-1 sm:grid-cols-2", a layout tier below the lg fold.
- **medium** `TYPE-03` `mentoring/alpha_pods/people/_pool.html.erb:16` typography: text-sm never for empty-state messages; the empty pool message is text-sm (16); line 39 is candidate metadata, an allowed use.
- **low** `EMPTY-01` `mentoring/alpha_pods/people/_pool.html.erb:16` empty-loading: An empty state uses ui_empty_state; an empty pool prints p "text-sm text-stone-muted", or nothing when empty is nil.

**`mentoring/alpha_schedule/rosters/_dialog.html.erb`** (used by 1)

- **medium** `BTN-04` `mentoring/alpha_schedule/rosters/_dialog.html.erb:51` buttons: One clear primary action per view; Search and every result row's "Add CALLSIGN" submit_button default to primary.
- **medium** `EMPTY-01` `mentoring/alpha_schedule/rosters/_dialog.html.erb:62` validation: An empty result uses ui_empty_state; no match prints p "text-error font-semibold", error colour for an empty search.
- **medium** `FORM-01` `mentoring/alpha_schedule/rosters/_dialog.html.erb:19` forms: Fields come from the builder; the search has a raw label and a text_field_tag with INPUT_CLASSES in a hand flex row, inside a builder form.
- **medium** `TYPE-03` `mentoring/alpha_schedule/rosters/_dialog.html.erb:54` typography: text-sm never for table content; "Not an Alpha or Prospective" in the Add column is text-sm.

**`mentoring/alphas_convert/_section.html.erb`** (used by 1)

- **medium** `MODAL-02` `mentoring/alphas_convert/_section.html.erb:85` modals: A destructive confirm is red; the bonk confirm (index 102-105) passes no variant: :error, so "Bonk Alphas" is a primary button.

**`mentoring/shift_report/_group_positions.html.erb`** (used by 1)

- **low** `EMPTY-01` `mentoring/shift_report/_group_positions.html.erb:8` empty-loading: An empty state uses ui_empty_state; three empty cases print muted p sentences (8, 12-14, 27).

**`person/_contact_details.html.erb`** (used by 1)

- **low** `EMPTY-02` `person/_contact_details.html.erb:9` empty-loading: EMPTY-02 says an empty value prints "—"; Camp and Emergency Contact print italic muted "None" / "None stated" (lines 9, 26)

**`person/_hero.html.erb`** (used by 1)

- **medium** `HERO-02` `person/_hero.html.erb:6` other: HERO-02 says the description is one sentence saying what the page does; the person overview's description holds badges, name, pronouns and pronunciation in a flex row

**`person/_summary_group_heading.html.erb`** (used by 1)

- **medium** `TYPE-04` `person/_summary_group_heading.html.erb:4` typography: TYPE-04 gives h3 one style (heading-title); this h3 adds a bottom rule (border-b border-line pb-1) and text-heading-primary colour, so it differs from every other h3

**`person/_summary_strip.html.erb`** (used by 1)

- **high** `TOUCH-01` `person/_summary_strip.html.erb:13` links: TOUCH-01 sets a 36px floor (min-h-9); the email and phone links use "inline-flex items-center min-h-7" (28px), lines 13, 22
- **low** `EMPTY-02` `person/_summary_strip.html.erb:25` empty-loading: EMPTY-02 says an empty value prints "—"; missing phone, years and former callsigns print italic muted "None" (lines 25, 51, 62, 72, 94)

**`person/_teams_positions.html.erb`** (used by 1)

- **medium** `TYPE-03` `person/_teams_positions.html.erb:9` tables-lists: TYPE-03: text-sm never for main content; team and position names render as text-sm divs in lg:columns-2 inside the accordions (lines 9, 26)

**`person/awards/_awards_table.html.erb`** (used by 1)

- **medium** `BTN-04` `person/awards/_awards_table.html.erb:5` buttons: BTN-04 wants one primary action per view; each of the three award sections renders its own :primary "Grant ... award" button

**`person/memberships/_position_checkbox.html.erb`** (used by 1)

- **medium** `FORM-01` `person/memberships/_position_checkbox.html.erb:6` forms: FORM-01: builder fields only; raw check_box_tag "position_ids[]" with the builder's checkbox classes instead of a builder field
- **medium** `FORM-01` `person/memberships/_position_checkbox.html.erb:13` forms: FORM-01: raw label "inline-flex items-center min-h-9 min-w-9 font-medium text-heading cursor-pointer" built by hand instead of the builder's label
- **medium** `NAV-01` `person/memberships/_position_checkbox.html.erb:31` navigation: NAV-01 says a dropdown is dropdown_menu with dropdown_item; the permissions menu fills it with raw li.menu-title and li span items, plus class overrides
- **medium** `TYPE-03` `person/memberships/_position_checkbox.html.erb:12` typography: TYPE-03 bans text-sm on form labels; the span wrapping each position's label and its markers is text-sm (icon text-xs at 15, 18, 21 is icon sizing)

**`person/memberships/_position_group.html.erb`** (used by 1)

- **medium** `TYPE-03` `person/memberships/_position_group.html.erb:3` typography: TYPE-03 bans text-sm on labels a reader needs; the position group title (e.g. "Optional Positions ...") is a div text-sm

**`person/memberships/_team_card.html.erb`** (used by 1)

- **medium** `BTN-04` `person/memberships/_team_card.html.erb:81` buttons: BTN-04 wants one primary action per view; every team card and the General Positions card (edit.html.erb 40) has its own primary submit_button "Save"
- **medium** `FORM-01` `person/memberships/_team_card.html.erb:11` forms: FORM-01: raw check_box_tag for team and manager with raw labels (17, 46) instead of builder fields
- **medium** `FORM-01` `person/memberships/_team_card.html.erb:17` forms: FORM-01: raw <label for> elements (17, 46) with hand-written classes in place of builder labels
- **medium** `FORM-01` `person/memberships/_team_card.html.erb:40` forms: pattern=forms manager checkbox is check_box_tag with CHECKBOX_CLASSES rather than a builder field
- **medium** `NAV-01` `person/memberships/_team_card.html.erb:28` navigation: NAV-01 says a dropdown is dropdown_menu with dropdown_item; the team's permission menu holds raw li.menu-title and li span items (28-30)
- **medium** `TYPE-03` `person/memberships/_team_card.html.erb:46` typography: TYPE-03 bans text-sm on form labels and empty-state messages; "Is Team Manager" label (46) and "Team does not have any positions." (77) are text-sm
- **low** `EMPTY-01` `person/memberships/_team_card.html.erb:77` empty-loading: EMPTY-01 says an empty state is always ui_empty_state; "Team does not have any positions." is p "text-sm italic text-stone-muted"

**`person/timesheets/_entries_table.html.erb`** (used by 1)

- **medium** `MODAL-02` `person/timesheets/_entries_table.html.erb:55` modals: MODAL-02 says a destructive confirm is red and says whether it can be undone; End Shift is an :error button but its confirm_modal passes no variant and says nothing about undoing
- **medium** `TABLE-03` `person/timesheets/_entries_table.html.erb:1` tables-lists: TABLE-03 says table content is text-base; the entries table passes size: "sm", which TableHelper turns into text-sm on the whole table

**`person/timesheets/_missing_requests_table.html.erb`** (used by 1)

- **medium** `BTN-05` `person/timesheets/_missing_requests_table.html.erb:21` buttons: BTN-05 gives :primary to primary actions; every row's Edit and View button is :primary (21, 25), while the entries table uses :secondary for the same actions

**`person/unified_flagging/_training_notes.html.erb`** (used by 1)

- **medium** `TYPE-03` `person/unified_flagging/_training_notes.html.erb:51` typography: TYPE-03 bans text-sm on paragraph content; the feedback-delivered statement is p "mt-2 text-sm" (text-sm on the 34 metadata line is allowed)
- **low** `EMPTY-01` `person/unified_flagging/_training_notes.html.erb:48` empty-loading: EMPTY-01 says an empty state is always ui_empty_state; "No training notes." is a plain p "text-body"

**`profile/_alerts.html.erb`** (used by 1)

- **medium** `STYLE-03` `profile/_alerts.html.erb:35` tables-lists: Use the helper where one exists; group header rows are raw <tr><td colspan=3 class="px-3 py-2 font-semibold ... bg-base-200"> inside ui_table bodies (35, 76) instead of t.row/t.cell.

**`profile/_bmid.html.erb`** (used by 1)

- **medium** `BTN-04` `profile/_bmid.html.erb:26` buttons: One primary action per view; "Adjust" is :primary in the BMID section while profile/show:161 "My Information Is Correct" is also :primary when both show.
- **medium** `BTN-05` `profile/_bmid.html.erb:20` buttons: :error is the destructive variant; Withdraw (DELETE, confirmed with variant :error) is a :warning button_link.

**`profile/_camp.html.erb`** (used by 1)

- **low** `EMPTY-02` `profile/_camp.html.erb:11` empty-loading: Empty value prints "—"; empty camp location prints none_stated, an italic "None stated".

**`profile/_clothing.html.erb`** (used by 1)

- **low** `EMPTY-02` `profile/_clothing.html.erb:10` empty-loading: Empty value prints "—"; missing shirt choices print italic "None stated" via none_stated (10, 14, 18).

**`profile/_emergency_contact.html.erb`** (used by 1)

- **low** `EMPTY-02` `profile/_emergency_contact.html.erb:6` empty-loading: Empty value prints "—"; missing emergency contact prints italic "None stated".

**`profile/_identity_info.html.erb`** (used by 1)

- **low** `EMPTY-02` `profile/_identity_info.html.erb:37` empty-loading: Empty value prints "—"; missing values print italic "no preferred first name given" (29) and "not stated" (37, 47).
- **low** `TYPE-04` `profile/_identity_info.html.erb:8` typography: Nothing inside a section outweighs its title; callsign div "text-lg font-semibold" exceeds the text-base section title below lg.

**`profile/_languages.html.erb`** (used by 1)

- **low** `EMPTY-01` `profile/_languages.html.erb:33` empty-loading: Empty state is always ui_empty_state; no languages shows a plain muted span (profile_languages/index uses ui_empty_state for the same text).

**`profile/_mailing_address.html.erb`** (used by 1)

- **low** `EMPTY-02` `profile/_mailing_address.html.erb:25` empty-loading: Empty value prints "—"; missing address prints italic "None stated".

**`scheduling/shift_lead/_below_min.html.erb`** (used by 1)

- **low** `COPY-03` `scheduling/shift_lead/_below_min.html.erb:21` typography: Headings and table headings are Title Case; column heading "Signed up"/"On duty" (21, 48) and heading "N positions below minimum" (41) are sentence case.

**`scheduling/shift_lead/_callsign.html.erb`** (used by 1)

- **low** `COLOR-05` `scheduling/shift_lead/_callsign.html.erb:7` icons: A status icon takes icon-error; the not-on-site ban icon uses text-error (it does carry label:).

**`scheduling/shift_lead/_picker.html.erb`** (used by 1)

- **medium** `FORM-01` `scheduling/shift_lead/_picker.html.erb:37` forms: Forms use the builder; picker is form_tag + label_tag with hand classes + select_tag borrowing SELECT_CLASSES (37-46).
- **medium** `FORM-01` `scheduling/shift_lead/_picker.html.erb:42` forms: Builder fields only; select_tag borrows SELECT_CLASSES instead of f.select.
- **low** `COPY-03` `scheduling/shift_lead/_picker.html.erb:32` typography: Headings are Title Case; the disclosure heading reads "Shift period".

**`scheduling/shift_lead/_roster.html.erb`** (used by 1)

- **high** `TABLE-02` `scheduling/shift_lead/_roster.html.erb:92` tables-lists: ui_table's own fold is the narrow strategy; phones get a hand-built rounded-box border divide-y list with striped divs, unlike every sibling table.
- **medium** `TABLE-02` `scheduling/shift_lead/_roster.html.erb:36` tables-lists: ui_table stays responsive except listed cases; the ten-column roster passes responsive: false and is hidden below lg, replaced by a hand-built list.
- **medium** `TYPE-03` `scheduling/shift_lead/_roster.html.erb:107` typography: text-sm never for primary card information; card lines for years, details and positions use text-sm.
- **medium** `TYPE-03` `scheduling/shift_lead/_roster.html.erb:114` typography: text-sm never for primary card information; phone roster years, pronouns/gender, positions and certifications are text-sm (97, 107, 114, 117).
- **low** `EMPTY-02` `scheduling/shift_lead/_roster.html.erb:58` typography: An empty value prints "—"; pronouns, gender and positions print "-" (58, 59, 64).
- **low** `ICON-04` `scheduling/shift_lead/_roster.html.erb:72` icons: An icon explained only in the card carries fa_icon label:; the award icon marking a certification has no label (72, 118).

**`scheduling/shift_lead/_sort_control.html.erb`** (used by 1)

- **medium** `FORM-01` `scheduling/shift_lead/_sort_control.html.erb:16` forms: Forms use the builder; sort control is form_tag + label_tag + select_tag with SELECT_CLASSES.
- **medium** `FORM-01` `scheduling/shift_lead/_sort_control.html.erb:23` forms: label_tag stands in for a builder label.
- **medium** `TYPE-03` `scheduling/shift_lead/_sort_control.html.erb:24` typography: text-sm never for form labels; the "Sort by" label is text-sm text-stone-muted inline.

**`scheduling/shift_lead/_status_band.html.erb`** (used by 1)

- **medium** `CARD-01` `scheduling/shift_lead/_status_band.html.erb:13` cards: card-standard is rendered by ui_card with no shadow; the band is a raw div card-standard p-2 shadow-xs lg:p-3.
- **medium** `STAT-01` `scheduling/shift_lead/_status_band.html.erb:27` cards: Summary tiles go in ui_stat_row; six size :sm tiles sit in a hand grid grid-cols-3 lg:grid-cols-6 gap-2.
- **low** `SHADOW-01` `scheduling/shift_lead/_status_band.html.erb:13` spacing: Flat by default, no shadow on a component; the status band adds shadow-xs.

**`sessions/_password_form.html.erb`** (used by 1)

- **medium** `BTN-05` `sessions/_password_form.html.erb:62` buttons: :primary for primary actions, :warning for warning actions; Sign In submit is :warning lg (amber), consistent across door pages.
- **low** `COLOR-05` `sessions/_password_form.html.erb:17` icons: Icons are neutral unless status; field icons use icon_class "... text-warning" (17, 43).
- **low** `FORM-07` `sessions/_password_form.html.erb:7` forms: Field widths fit their content (email w-full sm:w-72); email and password fields fill the column with no width: (login-input).

**`sessions/_sso_door.html.erb`** (used by 1)

- **medium** `BTN-05` `sessions/_sso_door.html.erb:10` buttons: Primary action takes :primary; "Sign In with the Ranger Clubhouse" is :warning lg with login-submit-button.

**`shift_operations/cruise_direction/_board.html.erb`** (used by 1)

- **low** `COPY-04` `shift_operations/cruise_direction/_board.html.erb:33` empty-loading: pattern=empty-loading Rule: "Add X" opens a create form, never "Create"; empty state says "Use Create pod" while the button reads "Add Pod".

**`shift_operations/cruise_direction/_pickers.html.erb`** (used by 1)

- **medium** `FORM-01` `shift_operations/cruise_direction/_pickers.html.erb:19` forms: Forms use AppFormBuilder; picker is form_tag + label_tag + select_tag with AppFormBuilder::SELECT_CLASSES, auto-submitting.
- **medium** `FORM-01` `shift_operations/cruise_direction/_pickers.html.erb:27` forms: select_tag in place of f.select, styled with SELECT_CLASSES.

**`shift_operations/cruise_direction/_pod.html.erb`** (used by 1)

- **low** `EMPTY-01` `shift_operations/cruise_direction/_pod.html.erb:51` empty-loading: Empty collection should be ui_empty_state; empty pod is a muted italic <p> "No one is in this pod yet." ("No location yet" states a fact).

**`shift_operations/cruise_direction/_stats.html.erb`** (used by 1)

- **medium** `STAT-01` `shift_operations/cruise_direction/_stats.html.erb:12` other: Summary tiles go in ui_stat_row; these ui_stat_box tiles sit in a hand-rolled "flex flex-row flex-wrap gap-2 lg:gap-4" div.

**`shift_operations/cruise_direction/people/_dialog.html.erb`** (used by 1)

- **medium** `TYPE-03` `shift_operations/cruise_direction/people/_dialog.html.erb:42` typography: text-sm never for paragraphs; the explanatory sentence in the fold is a text-sm <p>.
- **low** `EMPTY-01` `shift_operations/cruise_direction/people/_dialog.html.erb:32` empty-loading: Empty collection should be ui_empty_state; empty current pool is <p class="text-stone-muted">.

**`shift_operations/cruise_direction/people/_pool.html.erb`** (used by 1)

- **medium** `BP-01` `shift_operations/cruise_direction/people/_pool.html.erb:11` spacing: pattern=spacing sm: only in a field width:; candidate list uses sm:grid-cols-2, a column tier below lg.

**`shift_operations/cruise_direction/pods/_dialog.html.erb`** (used by 1)

- **low** `COPY-03` `shift_operations/cruise_direction/pods/_dialog.html.erb:51` buttons: Button labels are Title Case; the delete button reads "Delete pod".
- **low** `FORM-10` `shift_operations/cruise_direction/pods/_dialog.html.erb:30` spacing: Sub-section divider is mt-4 pt-3 border-t border-line; this uses border-base-300.

**`teams_positions/position_sanity_checker/_results.html.erb`** (used by 1)

- **medium** `TYPE-05` `teams_positions/position_sanity_checker/_results.html.erb:14` toasts-alerts: Rule says clear heading hierarchy; the page-level "N repairs made" callout title (and "Nothing Was Selected", 56) render as h4 directly under the h1.
- **low** `COLOR-05` `teams_positions/position_sanity_checker/_results.html.erb:30` icons: Rule says a status icon takes icon-success; the success line's circle-check uses fa_icon class "text-success".

**`ticketing/access_documents/_summary_legend.html.erb`** (used by 1)

- **medium** `BP-01` `ticketing/access_documents/_summary_legend.html.erb:13` spacing: pattern=spacing Rule: sm: only inside a field width:. Code: legend grid "grid-cols-1 sm:grid-cols-2 lg:grid-cols-3" creates an extra sm layout tier.

**`ticketing/bulk_access_documents/_consequence.html.erb`** (used by 1)

- **medium** `A11Y-01` `ticketing/bulk_access_documents/_consequence.html.erb:15` toasts-alerts: Rule: status never by colour alone. Code: info callout identifies duplicate rows only as "the amber ones above"; whether those rows also carry an icon is in common/bulk_upload/preview, outside scope.

**`ticketing/bulk_access_documents/_formats.html.erb`** (used by 1)

- **medium** `HELP-02` `ticketing/bulk_access_documents/_formats.html.erb:12` spacing: Rule: one collapsed ui_disclosure card per page. Code: partial adds two format cards in a div "space-y-2 mb-4".
- **medium** `LIST-01` `ticketing/bulk_access_documents/_formats.html.erb:16` typography: Rule: instructional content is a Q&A dl.instruction-list, not paragraphs. Code: format rules as three paragraphs with strong leads (16, 43, 49) inside the card.

**`ticketing/statistics/_pipeline_card.html.erb`** (used by 1)

- **medium** `CARD-01` `ticketing/statistics/_pipeline_card.html.erb:23` cards: Rule: the card utility is rendered by ui_card. Code: hand div "card-standard p-4" as the card container.
- **low** `STYLE-01` `ticketing/statistics/_pipeline_card.html.erb:33` other: pattern=other Rule: no inline style= attribute. Code: segment width set by style="width: N%" holding a computed number.

**`timesheets/correction_stats/_decision_card.html.erb`** (used by 1)

- **low** `EMPTY-01` `timesheets/correction_stats/_decision_card.html.erb:60` empty-loading: Empty state should be ui_empty_state; zero total prints a plain muted <p>.
- **low** `STYLE-01` `timesheets/correction_stats/_decision_card.html.erb:30` other: pattern=other No inline style=; segment width is an inline style holding a computed percent (CSS rules route it through a custom property).

**`timesheets/correction_stats/_top_list.html.erb`** (used by 1)

- **low** `EMPTY-01` `timesheets/correction_stats/_top_list.html.erb:23` empty-loading: Empty collection should be ui_empty_state; empty leaderboard is a plain muted <p> "None this year."

**`timesheets/early_late_checkins/_section.html.erb`** (used by 1)

- **low** `EMPTY-01` `timesheets/early_late_checkins/_section.html.erb:24` empty-loading: Empty collection should be ui_empty_state; both empty texts are muted italic <p> (19, 24).

**`timesheets/sanity_checker/_entries.html.erb`** (used by 1)

- **low** `COPY-03` `timesheets/sanity_checker/_entries.html.erb:20` tables-lists: Table headings are Title Case; "Entry / shift", "On duty / off duty" (20) and "Duration / shift length" (21) are sentence case.

**`timesheets/timesheet_slot_repair/_group.html.erb`** (used by 1)

- **medium** `TYPE-03` `timesheets/timesheet_slot_repair/_group.html.erb:36` typography: Table content is never text-sm; status, check-in time and reason lines in cells are text-sm (36, 40, 48).

**`timesheets/timesheet_slot_repair/_results.html.erb`** (used by 1)

- **low** `COLOR-05` `timesheets/timesheet_slot_repair/_results.html.erb:28` icons: A status icon takes icon-success; this one is coloured with class text-success.

**`timesheets/timesheet_slot_repair/_shift.html.erb`** (used by 1)

- **medium** `TYPE-03` `timesheets/timesheet_slot_repair/_shift.html.erb:4` typography: Table content is never text-sm; shift description and time inside cells are text-sm.

**`training/all_notes/_notes.html.erb`** (used by 1)

- **low** `COPY-08` `training/all_notes/_notes.html.erb:13` typography: pattern=typography Rule: dates come from DateTimeHelper, never strftime in a view. The note date is formatted with strftime("%b %-d") in the template.
- **low** `EMPTY-01` `training/all_notes/_notes.html.erb:6` empty-loading: Rule: empty states always use ui_empty_state. A person with no notes shows a muted italic lowercase "no notes" span.

**`training/mentees/_row.html.erb`** (used by 1)

- **low** `MODAL-02` `training/mentees/_row.html.erb:34` buttons: Rule: a confirm asks with the action and says whether it can be undone. "Revoke every … mentee position from X?" never says it can be undone (Restore is offered).

**`training/mentoring/assignments/_general_notes.html.erb`** (used by 1)

- **medium** `FORM-01` `training/mentoring/assignments/_general_notes.html.erb:14` forms: Rule: forms use AppFormBuilder fields. label_tag, text_area_tag and a tag.p help line copy the builder's classes and aria-describedby by hand.

**`training/mentoring/assignments/_roster.html.erb`** (used by 1)

- **medium** `FORM-01` `training/mentoring/assignments/_roster.html.erb:172` forms: Rule: builder fields only. select_tag (result and mentor selects, 172 and 211) borrows SELECT_CLASSES.
- **medium** `FORM-01` `training/mentoring/assignments/_roster.html.erb:211` forms: Rule: forms use AppFormBuilder fields. Selects, labels and textareas are select_tag/label_tag/text_area_tag with the builder's class constants; they look the same.
- **medium** `FORM-01` `training/mentoring/assignments/_roster.html.erb:217` forms: Rule: builder fields only. text_area_tag for mentor notes borrows TEXTAREA_CLASSES.
- **medium** `FORM-06` `training/mentoring/assignments/_roster.html.erb:33` validation: Rule: errors show through the builder with ui_form's summary at the top. ui_form gets no_error_summary: true and a hand-written :error callout "Nothing Was Recorded" stands in.
- **medium** `FORM-06` `training/mentoring/assignments/_roster.html.erb:231` validation: Rule: a field error is the builder's message with role="alert" under the field. Code puts a text-error span with icon in its own table row, no role="alert".

**`training/mentoring/assignments/_upcoming.html.erb`** (used by 1)

- **medium** `COLOR-02` `training/mentoring/assignments/_upcoming.html.erb:7` other: Rule: colour carries meaning, never decoration. A :success flag callout heads an upcoming shift with no sign-ins, where nothing has succeeded.

**`training/sessions/_session_table.html.erb`** (used by 1)

- **medium** `EMPTY-01` `training/sessions/_session_table.html.erb:57` toasts-alerts: Rule: empty states use ui_empty_state. No trainer slots shows <p class="text-error font-semibold"> plus a rule paragraph in the cell.
- **medium** `TOUCH-01` `training/sessions/_session_table.html.erb:24` links: Rule: a bare link gets min-h-9; TABLE_LINK_CLASSES is the one table exception. Session time link_to uses only "font-medium", neither floor nor exception.
- **low** `EMPTY-01` `training/sessions/_session_table.html.erb:51` empty-loading: Rule: empty states use ui_empty_state. Empty trainer group shows muted "No trainers signed up yet." span.

**`training/sessions/_stats.html.erb`** (used by 1)

- **low** `COPY-03` `training/sessions/_stats.html.erb:10` typography: Rule: every scanned label is Title Case. The tile label reads "Signed up" / "Signed up — FULL" beside Title Case siblings ("ART Vets", "Inactive / Retired").

**`training/sessions/_trainee_card.html.erb`** (used by 1)

- **medium** `BTN-04` `training/sessions/_trainee_card.html.erb:71` buttons: Rule: one primary action per view. Every trainee card has a :primary "Score" button, beside the trainer section's primary "Save Trainers".
- **low** `EMPTY-01` `training/sessions/_trainee_card.html.erb:59` empty-loading: Rule: empty states use ui_empty_state. No notes shows a muted italic "No notes yet." span.
- **low** `TYPE-04` `training/sessions/_trainee_card.html.erb:21` typography: Rule: nothing in a section outweighs its title (heading-section text-base lg:text-lg semibold). Callsign span is text-lg font-semibold at every width, so heavier on phones.

**`training/sessions/_trainees_section.html.erb`** (used by 1)

- **medium** `TOAST-03` `training/sessions/_trainees_section.html.erb:49` buttons: Rule: a copy is confirmed by clipboard_button's Copied tip. Code builds button_action with the copy-to-clipboard controller by hand (same tip) instead of clipboard_button.

**`training/sessions/_trainer_section.html.erb`** (used by 1)

- **medium** `FORM-01` `training/sessions/_trainer_section.html.erb:39` forms: Rule: builder fields only. Per-row select_tag borrows SELECT_CLASSES.
- **medium** `FORM-01` `training/sessions/_trainer_section.html.erb:46` forms: Rule: forms use builder fields. Attendance select is select_tag with the builder's class constant and an aria label; looks the same.
- **medium** `FORM-01` `training/sessions/_trainer_section.html.erb:50` forms: Rule: builder fields. Hand-built label (min-h-9) around hidden_field_tag + check_box_tag CHECKBOX_CLASSES + "Lead" span stands in for f.check_box.

**`training/sessions/graduations/_dialog.html.erb`** (used by 1)

- **medium** `EMPTY-01` `training/sessions/graduations/_dialog.html.erb:78` empty-loading: Rule: empty states use ui_empty_state. No candidates shows <p class="text-error font-semibold mb-3">No eligible candidates were found.</p>.
- **medium** `FORM-01` `training/sessions/graduations/_dialog.html.erb:58` forms: Rule: builder fields. Override rows use a raw <label> around check_box_tag (CHECKBOX_CLASSES) in a border-t divider, not f.check_box.

**`training/sessions/rosters/_dialog.html.erb`** (used by 1)

- **medium** `BTN-04` `training/sessions/rosters/_dialog.html.erb:75` forms: Rule: one primary action per view. Every result row has its own primary submit_button "Add <callsign>", after a primary "Search".
- **medium** `EMPTY-01` `training/sessions/rosters/_dialog.html.erb:83` empty-loading: Rule: empty states use ui_empty_state. No search match shows <p class="text-error font-semibold">.
- **medium** `FORM-01` `training/sessions/rosters/_dialog.html.erb:24` forms: Rule: builder fields. Labels "font-medium block mb-1" plus select_tag SELECT_CLASSES and text_field_tag INPUT_CLASSES w-full bypass f.select/f.text_field.
- **medium** `FORM-01` `training/sessions/rosters/_dialog.html.erb:40` forms: Rule: builder fields only. text_field_tag for the search query.

**`training/sessions/scores/_dialog.html.erb`** (used by 1)

- **low** `EMPTY-01` `training/sessions/scores/_dialog.html.erb:56` empty-loading: Rule: empty states use ui_empty_state. No notes shows <p class="text-stone-muted italic mb-2">No notes yet.</p>.

**`vc/application_import/_results.html.erb`** (used by 1)

- **medium** `STAT-01` `vc/application_import/_results.html.erb:38` other: Summary tiles go in ui_stat_row, never a hand-rolled div or grid; the four ui_stat_box tiles sit in "grid grid-cols-2 lg:grid-cols-4 gap-2 lg:gap-4 my-4".

**`vc/applications/_action_bar.html.erb`** (used by 1)

- **low** `COPY-03` `vc/applications/_action_bar.html.erb:20` typography: Every label a reader scans is Title Case; menu items read "Assign to self", "Assign to VC…", "Clear assignment" (20, 24, 27).

**`vc/applications/_admin_section.html.erb`** (used by 1)

- **low** `MODAL-02` `vc/applications/_admin_section.html.erb:17` buttons: Confirm asks with the action, not "Are you sure…"; delete_button's message reads "Are you absolutely sure you want to delete application …?"

**`vc/applications/_applications_table.html.erb`** (used by 1)

- **low** `EMPTY-02` `vc/applications/_applications_table.html.erb:43` empty-loading: An empty value prints "—"; a missing Last Updated prints "-".

**`vc/applications/_audit_log_section.html.erb`** (used by 1)

- **low** `EMPTY-02` `vc/applications/_audit_log_section.html.erb:17` empty-loading: An empty value prints "—"; an unknown author prints "- unknown -".
- **low** `EMPTY-02` `vc/applications/_audit_log_section.html.erb:29` typography: An empty value prints "—"; blank from/to values print as italic <em>blank</em>.

**`vc/applications/_eligibility_stage.html.erb`** (used by 1)

- **low** `COPY-03` `vc/applications/_eligibility_stage.html.erb:3` typography: Labels are Title Case; ui_label_value rows "BRC events" (3) and "Experience type" (27) are sentence case (bpguid's rows use Title Case).

**`vc/applications/_notes_list.html.erb`** (used by 1)

- **medium** `BTN-02` `vc/applications/_notes_list.html.erb:23` buttons: Button colour comes from the variant; the Delete button_link is :ghost recoloured with class "text-error" instead of an :error variant.
- **medium** `CARD-01` `vc/applications/_notes_list.html.erb:11` cards: Cards come from ui_card/card-standard; each note is an <li> with its own border, rounded-lg and p-3 acting as a card.
- **medium** `TYPE-03` `vc/applications/_notes_list.html.erb:5` typography: text-sm is never for paragraph content; the notes explanation <p> is text-sm. Line 12 (timestamp and author) is metadata and fine.
- **low** `EMPTY-01` `vc/applications/_notes_list.html.erb:7` empty-loading: Empty collections use ui_empty_state; no notes renders a plain muted <p>.

**`vc/applications/_rail.html.erb`** (used by 1)

- **medium** `TYPE-05` `vc/applications/_rail.html.erb:13` cards: Heading hierarchy is consistent; sibling rail sections are titled h2 by ui_section, but the two notes sections pass no title and carry a raw h3 instead.

**`vc/applications/_status_actions.html.erb`** (used by 1)

- **low** `COPY-03` `vc/applications/_status_actions.html.erb:15` typography: Labels are Title Case; Reject and Hold menu items are sentence case ("Lacking event experience", "Why Ranger answer issue", "Ask for event confirmation", lines 15-36).

**`vc/bpguid/_results.html.erb`** (used by 1)

- **low** `MODAL-02` `vc/bpguid/_results.html.erb:101` modals: Confirm says whether it can be undone; Replace BPGUID asks with the action (variant :error) but never says the link can be replaced again or only an Admin can remove it.

**`vc/create_prospectives/_results.html.erb`** (used by 1)

- **medium** `STAT-01` `vc/create_prospectives/_results.html.erb:41` other: Summary tiles go in ui_stat_row, never a hand-rolled grid; the ui_stat_box tiles sit in "grid grid-cols-2 lg:grid-cols-4 gap-2 lg:gap-4 my-4".

**`vc/handle_checker/_result.html.erb`** (used by 1)

- **medium** `TYPE-03` `vc/handle_checker/_result.html.erb:31` typography: text-sm is never for table content; the conflict "Reason:" line inside a table cell is text-sm (the overflow note at 10 is supporting text and fine).
- **medium** `TYPE-03` `vc/handle_checker/_result.html.erb:40` typography: Table content is text-base; the Reason line (31) and the rowspan Rule cell (40) are text-sm text-stone-muted.
- **low** `EMPTY-01` `vc/handle_checker/_result.html.erb:8` empty-loading: Empty collections use ui_empty_state; a handle with no conflicts shows plain text "No conflicts found." from handle_checker_result_summary and omits the table.

**`vc/photos_review/_photo.html.erb`** (used by 1)

- **low** `EMPTY-01` `vc/photos_review/_photo.html.erb:78` typography: Empty collections use ui_empty_state; no prior rejections shows a bold <div class="font-semibold"> sentence.
- **low** `EMPTY-02` `vc/photos_review/_photo.html.erb:90` empty-loading: An empty value prints "—"; a missing rejection message prints italic <i>none given</i>.
- **low** `MODAL-02` `vc/photos_review/_photo.html.erb:47` modals: Confirm says whether it can be undone; Approve Photo asks with the action but, though it removes every other photo, says nothing about undo.
- **low** `TYPE-05` `vc/photos_review/_photo.html.erb:9` typography: Heading hierarchy runs h1 > h2 > h3; each review card's callsign is an h3 directly under the page h1, with no h2 section between.

**`vc/spigot_flow_report/_callsign_cell.html.erb`** (used by 1)

- **low** `STYLE-01` `vc/spigot_flow_report/_callsign_cell.html.erb:9` other: No inline style= attribute; the popover trigger and panel set anchor-name and position-anchor through style (a per-cell name, explained only by the popover comment).

**`assets/stylesheets/components/mega-menu.css`** (used by 0)

- **low** `BP-02` `assets/stylesheets/components/mega-menu.css:20` navigation: pattern=navigation Guide: write the lg fold as theme(--breakpoint-lg) (2924-2925). mega-menu.css uses literal @media (min-width: 1024px); being min-width it matches lg: exactly, so no dead band, only the literal.

**`helpers/admin/log_styles_helper.rb`** (used by 0)

- **medium** `BTN-05` `helpers/admin/log_styles_helper.rb:41` navigation: Rule: :primary is for primary actions. Code: log_mode_button uses :primary to mark the current view (a state), :secondary for the other mode.
- **medium** `TYPE-03` `helpers/admin/log_styles_helper.rb:11` typography: Rule: table content is text-base, never text-sm. Code: LOG_TEXT "text-sm leading-snug text-body" sets every admin log table cell in text-sm.

**`helpers/application_helper.rb`** (used by 0)

- **medium** `TYPE-03` `helpers/application_helper.rb:232` typography: TYPE-03 bans text-sm for paragraphs; hour_not_counted_disclaimer's two-sentence note is text-sm. Line 338 is text-base and fine.
- **low** `EMPTY-02` `helpers/application_helper.rb:81` icons: pattern=empty-loading none_stated prints italic muted "None stated"; EMPTY-02 wants "—" for an empty value. Not an icon (the i tag is italics).

**`helpers/button_helper.rb`** (used by 0)

- **low** `COLOR-01` `helpers/button_helper.rb:63` color: COLOR-01 bans a dark: pair on a raw colour in markup; the sticky row's shadow is rgba(0,0,0,0.1) with a dark: rgba twin in the helper.
- **low** `STYLE-01` `helpers/button_helper.rb:83` spacing: the rule: no inline style= attribute

**`helpers/dashboard_helper.rb`** (used by 0)

- **medium** `MOTION-01` `helpers/dashboard_helper.rb:41` other: Rule allows animate-pulse on urgent badges only; helper pulses the action-needed (warning) badge, not the urgent one. Lowercase badge labels noted separately

**`helpers/form_helper.rb`** (used by 0)

- **high** `TOUCH-01` `helpers/form_helper.rb:950` forms: Guide puts the 36px class on the wrapping label of a radio (579); check_box (933) wraps correctly, radio_button's label is a sibling and the small radio is outside it.
- **high** `TYPE-02` `helpers/form_helper.rb:792` typography: TYPE-02 bans text-xs on labels a reader needs; the "(required)" marker inside every required label is text-xs. Line 816 is text-sm icon sizing and is fine.
- **medium** `BP-01` `helpers/form_helper.rb:1052` forms: pattern=forms sm: is allowed only in a field width:; horizontal collection radios step column count at sm:columns-2, a layout tier below lg.
- **low** `SPACE-02` `helpers/form_helper.rb:1189` tables-lists: Bulleted lists are list-bulleted; form_error_summary's ul draws bullet spans by hand.

**`helpers/icon_helper.rb`** (used by 0)

- **low** `STYLE-01` `helpers/icon_helper.rb:81` spacing: the rule: no inline style= attribute

**`helpers/mailer_helper.rb`** (used by 0)

- **low** `STYLE-01` `helpers/mailer_helper.rb:7` spacing: the rule: no inline style= attribute

**`helpers/messages_helper.rb`** (used by 0)

- **high** `TABS-01` `helpers/messages_helper.rb:35` navigation: Rule: tabs come from tab_navigation (tabs-border), never hand-written. messages_folder_tab hand-builds `tab`/`tab-active` anchors with role=tab inside a tabs-lift tablist.
- **low** `COPY-08` `helpers/messages_helper.rb:75` other: pattern=other Rule: dates come from DateTimeHelper formats. message_list_time hand-writes "%b %-d" (Jan 8), a format the guide's table does not list, via strftime.

**`helpers/modal_helper.rb`** (used by 0)

- **medium** `TYPE-04` `helpers/modal_helper.rb:181` typography: TYPE-04: h3 takes heading-title. Modal title h3 is modal-title-text, text-xl font-semibold (modals.css:13).
- **low** `COPY-03` `helpers/modal_helper.rb:57` buttons: COPY-03: button labels are Title Case. The backdrop button's text, its accessible name, is lowercase "close"; a raw button inside daisyUI's documented backdrop.
- **low** `MODAL-02` `helpers/modal_helper.rb:129` modals: MODAL-02: ask with the action and say if undoable. confirm_modal_dialog defaults to "Confirm" / "Continue?" with a primary confirm button.
- **low** `TOUCH-02` `helpers/modal_helper.rb:185` buttons: TOUCH-02: an icon-only ButtonHelper button takes btn-square. The modal close is btn-circle (same 36px, round).

**`helpers/page_layout_helper.rb`** (used by 0)

- **medium** `FORM-01` `helpers/page_layout_helper.rb:42` forms: form_tag in both year selectors (42, 67) instead of the builder; same departure as M0292 and M0293.
- **medium** `FORM-01` `helpers/page_layout_helper.rb:49` forms: select_tag in both year selectors standing in for f.select.
- **medium** `FORM-01` `helpers/page_layout_helper.rb:67` forms: pattern=forms Compact selector is form_tag + select_tag (select select-sm) with a text-lg raw label, not AppFormBuilder.
- **medium** `FORM-01` `helpers/page_layout_helper.rb:75` forms: select select-sm written by hand in year_selector_compact rather than a builder field.
- **low** `HERO-03` `helpers/page_layout_helper.rb:102` forms: HERO-03: year selector lives in the hero. title_year_selector puts it under page_title outside a hero; zero callers.
- **low** `TYPE-08` `helpers/page_layout_helper.rb:10` typography: TYPE-08: headings font-semibold. page_title's h1 is text-3xl font-normal (the size is guide 473's legacy entry).

**`helpers/sidebar_helper.rb`** (used by 0)

- **low** `NAV-02` `helpers/sidebar_helper.rb:62` navigation: Guide 2047-2067 and 2245-2252 describe sidebar-backdrop/sidebar-drawer utilities; the helper builds daisyUI drawer-side/drawer-overlay instead. The guide's structure is stale.
- **low** `NAV-02` `helpers/sidebar_helper.rb:100` spacing: Guide 2260 sets the sidebar logo at 180px; code uses arbitrary h-[140px] w-[140px] with opacity-30.

**`helpers/training/session_link_helper.rb`** (used by 0)

- **low** `EMPTY-02` `helpers/training/session_link_helper.rb:43` empty-loading: Rule: an empty value prints "—". Code prints muted "(no description)" when a slot has no description.

**`helpers/ui_components/ui_accent_card_helper.rb`** (used by 0)

- **low** `SHADOW-01` `helpers/ui_components/ui_accent_card_helper.rb:81` cards: pattern=cards SHADOW-01: hover is a colour change, never a lift. ui_accent_card adds hover:shadow-sm with transition-all on a non-interactive card.

**`helpers/ui_components/ui_card_helper.rb`** (used by 0)

- **low** `TYPE-05` `helpers/ui_components/ui_card_helper.rb:88` typography: TYPE-05: clear heading hierarchy. ui_card_section always emits h6, skipping levels.

**`helpers/ui_components/ui_hero_panel_helper.rb`** (used by 0)

- **low** `COLOR-05` `helpers/ui_components/ui_hero_panel_helper.rb:70` icons: COLOR-05: icons neutral unless status. Every hero title icon is icon-warning (gold) as decoration.

**`helpers/ui_components/ui_progress_bar_helper.rb`** (used by 0)

- **low** `STYLE-01` `helpers/ui_components/ui_progress_bar_helper.rb:106` other: pattern=other STYLE-01 bans inline style=; ui_progress_bar's fill width is style="width: N%".

**`helpers/ui_components/ui_progress_completed_bar_helper.rb`** (used by 0)

- **low** `STYLE-01` `helpers/ui_components/ui_progress_completed_bar_helper.rb:32` other: pattern=other Inline style="width: N%" on the progress fill.
- **low** `STYLE-01` `helpers/ui_components/ui_progress_completed_bar_helper.rb:40` other: pattern=other Inline style="width: N%" on the progress pulse.

**`javascript/controllers/confirm_checkbox.js`** (used by 0)

- **medium** `MODAL-02` `javascript/controllers/confirm_checkbox.js:3` modals: pattern=modals Guide: confirmations use the app's dialog (confirm_modal). Code: confirmChecked asks with native window.confirm; used for permission grants by membership-editor and permission-editor.

**`javascript/controllers/photo_cropper_controller.js`** (used by 0)

- **medium** `ALERT-01` `javascript/controllers/photo_cropper_controller.js:245` toasts-alerts: pattern=toasts-alerts Not a confirmation. Guide: notices are inline callouts. Code: window.alert("Please select a crop area before saving"), no closing period (COPY-06).
- **medium** `ALERT-01` `javascript/controllers/photo_cropper_controller.js:251` toasts-alerts: pattern=toasts-alerts Not a confirmation. Guide: notices are inline callouts. Code: window.alert for the gap check; sibling photo-upload shows the same kind of error in an inline error box.
- **medium** `ALERT-01` `javascript/controllers/photo_cropper_controller.js:270` toasts-alerts: pattern=toasts-alerts Not a confirmation. Guide: notices are inline callouts. Code: window.alert(`Error: ${error.message}`) for a failed save.

**`application/_mega_menu.html.erb`** (used by 0)

- **medium** `MODAL-01` `application/_mega_menu.html.erb:5` modals: Rule: modals from ModalHelper, opened by the modal controller. Code: custom <dialog class="mega-menu-dialog"> styled in its own CSS and opened by mega-menu controller.

**`application/_public_menu.html.erb`** (used by 0)

- **medium** `BTN-01` `application/_public_menu.html.erb:9` links: Brand link styled "btn btn-ghost text-xl no-decoration" by hand rather than through button_link :ghost (same as _top_menu phone brand).

**`application/_search_bar_placeholder.html.erb`** (used by 0)

- **medium** `BTN-01` `application/_search_bar_placeholder.html.erb:106` buttons: Hand-written "btn btn-sm" on the mode labels instead of a ButtonHelper method, plus has-[:checked]:bg-primary/border-primary colour overrides.
- **medium** `FORM-01` `application/_search_bar_placeholder.html.erb:117` forms: Rule: fields via AppFormBuilder. Code: raw <select class="select select-sm min-h-9 w-auto lg:hidden"> for mode below lg, daisyUI-styled.
- **medium** `MODAL-01` `application/_search_bar_placeholder.html.erb:83` modals: Search <dialog> not built with ModalHelper; not a confirm, so MODAL-02 (hint) does not apply.
- **medium** `MODAL-01` `application/_search_bar_placeholder.html.erb:87` modals: Rule: ModalHelper modal. Code: <dialog> with "rounded-xl shadow-2xl border ... backdrop:backdrop-blur-sm", top-anchored at mt-[15vh], no daisyUI modal/modal-box.
- **medium** `TYPE-03` `application/_search_bar_placeholder.html.erb:101` typography: text-sm barred for form labels; the "Mode" label of the mode radio group is text-sm. Hint p at 129 is help text (allowed); text-xs at 63,149 is kbd chips (see R13443).
- **low** `BP-01` `application/_search_bar_placeholder.html.erb:62` typography: pattern=typography md: is only for .button-row stacking; "Search" label uses "hidden md:inline-block".

**`application/_top_menu.html.erb`** (used by 0)

- **medium** `BTN-01` `application/_top_menu.html.erb:38` buttons: No hand-written btn classes; brand links (38, 65) are link_to "btn btn-ghost". 35 is the documented drawer label; 80, 111 are ButtonHelper/dropdown_menu with btn-square (compliant).
- **medium** `BTN-01` `application/_top_menu.html.erb:65` buttons: pattern=buttons Phone brand link_to "btn btn-ghost text-xl no-decoration px-1" written by hand.
- **low** `COPY-03` `application/_top_menu.html.erb:92` buttons: Prepositions of four letters or fewer stay lowercase; menu buttons read "Switch To Dark Theme" and "Switch To Light Theme".

**`autocomplete/_item.html.erb`** (used by 0)

- **high** `TYPE-02` `autocomplete/_item.html.erb:27` typography: text-xs never for content a reader needs; meta lines (status and name, legal first name, FKA, phone match) are text-xs. Title text-sm is allowed for dropdowns.

**`common/_error_summary.html.erb`** (used by 0)

- **medium** `FORM-06` `common/_error_summary.html.erb:5` validation: Rule: the summary is ui_form's (form_error_summary). common/error_summary is a second hand-built summary with its own lead and bullets; only _form_wrapper renders it, and nothing renders that.

**`common/_form_wrapper.html.erb`** (used by 0)

- **medium** `FORM-06` `common/_form_wrapper.html.erb:2` validation: Rule: errors show through ui_form's summary. _form_wrapper renders the hand-built common/error_summary instead of form_error_summary.

**`common/_toast.html.erb`** (used by 0)

- **medium** `BTN-01` `common/_toast.html.erb:9` icons: Same raw toast close button as M0065; it is icon-only and has aria-label "Close".

**`common/_years_breakdown.html.erb`** (used by 0)

- **low** `EMPTY-02` `common/_years_breakdown.html.erb:17` empty-loading: Rule: an empty value prints "—". Rangered events and service years print italic muted "none" (lines 17, 34).

**`common/messages/_find_recipient_form.html.erb`** (used by 0)

- **medium** `BTN-01` `common/messages/_find_recipient_form.html.erb:31` buttons: button_to built from button_classes instead of a ButtonHelper method; its aria-label "Select <callsign>" also replaces the visible "Select <role>".
- **medium** `BTN-04` `common/messages/_find_recipient_form.html.erb:34` buttons: Rule: one clear primary action per view. Each of up to five results gets a full-width :primary "Select" button, beside the modal's own submit.
- **medium** `CARD-01` `common/messages/_find_recipient_form.html.erb:15` tables-lists: Rule: containers come from ui_card. Each search result li is a hand-made `border border-line rounded-lg p-3` box.
- **low** `FORM-07` `common/messages/_find_recipient_form.html.erb:6` forms: Rule: widths fit their content. The Callsign query field is w-full.

**`common/schedule/_people_signed_up.html.erb`** (used by 0)

- **low** `COPY-07` `common/schedule/_people_signed_up.html.erb:34` typography: Never "signup"; counts read "N signups in this shift" (34, 47, 64, 88).
- **low** `EMPTY-01` `common/schedule/_people_signed_up.html.erb:42` empty-loading: An empty state is always ui_empty_state; empty lists are bare text (42, 98) or div "font-semibold my-2" (56, 73) styled like the count lines.

**`common/scheduling/_linked_slots_full.html.erb`** (used by 0)

- **medium** `LIST-01` `common/scheduling/_linked_slots_full.html.erb:5` tables-lists: Explanatory Q&A is a dl.instruction-list; this dl is "space-y-2 text-body" with dt "font-bold text-heading", a hand-styled Q&A list.

**`common/scheduling/_missing_requirements.html.erb`** (used by 0)

- **medium** `LIST-01` `common/scheduling/_missing_requirements.html.erb:3` other: Instructional content is a Q&A instruction-list, not paragraphs; three prose paragraphs (rules, Note:) with a bare mail_to line explain the Online Course requirement.

**`common/scheduling/_missing_requirements_modal.html.erb`** (used by 0)

- **low** `COPY-07` `common/scheduling/_missing_requirements_modal.html.erb:3` typography: "sign-up" as a noun takes the hyphen; the modal title reads "Missing Sign Up Prerequisite(s)".

**`common/scheduling/_mvr_eligible.html.erb`** (used by 0)

- **medium** `TYPE-03` `common/scheduling/_mvr_eligible.html.erb:52` typography: text-sm is never for paragraph content; the deadline's "No exceptions." is a p "text-sm" (49 is text-base, fine).

**`common/scheduling/_slot_additional_info_modal.html.erb`** (used by 0)

- **low** `MODAL-01` `common/scheduling/_slot_additional_info_modal.html.erb:1` modals: The guide's modal has m.title, m.body and a footer; this one has no m.title. Lead correction: it does get a Close footer, which the helper appends (modal_helper.rb:49-51).

**`common/shift_manage/_correct_position_modal.html.erb`** (used by 0)

- **low** `FORM-07` `common/shift_manage/_correct_position_modal.html.erb:21` forms: Field widths fit content and are responsive (selects w-full sm:w-44 via width:); the select gets class "w-full" at every width.

**`common/shift_manage/_too_short_modal.html.erb`** (used by 0)

- **medium** `BTN-05` `common/shift_manage/_too_short_modal.html.erb:32` buttons: Destructive actions take :error; the Delete Entry delete_button is forced to variant :secondary, grey like the safe options.
- **low** `CARD-02` `common/shift_manage/_too_short_modal.html.erb:12` cards: A title that labels the card's content takes heading_level:; the three option cards (12, 23, 44) label their options but render div titles. Variant :secondary is correct.
- **low** `MODAL-02` `common/shift_manage/_too_short_modal.html.erb:38` modals: A confirm asks "<Verb> <thing>?" and says whether it can be undone, not "Are you sure"; this reads "Are you absolutely sure you want to delete the entry?"

**`hq/shared/_danger_notices.html.erb`** (used by 0)

- **medium** `COLOR-03` `hq/shared/_danger_notices.html.erb:23` color: No coloured text for emphasis; inside an error callout the instruction Do not start their Alpha shift is strong text-error.

**`hq/shared/_header.html.erb`** (used by 0)

- **low** `HERO-02` `hq/shared/_header.html.erb:13` typography: The hero description is one sentence saying what the page does; the HQ shell description is the label HQ Window Interface.

**`hq/shared/_warning_modals.html.erb`** (used by 0)

- **medium** `COLOR-03` `hq/shared/_warning_modals.html.erb:25` color: No coloured text for emphasis; modals emphasise Heads up (text-warning) and the do-not instructions (text-error) with coloured strong text, lines 13, 25, 38.

**`hq/shift_manage/_missing_request_modal.html.erb`** (used by 0)

- **low** `COPY-04` `hq/shift_manage/_missing_request_modal.html.erb:5` typography: Never New or Submit; modal title is New Missing Timesheet Request and the submit reads Submit Request (line 29).

**`hq/shift_manage/_pog_cancel_modal.html.erb`** (used by 0)

- **medium** `MODAL-02` `hq/shift_manage/_pog_cancel_modal.html.erb:22` modals: A destructive confirm is red; the cancel-pog dialog submits through modal_form_footer with the default :primary variant.

**`hq/shift_manage/_pog_guideline.html.erb`** (used by 0)

- **medium** `COLOR-03` `hq/shift_manage/_pog_guideline.html.erb:11` color: No coloured text for emphasis; the guideline headline gets text-error via emphasis local (_pog_guidelines line 19).

**`layouts/print.html.erb`** (used by 0)

- **medium** `COLOR-01` `layouts/print.html.erb:59` color: pattern=color Never a palette value; body has print:bg-white (print-only, reason in comment).
- **low** `COLOR-01` `layouts/print.html.erb:41` color: Semantic tokens only; print rule uses literal "#fff" for :root background.
- **low** `STYLE-01` `layouts/print.html.erb:39` color: Rule: no per-view CSS. Code: inline <style> block in layouts/print for @page size/margins and print background (comment explains @page cannot be scoped).

**`me/vehicles_dashboard/_eligible_positions.html.erb`** (used by 0)

- **medium** `COLOR-03` `me/vehicles_dashboard/_eligible_positions.html.erb:25` color: No coloured text for emphasis; a p text-warning paragraph inside an :info callout
- **medium** `STYLE-03` `me/vehicles_dashboard/_eligible_positions.html.erb:16` cards: Use the helper where one exists; hand-made bg-default p-4 rounded-lg box holds the position list
- **low** `TYPE-04` `me/vehicles_dashboard/_eligible_positions.html.erb:8` typography: Heading levels take the heading utilities; h6 styled font-semibold by hand (hierarchy jump filed as F TYPE-05)
- **low** `TYPE-05` `me/vehicles_dashboard/_eligible_positions.html.erb:8` typography: Hierarchy runs h1 > h2 > h3; an h6 sits under the section h2 (and an h3 in the agreement-needed branch), skipping levels

**`me/vehicles_dashboard/_pvr_requests.html.erb`** (used by 0)

- **medium** `BTN-05` `me/vehicles_dashboard/_pvr_requests.html.erb:70` buttons: Destructive actions take :error (delete_button); Delete is a button_link :secondary with a confirm_modal
- **medium** `BTN-06` `me/vehicles_dashboard/_pvr_requests.html.erb:65` buttons: edit_link is the one edit control; Edit is a button_link :primary with a pen icon (Delete :secondary filed as F BTN-05)
- **medium** `CARD-01` `me/vehicles_dashboard/_pvr_requests.html.erb:6` cards: card-standard is rendered by ui_card with no shadow; raw div card-standard with shadow-sm and hover lift
- **medium** `STYLE-03` `me/vehicles_dashboard/_pvr_requests.html.erb:37` cards: Use the helper where one exists; reviewer response is a hand-made bg-default bordered rounded box with an uppercase label
- **medium** `TYPE-03` `me/vehicles_dashboard/_pvr_requests.html.erb:43` typography: text-sm never for primary card information; vehicle colour/plate (13), reviewer response (37) and permit/logo/fuel/amber values (43) are text-sm
- **low** `SHADOW-01` `me/vehicles_dashboard/_pvr_requests.html.erb:6` spacing: Flat by default; card-standard with shadow-sm and hover:shadow-md
- **low** `TYPE-04` `me/vehicles_dashboard/_pvr_requests.html.erb:10` typography: <h4> takes heading-title; vehicle title sets text-base font-semibold by hand

**`me/vehicles_dashboard/_pvr_status_agreement_needed.html.erb`** (used by 0)

- **medium** `BTN-05` `me/vehicles_dashboard/_pvr_status_agreement_needed.html.erb:27` buttons: :warning is for warnings; the "Sign Agreement" call to action is a :warning button_link

**`me/vehicles_dashboard/_pvr_status_eligible.html.erb`** (used by 0)

- **low** `COPY-04` `me/vehicles_dashboard/_pvr_status_eligible.html.erb:13` buttons: Opening a create form says "Add [Entity]", never "New"; button reads "New Vehicle Request"

**`me/vehicles_dashboard/_pvr_status_ineligible.html.erb`** (used by 0)

- **medium** `COLOR-03` `me/vehicles_dashboard/_pvr_status_ineligible.html.erb:10` color: No coloured text for emphasis; div text-warning sentence inside an :info callout

**`me/vehicles_dashboard/_pvr_status_potential.html.erb`** (used by 0)

- **medium** `COLOR-03` `me/vehicles_dashboard/_pvr_status_potential.html.erb:4` color: No coloured text for emphasis; p text-warning inside an :info callout

**`shift_operations/rollcall/_blocked_dialog.html.erb`** (used by 0)

- **low** `COPY-07` `shift_operations/rollcall/_blocked_dialog.html.erb:10` modals: "check-in" is the noun; the modal title reads "Check In Is Blocked".

**`test_harness/autocomplete_fixture.html.erb`** (used by 0)

- **low** `COLOR-02` `test_harness/autocomplete_fixture.html.erb:10` other: Colour carries meaning, never decoration; fixture body is bg-primary. Fixture page.
- **low** `COPY-07` `test_harness/autocomplete_fixture.html.erb:20` typography: pattern=typography Ellipsis is "…"; fixture placeholder "Search people..." (also 68 "(select on blur)...", 101 "(free text)...").
- **low** `COPY-07` `test_harness/autocomplete_fixture.html.erb:43` typography: pattern=typography Ellipsis is "…"; "Search with recents...". Fixture.
- **low** `COPY-07` `test_harness/autocomplete_fixture.html.erb:118` typography: pattern=typography Ellipsis is "…"; "Search near bottom...". Fixture.
- **low** `FORM-01` `test_harness/autocomplete_fixture.html.erb:85` forms: Fields via the builder; fixture focus sinks are raw <input type=text> (85, 95). Fixture.
- **low** `FORM-02` `test_harness/autocomplete_fixture.html.erb:85` forms: Every field has a visible label; fixture inputs at 85 and 95 have none. Fixture.
- **low** `STYLE-01` `test_harness/autocomplete_fixture.html.erb:110` spacing: pattern=spacing No inline style=; fixture spacer div style="min-height: 90vh". Fixture.
- **low** `TYPE-04` `test_harness/autocomplete_fixture.html.erb:37` typography: <h2> takes heading-section; fixture h2s are "text-lg font-bold mb-4" (37, 62, 112) and bare (93).

**`test_harness/search_bar_fixture.html.erb`** (used by 0)

- **low** `COLOR-02` `test_harness/search_bar_fixture.html.erb:10` other: Colour never decoration; search-bar fixture body is bg-primary, h1 "text-xl font-bold". Fixture.

**`training/mentees/destroy.turbo_stream.erb`** (used by 0)

- **low** `COPY-05` `training/mentees/destroy.turbo_stream.erb:6` toasts-alerts: Rule: a success reads "<Thing> <past participle>." with no "has been". Toast reads "X's mentee positions have been revoked."

**`training/mentees/restore.turbo_stream.erb`** (used by 0)

- **low** `COPY-05` `training/mentees/restore.turbo_stream.erb:5` toasts-alerts: Rule: success reads "<Thing> <past participle>." without "has been". Toast reads "X's mentee positions have been restored."

**`vc/applications/_callsign_stage.html.erb`** (used by 0)

- **medium** `COLOR-03` `vc/applications/_callsign_stage.html.erb:15` color: No coloured text for emphasis; the approved callsign value is shown in "font-bold text-success" though the row label already says Approved callsign.
- **medium** `EMPTY-01` `vc/applications/_callsign_stage.html.erb:46` empty-loading: Empty collections use ui_empty_state; no submitted handles shows red "none submitted" text, no rejections a muted span (94), no message a text-sm div (109).
- **medium** `TYPE-03` `vc/applications/_callsign_stage.html.erb:109` typography: text-sm is never for empty-state messages; "No rejection message was given." is text-sm. Line 105 is a disclosure summary (see R14624).
- **low** `COPY-03` `vc/applications/_callsign_stage.html.erb:13` typography: Labels are Title Case; row labels "Approved callsign", "Submitted handles", "Rejected handles" (13, 24, 92) and menu items "Reject handle submissions…", "Edit handles list…" (81, 84, 87) are sentence case.

**`vc/applications/_paragraph_stage.html.erb`** (used by 0)

- **low** `COPY-03` `vc/applications/_paragraph_stage.html.erb:39` typography: Labels are Title Case; the row label "Regional experience" is sentence case.
- **low** `EMPTY-02` `vc/applications/_paragraph_stage.html.erb:13` typography: An empty value prints "—"; an unknown reviewer prints "- unknown -".

**`vc/applications/_personal_info_stage.html.erb`** (used by 0)

- **low** `COPY-03` `vc/applications/_personal_info_stage.html.erb:42` typography: Labels are Title Case; the row label "Emergency contact" is sentence case.

**`public/400.html`** (used by 0)

- **low** `COPY-03` `public/400.html:153` typography: Headings are Title Case; h1 reads "The Clubhouse couldn’t read that request." as a sentence.
- **low** `STYLE-01` `public/400.html:12` other: No CSS outside components/; static 400 page carries its own <style> with oklch tokens mirrored from the theme (same template as 404).

**`public/404.html`** (used by 0)

- **low** `COPY-03` `public/404.html:153` typography: Headings are Title Case; h1 reads "That page isn’t here." as a sentence.
- **low** `STYLE-01` `public/404.html:12` other: Rule: no per-page CSS. Code: inline <style> copying theme tokens (commented), theme script, a.action button look, footer code chip; static file outside the asset pipeline.

**`public/406-unsupported-browser.html`** (used by 0)

- **medium** `STYLE-01` `public/406-unsupported-browser.html:14` other: No per-page CSS; 406 page inlines hex copies of the tokens and darkens only by prefers-color-scheme, so a saved theme choice is ignored.
- **low** `COPY-03` `public/406-unsupported-browser.html:87` typography: Headings are Title Case; h1 reads "This browser is too old for the Clubhouse." as a sentence.

**`public/422.html`** (used by 0)

- **low** `COPY-03` `public/422.html:153` typography: Headings are Title Case; h1 reads "That change was rejected." as a sentence.
- **low** `STYLE-01` `public/422.html:12` other: Static 422 page with inline <style> token copy (same template as 404).

**`public/500.html`** (used by 0)

- **low** `COPY-03` `public/500.html:153` typography: Headings are Title Case; h1 reads "Something broke on our end." as a sentence.
- **low** `STYLE-01` `public/500.html:12` other: Static 500 page with inline <style> token copy (same as 404 plus mailto footer).

### 3.3 Shared layer: helpers, stylesheets, controllers

Where the implementation of a shared component differs from what the guide documents for it. One fix
here changes every page that uses the component.

**css** (35)

- **high** `TOUCH-01` `mega-menu-item / -item-link / -item-title / -item-cat / -item-desc` (`assets/stylesheets/components/mega-menu.css:102`): Guide: 36px floor, min-h-9 for a bare link (572-576). mega-menu-item-link is a link with py-1 and min-h-8 (32px); a title-only item measures about 25px of content, so it renders 32px.
- **high** `TYPE-02` `vc-progress-item + -success/-danger/-warning/-pending/-neutral` (`assets/stylesheets/components/vc-applications.css:7`): Guide: text-xs never for labels or content a reader needs (489-494). Section-jump status pills label at text-xs; neutral uses text-base-content/60 off the ladder. min-h-9 matches TOUCH-01.
- **high** `TYPE-02` `hero-stat / hero-stat-flame / hero-stat-award / hero-stat-label / hero-stat-value` (`assets/stylesheets/components/hero-panel.css:28`): Guide: never text-xs for labels a reader needs (489-494). hero-stat-label is 0.75rem. Also a decorative warning-to-error gradient (flame) and a new pinned gold (award) against 180-188; values off the type scale.
- **high** `TYPE-02` `ac-group / ac-group-header` (`assets/stylesheets/components/autocomplete.css:96`): Guide: never text-xs for labels users need (494). The group header that names each result group is text-xs uppercase muted. Separator between groups matches 2352.
- **high** `TYPE-02` `ac-filter-chip / ac-filter-chip-active / ac-filter-count` (`assets/stylesheets/components/autocomplete.css:129`): Guide: text-xs only for badges and similar, never labels a reader needs (480-494). Filter chips, toggle controls, label at text-xs; min-h-9 and focus ring match. Active hover mixes in literal black.
- **medium** `AC-01` `ac-option / ac-option-active` (`assets/stylesheets/components/autocomplete.css:62`): Guide: ac-option-active is the keyboard-selected option "with brand ring" (2351). CSS paints an 18% success-green tint and a 3px inset green bar, no brand ring. ac-option min-h-9 matches 2350.
- **medium** `BP-01` `breakpoints in media queries` (`assets/stylesheets/components/hq-window.css:37`): Guide: md marks only button-row stacking and its spacer (2947-2961). hq-window.css:37 adds an md-to-lg band laying the HQ summary out as a row. Literal 1024px also at mega-menu.css:20, label-value.css:33 (BP-02).
- **medium** `BTN-01` `camera-preview / camera-video / camera-capture-btn / camera-select` (`assets/stylesheets/components/camera.css:8`): Guide: buttons come from ButtonHelper, colour from the variant (1071, 1101). camera-capture-btn hand-styles a round bg-primary button with shadow and active:scale-95; camera-select is a hand-rolled select, not daisyUI select (FORM-01).
- **medium** `BTN-02` `login-submit-button` (`assets/stylesheets/login.css:262`): Guide: no hand-applied colour on a button, colour and hover come from the variant (1101-1103). Layers a warning gradient face, warm shadow, brightness hover and a 1px press translate over the helper's variant.
- **medium** `COLOR-02` `login-panel` (`assets/stylesheets/login.css:26`): Guide: colour never decoration; non-semantic amber is three documented legacy pieces, not to extend (153, 178, 180-188). The panel adds an amber gradient frame, radial amber wash and warm glow; also sm: padding outside field widths (BP-01).
- **medium** `COLOR-02` `login-backdrop` (`assets/stylesheets/login.css:119`): Guide: no coloured decoration (153, 178). A page-sized Rangers logo mask filled with warning at 20% sits behind the sign-in door, decoration in the status colour.
- **medium** `COLOR-02` `login-doors / -doors-title / -doors-lede / -doors-list / -door-lead` (`assets/stylesheets/login.css:319`): Guide: no coloured decoration, links in primary (153, 157). Amber top edge, amber wash and amber links and icons; lede at 0.8125rem and descriptions at 0.85rem sit below text-base (TYPE-03).
- **medium** `COLOR-06` `modal-header-bar / modal-title-text / modal-body-content / modal-footer-bar` (`assets/stylesheets/components/modals.css:8`): Guide: modal titles take text-heading-primary (971). modal-title-text sets text-xl font-semibold text-base-content, body ink at L40 rather than heading ink. The four utilities are otherwise undocumented (the guide shows daisyUI modal-box/modal-action).
- **medium** `COLOR-06` `progress-container / progress-bar / progress-bar-pulse / progress-labels-container` (`assets/stylesheets/components/progress.css:11`): Guide: one neutral utility per purpose (983). Labels use text-sm text-base-content/60, off the ladder. Bar gradient and pulse match 724 and 733; the 500ms width transition has no reduced-motion rule.
- **medium** `COLOR-07` `form fieldset / form fieldset > legend` (`assets/stylesheets/components/forms.css:7`): Guide: gradients belong to progress components only, never cards or other elements (757-760); colour is never decoration (COLOR-02). Every form fieldset gets a primary left rule and a primary/5 gradient. Legend text-lg semibold matches 470/4034.
- **medium** `MOTION-01` `toast-base` (`assets/stylesheets/components/toasts.css:9`): Guide: entrance animations are decorative and avoided; approved motion must honour prefers-reduced-motion (3218-3220). Toasts slide in from translateX(100%) over 300ms with no reduced-motion rule. Composition matches 875.
- **medium** `MOTION-01` `@media (prefers-reduced-motion) .animate-pulse` (`assets/stylesheets/accessibility.css:40`): Guide: the approved motion, animate-spin spinners included, must honour prefers-reduced-motion (3218-3219). The only global guard stops animate-pulse; Tailwind animate-spin (5 views) has none, only sso/hand_back adds motion-reduce.
- **medium** `MOTION-01` `btn-copy-success` (`assets/stylesheets/components/buttons.css:123`): Guide: motion is functional only, from an approved set, and honours prefers-reduced-motion (3218-3220). Keyframed scale bounce and zoom-fade on copy (3 call sites), no reduced-motion rule; the guide's copy confirmation has no animation (1769).
- **medium** `RADIUS-01` `--radius-field` (`assets/tailwind/application.css:56`): Guide radius table: buttons and inputs take rounded-base, 12px (588). daisyUI draws every btn and input at --radius-field, 0.5rem (8px), so ButtonHelper buttons and builder inputs are 8px while rounded-base call sites are 12px.
- **medium** `TYPE-03` `login-field / login-label-row / login-label-link` (`assets/stylesheets/login.css:156`): Guide: form labels are text-base, never text-sm (469, 516). Login labels and the forgot-password link are 0.8125rem, below text-sm. The required asterisk is hidden too (FORM-03 asks for it).
- **medium** `TYPE-03` `ac-empty / ac-error / ac-loading` (`assets/stylesheets/components/autocomplete.css:158`): Guide: never text-sm for empty-state messages (518). ac-empty is text-sm muted. ac-error text-sm is allowed (507); ac-loading has no rule.
- **medium** `TYPE-04` `mega-menu-panel-title / mega-menu-section-title` (`assets/stylesheets/components/mega-menu.css:84`): Guide: <h3>/<h4> take heading-title, one style per level (532-534). These go on <h3> (text-lg semibold muted) and <h4> (text-sm semibold muted) in me/menu/_content: own sizes and muted ink on headings.
- **low** `BP-02` `mega-menu-dialog` (`assets/stylesheets/components/mega-menu.css:8`): Guide: write the lg fold as theme(--breakpoint-lg) (2924-2925). Uses @media (min-width: 1024px); min-width avoids the overlap bug. Otherwise undocumented: full-screen dialog, rgb(0 0 0 / 0.5) backdrop, shadow-xl.
- **low** `BP-02` `ui-label-value` (`assets/stylesheets/components/label-value.css:14`): Guide: write the lg fold through theme(--breakpoint-lg) (2924-2925). @media (width >= 1024px) literal. Label/value displays otherwise have no rule.
- **low** `COLOR-01` `box-success / box-accent-success` (`assets/stylesheets/components/boxes.css:36`): Guide token tables: success borders border-success/30, soft surfaces bg-success/10 (406, 419). The success callout uses bg-success/5 and border-success/20.
- **low** `COLOR-01` `box-warning / box-accent-warning` (`assets/stylesheets/components/boxes.css:45`): Guide: warning borders border-warning/30 (420). The warning callout uses a full-strength border-warning, and an unlayered rule forces every descendant except .btn/.badge to amber ink, body text included.
- **low** `COLOR-01` `box-error / box-accent-error` (`assets/stylesheets/components/boxes.css:73`): Guide token tables: border-error/30, bg-error/10 (409-410, 421). The error callout uses bg-error/5 and border-error/20.
- **low** `COLOR-02` `--hero-stat-hue` (`assets/stylesheets/components/hero-panel.css:39`): Guide: non-semantic amber is three documented legacy pieces, not to be extended (180-188). hero-stat-award pins a new gold, oklch(50% 0.13 85) / oklch(83% 0.17 90), and flame mixes warning into error for decoration.
- **low** `MOTION-01` `toast-progress` (`assets/stylesheets/components/toasts.css:23`): Approved motion lists spinners, the progress pulse, urgent badges, the sidebar slide (3218-3219). The toast countdown bar animates its width with no reduced-motion rule; undocumented class.
- **low** `NAV-02` `sidebar-section-header` (`assets/stylesheets/components/sidebar.css:14`): Guide composition: p-3 font-semibold uppercase tracking-wider overflow-hidden text-ellipsis (2251). CSS: px-3 py-1 text-sm uppercase overflow-hidden text-ellipsis, no semibold, no tracking, tighter vertical padding.
- **low** `NAV-02` `sidebar-badge` (`assets/stylesheets/components/sidebar.css:18`): Guide composition: inline-flex min-w-[1.125rem] h-4.5 ms-2 px-1.5 text-xs font-medium rounded-full (2252). CSS: @apply badge badge-sm ms-2, daisyUI's small badge instead.
- **low** `SHADOW-01` `sticky-progress-container` (`assets/stylesheets/components/progress.css:7`): Guide: a new component gets no shadow (610). The sticky VC action bar carries shadow-sm (plus transition-all 200ms); used once in vc/applications/_action_bar.
- **low** `SPACE-01` `button-row` (`assets/stylesheets/components/buttons.css:30`): Guide: button-row gaps are gap-2 or gap-4 (553). The row uses 1.5vh row gap and 1.5vw column gap, viewport-relative (about 6px on a phone, 29px at 1920). md stacking is the sanctioned use (2952).
- **low** `STYLE-04` `inline-flex-center` (`assets/stylesheets/components/flex-patterns.css:5`): Guide documents inline-flex-center mapping to inline-flex items-center (645, 652). No such @utility exists in flex-patterns.css, so the class would compile to nothing; no call site uses it.
- **low** `TYPE-06` `--font-mono` (`assets/tailwind/application.css:107`): Guide stack (433-434) lists ui-monospace and monospace as generic keywords; CSS quotes them ("ui-monospace", "monospace"), which makes them family names that match nothing, so if the mono woff2 fails the fallback is the next named font, never the generic.

**helpers-components** (26)

- **high** `A11Y-02` `modal` (`helpers/modal_helper.rb:30`): API matches guide 1588-1603 (title/body/footer, modal controller). The dialog carries no aria-labelledby to its h3 or aria-modal, and modal_controller.js adds none, so it has no accessible name. Confirm in a rendered page.
- **medium** `ALERT-01` `hour_not_counted_disclaimer` (`helpers/application_helper.rb:231`): ALERT-01: inline notices are ui_callout_box. This is a "Note:" disclaimer in a plain div.my-2.text-sm (also TYPE-03: paragraph text in text-sm).
- **medium** `CARD-01` `ui_card` (`helpers/ui_components/ui_card_helper.rb:37`): CARD-01 / guide 711-713: card-standard has no shadow and a card that needs one adds shadow-xs at the call site. ui_card defaults shadow: :xs, so every card gets one. width:/height: inline style as documented (1214).
- **medium** `CARD-03` `ui_section` (`helpers/ui_components/ui_section_helper.rb:10`): Guide 1964/1971: border: false removes the body padding. Code always keeps px-4 pb-2 and border: false drops only a second px-4 pb-1. Guide title padding px-4 py-2; code px-4 pt-2 mb-1.
- **medium** `FORM-01` `year_selector` (`helpers/page_layout_helper.rb:37`): Behaviour matches guide 3050-3055 (mobile full selector, auto-submit). FORM-01 wants AppFormBuilder; this is form_tag + select_tag + raw label borrowing the builder's horizontal classes.
- **medium** `FORM-01` `year_selector_compact` (`helpers/page_layout_helper.rb:62`): The documented desktop compact selector, built from form_tag + select_tag (select select-sm) and a text-lg raw label, not the builder. aria-label "Select year to view" replaces the visible label's name.
- **medium** `MODAL-02` `delete_button` (`helpers/button_helper.rb:217`): Guide 1130 says delete_button "includes confirmation". Code confirms only when confirm_message: or confirm_modal: is passed; a bare delete_button url deletes on click. Both confirm paths do use variant :error.
- **medium** `NAV-02` `sidebar_item` (`helpers/sidebar_helper.rb:129`): Guide 2143-2153 lists icon:, icon_type:, badge:, badge_variant:. Code accepts all four and renders none (render_sidebar_content has no caller). active/active_prefix/use_turbo/aria-current match.
- **medium** `TYPE-03` `ui_label_value` (`helpers/ui_components/ui_label_value_helper.rb:36`): Undocumented. TYPE-03 bans text-sm for labels and primary content; the default size: :sm sets the whole label/value list in text-sm. label_width travels as an inline style property.
- **medium** `TYPE-03` `action_box` (`helpers/ui_components/action_box_helper.rb:49`): Undocumented card. TYPE-03 bans text-sm for primary card information; the description is text-sm. The icon is always icon-warning (COLOR-05), and icon_position: :end is not a ButtonHelper option.
- **medium** `TYPE-04` `ModalBuilder title / body / footer / close_button` (`helpers/modal_helper.rb:176`): TYPE-04: h3 takes heading-title. The title h3 is modal-title-text (text-xl, modals.css), and the guide sample (808) shows text-lg. Close icon button is btn-circle, not btn-square (TOUCH-02).
- **low** `A11Y-02` `sidebar_submenu` (`helpers/sidebar_helper.rb:119`): Guide 2184-2188: a grouping title with no interactive disclosure. Code puts a fixed aria-expanded="false" on a non-interactive div, a state that never changes and has no control.
- **low** `COLOR-01` `button_row` (`helpers/button_helper.rb:52`): Sticky row, spacer and --button-row-controls match guide 2844-2889. The sticky shadow is an arbitrary rgba value with a dark: twin in helper markup (line 63); guide 1013-1014 keeps dark: pairs on raw values to component CSS.
- **low** `COLOR-01` `ui_progress_box` (`helpers/ui_components/ui_progress_box_helper.rb:97`): COLOR-01 bans palette colours and dark: pairs in markup. ICON_BADGE_BASE uses from-amber-100 to-orange-100 dark:from-amber-900/40 (line 21); guide 736-743 records it as tolerated legacy.
- **low** `COLOR-05` `qualification_icon / ... / qualification_unit` (`helpers/application_helper.rb:283`): COLOR-05: a status icon takes icon-success/warning/error/info. The "on track" hourglass is text-primary (line 287); none of the four state icons has a label:.
- **low** `COPY-04` `submit_button` (`helpers/button_helper.rb:239`): Guide shows submit_button "Save"; COPY-04 bans "Submit". The default label is "Submit" (line 241). Otherwise a btn-primary btn-sm input as documented; no icon support.
- **low** `EMPTY-02` `years_breakdown` (`helpers/year_helper.rb:4`): Undocumented; its partial (common/_years_breakdown.html.erb:17,34) prints empty values as italic muted "none" rather than "—", and hand-writes dl.ui-label-value with a class on only the first dt.
- **low** `EMPTY-02` `year_range` (`helpers/year_helper.rb:8`): EMPTY-02: an empty value prints "—". No years renders span.text-stone-muted "none".
- **low** `HERO-04` `back_to` (`helpers/application_helper.rb:245`): Guide 3074-3075: text link with left arrow, muted colour with hover state. Code rests at text-body and hovers to text-stone-emphasis, the same --color-body token (guide 955), so no muted rest and no visible hover.
- **low** `NAV-02` `sidebar_menu` (`helpers/sidebar_helper.rb:55`): Guide 2117-2126 gives width default "w-65 lg:w-45"; code "w-65 lg:w-50" (comment says lg:w-55). Guide logo is 180px with pt/mt/mb-10; code h-[140px] w-[140px], absolute, mb-5, opacity-30. Header row matches 2070-2088.
- **low** `NAV-02` `sidebar_badge (private)` (`helpers/sidebar_helper.rb:240`): Guide 2213: info badge is brand text, background and border. Code's info variant has no text colour. The helper is unreachable (no caller of render_sidebar_content).
- **low** `NAV-04` `dropdown_scroll_list` (`helpers/application_helper.rb:65`): Guide 3303 says the letter links are plain fragments with data-turbo="false". The partial's dropdown_item links carry no data-turbo and rely on application.js turbo:click to scroll instead.
- **low** `SHADOW-01` `ui_accent_card` (`helpers/ui_components/ui_accent_card_helper.rb:62`): API, variants and heading_level match guide 1257-1289. SHADOW-01: hover is a colour change, never a lift; the card adds transition-all hover:shadow-sm on a non-interactive article. info border is full opacity, others /30.
- **low** `STYLE-01` `render_progress_bar` (`helpers/ui_components/ui_progress_completed_bar_helper.rb:12`): Gradient fill and pulse classes as guide 721-733. Fill and pulse widths are inline styles (lines 32, 40); a 5% floor is what aria-valuenow reports at 0.
- **low** `STYLE-01` `ui_progress_bar` (`helpers/ui_components/ui_progress_bar_helper.rb:52`): Variants, sizes and label: match guide 1902-1917. The fill width is an inline style="width: N%" (line 106), a computed number.
- **low** `STYLE-01` `photo_tag` (`helpers/application_helper.rb:142`): STYLE-01: no inline style=. width:/height: become an inline px style (lines 148-149). Missing photo falls back to an unlabelled user icon.

**helpers-forms** (14)

- **high** `FORM-03` `required marker (required_marker, private)` (`helpers/form_helper.rb:788`): Guide: red asterisk plus screen-reader text "(required)" (2400, 2710). Default prints visible "(required)" in text-xs (TYPE-02 bans text-xs on labels); required_label: "" prints an asterisk with no text alternative. Neither variant matches.
- **high** `FORM-04` `help text (help_text_tag, public)` (`helpers/form_helper.rb:834`): Guide: help text tied by aria-describedby (2711), help_mode :tooltip documented (2464). Inline mode complies (text-sm text-body). Tooltip mode puts help only in a title on an unfocusable span while aria-describedby names a "_hint" id that is never rendered.
- **high** `TOUCH-01` `radio_button` (`helpers/form_helper.rb:469`): Guide: the 36px class goes on the wrapping <label> of a checkbox or radio (579). The radio sits outside its label; the label has min-h-9 but the radio-sm itself is about 20px. required: is also dropped (FORM-03).
- **medium** `CARD-02` `agreement_status, agreement_border_class, agreement_bg_class` (`helpers/agreement_helper.rb:9`): Guide: a left-border accent card is ui_accent_card with a status variant (1216-1296). These hashes feed hand-built accent cards (comment line 4 says so); not_available uses border-l-secondary while the others are non-directional /30 tints.
- **medium** `COLOR-05` `agreement_icon` (`helpers/agreement_helper.rb:29`): Guide: icons are neutral (text-stone-muted/text-stone-icon) or a status icon-* class (635-637). Signed and pending use icon-success/icon-warning; not_available uses text-secondary, neither neutral nor a status icon class.
- **medium** `FORM-03` `check_box` (`helpers/form_helper.rb:454`): Guide: required: shows the marker and adds the required attribute for all fields (2462). check_box consumes required: and renders neither. Also, in horizontal/auto layout label: becomes an unassociated <span> (881-883, 906-908), leaving the box unnamed without inline_label (FORM-02, high).
- **medium** `FORM-05` `collection_radio_buttons` (`helpers/form_helper.rb:483`): Guide: radio groups get a fieldset with legend (2403, 2589). Vertical and :stacked do; horizontal/auto inline name the group with a plain <span>, so the group has no accessible name. Items repeat the radio-outside-label TOUCH-01 gap; sm:columns-2 breaks BP-01.
- **medium** `FORM-07` `text_area` (`helpers/form_helper.rb:382`): Guide comment (2503) promises a 120px minimum height; the field is "textarea w-full resize-y" and daisyUI 5's textarea sets min-height 5rem (80px). No CSS in components/ raises it. Default w-full is also wider than the width table suggests.
- **medium** `SPACE-01` `layout :horizontal (build_horizontal_field)` (`helpers/form_helper.rb:117`): Guide sets form field spacing at mb-3 (2397, SPACE-01); the horizontal wrapper has no bottom margin, so stacked horizontal fields touch unless the caller spaces them. Error label also drops lg:mr-2 (119), shifting the column on error.
- **low** `A11Y-02` `callsign_chips_field` (`helpers/form_helper.rb:364`): Guide (2571) says the input's aria-label is "Add a callsign"; the field passes aria_label: nil (_callsign_chips.html.erb:15) so the visible label names it instead. Code is defensible; guide text is stale.
- **low** `COPY-08` `DateTimeHelper format constants` (`helpers/date_time_helper.rb:23`): Table (3871-3872): CSV timestamps "2026-01-08 14:30:00" and a chip "Thu 1/8 14:30". CSV_TIME drops the seconds ("%Y-%m-%d %H:%M"); CHIP_TIME, used for filter-chip timestamps, is the ISO form, not SHORT_DAY_TIME. Other constants match.
- **low** `EMPTY-02` `gender_format` (`helpers/gender_helper.rb:6`): Guide: an empty value prints "—" (3853). A person with no gender identity, or custom with no text, prints "Not specified".
- **low** `SPACE-02` `form_error_summary` (`helpers/form_helper.rb:1184`): Guide: a bulleted list is list-bulleted (556-568). The summary's <ul class="mt-2 space-y-1"> draws its own bullets with an &bullet; span per item. Otherwise COMPLIANT FORM-06: ui_callout_box :error at the top, role=alert, focusable id.
- **low** `STYLE-03` `common/_error_summary (partial)` (`common/_error_summary.html.erb:1`): Guide: the error summary is ui_form's (2684), i.e. form_error_summary. This second summary differs in wording ("The following errors were found:"), weight, and lacks the id/tabindex focus target. Rendered only by the uncalled _form_wrapper.

**js** (15)

- **high** `A11Y-02` `camera` (`javascript/controllers/camera_controller.js:63`): Guide: everything works from the keyboard; tabs come from tab_navigation (TABS-01). Code: hand-rolled Upload/Camera tabs set tabIndex -1 on the idle tab with no arrow-key handler, so "Take Selfie" is unreachable by Tab.
- **high** `A11Y-02` `tabs` (`javascript/controllers/tabs_controller.js:63`): Guide: everything works from the keyboard; tab_navigation wires the ARIA. Code: idle tabs get tabindex -1 (also tabs_helper.rb:102) but no arrow-key handler exists, so keyboard users cannot reach any tab but the active one.
- **medium** `ALERT-01` `photo-cropper` (`javascript/controllers/photo_cropper_controller.js:238`): Guide: inline notices are ui_callout_box. Code: window.alert for crop errors (238, 245, 251, 270), unlike photo-upload and passkey which unhide an inline error box; 238 and 245 also lack a period (COPY-06).
- **medium** `BP-01` `vanilla-calendar` (`javascript/controllers/vanilla_calendar_controller.js:177`): Guide: lg is the one structural fold. Code: width <= 768 or a mobile user agent swaps the picker for a native datetime-local input. Also builds a raw <button class="vc-close-btn"> (line 101), not ButtonHelper.
- **medium** `DISC-01` `toggle` (`javascript/controllers/toggle_controller.js:55`): Guide: collapsible content is ui_accordion or ui_disclosure (native <details>), long text read-more. Code: a JS disclosure toggling hidden/hidden! and aria-expanded, swapping the trigger's innerHTML label ("Hide Notes"), in 7 views.
- **medium** `MODAL-02` `permission-editor` (`javascript/controllers/permission_editor_controller.js:42`): Guide: confirm in the app dialog with "<Verb> <thing>?" plus whether it can be undone. Code: native confirm() on submit, opening "WARNING: <titles> require prior approval…", and window.confirm on toggle (line 29).
- **medium** `MODAL-02` `unsaved-changes` (`javascript/controllers/unsaved_changes_controller.js:84`): Guide: confirm in the app dialog, asking with the action. Code: window.confirm("You have unsaved changes. Leaving this page will discard them. Continue?") on turbo:before-visit; beforeunload shows the browser's own prompt.
- **medium** `MODAL-02` `membership-editor` (`javascript/controllers/membership_editor_controller.js:92`): Guide: confirm in the app dialog, asking with the action and saying if it can be undone. Code: multi-paragraph window.confirm texts ("Grant this position anyway?", "Make them a Clubhouse Manager anyway?") via confirm_checkbox.
- **medium** `MODAL-02` `hq-shift (extends unsaved-changes)` (`javascript/controllers/hq_shift_controller.js:315`): Guide: confirms use the app dialog and ask "<Verb> <thing>?". Code: leave guards via window.confirm ("It looks like a shift was not started. Leave this page anyway?"). Also animate-pulse on a checklist chip (line 236), not a badge.
- **medium** `MOTION-01` `toast` (`javascript/controllers/toast_controller.js:12`): Guide: motion is the approved set only, honouring reduced motion. Code: "show" triggers a 300ms slide-in/out (toasts.css toast-base) with no reduced-motion override. Durations and roles match TOAST-01 (6000ms, error stays).
- **medium** `MOTION-01` `autocomplete` (`javascript/controllers/autocomplete_controller.js:894`): Guide: approved spinners must honour prefers-reduced-motion. Code: "Searching…" row builds an animate-spin icon with no reduced-motion override (none in accessibility.css or autocomplete.css). ac-* classes otherwise follow AC-01.
- **low** `COPY-06` `photo-upload` (`javascript/controllers/photo_upload_controller.js:56`): Guide: messages are whole sentences ending in a period. Code: "Please select an image" and "File must be less than N MB" (line 67) have none. Thumbnail built with innerHTML also carries shadow-xs (SHADOW-01).
- **low** `COPY-08` `bookmark (extends kiosk)` (`javascript/controllers/bookmark_controller.js:30`): Guide: times use a 24-hour clock. Code: toLocaleString with hour "2-digit" and no hourCycle, so an en-US browser shows a 12-hour clock with AM/PM on the kiosk page.
- **low** `EMPTY-02` `country-state` (`javascript/controllers/country_state_controller.js:62`): Guide: an empty value prints "—". Code: the state select's blank option is "-" (lines 62, 80). Also dims the label with opacity-60 for a disabled field, which no rule covers.
- **low** `FORM-06` `form` (`javascript/controllers/form_controller.js:21`): Guide: the first error field receives focus automatically. Code: focuses #form-error-summary first and only falls back to the first errored field when no summary exists.

## 4. Guidelines to write

Patterns in use that no rule in the guide addresses, ranked by how many audited templates use them. "Variants found" are the implementations in the code, with the number of files each appears in. The recommendation names the variant that should become the standard: usually the one already used most, unless another is already a shared helper.

Two kinds of entry are mixed here on purpose. Some are patterns the guide never mentions (links, pagination, loading states). Others are shared helpers that exist, are used widely and work, but have no entry in the guide (`modal_dialog`, `export_csv_link`, `ui_label_value`): for those the guideline to write is mostly the documentation of what the code already does. `docs/UI-COMPONENTS.md` may describe some of them; this audit used the guide alone, as instructed, so anything documented only there counts as uncovered.

| # | Uncovered pattern | Templates | Variants found (files) | Recommended standard |
|---|---|---|---|---|
| 1 | Plain links and link helpers (479 uses) | 284 | `link_to` (133), `person_display_link` (84), `callsign_link` (60), `css:tap-target-link` (27), `email_link_or_dash` (24), `mail_to` (25), `ext_link` (15), `css:no-decoration` (10) | Write a Links section. Standard: a bare `<a>`/`link_to` (already primary and underlined on hover from base.css) for prose links; `person_display_link`/`callsign_link` for people; `ext_link` for anything leaving the app; `email_link_or_dash` for addresses; `tap-target-link` when a link stands alone. Say when a link is a `button_link` instead. |
| 2 | Count lines, meta lines and hand-made sub-headings (156 uses) | 177 | `utility-heading` (38), `ui_subheading` (8), `<h1>` (11), `count-line` (10), `bare-text-fragment` (10), `intro-paragraph` (7), `ui_section_title` (6), `muted-meta` (4) | Document `ui_subheading` and `ui_section_title`, and give the count line one form (`text-lg` per LAYOUT-03 on level 1; `filter_bar count:` elsewhere). Muted meta lines take `text-stone-muted`. |
| 3 | Client-side field constraints (`min`, `max`, `pattern`) (66 uses) | 104 | `html-constraint-attribute` (66) | Add to Form Patterns: when to set `min`/`max`/`pattern`, and that every constraint needs a matching server validation and message (COPY-06). The guide covers `maxlength` only. |
| 4 | Inline emphasis tags (`<b>`, `<em>`, `<i>`, `<small>`) (98 uses) | 99 | `<b>` (75), `<em>` (12), `<i>` (4), `<strong>` (3), `<small>` (1) | One line under COLOR-03: emphasis is `<strong>`; `<b>`, `<i>` and `<small>` are not used; `<em>` only for a title or term. 75 files use `<b>` for the same job as `<strong>`. |
| 5 | Where buttons sit (`button_row` or a bare wrapper) (91 uses) | 98 | `button-wrapper-div` (9), `button_link` (6), `button-outside-row` (5), `buttons-outside-button-row` (4), `action-row` (4), `delete_button` (3), `submit-in-plain-div` (3), `cell-action-group` (3) | Decide it and say it: every group of page actions and every form's submit sits in `button_row` (it handles stacking below `md` and the sticky spacer); one button inside a callout, a table cell or a section's title row is exempt. Then fix the guide's own Quick Actions example, which uses a bare div. |
| 6 | Stimulus behaviours with no guide entry (113 uses) | 93 | `stimulus:scroll-to-top` (29), `stimulus:toggle` (7), `scroll-to-top-marker` (6), `hidden-behaviour-div` (6), `stimulus:unsaved-changes` (5), `stimulus:local-time` (4), `data-controller:scroll-to-top` (3), `stimulus:passkey` (3) | Add a short Behaviours table (controller, what it does, where allowed) for the controllers pages attach directly; the guide lists four of roughly sixty. Start with `toggle`, `unsaved-changes`, `scroll-to-top`, `local-time`, `position-picker`. |
| 7 | CSV export control (`export_csv_link`) (84 uses) | 84 | `export_csv_link` (84) | Document `export_csv_link` as the export control. TABLE-05 and the pattern 6 examples show `button_link "Export CSV", :secondary, ..., icon: "file-csv"`; 84 files use the helper. Make the helper the standard and fix the label there. |
| 8 | Hand-built list rows and non-bulleted lists (81 uses) | 81 | `custom-list-row` (24), `<ul>` (21), `ui_table_rows` (4), `single-row-table` (3), `css:callsign-list` (2), `detail-row-without-label` (2), `expandable-detail-row` (2), `ui_drill_down_row` (2) | Document the plain list row (a link or record per line with a divider) as a component, or name `ui_drill_down_row` as its standard outside records-management pages. |
| 9 | Layout utilities and wrappers (`two-column-lg`, `stack-to-row-lg`, width caps) (70 uses) | 75 | `page-width-wrapper` (20), `css:two-column-lg` (15), `css:stack-to-row-lg` (11), `action-row-wrapper` (9), `spacing-wrapper-div` (5), `hero-wrapper` (3), `grid-layout` (2), `button-row-wrapper` (2) | Either document `two-column-lg` and `stack-to-row-lg` in Custom Utility Classes or replace them with the `flex flex-col lg:flex-row gap-4` the guide writes out; name the allowed page width caps (`lg:w-3/4`, `max-w-3xl`). |
| 10 | Collection with no empty branch (43 uses) | 74 | `empty-not-handled` (38), `ui_empty_state` (1), `callout-instead-of-empty` (1), `filtered-empty-not-handled` (1), `render-nothing` (1), `empty-hidden` (1) | Add one sentence to EMPTY-01: every list, table or section that can be empty renders `ui_empty_state` (or says why it cannot be empty). Today the rule covers how an empty state looks, not whether one is required. |
| 11 | Separator and arrow glyphs in text (79 uses) | 73 | `html-entity-or-glyph` (58), `arrow-glyph` (9), `glyph-separator` (4), `glyph-bullet` (4), `glyph-arrow` (2), `glyph-breadcrumb` (1), `glyph-brackets` (1) | Say which glyphs are text and which are icons: "·" and "—" as separators are punctuation; a "→" or "✓" carrying meaning is an icon and goes through `fa_icon`. |
| 12 | Label and value display (94 uses) | 72 | `ui_label_value` (26), `definition-grid` (17), `<dl>` (11), `ui_data_block` (7), `stacked-cell-list` (6), `stacked-cell` (6), `stacked-cell-subline` (5), `stacked-cell-lines` (4) | Document `ui_label_value` as the standard for a record's label/value block (30 uses), with its size default stated; fold the raw `<dl>` grids, flex rows and header-less `ui_table`s into it. |
| 13 | Loading and busy states (96 uses) | 68 | `turbo_frame_tag` (44), `submit-busy-text` (11), `lazy-turbo-frame-or-image` (11), `partial:shared/frame_spinner` (4), `plain-text-loading` (4), `custom-spinner` (4), `shared/frame_spinner` (3), `turbo_empty_frame` (2) | Write a Loading States section. Standard: `shared/_frame_spinner` inside a lazy `turbo_frame_tag`; `turbo_submits_with` text on a submit that takes time; `aria-busy` on the region. Retire the inline copy, the `border-[3px]` spinner and the plain "Loading…" paragraphs. |
| 14 | Worded or styled placeholder for an empty value (45 uses) | 66 | `plain-text-empty` (20), `muted-placeholder` (3), `imported-marker` (3), `text-placeholders` (2), `pronouns_format` (1), `event_date_window` (1), `<br>` (1), `muted-meta-line` (1) | Extend EMPTY-02: `value_or_dash` is the helper for a blank value; say whether a worded placeholder ("Never", "None stated", "not yet") is allowed and, if so, that it is `none_stated`-style muted text rather than ad-hoc italics. |
| 15 | Shared helper called with its own classes (57 uses) | 64 | `helper-class-override` (54) | Say, per helper, what `class:` may carry (layout and width only) and what it may not (colour, type size, radius). |
| 16 | Inline notices that are not callouts (50 uses) | 50 | `plain-text-alert` (30), `ui_toast_render` (3), `inline-error-text` (3), `helper-class-override` (3), `status-by-color` (2), `ui_flash_successful` (1), `ui_success_text` (1), `callout-wrapping-form` (1) | Settle ALERT-01's scope: a one-line notice inside a card or dashboard step is either a compact `ui_callout_box` or `text-error` with an icon. About 15 dashboard steps use bold red paragraphs. |
| 17 | Line breaks used for spacing (33 uses) | 38 | `<br>` (32), `<hr>` (1) | One line under Spacing: no `<br>` for vertical space; use a block element with a scale margin. `<br>` stays for an address or a line of verse. |
| 18 | Dialog shell and footer (`modal_dialog`, `modal_form_footer`) (80 uses) | 34 | `modal_dialog` (47), `modal_form_footer` (32), `modal_close_dialog` (1) | Make `modal_dialog` + `modal_form_footer` the documented standard for form dialogs (47 and 32 files against 28 for the `modal` builder the guide shows); keep `modal` for non-form dialogs. Name the default size: the guide's comment says `:md`, the code defaults to `:lg`. |
| 19 | Area badge maps and yes/no badges (31 uses) | 33 | `yes_no_badge` (10), `severity_style` (3), `utility-badge` (3), `status-by-color` (2), `status-medallion-block` (2), `badge-or-plain-text` (1), `status-by-weight` (1), `badge-vs-plain-text` (1) | Document `yes_no_badge` and require a status-to-variant map to live in one place per status family; two helpers colour the same verdict differently. |
| 20 | Page-specific grids, boards and charts (42 uses) | 26 | `grid-table` (3), `css:hq-forecast-table` (1), `css:shift-coverage-grid` (1), `css:roster-col-callsign` (1), `css:roster-col-select` (1), `css:roster-frozen-cell` (1), `css:roster-frozen-heading` (1), `css:roster-grid` (1) | List the approved one-page components (roster grid, hours and credits grid, HQ forecast Gantt, credit chart, photo board, VC stage cards) with their owner pages, as the guide does for the review pane, so PROC-01 has a record. |
| 21 | Column and grid recipes (21 uses) | 26 | `grid-layout` (17), `tw-arbitrary-value` (2), `checkbox-columns` (1), `grid-table` (1) | Say whether `gap-4` is the grid gap or an example, and whether CSS columns and an `xl:` fold are allowed for card grids. |
| 22 | Photos, avatars and images (57 uses) | 25 | `image_tag` (9), `avatar` (6), `avatar-placeholder` (3), `avatar-photo` (2), `css:camera-preview` (1), `css:photo-board-no-host-next` (1), `css:photo-board-position` (1), `css:photo-board-rail` (1) | Document the avatar and photo treatments (sizes from `PersonPhoto` constants, the placeholder, `rounded-full`), and move the computed width/height from inline `style` to a custom property. |
| 23 | Stat links, action boxes and icon items (22 uses) | 25 | `ui_icon_item` (10), `ui_stat_link` (8), `action_box` (4) | Document `ui_stat_link` (a stat tile that filters), `action_box` and `ui_icon_item`, or fold them into `ui_stat_box` and `ui_section`. |
| 24 | Back link repeated at the foot of a page, or on a page with no hero (16 uses) | 24 | `back_to` (5), `button_link` (4), `bottom-back-button` (2), `back-button-row` (1), `back-slot-cross-interface` (1), `print-back-link` (1), `no-back-link` (1), `print-screen-nav` (1) | Allow or forbid a second "Back to X" at the foot of a long page; give print sheets one shared `print:hidden` navigation partial (three sheets copy it inline). |
| 25 | Form page shape (13 uses) | 22 | `form-hero-no-description` (2), `form-without-section` (2), `form-inside-section` (2), `form-page-no-back-no-sections` (2), `ui_form` (1), `ui_callout_box` (1), `callout-order` (1), `stat-row-on-form` (1) | Mark the form page structure PREFERRED and name what is fixed (hero with back link, `ui_form`, button row last) and what is free (sections inside or around the form, a stat row above an edit form). |
| 26 | Bulk selection (`bulk_select`) (71 uses) | 21 | `bulk_select` (21), `bulk_select_checkbox` (21), `bulk_select_all` (21), `bulk_select_count` (4) | Document `bulk_select` (select-all, row checkbox, count) as the standard for acting on several rows; the guide names it once (line 3519) without an API or placement rule. |
| 27 | Spacing values outside the guide's common patterns (14 uses) | 21 | `tw-arbitrary-value` (4), `helper-class-override` (2), `card-p-3` (2), `row-stack` (1), `button-group-div` (1), `card-padding` (1), `page-wrapper` (1), `arbitrary-values` (1) | Turn "common patterns" into rules or label them examples: card padding (`p-3` is in use beside `p-4`), the gap between sections, and the button-row gap (the row itself uses viewport units). |
| 28 | Page header outside the app shell (sign-in, kiosk, print, error pages) (31 uses) | 19 | `no hero_panel` (13), `static-error-no-hero` (5), `raw-heading-with-utilities` (4), `door-heading-not-hero` (4), `<h1>` (2), `fixture-no-hero` (2), `helper-class-override` (1) | Write the exemption: sign-in and SSO pages use `sessions/_heading`; kiosk, wall-display and print layouts carry their own masthead; static error pages are exempt. Everything inside the app shell takes `hero_panel`. |
| 29 | Tooltips (14 uses) | 19 | `tooltip-or-title-attribute` (10), `class:tooltip` (2), `title-tooltip` (1) | Write a Tooltips entry: `fa_icon ... label:` for an icon's meaning, `help_mode: :tooltip` for a field (after fixing its `aria-describedby`), and no bare `title=` for information a touch user needs. |
| 30 | Form errors reported outside the builder (24 uses) | 17 | `model-errors-inline` (7), `errors-via-flash` (4), `not-handled` (4), `ui_flash_submit_error` (1), `helper-class-override` (1), `required-attribute-only` (1), `plain-text-hint` (1), `empty-not-handled` (1) | Add to FORM-06: a form without a model (bulk tools, searches) reports a refusal in an error `ui_callout_box` above the form, not in a flash alone and not in red text. |
| 31 | Print sheets (156 uses) | 16 | `css:alpha-sheet` (5), `css:alpha-running-head` (3), `css:alpha-callsign` (3), `css:alpha-subline` (3), `print-masthead` (2), `print-sheet` (2), `css:alpha-block-end` (2), `css:alpha-when` (2) | Write a Print Sheets section: the shared skeleton (masthead, running head, doc label, legend), the `print` layout, hex literals allowed for paper, raw `<table>` allowed, and one shared stylesheet instead of five families that repeat it. |
| 32 | Pagination (`ui_pager`) (30 uses) | 16 | `ui_pager` (16), `ui_pager_meta` (1), `ui_pager top and bottom` (1), `prev-next-pager` (1) | Document `ui_pager`: where it sits (above and below the list, or below only), the count line beside it, and its relation to `filter_bar count:`. |
| 33 | Hero with no description (14 uses) | 14 | `hero-no-description` (13), `helper-class-override` (1) | Say whether a description is required. If it is, 13 heroes (mostly new and edit forms under /person) need a sentence; if not, say a form page may omit it. |
| 34 | Arbitrary Tailwind values (8 uses) | 12 | `tw-arbitrary-value` (6), `arbitrary-width-constant` (2) | The guide bans three specific arbitrary values (TOUCH-01) and uses several itself. State the general rule AGENTS.md already has: no arbitrary value without a written reason; a computed number goes through a CSS custom property. |
| 35 | Navbar and mega menu (38 uses) | 9 | `<nav>` (8), `css:mega-menu-item-desc` (2), `css:mega-menu-item-title` (2), `class:navbar` (2), `css:mega-menu-item` (2), `css:mega-menu-star-spacer` (1), `css:mega-menu-item-cat` (1), `css:mega-menu-tabs` (1) | Add Navbar and Mega Menu entries beside Sidebar: the 36px floor (the mega menu's item links are `min-h-8`), the search field, and which buttons are ghost. |
| 36 | Login and public pages (31 uses) | 6 | `css:login-panel` (6), `css:login-submit-button` (5), `css:login-field` (3), `css:login-input` (3), `css:login-title` (1), `css:login-tagline` (1), `css:login-status` (1), `css:login-doors-title` (1) | Document the login page's component set (panel, input, submit) or state that `login.css` is exempt from the component rules; five of its classes are unused. |
| 37 | Embedded frames and media (5 uses) | 3 | `<iframe>` (2), `<video>` (1) | No rule needed unless more appear; note the allowed uses (document preview, camera capture). |
| 38 | Other one-off markup (327 uses) | 266 | `ui_section` (6), `tw-text-size` (6), `grid-layout` (5), `submit-default-variant` (5), `attribute` (5), `fa_icon` (4), `instruction-list-in-section` (3), `bullet-join` (3) | Review case by case; most are single uses. |
| 39 | Undocumented shared helpers, classes and controllers (shared layer) (192 uses) | 0 | `bulk_select` (1), `bulk_select_all` (1), `bulk_select_count` (1), `position_picker_count_label` (1), `bulk_select_checkbox` (1), `filter_chips / active_filters / known_filter / filter_time / ... / filter_url` (1), `ui_card_image` (1), `ui_data_block` (1) | Add the missing entries to the Component Library, or mark each helper internal. The per-item list is in findings.json (`variant` starting `component:`). |

### Rules too vague to judge against

Marked UNCOVERED rather than guessed at. Each needs a sentence added to the guide.

- **BTN-07** (91 cases, 98 templates): Buttons sit in a `button_row`; a form's save and cancel are `f.submit` + `cancel_link` in one; a sticky row holds contro
  - What the guide leaves open: the guide shows button_row in its form and records-management examples but never requires it, and its own Quick Actions example (3608-3615) puts buttons in a bare div.
  - e.g. Rule: buttons sit in a button_row. Code: the Delete All Bug Reports button sits alone in div.mt-4.
  - e.g. Rule: buttons sit in a button_row. Code: Delete All Entries shares a flex div with the pager. Its confirm is red via delete_button (MODAL-02 met).
  - e.g. Rule: buttons sit in a button_row. Code: Delete Old Entries shares a flex div with the pager.
  - row actions (toggle, edit_link, ext_link) in a flex gap-1 div inside a table cell; the rule does not address cells.
- **EMPTY-01** (42 cases, 73 templates): An empty state is always `ui_empty_state`; never a hand-rolled box.
  - the progress box is suppressed with 0 or 1 task; a progress summary is not a collection, and the rule does not say it needs an empty branch.
  - the task ul renders empty if all three counts are zero while @have_outstanding is true; can't tell from code whether that state occurs.
  - notes show ui_empty_state only when the caller passes empty_message, else nothing; rule does not say every collection needs an empty branch.
- **ALERT-01** (41 cases, 47 templates): Inline notices are `ui_callout_box` (`:success`, `:info`, `:warning`, `:error`, `:secondary`) or `ui_alert_banner`.
  - What the guide leaves open: the guide documents ui_callout_box as the notice component but does not say a one-line warning inside a card, cell or dialog must be one.
  - e.g. Rule: inline notices are ui_callout_box. Code: why the address form is locked is a plain p.mt-4 sentence.
  - e.g. Inline notices are ui_callout_box; the limit-reached warning is a div "text-error mt-1" (9, 23) nested in plain text.
  - e.g. Inline notices are ui_callout_box; the arrive-early warning is p "text-error mb-2" written in capitals among plain paragraphs.
  - rule does not say whether a one-line error message (red text plus icon) inside a dashboard step card is an inline notice needing ui_callout_box
- **EMPTY-02** (40 cases, 59 templates): An empty value prints "—".
  - missing author prints italic "*imported*", words saying why the value is absent (×2)
  - blank sender prints italic "- Clubhouse -", a fact (the system sent it) rather than a missing value.
  - muted words "No years at an HQ desk" state a fact rather than an empty value.
- **HERO-01** (31 cases, 19 templates): Every page's header is a `hero_panel`.
  - What the guide leaves open: "all pages use hero_panel" (3027) sits beside "used across all /me routes" (1782); the guide does not say whether pages outside the app shell (sign-in, kiosk and wall displays, print sheets, static error pages, fixtures) take a hero.
  - e.g. Every page header is a hero_panel; the kiosk bookmark page heads itself with a raw <h1 class="text-xl font-semibold px-3 pt-3">.
  - e.g. Page header should be hero_panel; not_found heads itself with a raw <h1 class="text-xl font-semibold mb-3">.
  - e.g. Page header should be hero_panel; a raw h1 with its own size and padding names the document.
  - hero_panel used, but panel.title takes a class: flex row holding callsign, a text-lg status and a text-base pronouns div; rule does not say what a title may hold.
- **ICON-01** (22 cases, 12 templates): Icons are FontAwesome Free 7.1, drawn by `fa_icon`.
  - typographic arrow in sentence text (×7)
  - literal arrow in bare text (×4)
  - literal arrow character in bare text (×2)
- **LAYOUT-02** (21 cases, 26 templates): Columns are `flex flex-col lg:flex-row gap-4` or `grid grid-cols-1 lg:grid-cols-N gap-4`.
  - What the guide leaves open: the guide gives two column recipes as examples (3077-3092); it does not say another grid, gap or column method is wrong.
  - e.g. Columns are flex or grid grid-cols-1 lg:grid-cols-N gap-4; this grid uses an arbitrary track list lg:grid-cols-[1fr_auto_auto] with gap-3/lg:gap-6.
  - e.g. Columns are flex flex-col lg:flex-row gap-4 or grid grid-cols-1 lg:grid-cols-N; the body uses an arbitrary track list lg:grid-cols-[1fr_20rem].
  - e.g. Columns are flex flex-col lg:flex-row gap-4; this is flex-col md:flex-row md:gap-6 with a md:w-60 lg:w-72 sticky rail and order swaps.
  - checkbox list in CSS columns (lg:columns-2) rather than flex or grid; the rule covers page columns, not a long checkbox list.
- **HERO-04** (16 cases, 24 templates): Back navigation lives in the hero panel (`panel.back_to` with `back_to`).
  - What the guide leaves open: the guide says where the back link lives; it does not address a second link at the foot of a page, or pages that have no hero (print sheets).
  - e.g. Back navigation lives in the hero; a second back control, button_link "Back to This Broadcast" :primary, repeats the hero back_to in the body.
  - e.g. Back navigation lives in the hero; outside the wizard every step page adds a body "Back to Tickets & Provisions" button duplicating the hero link
  - e.g. Back navigation lives in the hero panel; print view puts back_to in a print:hidden div with a hint, an inline copy of alpha_schedule/_print_screen_nav.
  - says back navigation lives in panel.back_to; silent on that slot holding a cross-interface switch ("Switch to HQ Interface") with no back link
- **FORM-07** (15 cases, 15 templates): Field widths fit their content and are responsive (`w-full sm:w-48` and friends) rather than full width.
  - filter_bar selects are w-full with wrapper flex-1 in a form_row; the rule's widths are for standalone fields and say nothing about filter-panel rows.
  - free-text filter in filter_bar at w-full with flex-1; the width table does not cover filter-panel rows.
  - selects are w-full with flex-1 in a form_row, and w-full lg:w-96 (lg: rather than sm:); the rule does not settle paired selects.
- **TABLE-01** (15 cases, 19 templates): Data tables are `ui_table`.
  - class: on t.cell is undocumented; whitespace-nowrap only. (×2)
  - blank signature grid of fill-in rules with a colspan legend row; rule does not say whether a blank form grid must be ui_table.
  - a card's two-row flex layout with title/description, then content, duration and credits in fixed-width columns; the rule does not say when such a row is a data table.
- **SPACE-01** (14 cases, 21 templates): Spacing follows the Tailwind scale; card padding `p-4` or `p-2 lg:p-4`, section margin `mb-4`, button-row gaps `gap-2` o
  - What the guide leaves open: the guide lists "common patterns" (549-554) rather than required values, and has no general rule on arbitrary values.
  - e.g. Spacing follows the Tailwind scale; count pill uses arbitrary min-w-[1.5rem]
  - e.g. Spacing on the Tailwind scale; arbitrary "lg:w-[50%]" (131) and "border-[3px]" spinners (197, 255).
  - e.g. Tailwind scale spacing; fixture contenteditable uses min-h-[100px]. Fixture.
  - lg:max-h-[70vh] is a height cap, not spacing; the guide has no arbitrary-value rule. A comment explains it.
- **HERO-02** (14 cases, 14 templates): The hero description is one sentence saying what the page does.
  - What the guide leaves open: the guide says what a hero description must be (one sentence), not that every hero needs one.
  - e.g. Rule: the hero description is one sentence saying what the page does. Code: hero_panel has no description (and no id).
  - e.g. Rule: the hero description is one sentence saying what the page does. Code: hero_panel has no description.
  - e.g. HERO-02 wants a one-sentence description; the hero has none
  - the rule fixes the description to one sentence but not its styling; this one is text-lg, font-semibold and status-coloured.
- **FORM-06** (14 cases, 11 templates): Errors show through the builder: `input-error` on the field, a message with `role="alert"` under it, and `ui_form`'s sum
  - full_messages read to build the multi-row failure list on manage/index, not a single-form inline error; rule does not settle multi-row grids.
  - errors.any? counts and re-dirties failed rows in a multi-row grid with no_error_summary; rule does not settle grid forms whose summary lives in a page callout.
  - per-line validation results listed in a review table, not builder field errors; rule does not cover it.
- **FORM-08** (13 cases, 22 templates): A form page is hero panel (with back link), optional callouts, `ui_form` with sections, then the button row.
  - What the guide leaves open: the form page structure (2722-2747) is a recommended shape; the guide's own hybrid example wraps ui_form in a ui_section, and a description or back link is optional.
  - e.g. FORM-08 says a form page is hero, callouts, then ui_form with sections; the edit note form puts its textarea straight in ui_form with no ui_section, unlike new.html.erb
  - e.g. Form page order is hero, callouts, then ui_form; the "How Shirts Are Awarded" callout sits inside the ui_form.
  - e.g. Rule: a form page's hero carries a description and back link. New and edit (edit.html.erb 1) heroes have a back link but no description.
- **BTN-05** (10 cases, 10 templates): Variants by role: `:primary` primary actions, `:secondary` secondary, `:error` destructive, `:success` positive, `:warni
  - Apply Filters at default primary variant; teams_positions siblings use :secondary. (×3)
  - rule does not say whether a filter bar's Apply is primary or secondary; here :secondary, ticketing filter bars use default primary. (×2)
  - view toggle shows the current view as :primary and the other as :secondary; the rule does not settle variants for a selected-state toggle pair.
- **TYPE-04** (9 cases, 9 templates): One style per heading level: `<h2>` takes `heading-section`, `<h3>` and `<h4>` take `heading-title`; nothing inside a se
  - sheet title is h1 "text-2xl font-semibold"; the rule styles h2 to h4 and says nothing of h1.
  - print-sheet h1 styled by .alpha-shift; the rule does not give h1 a style.
  - print-sheet h1 styled by .alpha-info-title; the rule does not give h1 a style.
- **HELP-02** (8 cases, 5 templates): A rule, legend or how-to goes in one collapsed `ui_disclosure variant: :card` per page ("About This Report" / "How This 
  - instruction-list in an open ui_section on a form page (same as R11583).
  - instruction-list in an open ui_section on a form page (same as R11585).
  - instruction-list in an open ui_section on a form page (same as R11592).
- **TYPE-03** (6 cases, 14 templates): `text-sm` only for secondary content (compact navigation, `btn-sm`, badges and pills, help and error text, metadata, fin
  - a footnote `*` marker at text-sm in a table cell; the rule names table content and fine print but not a footnote marker.
  - "No Photo" caption at text-sm inside an avatar placeholder; rule bans text-sm for empty-state messages but this is a photo placeholder.
  - text-sm on the Alpha-shift state word in the review list line, matching the shared row's other text-sm items; rule does not say whether that line is metadata.
- **FORM-01** (6 cases, 9 templates): Forms use `AppFormBuilder` through `ui_form` (or `form_with ... builder: AppFormBuilder`); never a raw form without the 
  - fieldless hidden form_tag used only as the submit target for mega-menu stars; the rule does not say whether such a carrier form needs the builder.
  - daisyUI input class on a standalone filter input outside any form
  - search_field_tag used as a client-side filter, not a form field
- **LAYOUT-03** (5 cases, 5 templates): Records management: level 1 has no filter bar or table, a `text-lg` count line and rows in `lg:w-3/4`; a row badges only
  - lg:w-3/4 is ruled for records-management level 1; this roster borrows it. (×2)
  - level 2 should have two empty states, but this status filter is built from the roster and cannot empty the table, so the second state would be unreachable.
  - lg:w-3/4 row width is ruled for records-management level 1; this drill-down board borrows it with flex gap-6.
- **CARD-03** (5 cases, 5 templates): Related content is grouped in `ui_section`; two columns come from a `flex flex-col lg:flex-row gap-4` wrapper.
  - ui_section with no title wrapping the description and form; the rule does not say a section needs a title.
  - untitled ui_section wrapping the whole page body; rule does not say whether a section needs a title
  - "Asset Authorization" ui_section has no icon while its sibling sections do; no rule requires section icons
- **COLOR-06** (5 cases, 12 templates): The same neutral text utility is used for the same purpose across pages (ladder: `text-heading`, `text-body`/`text-stone
  - me-muted is documented as the muted helper (guide 1058) yet the ladder names text-stone-muted; the rule does not say whether the alias counts as the same utility.
  - me-muted alias vs text-stone-muted; the rule does not settle the alias.
  - me-muted alias on the filing note; the rule does not settle the alias.
- **TABLE-05** (4 cases, 4 templates): On a page with a filter bar the CSV export sits in `filter_bar actions:`, not in a `button_row` above or below it.
  - export placement is ruled only for pages with a filter bar; this page has none, so export_csv_link sits in a button_row inside a bare my-4 div.
  - no filter bar on this page, so the rule does not place the export; it sits in a button_row inside a bare my-4 div.
  - page has no filter bar, so the rule does not place the export; it sits in a button_row inside a bare my-4 div.
- **TOAST-01** (4 cases, 1 templates): Flash messages are set in the controller and rendered by the layout as toasts; type decides duration and ARIA role.
  - client-shown toast from a <template>, not a controller flash
  - the rule covers controller flash rendered by the layout; it does not address a toast streamed by ui_toast_render from a turbo_stream view.
  - a toast rendered by ui_toast_render inside a turbo_stream response is not addressed by the flash rule.
- **TYPE-02** (4 cases, 1 templates): `text-xs` only for `btn-xs`, badges, mobile-only table labels, icon sizing in links, decorative footer text, labels insi
  - lists icon sizing within links as a text-xs use; these are text-xs icons beside muted words (All Rangers, All Accounts, Clears on join), not in links
  - kbd shortcut chip in text-xs on chrome tokens; the rule does not settle whether a shortcut hint counts as content a reader needs.
  - hand-built kbd hint chips in text-xs (trigger's ⌘K at 63-66, "esc" at 149); the rule neither lists keyboard-shortcut hints as allowed nor clearly as content a reader needs.
- **BADGE-01** (3 cases, 3 templates): Badges come from `ui_badge` (variants primary, secondary, success, warning, error).
  - ui_badge given class opacity-60 to de-emphasise zero counts; no rule settles opacity on badges and contrast needs a rendered check.
  - mentee_status_badge returns the plain string "no alpha sign-up" in one branch and ui_badge in the others; rule does not say whether one state of a badge set may be text.
  - class: on ui_badge is undocumented; shrink-0 only.
- **STAT-01** (3 cases, 3 templates): A page's summary tiles are `ui_stat_box` inside `ui_stat_row`; never a hand-rolled div or grid.
  - ui_stat_box value is a phrase of channel names ("Text and Email"), not a number; the rule does not say values must be figures.
  - the rule fixes the container, not tile width; each ui_stat_box gets a fixed class "w-20".
  - the rule covers summary tiles; a single ui_stat_box "Expired" labelled "Status" is used as a status indicator, not a number.
- **ICON-04** (3 cases, 3 templates): An icon whose meaning is explained only in the page's card carries `fa_icon … label:`.
  - "Sent By" column is icons with sr-only names, no tooltip or visible legend; the rule covers icons explained in a page card.
  - rule covers icons explained in a page card; these channel icons have sr-only names but no tooltip, label: or visible legend, so sighted readers get icons only.
  - requires label: when an icon is explained only in the page's card; this ban icon has no label: and is explained by a legend div on the page, not a card, so screen readers get no meaning
- **COPY-03** (3 cases, 2 templates): Every heading and button label is Title Case; a heading is a label, not a question.
  - rule does not list badge labels (its own CARD-02 example is lowercase "urgent"); lowercase labels, no icons, unlike operational_summary/_training
  - section badges are lowercase strings ("completed", "action needed"); rule does not list badges
  - section badges are lowercase strings; rule does not list badges
- **STYLE-01** (3 cases, 1 templates): No inline `style=` attribute, no scoped or per-view CSS, no CSS outside `components/`.
  - container_class/class name page-specific CSS in components/hours-credits.css; guide does not say whether a one-page component file is per-view CSS.
  - the rule bans CSS outside components/, yet 3944 lists base.css for exactly these element styles. Layered display:block.
  - rule bans a style= attribute in markup; this sets a computed px custom property (--dropdown-fit-shift) from JS to keep a dropdown_scroll_list panel inside the row.
- **DISC-01** (3 cases, 5 templates): Collapsible content is `ui_accordion` or `ui_disclosure` (native `<details>`); `unstyled: true` only for a custom shell 
  - ui_accordion is used, but summary_class re-writes its focus ring and layout (focus:outline-none, ring-primary); the rule does not say whether summary_class may restyle the summary.
  - nested inline ui_disclosure with summary_class "font-semibold text-body"; the option is undocumented.
  - the guide does not say how an icon joins a disclosure title; here a span.font-semibold wraps fa_icon(end: 2) plus text.
- **BTN-01** (3 cases, 0 templates): Buttons come from `ButtonHelper` methods; never raw button HTML or the `btn` classes written by hand. The client-side so
  - dropdown_button is a raw button styled as a dropdown-link menu row; no ButtonHelper method builds a menu row.
  - the guide documents clipboard_button (TOAST-03) but not that its icon control is a raw button with no btn class.
  - undocumented menu row that acts on the page, a raw tag.button styled as dropdown-link; the rule does not say how a menu-item action is built.
- **TABS-01** (3 cases, 2 templates): Tabs come from `tab_navigation`; the `tabs` markup is not hand-written.
  - a two-button Search/Live mode switch acts as a view switch; the rule does not say whether that is tabs.
  - Search/Live mode switch from two log_mode_button calls; the rule does not say whether a view switch is tabs.
  - a panel switcher made of ghost button_actions with aria-current true/false, not tab roles; the rule covers tabs but not whether this switcher is one.
- **BTN-02** (3 cases, 1 templates): No hand-applied `bg-*` or `ring-*` utilities on a button; colour, hover and focus come from the variant.
  - btn-link class added to a ButtonHelper button; the button itself comes from button_action.
  - button_action :ghost given class btn-link font-normal align-baseline; rule bans bg-/ring- utilities but does not settle restyling a button as a link.
  - rule bans only bg-/ring- overrides; class "py-4 text-lg" enlarges the button outside the size scale.
- **SPACE-02** (2 cases, 2 templates): A bulleted list is `list-bulleted`, a numbered one `list-numbered`; never `list-disc`/`list-decimal` on their own, a num
  - note lines are divs prefixed by a literal &mdash;; rule names list classes but not whether dash-prefixed lines must be a list.
  - note lines are divs prefixed by a literal &mdash;; rule does not say whether dash-prefixed lines must be a list.
- **MODAL-01** (2 cases, 0 templates): Modals come from `ModalHelper` (`modal` with `m.title`, `m.body`, `m.footer`), with a `button_row` footer and `modal_clo
  - rule says modals open through the modal controller; this on-demand base (one modal at a time, backdrop click, hotkey, error callouts by kind) serves search and mega menu and is not documented.
  - a multi-step wizard in one native <dialog> opened with its own showModal and step machine, not the modal controller; the guide has no wizard pattern.
- **BTN-06** (2 cases, 2 templates): `edit_link` is the one edit control.
  - rule does not say whether a record id link that opens the edit form counts as an edit control; here a TABLE_LINK_CLASSES link.
  - rule makes edit_link the edit control but says nothing about a row link to a show/review page; this one says "Edit" and opens the read view.
- **COLOR-02** (2 cases, 2 templates): Colour carries meaning (status, warning, success), never decoration: no coloured backgrounds, borders or gradients witho
  - "With Notes" tile is :warning at every count; the guide's own stat-row example colours a count :warning unconditionally, so the rule does not settle it.
  - "Signed Up Again" turns :warning only when positive, but "On Shift Now" is :success at any count, including zero; the rule does not settle constant tile colours.
- **MODAL-02** (2 cases, 4 templates): A confirm dialog asks with the action (`Delete this note?`) and says whether it can be undone; a destructive confirm is 
  - menu confirm ("Confirm {title}", "{description}?") at primary for a sign-out; the rule does not say whether a non-destructive confirm must state undoability.
  - export confirm (method :get, "Calendar Export Warning", "Download Schedule") is not destructive; the rule's wording guidance is written for destructive confirms.
- **COPY-04** (2 cases, 2 templates): One verb per action: "Add X" opens a create form, "Save X" submits, "Delete X" destroys, "Remove from X" takes out of a 
  - rule fixes the verb (Bank) but not the rest; labels vary "Bank This Ticket", "Bank It", "Bank for Later"
  - submit reads "Save" while sibling profile edits say "Save Changes"; the rule's "Save [Entity]" does not settle a bare "Save" or "Save Changes".
- **FORM-10** (2 cases, 2 templates): A sub-group inside a section is divided with `mt-4 pt-3 border-t border-line`.
  - the divider rule covers field groups (mt-4 pt-3 border-t); this card footer rule uses pt-3 mt-3 border-t above the button_row.
  - card footer divider pt-3 mt-3 border-t over a button_row; the divider rule covers form field groups only.
- **LIST-01** (2 cases, 3 templates): Instructional or explanatory content is a Q&A `dl.instruction-list`, not paragraphs.
  - instruction-list whose dt states the current value ("Current position: X") rather than a question; the rule does not settle a non-question dt.
  - dl.instruction-list mb-3 used as a value-plus-instruction pair (15, 22, 29), not Q&A.
- **FORM-04** (1 cases, 0 templates): Help text is the field's `help_text:`, tied to it by `aria-describedby`.
  - guide shows input_counter_data usage only; the "N of MAX characters" div is not tied to the field by aria-describedby and is not a live region.
- **NAV-01** (1 cases, 0 templates): A dropdown menu is `dropdown_menu` with `dropdown_item`.
  - rule names dropdown_menu/dropdown_item but not close-on-outside-click or close-on-link behaviour; no Escape handling, native <details> summary still toggles from the keyboard.
- **COLOR-03** (1 cases, 0 templates): No coloured text for emphasis; use weight and size.
  - the playa-time line sets its <strong> in text-warning; the code does not show whether that marks a status or is emphasis.
- **SHADOW-01** (1 cases, 1 templates): Flat by default: a new component gets no shadow; hover is a colour change, never a lift.
  - the rule says new components are flat but does not say whether a floating popover panel (rounded-box shadow-lg) may cast a shadow.
- **LAYOUT-04** (1 cases, 8 templates): Review pane: one line per record, the pane in its own `uf-pane` frame, selection by `?person=`, the legend in the page's
  - the mailbox reuses review-line rows, but each runs three lines (party, subject, snippet); "one line per record" is written for the intake pages.
- **LAYOUT-01** (1 cases, 1 templates): A page follows one of the seven layout patterns (dashboard, directory, detail, form, special, records management, review
  - the Special pattern allows a custom layout, but the guide has no rule for an unattended wall display with its own layout file and CSS.
- **COPY-02** (1 cases, 6 templates): A person's status prints as stored; never `.titleize`.
  - status prints as stored but wrapped in literal &lt; &gt; brackets; the rule bans titleize only. Unknown note author prints <i>*imported*</i>.
- **TYPE-08** (1 cases, 1 templates): Weights by role: `font-normal` body, `font-medium` labels, `font-semibold` headings and buttons, `font-bold` strong emph
  - font-semibold on a grand-total cell; weights by role do not settle emphasis on a total.
- **FORM-02** (1 cases, 1 templates): Every field has a visible label; never placeholder-only.
  - guide documents hide_label but says every field has a visible label; grid fields rely on column headings plus aria-label. Widths w-full sm:w-NN follow FORM-07.
- **FORM-09** (1 cases, 2 templates): Rich text is for formatted body copy only; saved rich text renders inside `.lexxy-content` through `rich_text`.
  - cannot tell from scope whether document.body is saved Lexxy rich text; it renders via html_safe inside .lexxy-content rather than through rich_text.
- **NAV-04** (1 cases, 1 templates): A directory's quick navigation is `dropdown_scroll_list`, with plain fragment links (`data-turbo="false"`).
  - unwrapped text node "Jump to a callsign starting with the letter:" before dropdown_scroll_list; guide does not say whether the jump list takes a lead-in label.
- **CARD-01** (1 cases, 1 templates): One card utility: `card-standard`, rendered by `ui_card`; not `card-border`; no shadow by default; padding set at the ca
  - login-panel and nav.login-doors panels come from login.css, which the guide lists as the login page's stylesheet; it does not say whether those panels may stand in for ui_card.
- **BTN-04** (1 cases, 1 templates): One clear primary action per view.
  - the same primary "Print Selected" submit appears above and below a long table; rule does not say whether one action may repeat.
- **RADIUS-01** (1 cases, 2 templates): Radius by role: `rounded-base` buttons and inputs, `rounded-lg` modals and panels that are not cards, `rounded-full` bad
  - names rounded-full for avatars; the profile photo uses photo_tag with rounded-2xl and fixed AVATAR_WIDTH/HEIGHT, unclear whether a full profile photo counts as an avatar

## 5. Rules that could be enforced mechanically

Rules a grep or a small lint could enforce. `tools/rule_checks.rb` already contains a first version of each pattern and wrote today's hits to `data/mechanical.tsv`; nothing here is wired into CI. "Hits" is what the pattern matches today; "Real" is how many departures from that rule the audit confirmed in total, so where Real is larger than Hits the pattern needs widening, and the note says how. Three guards already exist and are named for completeness: `bin/css_lint.rb` (palette colours, arbitrary values), `test/views/hero_description_test.rb` (HERO-02) and `test/views/list_indent_test.rb` (SPACE-02), plus `fa_icon` raising on a missing regular glyph (ICON-03).

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

## 6. Not audited, and what code alone could not confirm

**Every template was opened.** No page was skipped: 629 templates and fragments, all 192 helper files, 58 stylesheets and 71 JavaScript files were read in full by one reviewer or another, and the wrapper pages that only render a shared template are covered through that template. What the audit did not reach:

| Not audited | Why |
|---|---|
| Email content | Mail bodies come from templates stored in the database (`app/lib/mail_template_*`); only the layout `app/views/mail/layouts/mailer.html.erb` is in the repository. It was inventoried; the guide does not address email, so its rows are UNCOVERED. |
| Flash and validation wording (COPY-05, COPY-06) | These strings live in controllers, models and `config/locales/en.yml`, outside the view layer the inventory covered. The two COPY-05 and one COPY-06 findings are incidental. A separate pass over `flash[...]` and `errors.add` is needed. |
| Menus as data | `app/lib/menus.rb` and the mega-menu definitions were read for icons and class strings only; menu labels were not checked against COPY-03. |
| Vendored styles | `vanilla-calendar-pro.css`, the three `lexxy-*.css` files, the vendored `driver.css`, `fontawesome-subset.css`. Their re-theming files (`components/lexxy.css`, `components/driver.css`) were audited. |
| CSV, PDF and other non-HTML responses | Out of scope for a UI audit. |
| The two `test_harness` fixtures | Audited, but they are not user-facing; their findings are all `low`. |
| States drawn by JavaScript | Autocomplete results, the "no results" and error rows, toast timing, the photo cropper, the HQ wizard steps and the roster filter exist only at runtime. The controllers were read (section 3.3); the resulting screens were not seen. |

**Rules that code cannot settle.** Four rules were never tested and have no findings: DENS-01 (density), DARK-01 (dark mode renders correctly), A11Y-03 (contrast) need a rendered page; PROC-01 and PROC-02 (approval before a new component or colour) are process rules, so an undocumented component is reported as UNCOVERED, never as a breach.

**What a rendered page would need to confirm.** Collected from the reviewers; each is a claim made from code that a browser could overturn or sharpen.

- **Contrast and dark mode.** The `opacity-60`/`70`/`75` treatments (expired announcement cards, zero-count badges, the "clear" rows on both sanity checkers); amber `text-warning` text on light surfaces; `dropdown_item_disabled`; `text-xs` labels on the HQ Gantt and the credit chart in dark mode; the error-red "live data" callouts in mentoring; the HQ section borders in dark mode. Nothing in this audit verifies dark mode at all.
- **Rendered target sizes.** The mega menu's item links (`min-h-8`, 32px in CSS), the person summary strip's email and phone links (`min-h-7`), the pod card's member links, the kiosk bookmark links, and radio buttons, whose label does not wrap the input.
- **Accessible names and keyboard reach.** That the `modal` dialog is announced without a name; that inactive tabs are unreachable by keyboard (code says so; a keyboard on the page proves it); whether `aria_hidden:` passed as a plain key on the Show Notes button emits a real `aria-hidden` on a focusable control; whether the unlabelled field and radio group on Admin › Settings edit have any name; how the required marker is announced; whether the ban icon in person memberships reaches a screen reader.
- **Phone layout.** Fields left at the builder's default `w-auto` width (the FORM-07 findings), the filter-panel selects, a `size: 70` field in a VC dialog, the languages select; whether the Hours & Credits table, whose `<thead>` is written by hand, still folds into labelled cards; the roster grid's sticky header and frozen columns.
- **Empty and failure states.** Whether a header-only table can appear on Potential Shirts and the survey ratings summary; whether the alert preferences form and the broadcast review can fail or come up empty; how a failed trainer-attendance save and a failed VC application dialog are reported (decided in controllers).
- **"Looks about the same" judgements.** Every `medium` rests on this. The ones reviewers were least sure of: hand-built stat grids against `ui_stat_row` (ticketing, sandman, tickets and provisions); the HQ site-registration dialog against `ModalHelper` modals; the roll call row buttons; the documents preview card; the ROC photo board; and all nine print sheets, which nobody saw printed.
- **Cascade questions.** Whether buttons and inputs render at 8px radius (`--radius-field: 0.5rem`) where the guide's table says 12px; `ui_section border: false` padding; the `hidden hidden!` collapse in person provisions; whether the form fieldset gradient paints radio groups; what daisyUI's `--depth` draws; whether `shadow-xs` on the shift-lead status band is visible.
- **Behaviour.** First-error focus (the controller focuses the summary first); the toast slide-in under reduced motion; the calendar's value format and close button; a 12-hour clock on the bookmark kiosk; whether the print, photo board and bookmark layouts, which render no flash, ever drop a message; the focus indicator on the mailbox search (`outline-none`); whether a person banner keeps its message's line breaks.

### What the page sweeps covered

Each reviewer checked these page-level rules on every template in its area and reported the count.

| Rule | Templates checked | Departures reported |
|---|---|---|
| A11Y-01 | 909 | 2 |
| A11Y-02 | 909 | 0 |
| BTN-03 | 909 | 0 |
| BTN-04 | 744 | 35 |
| BTN-05 | 909 | 24 |
| BTN-07 | 909 | 77 |
| COLOR-02 | 909 | 14 |
| COLOR-03 | 909 | 19 |
| COPY-03 | 909 | 76 |
| COPY-04 | 909 | 45 |
| COPY-10 | 909 | 3 |
| FORM-02 | 681 | 12 |
| FORM-03 | 681 | 4 |
| FORM-07 | 681 | 16 |
| FORM-08 | 310 | 16 |
| HELP-01 | 472 | 2 |
| HELP-02 | 576 | 29 |
| HERO-01 | 444 | 26 |
| HERO-02 | 418 | 27 |
| HERO-03 | 381 | 0 |
| HERO-04 | 408 | 18 |
| LAYOUT-03 | 53 | 8 |
| MODAL-02 | 697 | 39 |
| STAT-01 | 587 | 14 |
| STAT-02 | 418 | 0 |
| TABLE-02 | 717 | 3 |
| TABLE-04 | 594 | 4 |
| TABLE-05 | 549 | 0 |
| TOAST-01 | 31 | 0 |
| TYPE-05 | 870 | 17 |

## 7. Observations

Opinions, not findings. None of these is a departure from a written rule.

1. **Fix the shared layer first.** Ninety departures sit in helpers, stylesheets and controllers, and they are the only ones a single change removes from every page. In order of reach: the required marker and tooltip help in `AppFormBuilder`; keyboard access in `tabs_controller`; an accessible name on `modal`; `delete_button`'s missing default confirmation; `ui_label_value`'s `text-sm` default.

2. **The guide documents about half of the component layer.** Of 125 shared helper methods, 46 have no entry in the guide, including some of the most used (`modal_dialog` in 47 files, `export_csv_link` in 84, `person_display_link` in 84). If `docs/UI-COMPONENTS.md` is where those live, the guide should say so per component, because "a component not documented in this design guide" is the trigger for the approval workflow (PROC-01) and today that test fails for helpers nobody would call unapproved.

3. **Several of the guide's examples are not rules, and readers will take them as rules.** My own first pass did: five rule IDs I wrote from examples had to be withdrawn (BTN-07, LAYOUT-02, SPACE-01, FORM-08, and HERO-01 outside the app shell), which moved 204 findings from DIVERGENT to UNCOVERED. Where the guide means "must", it should say so; where it means "for instance", a marker would help. Assigning IDs in the guide itself, with the CRITICAL/PREFERRED/AVOID marker on each, would settle this and make future audits diffable by rule.

4. **The guide contradicts itself in a few places.** Section titles are `font-semibold` under Heading Levels (line 533) and `font-medium` in the Typography Quick Reference (line 4033). The sticky button row is described as "using the `sticky: true` option" (line 2846) above an example that does not pass it, and the helper is not sticky unless asked (`button_helper.rb:56`). `inline-flex-center` is listed as a custom utility (line 652) and no stylesheet defines it. The radius table gives buttons and inputs 12px while the theme sets `--radius-field` to 8px.

5. **"One primary action per view" needs a definition of view.** Thirty-five BTN-04 findings are mostly list pages with a primary button per card or row (one per trainee, one per application stage) and HQ screens with several live actions. Those may be the right design. The rule would be more useful if it said whether a card, a dialog and a table row each count as a view.

6. **The schedule and timesheet screens chose a tablet tier on purpose.** The `md:` findings in `common/schedule` and `common/timesheet` come from a sticky action rail that appears at 768px. That is a design decision at odds with BP-01 rather than an accident; either sanction it as a third use of `md` or rebuild the rail on the `lg` fold.

7. **Print sheets are a second design system.** Nine sheets, five stylesheet families that repeat one skeleton, raw tables, hex literals and their own chips and callouts. They account for a large share of the TABLE-01, COLOR-01, STYLE-01 and BADGE-01 findings. One shared print stylesheet and a paragraph in the guide would retire most of them.

8. **Dense log tables want their own sanction.** Admin logs set cells in `text-sm leading-snug` deliberately, through one constant (`Admin::LogStylesHelper::LOG_TEXT`, 8 findings). TYPE-03 forbids `text-sm` table content without exception; I would add one for logs rather than enlarge them.

9. **Empty values are the cheapest consistency win.** Sixty-four places print "-", "None" or italics where `value_or_dash` exists and is already used in 65 files. It is a mechanical replacement.

10. **Severity is conservative.** Only 52 findings are `high` because reviewers were told to reserve it for what a reader can see or cannot use. The copy findings (163) are all `low` and could be cleared in one sitting.

### Reviewers' observations, as recorded

<details><summary>167 notes from the classification pass</summary>

**admin**

- The admin log tables (Action, Legacy, Error, Request, Bug Reports, Jobs, Workers) all set cell text in text-sm through LOG_TEXT; one change to Admin::LogStylesHelper::LOG_TEXT would fix every TYPE-03 row in this group at once.
- Mode buttons on Action Logs and Request Log (filled primary = current view) work as tabs; tab_navigation or a documented segmented control would settle both TABS-01 and BTN-05.
- documents/body.html.erb prints stored HTML with html_safe; besides FORM-09, the rich_text helper presumably also sanitizes, so the swap is worth checking for safety, not only looks.
- enrollment_roster marks a missing account with red bold "* unknown *" while every sibling admin page uses a warning ui_badge for the same kind of state.
- Job state "In Progress" uses a :warning badge for a normal running state; warning colour reads as trouble.
- rbs_alerts/_group.html.erb:30 calls edit_link without an aria label, so every row's button is just "Edit"; sibling tables name the record in aria-label.
- Count lines vary across admin lists: ui_section title, div.text-lg, p.text-base, filter_bar count:, strong notice. A documented count-line pattern would settle them.
- Empty-value placeholders in admin mix "-", "—", "— none —", blank cells and fact words; value_or_dash is available and prints "—".
- settings/index description "Adjust system settings" has no full stop, and settings/edit back link reads "Settings Listing" while the page title is "System Settings".

**common-a**

- The mailbox folder row and the survey report switcher are two more hand-made tab rows; tab_navigation may need a link-tab mode (Turbo stream links, aria-current) so these can use it.
- button_to built from button_classes recurs for Turbo-safe one-button forms (mailbox toggles, Select recipient); a ButtonHelper method for a one-button form would retire it.
- Several partials have no callers (_form_wrapper, _error_summary, _preferred_name_disclaimer, _turbo_partial_wrapper) and could be deleted.
- The mailbox's review-pane rows are three lines; Pattern 7 says one line per record. Either the guide should list the mailbox as a variant or the rule should be scoped to the intake pages.
- Several aria-labels replace their visible text ("Select <callsign>" vs "Select Ranger", "Mark as unread" vs "Mark Unread"), which fails WCAG 2.5.3 Label in Name; no guide rule names it.

**common-b**

- The overlapping-shift badge differs between siblings: lowercase :error with no icon on the schedule row, "Overlapping shift" :warning with an icon on the slot card.
- The Show/Hide Sign-Ups toggle swaps in a minus icon on available sign-up cards but a plain "Hide Sign-Ups" on schedule rows.
- available_sign_ups/show's Upcoming Shifts title prints stray spaces from ERB whitespace ("(3 shifts , 2 sign-ups )").
- schedule/index's phone button reads "Available Sign-Up" (singular) while the desktop box says "Available Sign-Ups".
- Work history pages format credits with "%.2f" while the timesheet and schedule pages use credit_format.
- signup_summary's three stat boxes match the guide's own ui_stat_row example word for word but are not wrapped in ui_stat_row.
- schedule/index and timesheet/index share the same two-column md/rail layout with gap-6 vs gap-4; a shared helper or partial would stop the drift.
- timesheet/edit text-area labels are sentences ending in a colon ("Enter your brief explanation below:") rather than short field names.

**communication**

- alerts/edit.html.erb has no hero description, unlike every other page in scope; the admin field label "SMS Phone " (52) has a trailing space.
- person_banners/_banner.html.erb:30-34 says the message keeps its line breaks, but the div has no whitespace-pre-line, so stored newlines likely collapse; needs a rendered check.
- announcements/_announcement.html.erb:6 dims expired cards with opacity-70 over all text, which may push muted metadata below AA contrast; needs a rendered contrast check in both themes.
- Hero back_to labels are sentence case where sibling buttons are Title Case: rbs_history/show "Broadcast history" (9) and rbs_history/retried "This broadcast" (12).
- rbs_messages/index draws ui_pager twice, and the second shows under the empty state; and its toggle column has a blank "" heading that screen readers announce as an unnamed column.
- Five hand-made bordered message/text boxes (announcement, survey prologue/epilogue, broadcast review, broadcast record, message detail row) with differing max heights suggest a shared helper is missing.
- rbs/index.html.erb:15 quotes "Any time" while the section it names is titled "Any Time".
- Stat-box variant switching by count (warning/error when positive, else secondary/success) repeats across six pages with no documented rule for when a zero is green versus neutral.

**css**

- The guide's radius table (588) puts buttons and inputs at 12px, but daisyUI draws them at --radius-field 8px; either the table or the token should move, since the two disagree on every page.
- Status tints have four alpha ladders (box /5 /20, vc-progress /10 /30, review-line /10, login /10 /26) against one documented pair (bg-x/10, border-x/30); one callout tint scale would make the semantic colours read the same everywhere.
- Frozen first column and bounded 70vh scroll pane are each written four or three times (roster-matrix, hours-credits, top-hour-earners, shift-coverage, sandman-qualified) with different z-index and breakpoint choices; a shared matrix-table component would settle them.
- The five print sheets restate one paper-preview skeleton (8.5in, masthead rule, doc label, zebra rows) in hex and pt; a shared print-sheet base file and a documented print section in the guide would replace five copies.
- The login door makes amber its brand colour (frame, wash, backdrop, links, submit gradient, focus, caret), which contradicts the guide's statement that Signal Blue is the only chromatic chrome colour; if the door is a sanctioned exception the guide should say so beside 180-188.
- The guide contradicts itself on section titles: heading-section is font-semibold (533) while the Typography Quick Reference says font-medium (4032); and the hero panel is described as .box with rounded-xl (1962) while .box is rounded-lg.
- The guide's sidebar utility table (2247-2252) documents compositions the CSS no longer has (backdrop with bg-gray-900, badge built by hand, section header p-3 semibold); it reads as stale documentation rather than a target.
- Motion handling is per component (accessibility.css, autocomplete, login); one global prefers-reduced-motion rule covering animate-spin, transitions and keyframes would close the toast, copy-success, progress and photo-board gaps at once.
- Muted ink is spelled six ways in the stylesheet layer (text-stone-muted, me-muted, text-base-content/60, text-body-subtle, text-stone-subtle, text-stone-icon); the /60 opacity spellings in progress and vc-applications sit off the documented ladder.
- --color-info sits 2 degrees of hue from --color-primary, so info callouts, info badges and brand actions are the same blue; the guide warns blue is "spoken for twice over" (290) yet keeps the overlap.

**helpers-components**

- The guide's two "sticky" button_row examples (1138-1142, 2848-2853) omit sticky: true, so as written they render an ordinary row.
- The guide's modal example (1594-1599) wraps a button_row inside m.footer, but m.footer is already a button_row, so the sample nests one row in another.
- The guide contradicts itself on stat-box labels: ui_stat_box :sm is documented with a text-xs label and :md with text-sm (1340-1341), while TYPE-02/TYPE-03 bar those sizes for labels a reader needs.
- hero_panel's :h2 title is text-xl font-semibold (documented at 471), while TYPE-04 says every h2 takes heading-section; one of the two should give way.
- export_csv_link is the code's one export affordance, but the guide's records-management examples (3401, 3450) still spell button_link "Export CSV", :secondary; naming the helper in the guide would stop that drift.
- ui_callout_box defaults role="alert" for every type. An info, success or secondary note announced as an alert on each render is noisy; role="note" or none for static types would be calmer.
- Status icons drawn without label: (record_title, qualification_icon, photo_tag fallback) leave screen-reader users without the state that sighted readers get from shape and colour.
- tab_navigation names every tablist "Tabs"; taking a label from the caller would give each its own name.
- modal defaults to size :lg (max-w-2xl) while its header comment says :md, so every confirm_modal_dialog opens at 2xl for a one-line question.
- render_progress_bar floors progress to 5% and reports that in aria-valuenow, so "0 of 10" is announced as 5 percent.
- back_to's hover goes from text-body to text-stone-emphasis, which resolve to the same token; the link has no visible hover change.
- dropdown_item_disabled draws text-sm at base-content/40, likely below AA contrast; it has no callers, so this is latent.
- Icon default style varies by helper (button_action, ui_section, ui_empty_state regular; ui_badge, ui_accent_card, ui_stat_box solid); one default would cut the regular-glyph raises fa_icon guards against.
- Two progress-bar implementations coexist (ui_progress_bar utility-built, render_progress_bar custom CSS with gradient and pulse); the guide documents both without saying when to use which.
- delete_button renders an a with data-turbo-method rather than a button, so a destructive action is announced as a link.
- ui_disclosure :card bolds plain-string titles but not SafeBuffer ones, so two cards with the same title can differ in weight depending on how the caller built it.
- clipboard_button meets the 36px floor through a before:-inset-3.5 pseudo-element rather than min-h-9; TOUCH-01 does not say whether that counts.

**helpers-forms**

- The guide's required-field text (asterisk plus SR "(required)") and the builder disagree in both directions; pick one marker (asterisk with sr-only text at text-sm or larger) and make check_box and radio honour required: too.
- help_mode: :tooltip is documented as a peer of :inline but cannot reach keyboard or screen-reader users; either drop it from the guide or render the help in a focusable disclosure and keep the describedby target.
- The `form fieldset` selector in components/forms.css styles every fieldset in a form, so builder radio groups (class mb-3) likely pick up the primary left border and gradient meant for f.fieldset; needs a rendered page to confirm.
- A failed submit announces one role="alert" per invalid field plus the summary callout; consider role="alert" on the summary only and plain describedby text on fields.
- A field's help text disappears while it shows an error (field_suffix); readers lose the hint at the moment they need it. Showing both with two ids in describedby would keep it.
- Two error summaries and two form wrappers exist; common/_form_wrapper has no callers and common/_error_summary is used only by it. Removing both leaves ui_form as the single path.
- The guide documents 120px textarea height and Vanilla Calendar for date_field/time_field (2498-2503); the code gives 80px and native pickers. Either the guide or the builder should move.
- callsign_chips_field: the guide's "aria-label is Add a callsign" (2571) is stale; the code deliberately lets the visible label name the input. Update the guide.
- RolesHelper#has_role? returns a truthy array for any signed-in user without checking the role; worth confirming which has_role? views resolve to, since ApplicationController also exposes one.
- DateTimeHelper::CSV_TIME omits seconds while the guide's table lists CSV as "2026-01-08 14:30:00"; the guide row may simply need splitting into logs (seconds) and CSV (minutes).
- filter_bar's panel (rounded-base border) and chip (hand-built pill) could reuse rounded-lg and a badge-like utility; the chip and the callsign chip are two hand-built pills with different padding and remove controls.

**hq-assets**

- Stat-box labels are not in COPY-03's list, and the area is mixed: hq/timesheets/event_summary uses ALL CAPS (TOTAL HOURS, CREDITS, POSITIONS), while radio_checkout (Overdue radios, Radios flagged) and events_rangered (Not signed up) use sentence case beside Title Case siblings.
- components/hq-window.css line 37 adds an md..lg tablet tier for .hq-shell that is not @media screen and is not in the BP-03 table (which documents only 1800px and 2400px); BP-01 limits md: to button-row stacking.
- The HQ guided-flow accordion (_section) and suggested-task checklist (_todo_list, _todo_chip) say they are plan-approved, but neither is documented in DESIGN-GUIDE.md, so PROC-01 documentation looks outstanding.
- The two radio report siblings switch views differently: Radio Assets shows one :primary button naming the other view; Radio Checkout shows both views with the current one filled. The guide has no toggle or segmented-control pattern.
- Nine templates wrap a button_row in a bare div.my-4 or div.mb-4 just for spacing; a margin option on button_row (or a documented default) would remove the one-off wrapper.
- Status sentences on the On-Site Registration page are coloured h3 headings (heading-title text-success/text-error); they read as notices and might belong in ui_callout_box rather than in the heading outline.

**js**

- Tabs are the most serious JS finding: tabs_controller and camera_controller both use roving tabindex without arrow keys, so idle tabs are keyboard-unreachable on every tab_navigation page. Either add ArrowLeft/Right/Home/End or drop tabindex -1.
- Four confirmation mechanisms coexist (Turbo dialog, native window.confirm in unsaved-changes, confirm_checkbox and permission-editor submit). A JS helper that opens confirm_modal_dialog markup through Turbo.config.forms.confirm would let them all use the app dialog.
- animate-spin has no global prefers-reduced-motion override (accessibility.css only stops animate-pulse); the guide's claim that the approved set honours reduced motion is untrue for spinners anywhere, not only the autocomplete.
- Icons set from JS as raw class strings (autocomplete spinner, hq-shift chips, table-sort) bypass fa_icon's regular-style check (ICON-03); the guide says nothing about icons drawn at runtime.
- read-more defaults its toggle text to lowercase "more"/"less"; toggle swaps whole innerHTML labels. A single disclosure helper with documented label rules would settle both.
- Silent failures: copy-to-clipboard empty catch, tabs remote fetch logs to console only, pod-people/sortable PATCH errors unhandled. The guide's "immediate feedback" preference suggests a visible failure state.
- app/javascript/controllers/application.js sets Stimulus application.debug = true in every environment, logging every controller lifecycle event in production consoles.
- photo-board auto-advances groups every 5s on a wall display; the guide's AVOID on carousels is aimed at reader pages, and an explicit kiosk exception would make that clear.

**me**

- The dashboard step fragments carry ~15 one-line red text-error notices (several in ALL CAPS) inside status-coloured accent cards; the guide should say whether these are inline notices needing ui_callout_box, so they can be ranked consistently.
- Typographic arrows ("→") are used as connectors in about 12 dashboard step fragments; the guide does not say whether such glyphs count as icons, and the same steps elsewhere use an arrow-right fa_icon.
- Several buttons carry an aria-label that does not contain or differs from their visible text (_mvr_status_eligible:36 "Submit MVR Request", _pvr_status_eligible:12, _pvr_status_potential:20, vehicles index:46), which can break voice control (WCAG label-in-name); no guide rule covers it.
- Dead or unrouted code: app/views/me/event_info.html.erb has no route and placeholder tab text; dashboard_tasks/_dashboard_survey.html.erb has no caller; DashboardHelper#dashboard_step_status_class and #dashboard_step_icon have no caller.
- The awards page shows a reference info callout ("What These Awards Recognize") in its body; if the page counts as a report under HELP-02, that belongs in a collapsed About card. The guide's report-or-operated test does not clearly classify a page with no controls.
- Ticket claim actions use :success on sap.html and review.html but :primary on vehicle_pass.html and ticket.html; one variant for "claim" across the ticket wizard would read more consistently.
- Many TYPE-03 and TYPE-04 judgments in dashboard steps assume the ui_accent_card title renders as heading-title (text-base); a rendered page would confirm whether text-lg lines outweigh it.

**mentoring**

- Three print views (acceptance print_sheets, mentor assignments print_sheet, pods print_sheet) copy the _print_screen_nav block inline, and the pods sheet copies _sheet_masthead by hand; one partial with label and hint locals would remove the drift.
- The guide has no print-sheet pattern (back link outside a hero, masthead, @page rules in content_for :page_rules), so every sheet here reads as a HERO-01, HERO-04 and STYLE-01 departure; documenting it would turn these into one ruled exception.
- Several filtered pages pair filter_bar's primary "Apply Filters" with the page's own primary submit; the guide could say whether the filter bar's submit counts toward BTN-04.
- Alpha Sign-Out and Mentor Shift Report deliberately use an :error callout for live data and a :success callout for neutral shift info; a neutral or info variant would carry that without borrowing status colours.
- alpha_pods/index badges the pod count in :primary and the empty state in :secondary; primary for a count sits uneasily with COLOR-04 (primary for primary actions and key elements).
- The Training Notes box on the acceptance form prints empty when there are no passed trainings while the other notes boxes print a sentence; the inconsistency shows on paper.

**person**

- Create-form heroes say "New Access Document", "New Banner", "New Certification", "New FKA", "New Pog", "New Missing Timesheet Request" while the buttons that open them say "Add ..."; COPY-04 covers action labels, not page titles, but the reader sees two verbs.
- The same fact is drawn several ways across the area: "inactive" as red "[inactive]" text (_position_checkbox) and as ui_badge (_team_card); "Still On Duty" as a :warning badge (timesheets helper) and as red italic text (timesheets/log); the change arrow as fa_icon (access_documents/history) and as &rarr; (_log_entry_data).
- Count lines use four neutral treatments: me-muted (applications, certifications, status_history, tickets_provisions), text-body (scheduling/log), text-base-content/80 (pogs, swag) and no class (timesheets/index). One count-line helper would settle it.
- Vintage is ui_badge :secondary in the overview hero but :success on callsigns/edit.
- timesheet_status_badges paints "Correction Requested" :error and "Correction Rejected" :warning, so the pending state reads as more alarming than the rejected one.
- person/banners shows the same two visibility callouts on the index and again inside the form; on the form they could be one.
- callsigns/edit hides the Release Callsign action below lg with "hidden lg:flex", so the action does not exist on a phone.
- ui_label_value uses label_width "9rem" in contact details and "7rem" in the summary strip on the same page; certifications/show hand-builds the same display with grid-cols-[8rem_1fr].
- intake_notes/edit shouts "ADD A NEW NOTE." in capitals inside the warning; bold alone would carry it.
- Person::TimesheetsHelper#timesheet_status_icon and #missing_request_status_icon have no callers and could be deleted.
- site_log's filter submit is :secondary while timesheets/index's is the default primary; filter_bar submits should agree.
- Several pages wrap the whole body in an untitled ui_section (applications, certifications/index, status_history, empty states on scheduling/log and site_log); the guide never says whether a section may be untitled.

**scheduling**

- Apply Filters is the default primary variant on hq_forecast, burn_perimeters, sandman, schedule_by_callsign, shift_coverage, shift_drop and shift_signups but :secondary on early_arrivals, shift_lead, slots, credits and the copy pages; one convention would help.
- The Inactive slot badge is :secondary (slot_status_badge, Inactive position badges) on most pages but :warning in slots/position record_title and "N inactive" on slots/index.
- Icon-only edit_link on position credits versus a text "Edit Slot" edit_link on slots/position, two sibling records pages.
- Activate All / Deactivate All on slots/position change every slot of a position in one click with no confirmation.
- flake_report/position.html.erb:94 builds an empty-state message with .html_safe around an interpolated string; safe today (integers only) but fragile.

**shell-auth-profile**

- layouts/print, layouts/photo_board and layouts/bookmark render no flash at all. Harmless only if no controller sets flash before landing on those pages; that cannot be checked from the views.
- The door pages (sign in, forgot, reset, SSO) form their own consistent family: amber :warning lg submits, sessions/_heading, login.css panels, warning-tinted icons. The guide documents login.css and a motion exception but no hero or button exception; one written ruling would settle a dozen findings.
- sessions/forgot.html.erb shows a "Reset Password Disabled" warning above a working reset form; if the feature really is off, the form should not render, and if it is on, the notice is stale.
- profile/_alerts yes/no icons have no text alternative, so a screen reader hears empty SMS/Email cells; fa_icon label: (as ICON-04 describes) would fix it.
- Copy errors: profile/show:62 "Be alerted when to when new Clubhouse Message are received"; profile/_mailing_address:8-9 "to update update your profile"; layouts/me/timesheet:9 "Any timesheet entry ... are placeholders"; profile/show:49 says "Withdraw Photo" but the button reads "Withdraw".
- The search mode segmented control shows the selected mode only by a primary fill (has-[:checked]:bg-primary); worth a check that the checked segment reads as selected without colour.
- The search dialog input is named by aria-label while the visible mode hint above it is not tied to it; tying the hint by aria-labelledby or aria-describedby would match FORM-02's intent.
- _dialog_status titles are h3 inside dialogs that have no h2; h2 would keep the dialog's own outline clean.
- Register step chips use sentence-case questions ("Why are you here?") as labels; COPY-03 does not list badges, but they read as headings.
- application/_recipient_avatar has no partial caller per the Phase 1 agent; it may be dead.
- profile_photos/new "must NOT have" and profile/_mailing_address "are NOT synced" use capitals for emphasis.

**teams-people**

- Retention Report's table comment says it "stays a table and scrolls sideways", but the ui_table call omits responsive: false, so it folds to cards; the comment or the call is stale.
- Hero titles "New Position", "New Team" and "New Position Lineup" use the verb COPY-04 bans on buttons; the guide does not say whether a form page's title follows the Add verb.
- Apply Filters is :secondary on every teams_positions page, certificates and languages_known, but default primary on people_by_location, retention, unified flagging and status change pages; the area disagrees with itself.
- Level-1 drill indexes split two ways: text-lg count line (certificates, people_by_status, status change, roster, team documents) versus filter_bar count slot (membership, position grants, people_by_location).
- status_change_vintage puts aria-label on a role-less span, which assistive tech usually ignores; roster_management_helper's NOT_GRANTED uses sr-only text for the same job.
- Position Grants detail prints a bare "—" for not on site with no screen-reader text, while the on-site icon carries sr-only "On site".
- The amber text-warning count on the roster cards, and the opacity-75 clear rows on the sanity board, need a rendered contrast check in both themes.
- Special Teams Hours collects its report parameters in a ui_form inside a "Report Parameters" disclosure rather than a filter_bar; it reads as a run form, but it narrows the table the way filters do.
- Edit-page hero descriptions ("Training #12 — 5 people granted it, 3 shifts.") describe the record, not what the page does.
- Read-only permission grants show as plain divs on the position form and as secondary badges on the team form.

**ticketing-bmid**

- bmid/manage/_edit_grid renders the same primary "Save All Changes" submit at top (34) and bottom (157); worth deciding whether a duplicated primary meets BTN-04.
- The Skipped-items list exists three times: ticketing/trs_export/_skipped, bmid/export/_skipped and inline in bmid/export/unsubmit.html.erb:41-49. Candidate for one shared partial.
- The "Missing" arrival alarm is a shared partial (_summary_missing) but records.html.erb:66-68 inlines a copy without whitespace-nowrap.
- Count headlines above ledgers vary: div text-lg (three results pages), p text-lg (maintenance/preview), ui_stat_row (bmid results pages). No rule settles which.
- Boolean display varies: yes_no_badge, plain Yes/No (ticketing/provisions:68, bmid/badges/edit:80), and Yes/— (bmid tables). A rule would help.
- Filter bar Apply is default primary on ticketing and sanity check but :secondary on bmid manage and export; on trs_export/index the default creates a second primary.
- bmid/manage/index:120 empty message says "matching the filter criteria" on the branch where no filter is active.
- The bmid Edit Mode / Table View switch is one primary or secondary button_link; a mode toggle may read better as tabs or a segmented control.
- maintenance/results has no Back button in its empty state while unsubmit_provisions/results and maintenance/preview do.
- Field widths with lg: (trs_export/index:75 "w-full lg:w-96", bmid/export/index:79) differ from the guide's sm: width convention.

**timesheets-shiftops**

- Three table partials carry comments saying "desktop-first, scrolling sideways rather than restacking" (early_late_checkins/_section 28, forced_shift_start 77, timesheet_unconfirmed/_group 9) while the code keeps the responsive default; the comments mislead.
- Every filter bar sets its fields width: "w-full" with wrapper_class "flex-1"; FORM-07's width table does not say how fields inside filter_bar should size.
- Stat-box labels mix Title Case and sentence case on one row (On Duty: "On duty", "Out Longer Than Usual", "No shift attached"; slot repair "Shift to add"); COPY-03 does not list stat labels.
- Drill-down meta lines join parts with " • " on three pages (by position, by callsign, totals) and " · " everywhere else; one separator would read as one system.
- The ROC Photo Board is an unattended wall display with its own layout and CSS; a written kiosk exception would settle HERO-01 and the custom headings, cards and badges.
- Cruise Direction and Roll Call pickers are deliberate auto-submitting GET form_tags (the set-time dialog comment calls them the year_selector navigation pattern); the guide could document an auto-submit picker so FORM-01 stops flagging them.
- Hours & Credits hand-writes its thead, so the builder never collects column labels; whether the table folds into labelled cards below lg needs a rendered check at phone width.
- Sanity checker dims clear checks with opacity-75 on ui_drill_down_row; contrast in both themes needs a rendered check.
- Several modal and dialog paragraphs explain in text-sm or as red bold text where a callout already exists beside them (unavailable, people/_dialog, set-time and blocked dialogs); one callout per message would be calmer.

**training**

- clipboard_button is called without label: on completed_training/show (two tables) and multiple_enrollments (one per section), so several icon-only buttons share the name "Copy to clipboard"; the helper's own comment asks for a label wherever a page shows more than one, and the visible "Copy N addresses" text is not part of the button.
- "Add <callsign>" and "Add Anyway" submit an add directly, while COPY-04 reserves "Add X" for opening a create form; the rule has no verb for adding a person to a group (its counterpart to "Remove from X").
- rosters/_blocked falls back to "The sign-up was refused [<status>]." which prints a raw verdict code to the reader.
- The mentor assignment roster's back link reads "Choose another shift" (aria "Back to Choose another shift"), a verb phrase in sentence case where every sibling page's back_to names a page.
- The work history dialog opens with a visible three-sentence explanation (what is counted, what is excluded, how to drill down); HELP-02 does not say whether a report-style dialog should fold this into a card.
- The capacity, completed-training, multiple-enrollments and trainer-attendance pages put Export CSV in a button_row inside a bare my-4 div, while their filtered siblings put it in filter_bar actions:, so the export sits in two places across the area.
- The mentoring landing has no back link while its three sub-pages back to it; the session landing likewise has none.

**vc**

- _notes_list, photos_review/_photo and info hand-write <h3 class="heading-title text-heading mb-2">, the exact classes ui_subheading emits; ui_subheading would keep them in step.
- VC stage cards title each stage with a span inside <summary>, so the review page's main column has no headings between the h1 and the rail's h2s; a screen-reader user cannot jump between stages by heading.
- application_status_badge prints "Bug [status]" to reviewers for an unknown status; a neutral fallback label would read better.
- Lone buttons (export links in mt-3 divs on application_import, the upload commit submit) sit outside button_row; BTN-07 does not say whether a single button needs one, worth ruling on.
- The "Vintage" handle-type badge uses :error though vintage is not an error state; :warning may fit the meaning better.
- Spigot Flow headings are right-aligned (right: true) while every cell is centred (center: true), so columns do not line up with their headings.
- reset_pnvs empty state reads "Odd, no qualified applicants were found." — a tone departure from the other empty states; no copy rule names it.
- Several dialog fields (approve_callsign, edit_approved_handle, assign, adjust_status) rely on the builder default w-auto width; FORM-07 does not say whether that default counts as fitted.

</details>
