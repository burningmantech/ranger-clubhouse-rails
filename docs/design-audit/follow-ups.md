# Follow-ups from the design-consistency pass

Updated 2026-11-12, after the maintainer approved section A's recommendations and asked for the B3
controller fixes. Of the 1,490 work-list rows, 1,464 are closed (1,080 fixed, 253 already compliant, 118
waived by ruling or approved exception, 13 rejected as audit misreads). 26 remain: 25 blocked on new helper
or builder work and 1 deferred. Each row's ID is in `plan/ledger/<package>.txt` with the file and line.

Nothing below has been built.

## Done since the first version of this list

- **Section A (20 decisions):** approved as recommended. Built: `ui_text_box`, the mega menu search label,
  the announcement row's real button, `--color-paper`, and the retirement of `ui_section`'s `border:`
  option. The thirteen kept exceptions are written into the guide. A13 stays deferred (below).
- **Section B3 (10 controllers) and A20:** each page now reports a refusal on the page (an error callout,
  the builder's summary or a field error) instead of only in a toast.

## A. Deferred decision (1)

- **A13, a toast inside the HQ wizard dialog** (R04402, `hq/site_registration/_radios_step`): the step
  lives in a top-layer dialog, where a layout toast is dimmed behind it. It needs a toast region in the top
  layer, which is a new shared component.

## B. Blocked on new helper or builder work (25)

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

### B4. Kept as it is (1)

- `toggle_controller.js` (C0494): four of its seven views moved to `ui_disclosure`. The schedule's
  signed-up row, the sign-up slot and the timesheet entry keep it, because each lazy-loads a frame beside
  another button and system tests pin the button and the tab order.

## C. Found along the way, not on the work list

- **Training mentoring, Promote Without a Verdict:** when nothing is left to promote, the 422 page reports
  that only as a toast (`assignments_controller.rb`).
- **Person permissions edit:** the "—" cells sit at the top of each row while the checkbox sits in the
  middle.
- **Tab lists are all named "Tabs"** for screen readers (`tabs_helper.rb` hard-codes it); the photo upload
  page's used to say "Photo source". `tab_navigation` needs a `label:` option.
- **Labels in `app/lib`** the pass could not reach: "End The Shift", "Start A Shift" (HqTodo), and the
  dialog titles R13745 names.
- **Stale comments** in `shift_manage_concern.rb` and `hq/shift_manage/index` still name the old label
  "End Shift & Submit Correction".
- **`bin/css_check` reports two false failures**: it matches the element id `camera-select` and the `mt-0`
  inside `mt-0.5` as classes that no longer compile.
- **The form fieldset's left border** (`forms.css`) is flagged by the design hook on every edit of that
  file. The guide documents it as the theme's look; an ignore has to come from the maintainer.
- `test/lib/copy_casing_test.rb`, once cited as the Title Case guard, does not exist.

## D. Not rendered, still to look at

Code and tests cannot confirm these. Check them on a page before release.

- **The HQ window:** the summary's container query (lays across from 40rem, an estimate) at tablet width,
  and the leave guard on the HQ shift page. The test account used could not open HQ.
- **The B3 pages:** each refusal callout (slot bulk edits was checked: a refused submit from the foot of
  the page scrolls to the callout and focuses it), the photo reject dialog reopening with its error, the Twilio
  frame's callout and streamed toast, the roll call set-time dialog in the modal frame.
- **The approved items:** the announcement row without its hover state, the mega menu search label, the
  positions scroll box (now tinted, `p-3`).
- **The five print sheets on paper:** margin-box colours are now literal greys; the page is `bg-paper`.
- **The delete confirmation dialog**, and toasts with reduced motion on.
- **Light mode and 375px** for everything but the schedule, the timesheet, person memberships and person
  permissions, which were checked.
- The VC applications index (filters apply with a button), the credit chart's axis at `text-sm` on a phone.
