# Follow-ups from the design-consistency pass

Written 2026-11-12. The pass closed 1,417 of the 1,490 work-list rows (1,058 fixed, 253 already compliant,
93 waived by ruling, 13 rejected as audit misreads). The 73 below were left on purpose: 38 need the
maintainer's approval and 35 are blocked on work outside a design pass. Each row's ID is in
`plan/ledger/<package>.txt` with the file and line.

Recommendations are Claude's. Nothing here has been built.

## A. Needs a decision (38)

| # | Decision | Findings | What it would change | Recommendation |
|---|---|---|---|---|
| A1 | A scroll-box helper, `ui_text_box(max_height:)` | R12116, R12231, R12206, R12191, R12182, R12140 | Replaces 8 hand-built bordered, tinted, scrolling text boxes in the messaging pages | Approve: eight copies of one block is past the "third occurrence" rule |
| A2 | Decorative hero and action-box icons in gold | R00795 (and C0301's icon) | Neutral icons on every page header | Keep the gold and write it into the guide as the hero's look |
| A3 | Hero-stat award gold and flame gradient | C0064 | Replaces two pinned colours with tokens | Keep; document beside A2 |
| A4 | Person page header | F0135 | Moves badges, name and pronouns out of the hero description | Leave: it is the page's identity strip; write the exception |
| A5 | Mailbox folder tabs as a button group | R11899, R11766, R11792 | The guide's own new wording (a switch that loads another view is not tabs) restyles the mailbox | Keep the tabs and exempt the mailbox in the guide, or accept the restyle; needs your eye on a mockup |
| A6 | Mega menu: visible search label, panels as tabs | R04672, R12625 | Header layout change; panel switch redesign | Add the visible label (accessibility); leave the panels |
| A7 | Announcement row link styled as a button on a span | R12596 | Either a text link in the row or a real Read button | Real button; small change |
| A8 | Records pages: level-1 filter bars and the "N on duty" badge | F0225, F0226, F0227, F0228, F0231 | The layout rule would remove filters that decide what each row counts | Keep them; amend the records-management rule to allow a filter that scopes the counts |
| A9 | People Search criteria as a fieldset | R13777 | Reverses an earlier ruling of yours that a test pins | Keep your earlier ruling; exempt the panel in the guide |
| A10 | Shift Lead roster's phone list | R13270, R13271 | Standard table fold instead of the hand-built list | Keep; the partial documents why the fold was rejected |
| A11 | Red "live data" banners on the mentoring shift report and sign-out | R12787, R12840 | `:warning` or `:info` instead of `:error` | Keep red: it was an approved mockup |
| A12 | HQ window: guided-flow section, pinned checklist strip and its shadow | R12266, R12269, R04328 | Accordion and card styling on purpose-built HQ pieces | Keep; add the pinned strip to the guide's shadow table |
| A13 | Toast inside the HQ wizard dialog | R04402 | Needs a top-layer toast region | Defer with the controller work in B3 |
| A14 | Roll call roster row as one whole-row button | R14285 | New `ButtonHelper` method or a written exception | Written exception: the whole-row target is the point on a tablet |
| A15 | Segmented radio control in the search bar | R01638 | A segmented variant or helper | Approve a small variant if it appears a second time; leave for now |
| A16 | Drag-and-drop file field | R13559, R07350 | A dropzone variant of `f.file_field` | Leave: one use |
| A17 | A paper-white print token | R04479, M0092 | `--color-paper` in place of `bg-white` on print | Approve: print must be white and the palette ban has no token for it |
| A18 | `ui_section border: false` | C0340 | Make it remove padding as once documented, or retire it | Retire the option after checking its callers |
| A19 | Date picker's 768px switch to the native control | C0496 | Would move to the `lg` fold | Keep 768px: it is a touch-device swap, not a layout fold; say so in the guide |
| A20 | Mentoring roster form errors | R14543 | Expose the save result as model errors | Defer with B3 |

Also still open from Phase 2: the form fieldset's left border (`forms.css`), which the design hook flags
on every edit of that file. The guide documents it as the theme's look; an ignore has to come from you.

## B. Blocked on work outside this pass (35)

### B1. Form builder features (17)

- **Array-checkbox field** (R11686, R02218, R11688, R13097): `common/_checkbox_grid`, `_checkbox_row`,
  `_checkbox_tile` and their 12 callers still use `check_box_tag`.
- **Indexed repeated rows with per-row errors** (R01495, R11633, M0003, R11634, R01491, R01494, R01492):
  `admin/shift_coverage_positions/_position_rows`.
- **Compact inline layout** (C0260, R00315, R00317, C0261, M0293, R00313): the year selector in
  `page_layout_helper.rb`. Custom-id labels now work; the layout is what is missing.

### B2. Small helper additions (7)

- `button_helper.rb`: a `:link` variant (R11947) and a one-button POST form method for `button_to`
  (R11762, R02676).
- `navigation_helper.rb`: a non-link dropdown heading and text row (F0172, R13008).
- `ui_card_title`: a trailing badge slot (R14073).
- `common/provisions/_form`: a modal footer split so the BMID provision dialog's buttons sit in the footer
  (R13904).

### B3. Controllers that report a failure only as a toast (10)

The guide now asks for an error callout or a field error. Each needs its controller to hand the errors to
the view.

- `scheduling/position_credit_copies` (R13410), `slot_bulk_edits` (R13403), `slot_copies` (R13309)
- `teams_positions/bulk_positions` (R13604), `bulk_teams` (R13592)
- `vc/photos_review#reject` (R14699)
- `me/surveys` (R12664): must name the question in each error
- `ticketing/maintenance` (R13870)
- `admin/sms_management` Twilio frame (R01563): a streamed toast
- `shift_operations/rollcall` set-time dialog (R14275): an action that renders into the modal frame

### B4. Kept as it is (1)

- `toggle_controller.js` (C0494): four of its seven views moved to `ui_disclosure`. The schedule's
  signed-up row, the sign-up slot and the timesheet entry keep it, because each lazy-loads a frame beside
  another button and system tests pin the button and the tab order.

## C. Not rendered, still to look at

Code and tests cannot confirm these. Check them on a page before release.

- Tabs by keyboard (arrow, Home, End), on any `tab_navigation` page and the photo upload page. The tab
  list's accessible name is the helper's fixed "Tabs".
- The HQ summary's container query (lays across from 40rem, an estimate) at tablet width.
- Light mode and 375px for the pages most changed: the schedule, the timesheet, HQ shift manage,
  Shift Lead, person memberships, the photo upload and crop pages.
- The VC applications index: filters now apply with a button, not on change.
- Person permissions edit: the Grant column is folded into the Permission column.
- The credit chart's axis at `text-sm` on a phone (31 day numbers).
- The five print sheets on paper: margin-box colours are now literal greys.
- Toasts with reduced motion on; the leave guard on the HQ shift page.
- Labels in `app/lib` the pass could not reach: "End The Shift", "Start A Shift" (HqTodo), and the dialog
  titles R13745 names.
