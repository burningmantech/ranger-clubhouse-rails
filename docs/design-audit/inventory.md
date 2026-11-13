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


## Per-area page inventories

One file per `app/views` area; each lists every template with its route, layout, the partials it
reaches, and every pattern variant found in those files with `file:line`.

| Area | Templates | Pages | Fragments | Other | Inventory rows | File |
|---|---|---|---|---|---|---|
| admin | 45 | 37 | 6 | 2 | 1069 | [inventory/admin.md](inventory/admin.md) |
| alerts | 1 | 1 | 0 | 0 | 60 | [inventory/alerts.md](inventory/alerts.md) |
| asset_management | 10 | 10 | 0 | 0 | 275 | [inventory/asset_management.md](inventory/asset_management.md) |
| bmid | 14 | 11 | 3 | 0 | 495 | [inventory/bmid.md](inventory/bmid.md) |
| bookmarks | 3 | 2 | 1 | 0 | 36 | [inventory/bookmarks.md](inventory/bookmarks.md) |
| bug_reports | 1 | 0 | 1 | 0 | 16 | [inventory/bug_reports.md](inventory/bug_reports.md) |
| certificates | 2 | 2 | 0 | 0 | 38 | [inventory/certificates.md](inventory/certificates.md) |
| common | 29 | 25 | 2 | 2 | 1525 | [inventory/common.md](inventory/common.md) |
| communication | 23 | 23 | 0 | 0 | 740 | [inventory/communication.md](inventory/communication.md) |
| dashboard_tasks | 69 | 0 | 69 | 0 | 443 | [inventory/dashboard_tasks.md](inventory/dashboard_tasks.md) |
| hq | 21 | 17 | 2 | 2 | 1427 | [inventory/hq.md](inventory/hq.md) |
| layouts | 27 | 0 | 0 | 27 | 2908 | [inventory/layouts.md](inventory/layouts.md) |
| mail | 1 | 0 | 0 | 1 | 7 | [inventory/mail.md](inventory/mail.md) |
| me | 47 | 44 | 1 | 2 | 2136 | [inventory/me.md](inventory/me.md) |
| mentoring | 27 | 14 | 5 | 8 | 1157 | [inventory/mentoring.md](inventory/mentoring.md) |
| people | 13 | 13 | 0 | 0 | 480 | [inventory/people.md](inventory/people.md) |
| person | 70 | 68 | 0 | 2 | 2662 | [inventory/person.md](inventory/person.md) |
| pogs | 3 | 3 | 0 | 0 | 69 | [inventory/pogs.md](inventory/pogs.md) |
| profile | 6 | 6 | 0 | 0 | 210 | [inventory/profile.md](inventory/profile.md) |
| profile_languages | 3 | 3 | 0 | 0 | 52 | [inventory/profile_languages.md](inventory/profile_languages.md) |
| profile_photos | 2 | 2 | 0 | 0 | 95 | [inventory/profile_photos.md](inventory/profile_photos.md) |
| public | 5 | 0 | 0 | 5 | 5 | [inventory/public.md](inventory/public.md) |
| pwa | 2 | 0 | 0 | 2 | 1 | [inventory/pwa.md](inventory/pwa.md) |
| quartermaster | 11 | 11 | 0 | 0 | 248 | [inventory/quartermaster.md](inventory/quartermaster.md) |
| register | 1 | 1 | 0 | 0 | 24 | [inventory/register.md](inventory/register.md) |
| scheduling | 35 | 31 | 3 | 1 | 1002 | [inventory/scheduling.md](inventory/scheduling.md) |
| sessions | 4 | 4 | 0 | 0 | 159 | [inventory/sessions.md](inventory/sessions.md) |
| shift_operations | 16 | 10 | 6 | 0 | 602 | [inventory/shift_operations.md](inventory/shift_operations.md) |
| sso | 2 | 2 | 0 | 0 | 32 | [inventory/sso.md](inventory/sso.md) |
| teams_positions | 26 | 26 | 0 | 0 | 702 | [inventory/teams_positions.md](inventory/teams_positions.md) |
| test_harness | 2 | 0 | 0 | 2 | 73 | [inventory/test_harness.md](inventory/test_harness.md) |
| ticketing | 17 | 17 | 0 | 0 | 534 | [inventory/ticketing.md](inventory/ticketing.md) |
| timesheets | 17 | 17 | 0 | 0 | 521 | [inventory/timesheets.md](inventory/timesheets.md) |
| training | 32 | 22 | 6 | 4 | 1018 | [inventory/training.md](inventory/training.md) |
| vc | 37 | 23 | 14 | 0 | 972 | [inventory/vc.md](inventory/vc.md) |
| vehicles | 5 | 5 | 0 | 0 | 165 | [inventory/vehicles.md](inventory/vehicles.md) |

## Pattern variant catalogue

Every implementation variant found, per pattern. `Files` counts files containing it, `Pages` counts
page templates that reach it directly or through a statically rendered partial.

### buttons (84 variants)

| Variant | Impl | Files | Uses | Pages | Examples |
|---|---|---|---|---|---|
| `button_row` | shared-helper | 314 | 391 | 347 | `helpers/button_helper.rb:52` `helpers/modal_helper.rb:82` `views/admin/action_logs/index.html.erb:8` |
| `f.submit` | form-builder, shared-helper | 209 | 265 | 260 | `helpers/modal_helper.rb:83` `views/admin/action_logs/index.html.erb:72` `views/admin/documents/_form.html.erb:28` |
| `button_link` | shared-helper | 193 | 554 | 173 | `helpers/admin/jobs_helper.rb:71` `helpers/admin/log_styles_helper.rb:41` `helpers/asset_management/radio_checkout_helper.rb:19` |
| `cancel_link` | shared-helper | 69 | 73 | 109 | `helpers/button_helper.rb:175` `views/admin/documents/_form.html.erb:29` `views/admin/event_dates/_form.html.erb:37` |
| `delete_button` | shared-helper | 59 | 121 | 97 | `helpers/admin/jobs_helper.rb:75` `helpers/button_helper.rb:217` `views/admin/bug_reports/index.html.erb:74` |
| `export_csv_link` | shared-helper, area-helper | 84 | 101 | 83 | `helpers/button_helper.rb:204` `helpers/shift_operations/payroll_export_helper.rb:111` `views/admin/sms_management/index.html.erb:108` |
| `helper-class-override` | shared-helper, area-helper | 57 | 157 | 67 | `views/admin/settings/index.html.erb:19-21` `helpers/admin/action_logs_helper.rb:153-160` `views/common/_move_buttons.html.erb:12` |
| `edit_link` | shared-helper | 48 | 66 | 50 | `helpers/button_helper.rb:185` `helpers/ui_components/ui_section_helper.rb:93` `views/admin/documents/body.html.erb:10` |
| `button_action` | shared-helper | 45 | 113 | 43 | `helpers/admin/action_logs_helper.rb:153` `helpers/button_helper.rb:106` `helpers/mega_menu_helper.rb:100` |
| `modal_close_button` | shared-helper | 30 | 33 | 28 | `helpers/modal_helper.rb:84` `views/bmid/provisions/_list.html.erb:38` `views/bug_reports/new.html.erb:31` |
| `class:btn` | daisyui-class | 18 | 23 | 27 | `helpers/modal_helper.rb:185` `helpers/ui_components/clipboard_helper.rb:29` `helpers/ui_components/ui_match_stepper_helper.rb:37` |
| `submit_button` | shared-helper | 28 | 44 | 26 | `helpers/button_helper.rb:239` `helpers/modal_helper.rb:83` `views/bmid/manage/_edit_grid.html.erb:34` |
| `cancel_button` | shared-helper | 18 | 23 | 19 | `helpers/button_helper.rb:169` `views/admin/settings/edit.html.erb:48` `views/bmid/titles/_form.html.erb:38` |
| `oneoff:button-group-div` | one-off-markup | 5 | 15 | 15 | `views/common/messages/_compose_buttons.html.erb:5` `views/common/messages/_messages_panel_header.html.erb:55` `views/common/messages/_reply_form.html.erb:34-36` |
| `button_to` | rails-helper | 4 | 12 | 11 | `views/common/messages/_find_recipient_form.html.erb:31` `views/common/messages/_messages_panel_header.html.erb:59` `views/me/agreements/show.html.erb:21` |
| `oneoff:row-actions-flex` | one-off-markup | 3 | 12 | 10 | `views/person/banners/index.html.erb:47` `views/person/callsigns/edit.html.erb:117` `views/person/unified_flagging/_note.html.erb:19` |
| `oneoff:button-wrapper-div` | one-off-markup | 9 | 23 | 9 | `views/person/access_documents/edit.html.erb:9` `views/person/awards/_awards_table.html.erb:4` `views/person/awards/index.html.erb:32` |
| `oneoff:button-row-wrapper` | one-off-markup | 4 | 4 | 8 | `views/common/surveys/report.html.erb:46-53` `views/common/surveys/trainer.html.erb:26-30` `views/common/missing_requests/index.html.erb:7-9` |
| `area-button-helper` | area-helper | 8 | 20 | 7 | `views/admin/action_logs/index.html.erb:9` `views/admin/request_logs/index.html.erb:18` `views/asset_management/radio_checkout/index.html.erb:91` |
| `oneoff:action-row` | one-off-markup | 7 | 7 | 7 | `views/scheduling/no_shows_report/position.html.erb:33-37` `views/scheduling/schedule_by_position/position.html.erb:31-42` `views/scheduling/schedule_by_callsign/person.html.erb:32-43` |
| `oneoff:duplicated-action-set` | one-off-markup | 2 | 4 | 7 | `views/common/schedule/index.html.erb:52-100` `views/common/timesheet/index.html.erb:50-84` |
| `clipboard_button` | shared-helper | 8 | 26 | 6 | `helpers/ui_components/clipboard_helper.rb:5` `views/admin/oauth_clients/index.html.erb:31` `views/person/_contact_details.html.erb:40` |
| `oneoff:submit-default-variant` | shared-helper | 5 | 5 | 5 | `views/people/status_change_recommendations/show.html.erb:67` `views/people/retention_report/index.html.erb:62` `views/people/unified_flagging/index.html.erb:82` |
| `oneoff:icon-only-control` | shared-helper | 4 | 6 | 4 | `views/scheduling/position_credits/position.html.erb:94-95` `views/scheduling/slots/position.html.erb:111-118` `views/bmid/titles/index.html.erb:48-50` |
| `delete_button in form button_row` | shared-helper | 2 | 31 | 4 | `views/communication/announcements/_form.html.erb:38` `views/communication/surveys/_form.html.erb:63` |
| `oneoff:cancel-as-button-link` | shared-helper | 2 | 2 | 4 | `views/person/pogs/_form.html.erb:13` `views/person/swag/_form.html.erb:35` |
| `oneoff:breakpoint-only-button` | shared-helper | 1 | 1 | 4 | `views/common/messages/_compose.html.erb:32-35` |
| `oneoff:disabled-action-text` | one-off-markup | 1 | 1 | 4 | `views/common/schedule/_signed_up_row.html.erb:72-76` |
| `oneoff:disclosure-summary-as-button` | one-off-markup | 1 | 2 | 4 | `views/common/schedule/index.html.erb:46` |
| `oneoff:placeholder-slot` | one-off-markup | 1 | 2 | 4 | `views/common/_move_buttons.html.erb:10` |
| `oneoff:delete-via-button-link` | shared-helper | 3 | 16 | 3 | `views/profile/_bmid.html.erb:20` `views/profile_languages/index.html.erb:39` `views/profile_photos/crop.html.erb:142` |
| `f.submit formaction` | shared-helper | 2 | 3 | 2 | `views/communication/rbs_broadcasts/new.html.erb:45` `views/ticketing/trs_export/index.html.erb:100-115` |
| `f.submit variant:secondary` | shared-helper | 2 | 2 | 2 | `views/bmid/manage/_filter_bar.html.erb:70` `views/bmid/export/_filter_bar.html.erb:32` |
| `oneoff:copy-via-button-action` | shared-helper | 2 | 16 | 2 | `views/training/sessions/_trainees_section.html.erb:48` `views/training/untrained_people/index.html.erb:49` |
| `oneoff:edit-delete-pair` | shared-helper | 2 | 20 | 2 | `views/training/sessions/scores/_dialog.html.erb:37` `views/training/mentoring/assignments/_general_notes_list.html.erb:19` |
| `oneoff:export-in-button-row` | one-off-markup | 2 | 8 | 2 | `views/timesheets/timesheet_unconfirmed/index.html.erb:65` `views/shift_operations/payroll_missing_id/index.html.erb:42` |
| `oneoff:flex-action-cell` | one-off-markup | 2 | 5 | 2 | `views/asset_management/records/type.html.erb:100` `views/vehicles/registry/index.html.erb:135` |
| `oneoff:toolbar-row` | one-off-markup | 2 | 2 | 2 | `views/mentoring/alpha_acceptance_sheets/index.html.erb:78-83` `views/mentoring/alpha_mentor_assignments/index.html.erb:150-160` |
| `oneoff:utility-button` | daisyui-class, one-off-markup | 2 | 14 | 2 | `views/application/_top_menu.html.erb:35` `views/shift_operations/rollcall/_row.html.erb:40` |
| `delete_button confirm_modal` | shared-helper | 1 | 1 | 2 | `views/bmid/titles/_form.html.erb:40-47` |
| `oneoff:button-with-timestamp-row` | one-off-markup | 1 | 1 | 2 | `views/admin/sms_management/twilio.html.erb:116-120` |
| `<button>` | raw-html | 2 | 4 | 1 | `views/common/_toast.html.erb:9` `views/profile_photos/new.html.erb:87` |
| `button_action :ghost` | shared-helper | 1 | 2 | 1 | `views/communication/rbs_broadcasts/_position_checkboxes.html.erb:11` |
| `button_link :error in callout` | shared-helper | 1 | 15 | 1 | `views/communication/rbs_history/show.html.erb:28` |
| `button_link full_width` | shared-helper | 1 | 1 | 1 | `views/ticketing/maintenance/index.html.erb:45-50` |
| `button_row in section header` | shared-helper | 1 | 12 | 1 | `views/communication/surveys/_group_actions.html.erb:2` |
| `confirm_modal` | shared-helper | 1 | 2 | 1 | `views/hq/shift_manage/index.html.erb:148` |
| `delete_button relabelled` | shared-helper | 1 | 1 | 1 | `views/bmid/export/_previous_exports.html.erb:44-53` |
| `email_suppression_clear_button` | area-helper | 1 | 1 | 1 | `views/person/_banners.html.erb:55` |
| `f.submit size sm` | shared-helper | 1 | 3 | 1 | `views/alerts/edit.html.erb:110` |
| `f.submit variant:error` | shared-helper | 1 | 1 | 1 | `views/ticketing/unsubmit_provisions/index.html.erb:91-96` |
| `oneoff:bare-wrapper` | one-off-markup | 1 | 1 | 1 | `views/mentoring/alpha_signout/index.html.erb:70-75` |
| `oneoff:button-group` | one-off-markup | 1 | 1 | 1 | `views/profile/_bmid.html.erb:18` |
| `oneoff:button-in-paragraph` | one-off-markup | 1 | 1 | 1 | `views/ticketing/expiring/index.html.erb:47-54` |
| `oneoff:button-toolbar` | one-off-markup | 1 | 10 | 1 | `views/timesheets/timesheets_by_callsign/person.html.erb:53` |
| `oneoff:button-wrapper-p` | one-off-markup | 1 | 3 | 1 | `views/person/pogs/index.html.erb:14` |
| `oneoff:custom-capture-button` | custom-css | 1 | 7 | 1 | `views/profile_photos/new.html.erb:292` |
| `oneoff:fake-button-span` | one-off-markup | 1 | 4 | 1 | `views/me/dashboard/_announcements_section.html.erb:56` |
| `oneoff:ghost-select-all` | shared-helper | 1 | 8 | 1 | `views/teams_positions/special_teams_hours/index.html.erb:65` |
| `oneoff:hidden-on-mobile-action` | one-off-markup | 1 | 2 | 1 | `views/person/callsigns/edit.html.erb:22` |
| `oneoff:plain-text-disabled-action` | one-off-markup | 1 | 6 | 1 | `views/communication/mail_templates/index.html.erb:42` |
| `oneoff:print-hidden-wrapper` | one-off-markup | 1 | 1 | 1 | `views/mentoring/shift_report/index.html.erb:26-33` |
| `oneoff:responsive-icon-buttons` | shared-helper | 1 | 12 | 1 | `views/profile_photos/crop.html.erb:80` |
| `oneoff:row-primary-button` | shared-helper | 1 | 7 | 1 | `views/communication/surveys/index.html.erb:61` |
| `oneoff:secondary-destructive-link` | shared-helper | 1 | 10 | 1 | `views/communication/announcements/index.html.erb:21` |
| `oneoff:severity-coloured-button` | shared-helper | 1 | 4 | 1 | `views/communication/rbs/_type_card.html.erb:13` |
| `oneoff:submit-label` | form-builder | 1 | 1 | 1 | `views/profile/camp_edit.html.erb:36` |
| `oneoff:submit-variant-by-direction` | shared-helper | 1 | 2 | 1 | `views/teams_positions/bulk_teams/preview.html.erb:106` |
| `shared-partial` | shared-partial | 1 | 9 | 1 | `views/communication/surveys/_group.html.erb:49` |
| `submit_button variant switch` | shared-helper | 1 | 7 | 1 | `views/communication/rbs_broadcasts/review.html.erb:79` |
| `content_tag/tag.button` | rails-helper | 5 | 5 | 0 | `helpers/admin/salesforce_query_helper.rb:47` `helpers/modal_helper.rb:57` `helpers/navigation_helper.rb:82` |
| `dropdown_button` | shared-helper | 2 | 2 | 0 | `helpers/navigation_helper.rb:78` `views/application/_top_menu.html.erb:92` |
| `button_link + confirm_modal` | area-helper | 1 | 12 | 0 | `helpers/communication/surveys_helper.rb:95` |
| `button_tag` | rails-helper | 1 | 1 | 0 | `helpers/button_helper.rb:119` |
| `css:button-row` | custom-css(buttons.css) | 1 | 1 | 0 | `helpers/button_helper.rb:57` |
| `css:button-row-spacer` | custom-css(buttons.css) | 1 | 1 | 0 | `helpers/button_helper.rb:83` |
| `detail_row_toggle` | area-helper | 1 | 4 | 0 | `helpers/timesheets/correction_requests_helper.rb:44` |
| `match_step_button` | shared-helper | 1 | 3 | 0 | `helpers/ui_components/ui_match_stepper_helper.rb:28` |
| `oneoff:cell-action-group` | custom-css | 1 | 1 | 0 | `helpers/admin/jobs_helper.rb:130-145` |
| `oneoff:icon-plus-sr-text-button` | area-helper | 1 | 1 | 0 | `helpers/bmid/manage_helper.rb:287-313` |
| `oneoff:mail-btn-class` | custom-css | 1 | 18 | 0 | `views/mail/layouts/mailer.html.erb:57` |
| `oneoff:raw-sort-button` | raw-html | 1 | 1 | 0 | `helpers/admin/salesforce_query_helper.rb:45-51` |
| `submit_tag` | rails-helper | 1 | 1 | 0 | `helpers/button_helper.rb:246` |
| `ui_pager_button` | shared-helper | 1 | 2 | 0 | `helpers/ui_components/ui_pager_helper.rb:38` |

### links (38 variants)

| Variant | Impl | Files | Uses | Pages | Examples |
|---|---|---|---|---|---|
| `link_to` | rails-helper, area-helper | 133 | 193 | 126 | `helpers/admin/sms_management_helper.rb:166` `helpers/application_helper.rb:255` `helpers/asset_management/radio_assets_helper.rb:44` |
| `person_display_link` | shared-helper | 84 | 114 | 66 | `helpers/admin/action_logs_helper.rb:60` `helpers/admin/error_logs_helper.rb:28` `helpers/admin/legacy_log_helper.rb:19` |
| `callsign_link` | shared-helper, area-helper | 60 | 77 | 64 | `helpers/link_helper.rb:20` `helpers/shift_operations/payroll_missing_id_helper.rb:12` `helpers/timesheets/on_duty_helper.rb:34` |
| `mail_to` | rails-helper | 25 | 29 | 36 | `helpers/link_helper.rb:28` `views/bug_reports/new.html.erb:28` `views/common/messages/_messages_panel.html.erb:60` |
| `css:tap-target-link` | custom-css(accessibility.css) | 27 | 28 | 29 | `views/dashboard_tasks/_burn_weekend_shift_needed.html.erb:6` `views/dashboard_tasks/_dashboard_arts.html.erb:14` `views/dashboard_tasks/_dashboard_survey.html.erb:7` |
| `email_link_or_dash` | shared-helper | 24 | 25 | 27 | `helpers/link_helper.rb:27` `views/bmid/sanity_check/index.html.erb:92` `views/common/ticketing_maintenance/_results_table.html.erb:40` |
| `css:no-decoration` | custom-css(base.css) | 10 | 11 | 20 | `helpers/application_helper.rb:252` `helpers/ui_components/clipboard_helper.rb:23` `helpers/vc/applications_helper.rb:110` |
| `ext_link` | shared-helper, area-helper | 15 | 27 | 13 | `helpers/url_helper.rb:4` `helpers/vc/create_prospectives_helper.rb:118` `views/admin/documents/index.html.erb:67` |
| `area-link-helper` | area-helper | 12 | 18 | 10 | `views/scheduling/hq_forecast/burn_perimeters.html.erb:18` `views/scheduling/hq_forecast/index.html.erb:25` `views/shift_operations/payroll_export/index.html.erb:116` |
| `oneoff:table-link-classes` | rails-helper, area-helper | 11 | 26 | 10 | `views/admin/shift_coverage_groups/index.html.erb:43-44` `views/ticketing/provisions/index.html.erb:52-54` `views/bmid/sanity_check/index.html.erb:98-103` |
| `oneoff:utility-link` | one-off-markup | 7 | 15 | 8 | `views/me/dashboard/_announcements_section.html.erb:19` `views/me/operational_summary/_basic_driving.html.erb:24` `views/me/operational_summary/_mvr.html.erb:16` |
| `class:link` | daisyui-class, custom-css | 8 | 10 | 7 | `views/bmid/export/_buckets.html.erb:38` `views/mentoring/alpha_pods/_pod_card.html.erb:54` `views/mentoring/alphas_convert/index.html.erb:54` |
| `LinkHelper::TABLE_LINK_CLASSES` | rails-helper | 2 | 2 | 7 | `views/common/surveys/_session_label.html.erb:12-16` `views/common/surveys/_survey_table.html.erb:33-39` |
| `helper-class-override` | shared-helper, rails-helper | 2 | 2 | 7 | `views/common/unified_flagging/_name_line.html.erb:9` `views/common/rbs/_delivery_summary.html.erb:25` |
| `class:tap-target-link` | custom-css | 6 | 8 | 6 | `views/dashboard_tasks/_burn_weekend_shift_needed.html.erb:6` `views/dashboard_tasks/_dashboard_arts.html.erb:14` `views/dashboard_tasks/_dashboard_survey.html.erb:7` |
| `oneoff:coloured-mail-link` | one-off-markup | 1 | 1 | 4 | `views/common/scheduling/_signup_blockers.html.erb:60` |
| `oneoff:footer-link` | one-off-markup | 1 | 5 | 4 | `views/sessions/_footer_link.html.erb:5` |
| `<a>` | raw-html | 3 | 5 | 3 | `views/dashboard_tasks/_attend_alpha_shift_pending.html.erb:2` `views/profile/_mailing_address.html.erb:8` `views/vc/applications/_action_bar.html.erb:12` |
| `oneoff:underline-link` | area-helper, one-off-markup | 4 | 12 | 2 | `helpers/vc/applications_helper.rb:12` `views/vc/applications/_banners.html.erb:22` `views/vc/create_prospectives/index.html.erb:97` |
| `oneoff:thumbnail-link` | rails-helper | 2 | 20 | 2 | `views/vc/photos_review/_photo.html.erb:66` `views/vc/photos/index.html.erb:42` |
| `oneoff:underlined-link` | rails-helper | 2 | 11 | 1 | `views/communication/rbs_history/index.html.erb:71` `helpers/communication/rbs_helper.rb:363` |
| `account_link` | shared-helper | 1 | 6 | 1 | `views/vc/applications/_banners.html.erb:28` |
| `class:link link-primary` | daisyui-class | 1 | 1 | 1 | `views/bmid/export/_buckets.html.erb:36-39` |
| `link_to data turbo_frame _top` | rails-helper | 1 | 1 | 1 | `views/bug_reports/new.html.erb:24` |
| `oneoff:anchor-count-link` | raw-html | 1 | 3 | 1 | `views/vc/applications/_action_bar.html.erb:12` |
| `oneoff:font-medium-link` | rails-helper | 1 | 3 | 1 | `views/training/sessions/_session_table.html.erb:22` |
| `oneoff:in-page-anchor` | rails-helper | 1 | 1 | 1 | `views/profile/show.html.erb:65` |
| `oneoff:inline-link-touch-height` | one-off-markup | 1 | 2 | 1 | `views/person/_summary_strip.html.erb:13` |
| `oneoff:link_to-mailto-underline` | rails-helper | 1 | 2 | 1 | `views/alerts/edit.html.erb:93` |
| `oneoff:person-link-underline` | rails-helper | 1 | 1 | 1 | `views/admin/passkeys/index.html.erb:53` |
| `oneoff:tel-link` | rails-helper | 1 | 3 | 1 | `views/timesheets/timesheet_unconfirmed/_group.html.erb:35` |
| `oneoff:unlinked-fallback` | one-off-markup | 1 | 4 | 1 | `views/training/trainer_attendance/index.html.erb:54` |
| `content_tag/tag.a` | rails-helper | 3 | 3 | 0 | `helpers/button_helper.rb:162` `helpers/messages_helper.rb:35` `helpers/tabs_helper.rb:89` |
| `oneoff:link-class` | one-off-markup, area-helper | 2 | 8 | 0 | `views/register/_form.html.erb:45` `helpers/vc/handle_checker_helper.rb:65` |
| `oneoff:utility-button` | daisyui-class | 2 | 4 | 0 | `views/application/_top_menu.html.erb:38` `views/application/_public_menu.html.erb:9` |
| `nav_link_to` | shared-helper | 1 | 1 | 0 | `helpers/link_helper.rb:9` |
| `oneoff:external-link-by-hand` | rails-helper | 1 | 1 | 0 | `helpers/admin/sms_management_helper.rb:163-167` |
| `oneoff:sort-link` | hard-coded-value | 1 | 2 | 0 | `helpers/bmid/manage_helper.rb:72-75` |

### forms (145 variants)

| Variant | Impl | Files | Uses | Pages | Examples |
|---|---|---|---|---|---|
| `ui_form` | shared-helper | 157 | 270 | 197 | `helpers/ui_components/filter_bar_helper.rb:233` `helpers/ui_components/ui_form_helper.rb:21` `views/admin/documents/_form.html.erb:1` |
| `f.select` | form-builder, shared-helper | 136 | 298 | 170 | `helpers/bmid/manage_helper.rb:136` `views/admin/jobs/index.html.erb:42` `views/admin/online_courses/_form.html.erb:11` |
| `form_row` | shared-helper | 131 | 215 | 161 | `helpers/form_helper.rb:1174` `views/admin/action_logs/index.html.erb:20` `views/admin/documents/_form.html.erb:10` |
| `f.text_field` | form-builder, shared-helper | 94 | 169 | 125 | `views/admin/action_logs/index.html.erb:21` `views/admin/documents/_form.html.erb:11` `views/admin/error_logs/index.html.erb:10` |
| `filter_bar` | shared-helper | 88 | 216 | 88 | `helpers/ui_components/filter_bar_helper.rb:52` `views/admin/action_logs/index.html.erb:16` `views/admin/error_logs/index.html.erb:5` |
| `f.text_area` | form-builder | 65 | 76 | 86 | `views/admin/rbs_alerts/edit.html.erb:36` `views/admin/salesforce_query/index.html.erb:9` `views/admin/settings/edit.html.erb:31` |
| `helper-class-override` | shared-helper, shared-partial | 43 | 155 | 59 | `views/admin/passkeys/index.html.erb:28` `views/admin/salesforce_query/index.html.erb:9` `views/common/messages/_compose.html.erb:8` |
| `f.check_box` | form-builder | 35 | 89 | 51 | `views/admin/error_logs/index.html.erb:32` `views/admin/online_courses/_form.html.erb:16` `views/admin/permissions/edit.html.erb:30` |
| `f.fieldset` | form-builder, shared-helper | 27 | 52 | 41 | `views/admin/documents/_form.html.erb:3` `views/admin/event_dates/_form.html.erb:3` `views/admin/oauth_clients/_form.html.erb:5` |
| `<label>` | raw-html | 24 | 30 | 36 | `views/alerts/_alert_group.html.erb:72` `views/application/_search_bar_placeholder.html.erb:106` `views/application/_top_menu.html.erb:35` |
| `f.collection_radio_buttons` | form-builder, shared-helper | 19 | 48 | 33 | `views/admin/settings/edit.html.erb:16` `views/asset_management/records/_form.html.erb:35` `views/common/messages/_reply_form.html.erb:19` |
| `f.datetime_field` | form-builder | 21 | 41 | 31 | `views/admin/action_logs/index.html.erb:34` `views/admin/error_logs/index.html.erb:22` `views/admin/event_dates/_form.html.erb:8` |
| `form_with` | rails-helper | 32 | 82 | 27 | `helpers/ui_components/ui_form_helper.rb:37` `views/asset_management/search/index.html.erb:29` `views/common/_form_wrapper.html.erb:1` |
| `check_box_tag` | rails-helper | 13 | 46 | 27 | `helpers/ui_components/bulk_select_helper.rb:28` `views/common/_checkbox_grid.html.erb:13` `views/common/_checkbox_row.html.erb:16` |
| `f.number_field` | form-builder | 13 | 20 | 26 | `views/admin/documents/_form.html.erb:13` `views/bmid/titles/_form.html.erb:30` `views/common/provisions/_form.html.erb:35` |
| `options_for_select` | rails-helper | 29 | 49 | 23 | `helpers/bulk_upload_helper.rb:46` `helpers/mentor_helper.rb:53` `helpers/mentoring/alpha_mentor_assignments_helper.rb:52` |
| `f.rich_text_area` | form-builder | 6 | 8 | 23 | `views/common/documents/_body_field.html.erb:7` `views/common/messages/_compose.html.erb:56` `views/common/messages/_reply_form.html.erb:25` |
| `bulk_select_checkbox` | shared-helper | 21 | 31 | 21 | `helpers/ui_components/bulk_select_helper.rb:55` `views/bmid/export/_selection_table.html.erb:34` `views/mentoring/alpha_acceptance_sheets/index.html.erb:103` |
| `bulk_select_all` | shared-helper | 21 | 21 | 21 | `helpers/ui_components/bulk_select_helper.rb:22` `views/bmid/export/_selection_table.html.erb:12` `views/mentoring/alpha_acceptance_sheets/index.html.erb:79` |
| `bulk_select` | shared-helper | 21 | 25 | 20 | `helpers/ui_components/bulk_select_helper.rb:13` `views/bmid/export/index.html.erb:64` `views/mentoring/alpha_acceptance_sheets/index.html.erb:77` |
| `f.hidden_field` | form-builder | 10 | 18 | 19 | `views/admin/online_courses/_form.html.erb:4` `views/common/mentoring/index.html.erb:29` `views/common/messages/_reply_form.html.erb:12` |
| `oneoff:grid-layout` | one-off-markup | 8 | 47 | 19 | `views/common/_checkbox_grid.html.erb:10` `views/profile/identity_info_edit.html.erb:73` `views/profile/clothing_edit.html.erb:34` |
| `select_tag` | rails-helper | 14 | 27 | 14 | `helpers/page_layout_helper.rb:49` `views/admin/shift_coverage_positions/_position_rows.html.erb:28` `views/bmid/titles/_cell.html.erb:7` |
| `oneoff:checkbox-row` | one-off-markup | 1 | 1 | 11 | `views/common/_checkbox_row.html.erb:15-18` |
| `oneoff:field-width-html-class` | shared-helper | 3 | 7 | 10 | `views/common/bulk_upload/index.html.erb:55-58` `views/common/bmids/_fields.html.erb:8` `views/common/provisions/_form.html.erb:16` |
| `oneoff:checkbox-tile` | one-off-markup | 1 | 1 | 10 | `views/common/_checkbox_tile.html.erb:14-17` |
| `f.collection_select` | form-builder | 5 | 5 | 9 | `views/admin/permissions/new_art.html.erb:25` `views/bmid/titles/_form.html.erb:26` `views/common/assets/_change_attachment_modal.html.erb:12` |
| `content_tag/tag.input` | rails-helper | 4 | 6 | 9 | `helpers/form_helper.rb:298` `views/alerts/_alert_group.html.erb:73` `views/application/_search_bar_placeholder.html.erb:107` |
| `f.email_field` | form-builder | 7 | 7 | 8 | `views/people/create_account/new.html.erb:26` `views/register/_form.html.erb:59` `views/sessions/_password_form.html.erb:7` |
| `css:ac-keyboard-help` | custom-css(autocomplete.css) | 1 | 1 | 8 | `views/shared/_autocomplete.html.erb:67` |
| `oneoff:chip-input` | one-off-markup | 1 | 1 | 8 | `views/common/messages/_search_field.html.erb:16-34` |
| `oneoff:raw-input` | raw-html | 1 | 6 | 8 | `views/shared/_autocomplete.html.erb:34` |
| `f.password_field` | form-builder | 8 | 14 | 7 | `views/me/passkeys/new.html.erb:44` `views/me/password/edit.html.erb:7` `views/people/create_account/new.html.erb:59` |
| `label_tag` | rails-helper | 7 | 10 | 7 | `views/admin/shift_coverage_positions/_position_rows.html.erb:26` `views/scheduling/shift_lead/_picker.html.erb:38` `views/scheduling/shift_lead/_sort_control.html.erb:23` |
| `f.date_field` | form-builder | 5 | 8 | 7 | `views/admin/sms_management/index.html.erb:118` `views/person/certifications/_form.html.erb:15` `views/person/site_log/index.html.erb:40` |
| `f.search_field` | form-builder | 6 | 6 | 6 | `views/asset_management/search/index.html.erb:40` `views/people/languages_known/index.html.erb:16` `views/vc/applications/index.html.erb:30` |
| `f.label` | form-builder | 3 | 3 | 6 | `views/common/assets/_checkout_form.html.erb:13` `views/people/languages_known/index.html.erb:15` `views/sessions/_password_form.html.erb:29` |
| `filter_chips` | shared-helper, area-helper | 68 | 92 | 5 | `helpers/admin/action_logs_helper.rb:38` `helpers/admin/error_logs_helper.rb:20` `helpers/admin/jobs_helper.rb:41` |
| `form_tag` | rails-helper, raw-html | 7 | 10 | 5 | `helpers/page_layout_helper.rb:42` `views/application/_mega_menu.html.erb:18` `views/scheduling/shift_lead/_picker.html.erb:37` |
| `text_field_tag` | rails-helper | 4 | 4 | 5 | `views/admin/shift_coverage_positions/_position_rows.html.erb:38` `views/bmid/titles/_cell.html.erb:20` `views/mentoring/alpha_schedule/rosters/_dialog.html.erb:19` |
| `<input>` | raw-html | 5 | 9 | 4 | `views/alerts/_alert_group.html.erb:32` `views/layouts/application.html.erb:77` `views/profile_photos/new.html.erb:150` |
| `f.telephone_field` | form-builder | 5 | 7 | 4 | `views/alerts/edit.html.erb:101` `views/people/create_account/new.html.erb:48` `views/profile/identity_info_edit.html.erb:127` |
| `<fieldset>` | raw-html | 3 | 3 | 4 | `views/people/people_by_location/_filter_fields.html.erb:10` `views/vc/applications/edit_details.html.erb:20` `views/vc/thank_you_cards/index.html.erb:31` |
| `class:input` | daisyui-class | 3 | 3 | 4 | `views/me/menu/_content.html.erb:7` `views/people/languages_known/index.html.erb:18` `views/shift_operations/rollcall/_roster.html.erb:20` |
| `oneoff:raw-form-tag` | rails-helper | 3 | 32 | 4 | `views/shift_operations/payroll_export/index.html.erb:140` `views/shift_operations/cruise_direction/_pickers.html.erb:19` `views/shift_operations/rollcall/_pickers.html.erb:16` |
| `f.callsign_chips_field` | form-builder | 1 | 1 | 4 | `views/common/messages/_compose.html.erb:26` |
| `oneoff:hand-built-label` | one-off-markup | 1 | 1 | 4 | `views/common/assets/_checkout_form.html.erb:13-18` |
| `bulk_select_count` | shared-helper | 4 | 5 | 3 | `helpers/ui_components/bulk_select_helper.rb:33` `views/scheduling/position_credits/position.html.erb:113` `views/scheduling/slots/position.html.erb:138` |
| `hidden_field_tag` | rails-helper | 3 | 5 | 3 | `views/common/shift_manage/_blocked_modal.html.erb:23-26` `views/communication/survey_questions/_form.html.erb:5` `views/training/all_notes/index.html.erb:53` |
| `oneoff:search-submit-alignment` | one-off-markup | 3 | 23 | 3 | `views/vc/applications/index.html.erb:29` `views/vc/applications/search.html.erb:9` `views/vc/handle_checker/index.html.erb:18` |
| `oneoff:form-with-builder` | rails-helper | 2 | 4 | 3 | `views/shift_operations/cruise_direction/pods/_form.html.erb:9` `views/shift_operations/cruise_direction/people/_dialog.html.erb:18` |
| `oneoff:bare-fields-builder` | rails-helper | 1 | 1 | 3 | `views/scheduling/slots/_link_fieldsets.html.erb:4` |
| `oneoff:hand-built-field` | rails-helper, one-off-markup | 3 | 22 | 2 | `views/training/sessions/rosters/_dialog.html.erb:22` `views/training/mentoring/assignments/_general_notes.html.erb:13` `views/training/mentoring/assignments/_roster.html.erb:172` |
| `oneoff:raw-form` | rails-helper | 3 | 3 | 2 | `views/mentoring/alpha_schedule/rosters/_dialog.html.erb:11-24` `views/mentoring/alpha_schedule/rosters/_blocked.html.erb:57-63` `views/mentoring/alpha_pods/people/edit.html.erb:12-30` |
| `oneoff:field-width-option` | shared-helper | 2 | 10 | 2 | `views/common/_legal_name_fields.html.erb:10` `views/common/_mailing_address_fields.html.erb:15` |
| `oneoff:hand-built-checkbox-label` | one-off-markup | 2 | 15 | 2 | `views/training/sessions/_trainer_section.html.erb:50` `views/training/sessions/graduations/_dialog.html.erb:57` |
| `oneoff:per-row-form` | rails-helper | 2 | 11 | 2 | `views/mentoring/alpha_schedule/rosters/_dialog.html.erb:47-52` `views/training/sessions/rosters/_dialog.html.erb:67` |
| `oneoff:raw-group-label` | raw-html | 2 | 10 | 2 | `views/communication/rbs_messages/index.html.erb:40` `views/communication/rbs_broadcasts/_audience_fields.html.erb:37` |
| `oneoff:raw-label` | raw-html | 2 | 4 | 2 | `views/person/memberships/_position_checkbox.html.erb:13` `views/person/permissions/edit.html.erb:45` |
| `oneoff:two-forms-in-button-row` | shared-helper | 2 | 37 | 2 | `views/vc/create_prospectives/index.html.erb:67` `views/vc/application_import/index.html.erb:38` |
| `f.help_text_tag` | shared-helper | 1 | 1 | 2 | `views/admin/shift_coverage_groups/_form.html.erb:19-20` |
| `f.select options hash` | shared-helper | 1 | 10 | 2 | `views/communication/surveys/_form.html.erb:20` |
| `f.url_field` | form-builder | 1 | 1 | 2 | `views/admin/sms_management/twilio.html.erb:98` |
| `oneoff:checkbox-columns` | one-off-markup | 1 | 1 | 2 | `views/admin/shift_coverage_groups/_form.html.erb:26-34` |
| `oneoff:raw-field-tags-with-builder-classes` | rails-helper | 1 | 1 | 2 | `views/admin/shift_coverage_positions/_position_rows.html.erb:22-43` |
| `oneoff:raw-fieldset` | raw-html | 1 | 4 | 2 | `views/people/people_by_location/_filter_fields.html.erb:10` |
| `oneoff:raw-search-input` | raw-html | 1 | 6 | 2 | `views/shift_operations/rollcall/_roster.html.erb:18` |
| `oneoff:select-width-via-html-class` | rails-helper | 1 | 6 | 2 | `views/person/access_documents/_form.html.erb:17` |
| `oneoff:select-width-via-width-option` | shared-helper | 1 | 4 | 2 | `views/person/awards/_form.html.erb:20` |
| `oneoff:stimulus-wrapper-div` | one-off-markup | 1 | 1 | 2 | `views/asset_management/records/_form.html.erb:34` |
| `oneoff:type-specific-fields-always-shown` | shared-helper | 1 | 8 | 2 | `views/communication/survey_questions/_form.html.erb:29` |
| `<select>` | raw-html | 2 | 2 | 1 | `views/application/_search_bar_placeholder.html.erb:117` `views/profile_photos/new.html.erb:269` |
| `search_field_tag` | rails-helper | 1 | 9 | 1 | `views/me/menu/_content.html.erb:5` `views/me/menu/_content.html.erb:4` |
| `text_area_tag` | rails-helper | 2 | 2 | 1 | `views/training/mentoring/assignments/_general_notes.html.erb:14` `views/training/mentoring/assignments/_roster.html.erb:217` |
| `attribute` | attribute | 1 | 1 | 1 | `views/person/bmids/show.html.erb:43` |
| `bmid_filter_select` | area-helper | 1 | 1 | 1 | `views/bmid/manage/_filter_bar.html.erb:48-60` |
| `class:checkbox` | daisyui-class | 1 | 1 | 1 | `views/vc/applications/edit_details.html.erb:27` |
| `common/_checkbox_row` | shared-partial | 1 | 9 | 1 | `views/shift_operations/payroll_export/index.html.erb:59` |
| `css:camera-capture-btn` | custom-css(camera.css) | 1 | 1 | 1 | `views/profile_photos/new.html.erb:293` |
| `css:camera-preview` | custom-css(camera.css) | 1 | 1 | 1 | `views/profile_photos/new.html.erb:278` |
| `css:camera-select` | custom-css(camera.css) | 1 | 1 | 1 | `views/profile_photos/new.html.erb:270` |
| `css:camera-video` | custom-css(camera.css) | 1 | 1 | 1 | `views/profile_photos/new.html.erb:283` |
| `f.check_box in filter_bar` | shared-helper | 1 | 1 | 1 | `views/ticketing/access_documents/_summary_filter_bar.html.erb:43-44` |
| `f.radio_button` | form-builder | 1 | 2 | 1 | `views/me/surveys/_trainer_photo.html.erb:20` |
| `f.select width + wrapper_class` | shared-helper | 1 | 9 | 1 | `views/communication/announcements/index.html.erb:40` |
| `f.text_field in filter_bar` | shared-helper | 1 | 6 | 1 | `views/communication/person_banners/index.html.erb:42` |
| `f.time_field` | form-builder | 1 | 1 | 1 | `views/shift_operations/rollcall/_set_time_dialog.html.erb:30` |
| `fields_for` | rails-helper | 1 | 1 | 1 | `views/bmid/manage/_edit_grid.html.erb:62` |
| `filter_bar width override` | shared-helper | 1 | 1 | 1 | `views/ticketing/trs_export/index.html.erb:74-76` |
| `form_row check boxes` | shared-helper | 1 | 4 | 1 | `views/communication/rbs_broadcasts/_message_fields.html.erb:21` |
| `form_row single field` | shared-helper | 1 | 2 | 1 | `views/alerts/edit.html.erb:100` |
| `hide_label + aria` | shared-helper | 1 | 1 | 1 | `views/bmid/manage/_edit_grid.html.erb:81-148` |
| `oneoff:arbitrary-width` | hard-coded-value | 1 | 1 | 1 | `views/communication/rbs_broadcasts/_message_fields.html.erb:27` |
| `oneoff:auto-submit-group` | attribute | 1 | 1 | 1 | `views/vc/handle_checker/index.html.erb:44` |
| `oneoff:auto-submit-select` | attribute | 1 | 3 | 1 | `views/scheduling/shift_lead/_sort_control.html.erb:16` |
| `oneoff:checkbox-card-grid` | one-off-markup | 1 | 10 | 1 | `views/shift_operations/cruise_direction/people/_pool.html.erb:11` |
| `oneoff:checkbox-grid` | one-off-markup | 1 | 1 | 1 | `views/mentoring/alpha_pods/people/_pool.html.erb:19-45` |
| `oneoff:checkbox-row-with-badges` | one-off-markup | 1 | 3 | 1 | `views/person/agreements/_agreement_row.html.erb:1` |
| `oneoff:disabled-checkbox` | one-off-markup | 1 | 19 | 1 | `views/alerts/_alert_group.html.erb:51` |
| `oneoff:dropzone` | one-off-markup | 1 | 23 | 1 | `views/profile_photos/new.html.erb:131` |
| `oneoff:half-width-field` | shared-helper | 1 | 1 | 1 | `views/admin/legacy_log/index.html.erb:68-71` |
| `oneoff:hand-help-text` | one-off-markup | 1 | 3 | 1 | `views/communication/rbs_broadcasts/_audience_fields.html.erb:46` |
| `oneoff:hand-rolled-filter-bar` | one-off-markup | 1 | 16 | 1 | `views/vc/applications/index.html.erb:64` |
| `oneoff:hand-rolled-help-text` | one-off-markup | 1 | 4 | 1 | `views/person/callsigns/edit.html.erb:54` |
| `oneoff:hand-written-label-row` | custom-css | 1 | 5 | 1 | `views/sessions/_password_form.html.erb:27` |
| `oneoff:hidden-resubmit-form` | shared-helper | 1 | 11 | 1 | `views/vc/reserved_handles/upload.html.erb:41` |
| `oneoff:inline-label-value` | one-off-markup | 1 | 11 | 1 | `views/person/callsigns/edit.html.erb:71` |
| `oneoff:inline-search-row` | one-off-markup | 1 | 4 | 1 | `views/training/sessions/rosters/_dialog.html.erb:35` |
| `oneoff:raw-checkbox` | raw-html | 1 | 13 | 1 | `views/alerts/_alert_group.html.erb:32` |
| `oneoff:raw-checkbox-grid` | rails-helper | 1 | 13 | 1 | `views/vc/applications/edit_details.html.erb:20` |
| `oneoff:raw-checkbox-tile` | rails-helper | 1 | 7 | 1 | `views/vc/handle_checker/index.html.erb:64` |
| `oneoff:raw-field-tags` | rails-helper | 1 | 2 | 1 | `views/bmid/titles/_cell.html.erb:7-17` |
| `oneoff:raw-help-paragraph` | one-off-markup | 1 | 1 | 1 | `views/admin/rbs_alerts/edit.html.erb:39-44` |
| `oneoff:raw-label-select` | raw-html | 1 | 7 | 1 | `views/shift_operations/cruise_direction/people/edit.html.erb:18` |
| `oneoff:raw-select` | custom-css | 1 | 9 | 1 | `views/profile_photos/new.html.erb:266` |
| `oneoff:raw-select-all-wrapper` | raw-html | 1 | 1 | 1 | `views/ticketing/trs_export/index.html.erb:89` |
| `oneoff:search-form-not-filter-bar` | shared-helper | 1 | 1 | 1 | `views/admin/settings/index.html.erb:14-23` |
| `oneoff:size-attribute` | attribute | 1 | 1 | 1 | `views/vc/applications/dialogs/send_email.html.erb:9` |
| `oneoff:toolbar` | one-off-markup | 1 | 1 | 1 | `views/bmid/manage/_edit_grid.html.erb:30-39` |
| `oneoff:unknown-option` | attribute | 1 | 1 | 1 | `views/admin/settings/edit.html.erb:25` |
| `oneoff:unlabelled-field` | shared-helper | 1 | 1 | 1 | `views/admin/settings/edit.html.erb:38` |
| `options_from_collection_for_select` | rails-helper | 1 | 1 | 1 | `views/teams_positions/roster_management/show.html.erb:183` |
| `ui_disclosure` | shared-helper | 1 | 2 | 1 | `views/shift_operations/payroll_export/index.html.erb:26` |
| `ui_form(nil)` | shared-helper | 1 | 2 | 1 | `views/communication/rbs_broadcasts/review.html.erb:77` |
| `content_tag/tag.label` | rails-helper | 4 | 8 | 0 | `helpers/form_helper.rb:933` `helpers/page_layout_helper.rb:44` `helpers/sidebar_helper.rb:64` |
| `oneoff:all-option-blank-value` | area-helper | 3 | 8 | 0 | `helpers/timesheets/correction_requests_helper.rb:9` `helpers/timesheets/early_late_checkins_helper.rb:23` `helpers/shift_operations/payroll_export_helper.rb:76` |
| `ALL_FILTER_OPTION` | area-helper | 2 | 4 | 0 | `helpers/timesheets/forced_shift_start_helper.rb:45` `helpers/timesheets/hours_credits_helper.rb:25` |
| `class:join` | daisyui-class | 2 | 5 | 0 | `helpers/ui_components/ui_match_stepper_helper.rb:24` `views/application/_search_bar_placeholder.html.erb:104` |
| `class:select` | daisyui-class | 2 | 2 | 0 | `helpers/page_layout_helper.rb:75` `views/application/_search_bar_placeholder.html.erb:117` |
| `css:ac-results-inline` | custom-css(autocomplete.css) | 2 | 2 | 0 | `views/application/_search_bar_placeholder.html.erb:168` `views/test_harness/autocomplete_fixture.html.erb:79` |
| `oneoff:manual-chip` | area-helper | 2 | 2 | 0 | `helpers/scheduling/position_credits_helper.rb:12-17` `helpers/scheduling/shift_drop_report_helper.rb:14-18` |
| `oneoff:single-button-form` | rails-helper | 2 | 8 | 0 | `views/vc/applications/_personal_info_stage.html.erb:11` `views/vc/applications/_paragraph_stage.html.erb:21` |
| `year_selector` | shared-helper | 2 | 3 | 0 | `helpers/page_layout_helper.rb:37` `helpers/ui_components/ui_hero_panel_helper.rb:116` |
| `content_tag/tag.fieldset` | rails-helper | 1 | 4 | 0 | `helpers/form_helper.rb:526` |
| `content_tag/tag.form` | rails-helper | 1 | 1 | 0 | `helpers/modal_helper.rb:56` |
| `css:ac-loading` | custom-css(autocomplete.css) | 1 | 1 | 0 | `helpers/form_helper.rb:329` |
| `css:ac-results` | custom-css(autocomplete.css) | 1 | 1 | 0 | `helpers/form_helper.rb:337` |
| `filter_bar count` | area-helper | 1 | 4 | 0 | `helpers/timesheets/top_hour_earners_helper.rb:16` |
| `oneoff:carried-hidden-fields` | area-helper | 1 | 1 | 0 | `helpers/scheduling/shift_lead_helper.rb:123-127` |
| `oneoff:grouped-options` | area-helper | 1 | 5 | 0 | `helpers/shift_operations/cruise_direction_helper.rb:38` |
| `oneoff:grouped-select-options` | area-helper | 1 | 3 | 0 | `helpers/training/mentoring_helper.rb:106` |
| `oneoff:segmented-radio` | one-off-markup | 1 | 9 | 0 | `views/application/_search_bar_placeholder.html.erb:104` |
| `title_year_selector` | shared-helper | 1 | 1 | 0 | `helpers/page_layout_helper.rb:102` |
| `year_selector_compact` | shared-helper | 1 | 1 | 0 | `helpers/page_layout_helper.rb:62` |
| `year_selector_keep_fields` | shared-helper | 1 | 3 | 0 | `helpers/page_layout_helper.rb:55` |

### validation (35 variants)

| Variant | Impl | Files | Uses | Pages | Examples |
|---|---|---|---|---|---|
| `required-attribute` | attribute | 91 | 173 | 128 | `helpers/form_helper.rb:37` `views/admin/documents/_form.html.erb:11` `views/admin/event_dates/_form.html.erb:8` |
| `html-constraint-attribute` | attribute | 66 | 123 | 104 | `views/admin/action_logs/index.html.erb:23` `views/admin/documents/_form.html.erb:11` `views/admin/error_logs/index.html.erb:12` |
| `errors-via-form-builder` | shared-helper, form-builder | 45 | 93 | 71 | `views/admin/action_logs/index.html.erb:16-74` `views/admin/documents/_form.html.erb:1-41` `views/admin/event_dates/_form.html.erb:1-49` |
| `oneoff:inline-error-text` | one-off-markup | 9 | 29 | 12 | `views/common/ticketing_maintenance/_results_table.html.erb:42-50` `views/mentoring/alpha_schedule/rosters/_dialog.html.erb:62` `views/mentoring/alpha_mentor_assignments/index.html.erb:267-274` |
| `ui_callout_box` | shared-helper | 10 | 88 | 10 | `views/asset_management/search/index.html.erb:55` `views/me/personal_vehicles/_form.html.erb:5` `views/mentoring/alpha_schedule/rosters/_blocked.html.erb:22-24` |
| `model-errors-inline` | one-off | 13 | 22 | 9 | `helpers/bmid/manage_helper.rb:371` `helpers/form_helper.rb:1078` `helpers/ui_components/ui_form_helper.rb:31` |
| `errors-via-flash` | not-handled | 7 | 9 | 7 | `views/common/bulk_upload/index.html.erb:50` `views/scheduling/slot_copies/new.html.erb:54` `views/scheduling/slot_bulk_edits/new.html.erb:51-52` |
| `oneoff:no-error-summary` | shared-helper | 4 | 5 | 5 | `views/admin/sms_management/_lookup.html.erb:30-31` `views/me/surveys/show.html.erb:40` `views/vc/handle_checker/index.html.erb:11` |
| `not-handled` | not-handled | 4 | 10 | 4 | `views/alerts/_alert_group.html.erb:32` `views/teams_positions/roster_management/show.html.erb:100` `views/teams_positions/position_sanity_checker/check.html.erb:41` |
| `oneoff:table-row-error` | one-off-markup | 1 | 9 | 4 | `views/vc/maintenance/_results_table.html.erb:35` |
| `oneoff:error-summary-callout` | shared-helper, shared-partial | 3 | 3 | 2 | `views/common/_error_summary.html.erb:2-9` `views/mentoring/alpha_mentor_assignments/index.html.erb:40-45` `views/bmid/manage/index.html.erb:43-55` |
| `aria-invalid` | attribute | 2 | 3 | 2 | `helpers/form_helper.rb:1065` `views/admin/shift_coverage_positions/_position_rows.html.erb:33` |
| `oneoff:error-in-callout` | shared-helper | 2 | 9 | 2 | `views/people/search/index.html.erb:20` `views/people/bulk_lookup/index.html.erb:12` |
| `oneoff:errors-via-form-builder` | shared-helper | 2 | 7 | 2 | `views/me/passkeys/new.html.erb:10` `views/me/password/edit.html.erb:5` |
| `oneoff:failure-callout` | shared-helper | 2 | 2 | 2 | `views/ticketing/unsubmit_provisions/results.html.erb:20-26` `views/ticketing/trs_export/mark_submitted.html.erb:20-26` |
| `oneoff:js-error-callout` | shared-helper | 2 | 10 | 2 | `views/sessions/_passkey_door.html.erb:18` `views/profile_photos/new.html.erb:78` |
| `oneoff:fieldset-error-message` | shared-helper | 1 | 1 | 2 | `views/admin/shift_coverage_groups/_form.html.erb:16-21` |
| `oneoff:per-row-error-classes` | one-off-markup | 1 | 6 | 2 | `views/admin/shift_coverage_positions/_position_rows.html.erb:10-11` |
| `empty-not-handled` | not-handled | 1 | 1 | 1 | `views/bmid/titles/_cell.html.erb:20-23` |
| `oneoff:confirm-callout` | shared-helper | 1 | 1 | 1 | `views/mentoring/alpha_mentor_assignments/index.html.erb:32-38` |
| `oneoff:dirty-row-tint` | one-off-markup | 1 | 2 | 1 | `views/bmid/manage/_edit_grid.html.erb:29` |
| `oneoff:errors-on-review-page` | not-handled | 1 | 1 | 1 | `views/shift_operations/bulk_sign_in_out/index.html.erb:29` |
| `oneoff:plain-text-hint` | one-off-markup | 1 | 1 | 1 | `views/mentoring/alpha_schedule/rosters/_dialog.html.erb:64-65` |
| `oneoff:required-badge` | shared-helper | 1 | 3 | 1 | `views/me/surveys/_question.html.erb:16` |
| `oneoff:row-level-errors` | one-off-markup | 1 | 19 | 1 | `views/vc/reserved_handles/upload.html.erb:20` |
| `oneoff:script-shown-callout` | attribute | 1 | 9 | 1 | `views/me/passkeys/new.html.erb:17` |
| `form_error_summary` | shared-helper | 2 | 2 | 0 | `helpers/form_helper.rb:1184` `helpers/ui_components/ui_form_helper.rb:32` |
| `helper-class-override` | shared-helper | 1 | 1 | 0 | `views/common/messages/_find_recipient_form.html.erb:2` |
| `oneoff:error-sentence` | area-helper | 1 | 1 | 0 | `helpers/bmid/manage_helper.rb:370-372` |
| `oneoff:js-revealed-callout` | shared-helper | 1 | 9 | 0 | `views/register/_form.html.erb:41` |
| `oneoff:plain-text-alert` | one-off-markup | 1 | 9 | 0 | `views/shift_operations/rollcall/_blocked_dialog.html.erb:11` |
| `oneoff:required-attribute-only` | not-handled | 1 | 1 | 0 | `views/common/shift_manage/_blocked_modal.html.erb:21-30` |
| `partial:common/error_summary` | shared-partial | 1 | 1 | 0 | `views/common/_form_wrapper.html.erb:2` |
| `shared-partial` | shared-partial | 1 | 3 | 0 | `views/application/_search_bar_placeholder.html.erb:181` |
| `ui_flash_submit_error` | shared-helper | 1 | 1 | 0 | `helpers/ui_components/flash_helper.rb:12` |

### modals (26 variants)

| Variant | Impl | Files | Uses | Pages | Examples |
|---|---|---|---|---|---|
| `modal_dialog` | shared-helper | 47 | 75 | 34 | `helpers/modal_helper.rb:70` `views/bug_reports/new.html.erb:11` `views/common/assets/_change_attachment_modal.html.erb:5` |
| `confirm_modal` | shared-helper, area-helper | 29 | 67 | 26 | `helpers/button_helper.rb:227` `helpers/communication/surveys_helper.rb:99` `helpers/menu_helper.rb:94` |
| `confirm_modal_dialog` | shared-helper, area-helper | 27 | 60 | 24 | `helpers/button_helper.rb:229` `helpers/modal_helper.rb:100` `helpers/person/email_suppression_helper.rb:21` |
| `turbo-confirm` | attribute | 28 | 33 | 24 | `helpers/button_helper.rb:229` `helpers/modal_helper.rb:100` `helpers/person/email_suppression_helper.rb:21` |
| `modal_form_footer` | shared-helper | 32 | 37 | 21 | `helpers/modal_helper.rb:81` `views/bug_reports/new.html.erb:16` `views/common/assets/_change_attachment_modal.html.erb:17` |
| `modal` | shared-helper | 16 | 50 | 14 | `helpers/modal_helper.rb:30` `views/bmid/provisions/_list.html.erb:14` `views/bmid/provisions/_modal.html.erb:9` |
| `button_row` | shared-helper | 2 | 15 | 2 | `views/training/sessions/scores/_dialog.html.erb:83` `views/vc/applications/dialogs/more_handles.html.erb:14` |
| `delete_button` | shared-helper | 2 | 8 | 2 | `views/person/passkeys/index.html.erb:47` `views/person/sessions/index.html.erb:50` |
| `oneoff:custom-dialog` | raw-html | 3 | 17 | 1 | `views/hq/site_registration/show.html.erb:70` `views/application/_search_bar_placeholder.html.erb:83` `views/application/_mega_menu.html.erb:4` |
| `class:modal` | daisyui-class | 2 | 5 | 1 | `helpers/modal_helper.rb:38` `views/hq/site_registration/show.html.erb:70` |
| `attribute` | attribute | 1 | 5 | 1 | `views/person/statuses/edit.html.erb:14` |
| `css:modal-body-content` | custom-css(modals.css) | 1 | 1 | 1 | `views/hq/site_registration/show.html.erb:82` |
| `css:modal-header-bar` | custom-css(modals.css) | 1 | 1 | 1 | `views/hq/site_registration/show.html.erb:77` |
| `css:modal-title-text` | custom-css(modals.css) | 1 | 1 | 1 | `views/hq/site_registration/show.html.erb:78` |
| `oneoff:conditional-modal-link` | attribute | 1 | 1 | 1 | `views/mentoring/alpha_schedule/show.html.erb:43-51` |
| `oneoff:modal-state-switch` | shared-helper | 1 | 8 | 1 | `views/bug_reports/new.html.erb:10` |
| `oneoff:query-param-dialog` | shared-partial | 1 | 2 | 1 | `views/shift_operations/rollcall/sign_in.html.erb:79` |
| `oneoff:tour-popover` | attribute | 1 | 13 | 1 | `views/me/dashboard/_onboarding.html.erb:7` |
| `<dialog>` | raw-html | 2 | 2 | 0 | `views/application/_mega_menu.html.erb:4` `views/application/_search_bar_placeholder.html.erb:83` |
| `bmid_modal_frame` | area-helper | 1 | 1 | 0 | `helpers/bmid/manage_helper.rb:253-257` |
| `button_link` | shared-helper | 1 | 3 | 0 | `views/hq/shared/_summary_column.html.erb:21` |
| `content_tag/tag.dialog` | rails-helper | 1 | 1 | 0 | `helpers/modal_helper.rb:45` |
| `modal_close_button` | shared-helper | 1 | 2 | 0 | `views/shift_operations/rollcall/_blocked_dialog.html.erb:33` |
| `modal_close_dialog` | shared-helper | 1 | 1 | 0 | `helpers/modal_helper.rb:88` |
| `oneoff:confirm-body-partial` | one-off-markup | 1 | 5 | 0 | `views/person/assets/_delete_confirm.html.erb:1` |
| `oneoff:confirm-modal-option-hash` | shared-helper | 1 | 1 | 0 | `views/common/shift_manage/_too_short_modal.html.erb:30-41` |

### tables-lists (99 variants)

| Variant | Impl | Files | Uses | Pages | Examples |
|---|---|---|---|---|---|
| `ui_table` | shared-helper | 242 | 332 | 239 | `helpers/table_helper.rb:99` `views/admin/action_logs/_live.html.erb:42` `views/admin/action_logs/_table.html.erb:8` |
| `<dl>` | raw-html | 186 | 216 | 205 | `views/admin/action_logs/_live.html.erb:22` `views/admin/jobs/index.html.erb:14` `views/admin/legacy_log/index.html.erb:6` |
| `css:instruction-list` | custom-css(accessibility.css) | 171 | 194 | 193 | `views/admin/action_logs/_live.html.erb:22` `views/admin/jobs/index.html.erb:14` `views/admin/legacy_log/index.html.erb:6` |
| `<ul>` | raw-html | 82 | 110 | 75 | `views/bmid/export/_skipped.html.erb:8` `views/bmid/export/unsubmit.html.erb:44` `views/bmid/manage/index.html.erb:49` |
| `helper-class-override` | shared-helper | 42 | 90 | 44 | `views/admin/bug_reports/index.html.erb:32-33` `views/admin/jobs/_job.html.erb:8-9` `views/admin/request_logs/index.html.erb:113-114` |
| `css:list-bulleted` | custom-css(lists.css) | 50 | 56 | 42 | `views/bmid/export/_skipped.html.erb:8` `views/bmid/export/unsubmit.html.erb:44` `views/common/_error_summary.html.erb:4` |
| `oneoff:custom-list-row` | one-off-markup, custom-css | 27 | 214 | 37 | `views/admin/action_logs/_table.html.erb:45-49` `views/admin/action_logs/_table.html.erb:75-79` `views/admin/online_courses/moodle_catalog_courses.html.erb:21-23` |
| `class:instruction-list` | custom-css | 22 | 44 | 34 | `views/common/_event_summary_breakdown.html.erb:15-20` `views/common/_hours_not_eligible.html.erb:4-15` `views/common/scheduling/_burn_weekend_shift_recommendation.html.erb:4-17` |
| `ui_drill_down_row` | shared-helper, area-helper | 29 | 61 | 30 | `helpers/teams_positions/team_documents_helper.rb:22` `helpers/ui_components/ui_drill_down_row_helper.rb:43` `views/asset_management/records/index.html.erb:32` |
| `oneoff:definition-grid` | one-off-markup, custom-css | 21 | 150 | 26 | `views/common/_timesheet_confirm.html.erb:41-54` `views/common/schedule/_signed_up_row.html.erb:31-50` `views/common/scheduling/_confirm_signup_removal.html.erb:4-21` |
| `ui_label_value` | shared-helper | 26 | 48 | 22 | `helpers/ui_components/ui_label_value_helper.rb:36` `views/admin/action_logs/_table.html.erb:58` `views/admin/bug_reports/index.html.erb:56` |
| `oneoff:grid-table` | one-off-markup | 4 | 25 | 12 | `views/common/_entry_card_grid.html.erb:17-49` `views/common/missing_requests/_entry.html.erb:31-35` `views/alerts/_alert_group.html.erb:35` |
| `<ol>` | raw-html | 9 | 11 | 10 | `views/dashboard_tasks/_after_event_status_advisory.html.erb:5` `views/dashboard_tasks/_green_dot_mentee_shift_needed.html.erb:3` `views/dashboard_tasks/_missing_bpguid.html.erb:9` |
| `content_tag/tag.ul` | rails-helper | 5 | 6 | 9 | `helpers/form_helper.rb:1189` `helpers/navigation_helper.rb:50` `helpers/person/permissions_helper.rb:26` |
| `<table>` | raw-html | 8 | 43 | 8 | `views/mentoring/alpha_acceptance_sheets/print_sheets.html.erb:165` `views/mentoring/alpha_pods/print_sheet.html.erb:64` `views/mentoring/alpha_schedule/apparel.html.erb:30` |
| `css:list-numbered` | custom-css(lists.css) | 8 | 9 | 8 | `views/dashboard_tasks/_after_event_status_advisory.html.erb:5` `views/dashboard_tasks/_green_dot_mentee_shift_needed.html.erb:3` `views/dashboard_tasks/_missing_bpguid.html.erb:9` |
| `oneoff:muted-subline` | one-off-markup | 6 | 6 | 6 | `views/ticketing/expiring/index.html.erb:92` `views/ticketing/sap_candidates/index.html.erb:75-79` `views/bmid/titles/set.html.erb:57-60` |
| `oneoff:stacked-cell-list` | one-off-markup | 7 | 39 | 5 | `views/timesheets/early_late_checkins/index.html.erb:112` `views/timesheets/forced_shift_start/index.html.erb:111` `views/timesheets/sanity_checker/_overlapping.html.erb:18` |
| `oneoff:stacked-cell` | one-off-markup, area-helper | 6 | 22 | 5 | `helpers/training/mentees_helper.rb:48` `views/training/mentees/_row.html.erb:7` `views/training/all_notes/_notes.html.erb:8` |
| `class:list-bulleted` | custom-css | 5 | 9 | 5 | `views/hq/shift_manage/_assets_section.html.erb:27` `views/person/passkeys/new.html.erb:10` `views/shift_operations/bulk_sign_in_out/_formats.html.erb:32` |
| `oneoff:stacked-cell-subline` | one-off-markup | 5 | 12 | 5 | `views/asset_management/asset_history/index.html.erb:125` `views/asset_management/assets_outstanding/index.html.erb:103` `views/asset_management/radio_checkout/_checkout_table.html.erb:36` |
| `oneoff:sr-only-heading` | one-off-markup, shared-helper | 4 | 6 | 5 | `views/common/provisions/_list.html.erb:11-13` `views/teams_positions/position_sanity_checker/_findings_table.html.erb:12` `views/bmid/manage/_edit_grid.html.erb:46-48` |
| `oneoff:left-rule-block` | one-off-markup | 1 | 1 | 5 | `views/common/surveys/_answers.html.erb:6-12` |
| `oneoff:cell-action-group` | one-off-markup, custom-css | 4 | 4 | 4 | `views/admin/documents/index.html.erb:59-70` `views/admin/online_courses/index.html.erb:55-62` `views/admin/shift_coverage_groups/index.html.erb:52-58` |
| `ui_data_block` | shared-helper | 7 | 8 | 3 | `helpers/admin/action_logs_helper.rb:86` `helpers/admin/error_logs_helper.rb:139` `helpers/admin/request_logs_helper.rb:127` |
| `oneoff:stacked-cell-lines` | one-off-markup | 4 | 4 | 3 | `views/ticketing/unsubmit_provisions/index.html.erb:74-76` `views/ticketing/access_documents/_summary_notes.html.erb:13-20` `views/ticketing/access_documents/_summary_special.html.erb:9-19` |
| `oneoff:dash-literal-cell` | hard-coded-value | 3 | 6 | 3 | `views/teams_positions/bulk_teams/preview.html.erb:83` `views/teams_positions/bulk_positions/preview.html.erb:74` `views/people/people_by_location/_people_table.html.erb:29` |
| `oneoff:grid-layout` | one-off-markup | 3 | 15 | 3 | `views/communication/surveys/show.html.erb:28` `views/communication/rbs/index.html.erb:25` `views/communication/rbs_broadcasts/_position_checkboxes.html.erb:23` |
| `oneoff:single-row-table` | shared-helper | 3 | 58 | 3 | `views/person/missing_requests/edit.html.erb:22` `views/person/timesheets/edit.html.erb:40` `views/vc/photos_review/_photo.html.erb:14` |
| `oneoff:br-in-cell` | raw-html | 2 | 4 | 3 | `views/person/tickets_provisions/show.html.erb:87` `views/person/timesheets/_log_entry_data.html.erb:51` |
| `ui_table_rows` | shared-helper, area-helper | 4 | 11 | 2 | `helpers/table_helper.rb:149` `helpers/training/mentees_helper.rb:28` `views/admin/action_logs/_live_rows.html.erb:9` |
| `custom-css` | custom-css | 2 | 11 | 2 | `views/teams_positions/roster_management/show.html.erb:102` `views/people/people_by_status/show.html.erb:17` |
| `oneoff:bulleted-list-in-callout` | custom-css | 2 | 16 | 2 | `views/people/status_change_recommendations/show.html.erb:32` `views/people/bulk_status/_consequence.html.erb:17` |
| `oneoff:column-list` | one-off-markup | 2 | 30 | 2 | `views/me/operational_summary/_teams_and_positions.html.erb:18` `views/person/_teams_positions.html.erb:9` |
| `oneoff:detail-row-without-label` | shared-helper | 2 | 2 | 2 | `views/admin/error_logs/index.html.erb:78` `views/admin/jobs/_job.html.erb:22` |
| `oneoff:expandable-detail-row` | shared-helper | 2 | 7 | 2 | `views/vehicles/paperwork/index.html.erb:135` `views/vehicles/registry/index.html.erb:147` |
| `oneoff:hand-built-thead` | raw-html | 2 | 18 | 2 | `views/teams_positions/roster_management/show.html.erb:107` `views/timesheets/hours_credits/index.html.erb:112` |
| `oneoff:row-state-error` | shared-helper | 2 | 2 | 2 | `views/teams_positions/bulk_teams/preview.html.erb:75` `views/teams_positions/bulk_positions/preview.html.erb:66` |
| `oneoff:truncate-div` | one-off-markup | 2 | 2 | 2 | `views/admin/bug_reports/index.html.erb:40-41` `views/admin/error_logs/index.html.erb:74` |
| `oneoff:cell-with-action` | one-off-markup | 1 | 1 | 2 | `views/bmid/manage/_meals_cell.html.erb:18-23` |
| `oneoff:dl-fragment` | one-off-markup | 1 | 1 | 2 | `views/scheduling/shift_signups/_legend.html.erb:4-9` |
| `oneoff:inline-label-value` | one-off-markup | 1 | 8 | 2 | `views/person/timesheets/_log_entry_data.html.erb:11` |
| `oneoff:italic-log-list` | one-off-markup | 1 | 6 | 2 | `views/person/unified_flagging/_team_notes.html.erb:32` |
| `oneoff:readonly-plain-list` | one-off-markup | 1 | 6 | 2 | `views/teams_positions/position_records/_form.html.erb:161` |
| `css:callsign-list` | custom-css(callsign-list.css) | 2 | 5 | 1 | `views/common/schedule/_people_signed_up.html.erb:36` `views/people/people_by_status/show.html.erb:17` |
| `css:hours-credits-callsign` | custom-css(hours-credits.css) | 1 | 2 | 1 | `views/timesheets/hours_credits/index.html.erb:114` |
| `css:hours-credits-grid` | custom-css(hours-credits.css) | 1 | 1 | 1 | `views/timesheets/hours_credits/index.html.erb:102` |
| `css:hours-credits-group` | custom-css(hours-credits.css) | 1 | 6 | 1 | `views/timesheets/hours_credits/index.html.erb:127` |
| `css:hours-credits-pane` | custom-css(hours-credits.css) | 1 | 1 | 1 | `views/timesheets/hours_credits/index.html.erb:101` |
| `css:roster-col-callsign` | custom-css(roster-matrix.css) | 1 | 2 | 1 | `views/teams_positions/roster_management/show.html.erb:116` |
| `css:roster-col-select` | custom-css(roster-matrix.css) | 1 | 2 | 1 | `views/teams_positions/roster_management/show.html.erb:113` |
| `css:roster-frozen-cell` | custom-css(roster-matrix.css) | 1 | 2 | 1 | `views/teams_positions/roster_management/show.html.erb:140` |
| `css:roster-frozen-heading` | custom-css(roster-matrix.css) | 1 | 2 | 1 | `views/teams_positions/roster_management/show.html.erb:113` |
| `css:roster-grid` | custom-css(roster-matrix.css) | 1 | 1 | 1 | `views/teams_positions/roster_management/show.html.erb:102` |
| `css:roster-grid-pane` | custom-css(roster-matrix.css) | 1 | 1 | 1 | `views/teams_positions/roster_management/show.html.erb:106` |
| `css:shift-coverage-grid` | custom-css(shift-coverage.css) | 1 | 1 | 1 | `views/scheduling/shift_coverage/index.html.erb:76` |
| `css:top-hour-earners-grid` | custom-css(top-hour-earners.css) | 1 | 1 | 1 | `views/timesheets/top_hour_earners/index.html.erb:63` |
| `oneoff:action-group` | one-off-markup | 1 | 1 | 1 | `views/bmid/titles/index.html.erb:42` |
| `oneoff:br-stacked-cell` | raw-html | 1 | 2 | 1 | `views/communication/mail_templates/index.html.erb:38` |
| `oneoff:cell-typography-by-helper` | area-helper | 1 | 1 | 1 | `views/admin/request_logs/_live_rows.html.erb:8-12` |
| `oneoff:change-diff-row` | one-off-markup | 1 | 8 | 1 | `views/person/access_documents/history.html.erb:23` |
| `oneoff:change-list` | one-off-markup | 1 | 18 | 1 | `views/vc/applications/_audit_log_section.html.erb:23` |
| `oneoff:check-chip-list` | one-off-markup | 1 | 5 | 1 | `views/vc/applications/_decision_stage.html.erb:7` |
| `oneoff:dash-for-no-action` | shared-helper | 1 | 1 | 1 | `views/admin/event_dates/index.html.erb:48-49` |
| `oneoff:detail-row` | shared-helper | 1 | 5 | 1 | `views/training/mentoring/verdicts/index.html.erb:177` |
| `oneoff:duplicated-table` | shared-helper | 1 | 2 | 1 | `views/profile/_alerts.html.erb:27` |
| `oneoff:em-placeholder` | raw-html | 1 | 5 | 1 | `views/people/bulk_lookup/index.html.erb:101` |
| `oneoff:empty-cell` | one-off-markup | 1 | 1 | 1 | `views/admin/passkeys/index.html.erb:57-58` |
| `oneoff:empty-heading` | shared-helper | 1 | 1 | 1 | `views/bmid/export/_previous_exports.html.erb:24` |
| `oneoff:glyph-bullet-list` | one-off-markup | 1 | 9 | 1 | `views/dashboard_tasks/_bmid_will_not_be_printed.html.erb:3` |
| `oneoff:grid-list` | one-off-markup | 1 | 5 | 1 | `views/me/operational_summary/_certifications.html.erb:3` |
| `oneoff:group-header-row` | raw-html | 1 | 7 | 1 | `views/profile/_alerts.html.erb:34` |
| `oneoff:icon-list` | one-off-markup | 1 | 6 | 1 | `views/me/tickets/provisions.html.erb:46` |
| `oneoff:inline-sentence-list` | one-off-markup | 1 | 2 | 1 | `views/teams_positions/roster_management/preview.html.erb:63` |
| `oneoff:multi-row-record` | shared-helper | 1 | 6 | 1 | `views/training/mentoring/assignments/_roster.html.erb:165` |
| `oneoff:plain-text-cell` | one-off-markup | 1 | 4 | 1 | `views/person/unified_flagging/show.html.erb:60` |
| `oneoff:row-header-not-first` | one-off-markup | 1 | 2 | 1 | `views/shift_operations/payroll_export/_person.html.erb:23` |
| `oneoff:row-state-success` | shared-helper | 1 | 3 | 1 | `views/people/status_change_recommendations/_table_row.html.erb:8` |
| `oneoff:settings-list` | one-off-markup | 1 | 26 | 1 | `views/vc/create_prospectives/index.html.erb:40` |
| `oneoff:stack-to-row-lg` | custom-css | 1 | 2 | 1 | `views/communication/rbs_history/show.html.erb:66` |
| `oneoff:stacked-links-cell` | one-off-markup | 1 | 5 | 1 | `views/teams_positions/team_records/index.html.erb:86` |
| `oneoff:stacked-list-cell` | one-off-markup | 1 | 10 | 1 | `views/teams_positions/position_lineups/index.html.erb:38` |
| `oneoff:total-row` | shared-helper | 1 | 10 | 1 | `views/teams_positions/special_teams_hours/index.html.erb:169` |
| `oneoff:total-row-annotation` | one-off-markup | 1 | 3 | 1 | `views/training/capacity/index.html.erb:100` |
| `t.heading width` | shared-helper | 1 | 1 | 1 | `views/bmid/titles/set.html.erb:46` |
| `ui_table detail_row` | shared-helper | 1 | 12 | 1 | `views/communication/rbs_messages/index.html.erb:84` |
| `ui_table striped` | shared-helper | 1 | 1 | 1 | `views/ticketing/bulk_access_documents/_formats.html.erb:24-41` |
| `css:ui-label-value` | custom-css(label-value.css) | 2 | 2 | 0 | `helpers/ui_components/ui_label_value_helper.rb:41` `views/common/_years_breakdown.html.erb:10` |
| `class:callsign-list` | custom-css | 1 | 4 | 0 | `views/common/schedule/_people_signed_up.html.erb:36` |
| `class:ui-label-value` | custom-css | 1 | 1 | 0 | `views/common/_years_breakdown.html.erb:10-37` |
| `content_tag/tag.dl` | rails-helper | 1 | 1 | 0 | `helpers/ui_components/ui_label_value_helper.rb:44` |
| `content_tag/tag.table` | rails-helper | 1 | 1 | 0 | `helpers/table_helper.rb:203` |
| `oneoff:bulleted-list` | custom-css | 1 | 2 | 0 | `views/mentoring/alpha_schedule/rosters/_blocked.html.erb:27-31` |
| `oneoff:cell-width-classes` | hard-coded-value | 1 | 1 | 0 | `helpers/admin/salesforce_query_helper.rb:8` |
| `oneoff:dash-sr-only` | hard-coded-value | 1 | 4 | 0 | `helpers/teams_positions/roster_management_helper.rb:209` |
| `oneoff:indented-sublist` | area-helper | 1 | 1 | 0 | `helpers/scheduling/schedule_by_position_helper.rb:90-101` |
| `oneoff:mail-data-table` | custom-css | 1 | 15 | 0 | `views/mail/layouts/mailer.html.erb:85` |
| `oneoff:responsive-hide` | area-helper | 1 | 2 | 0 | `helpers/scheduling/shift_coverage_helper.rb:21` |
| `oneoff:utility-dl` | one-off-markup | 1 | 1 | 0 | `views/common/scheduling/_linked_slots_full.html.erb:5-24` |

### navigation (85 variants)

| Variant | Impl | Files | Uses | Pages | Examples |
|---|---|---|---|---|---|
| `hero_panel.back_to` | shared-helper | 261 | 267 | 299 | `helpers/ui_components/ui_hero_panel_helper.rb:242` `views/admin/documents/edit.html.erb:8` `views/admin/documents/new.html.erb:6` |
| `hero_panel.year_selector` | shared-helper | 95 | 100 | 99 | `helpers/ui_components/ui_hero_panel_helper.rb:229` `views/admin/online_courses/index.html.erb:4` `views/asset_management/asset_history/index.html.erb:18` |
| `ui_pager` | shared-helper | 16 | 40 | 15 | `helpers/ui_components/ui_pager_helper.rb:29` `views/admin/action_logs/index.html.erb:77` `views/admin/error_logs/index.html.erb:40` |
| `back_to` | shared-helper | 13 | 27 | 14 | `views/hq/shared/_header.html.erb:16` `views/vehicles/registry/edit.html.erb:4` `views/vehicles/registry/new.html.erb:4` |
| `button_link` | shared-helper | 5 | 15 | 11 | `views/me/tickets/_wizard_nav.html.erb:32` `views/teams_positions/position_sanity_checker/check.html.erb:14` `views/timesheets/timesheet_slot_repair/index.html.erb:67` |
| `oneoff:custom-tabs` | area-helper, custom-css | 5 | 40 | 11 | `views/common/messages/_folder_selector.html.erb:5-10` `helpers/messages_helper.rb:31-48` `views/me/menu/_content.html.erb:20` |
| `dropdown_scroll_list` | shared-helper, area-helper | 11 | 21 | 9 | `helpers/application_helper.rb:65` `views/me/directory/index.html.erb:16` `views/people/unified_flagging/index.html.erb:98` |
| `<nav>` | raw-html | 8 | 13 | 9 | `views/application/_public_menu.html.erb:7` `views/common/surveys/report.html.erb:16` `views/me/feedback/index.html.erb:42` |
| `class:tabs` | daisyui-class | 2 | 2 | 9 | `views/common/messages/_folder_selector.html.erb:5` `views/profile_photos/new.html.erb:86` |
| `ui_match_stepper` | shared-helper | 2 | 2 | 8 | `helpers/ui_components/ui_match_stepper_helper.rb:23` `views/common/messages/_messages_panel.html.erb:26` |
| `oneoff:sticky-stepper` | one-off-markup | 1 | 1 | 8 | `views/common/messages/_messages_panel.html.erb:25-28` |
| `oneoff:wizard-footer` | one-off-markup | 1 | 9 | 7 | `views/me/tickets/_wizard_nav.html.erb:16` |
| `dropdown_menu` | shared-helper | 9 | 25 | 5 | `helpers/navigation_helper.rb:41` `views/application/_top_menu.html.erb:102` `views/common/_dropdown_scroll_list.html.erb:13` |
| `helper-class-override` | shared-helper | 6 | 22 | 5 | `views/common/_dropdown_scroll_list.html.erb:13-15` `views/person/memberships/_position_checkbox.html.erb:27` `views/person/memberships/_team_card.html.erb:23` |
| `dropdown_item` | shared-helper | 7 | 22 | 4 | `helpers/navbar_helper.rb:67` `helpers/navigation_helper.rb:62` `views/common/_dropdown_scroll_list.html.erb:20` |
| `hero_panel back_to` | shared-helper | 2 | 4 | 4 | `views/common/timesheet/edit.html.erb:3-5` `views/timesheets/sanity_checker/check.html.erb:11` |
| `hero_panel back_to + year_selector` | shared-helper | 1 | 1 | 4 | `views/common/schedule/index.html.erb:15-21` |
| `ui_drill_down_row` | shared-helper | 3 | 17 | 3 | `views/timesheets/sanity_checker/index.html.erb:63` `views/timesheets/timesheet_by_position/index.html.erb:70` `views/timesheets/timesheet_totals_report/index.html.erb:45` |
| `year_selector` | shared-helper | 3 | 3 | 3 | `views/common/unified_flagging/index.html.erb:13` `views/me/feedback/index.html.erb:11` `views/person/scheduling/log.html.erb:8` |
| `class:dropdown` | daisyui-class | 4 | 5 | 2 | `helpers/navigation_helper.rb:50` `views/application/_top_menu.html.erb:103` `views/person/_actions.html.erb:66` |
| `oneoff:mode-toggle-buttons` | area-helper | 3 | 3 | 2 | `views/admin/action_logs/index.html.erb:8-11` `views/admin/request_logs/index.html.erb:17-20` `helpers/admin/log_styles_helper.rb:38-43` |
| `oneoff:view-toggle-button` | shared-helper, area-helper | 3 | 8 | 2 | `views/asset_management/radio_assets/index.html.erb:65` `helpers/asset_management/radio_checkout_helper.rb:16` `views/bmid/manage/index.html.erb:80-92` |
| `cancel_link` | shared-helper | 2 | 4 | 2 | `views/profile_languages/index.html.erb:57` `views/teams_positions/roster_management/preview.html.erb:10` |
| `oneoff:back-button-row` | shared-helper | 2 | 15 | 2 | `views/communication/rbs_history/retried.html.erb:28` `views/communication/rbs_broadcasts/sent.html.erb:28` |
| `oneoff:bottom-back-button` | shared-helper | 2 | 6 | 2 | `views/person/missing_requests/show.html.erb:36` `views/person/timesheets/edit.html.erb:61` |
| `oneoff:formaction-back-button` | shared-helper | 2 | 4 | 2 | `views/teams_positions/bulk_teams/preview.html.erb:119` `views/teams_positions/bulk_positions/preview.html.erb:110` |
| `oneoff:jump-to-letter` | shared-helper | 2 | 2 | 2 | `views/scheduling/schedule_by_position/index.html.erb:21-24` `views/scheduling/schedule_by_callsign/index.html.erb:53-56` |
| `oneoff:button-tabs` | shared-helper | 1 | 1 | 2 | `views/common/surveys/report.html.erb:15-26` |
| `oneoff:in-page-anchor-menu` | shared-helper | 1 | 1 | 2 | `views/common/_dropdown_scroll_list.html.erb:19-21` |
| `oneoff:print-screen-nav` | one-off-markup | 1 | 5 | 2 | `views/training/sessions/_print_screen_nav.html.erb:3` |
| `oneoff:progress-rail` | custom-css | 1 | 6 | 2 | `views/shift_operations/roc_photo_board/_board.html.erb:47` |
| `dropdown_divider` | shared-helper | 4 | 5 | 1 | `helpers/navbar_helper.rb:28` `helpers/navigation_helper.rb:91` `views/application/_top_menu.html.erb:95` |
| `tab_navigation` | shared-helper | 2 | 10 | 1 | `helpers/tabs_helper.rb:9` `views/me/event_info.html.erb:3` `views/me/event_info.html.erb:3` |
| `class:tab` | daisyui-class | 2 | 3 | 1 | `helpers/messages_helper.rb:37` `views/profile_photos/new.html.erb:89` |
| `css:mega-menu-item` | custom-css(mega-menu.css) | 2 | 2 | 1 | `views/me/menu/_content.html.erb:69` `views/me/menu/_item.html.erb:3` |
| `css:mega-menu-item-desc` | custom-css(mega-menu.css) | 2 | 2 | 1 | `helpers/mega_menu_helper.rb:111` `views/me/menu/_item.html.erb:17` |
| `css:mega-menu-item-title` | custom-css(mega-menu.css) | 2 | 2 | 1 | `helpers/mega_menu_helper.rb:110` `views/me/menu/_item.html.erb:10` |
| `area-helper` | area-helper | 1 | 1 | 1 | `views/register/show.html.erb:13` |
| `attribute` | attribute | 1 | 4 | 1 | `views/person/tickets_provisions/show.html.erb:5` |
| `css:bookmark-page` | custom-css(bookmark.css) | 1 | 1 | 1 | `views/bookmarks/show.html.erb:15` |
| `css:mega-menu-back` | custom-css(mega-menu.css) | 1 | 1 | 1 | `views/me/menu/_content.html.erb:92` |
| `css:mega-menu-body` | custom-css(mega-menu.css) | 1 | 1 | 1 | `views/me/menu/_content.html.erb:26` |
| `css:mega-menu-close` | custom-css(mega-menu.css) | 1 | 1 | 1 | `views/me/menu/_content.html.erb:14` |
| `css:mega-menu-content` | custom-css(mega-menu.css) | 1 | 1 | 1 | `views/me/menu/_content.html.erb:1` |
| `css:mega-menu-header` | custom-css(mega-menu.css) | 1 | 1 | 1 | `views/me/menu/_content.html.erb:3` |
| `css:mega-menu-item-cat` | custom-css(mega-menu.css) | 1 | 1 | 1 | `views/me/menu/_item.html.erb:13` |
| `css:mega-menu-items` | custom-css(mega-menu.css) | 1 | 6 | 1 | `views/me/menu/_content.html.erb:42` |
| `css:mega-menu-panel-title` | custom-css(mega-menu.css) | 1 | 5 | 1 | `views/me/menu/_content.html.erb:40` |
| `css:mega-menu-panels` | custom-css(mega-menu.css) | 1 | 1 | 1 | `views/me/menu/_content.html.erb:38` |
| `css:mega-menu-search` | custom-css(mega-menu.css) | 1 | 1 | 1 | `views/me/menu/_content.html.erb:7` |
| `css:mega-menu-section-title` | custom-css(mega-menu.css) | 1 | 2 | 1 | `views/me/menu/_content.html.erb:66` |
| `css:mega-menu-side` | custom-css(mega-menu.css) | 1 | 1 | 1 | `views/me/menu/_content.html.erb:28` |
| `css:mega-menu-side-divider` | custom-css(mega-menu.css) | 1 | 1 | 1 | `views/me/menu/_content.html.erb:31` |
| `css:mega-menu-star-spacer` | custom-css(mega-menu.css) | 1 | 1 | 1 | `views/me/menu/_item.html.erb:7` |
| `css:mega-menu-tabs` | custom-css(mega-menu.css) | 1 | 1 | 1 | `views/me/menu/_content.html.erb:20` |
| `hero_panel` | shared-helper | 1 | 1 | 1 | `views/person/work_history/index.html.erb:4` |
| `hero_panel back_to kwarg` | shared-helper | 1 | 1 | 1 | `views/alerts/edit.html.erb:4` |
| `oneoff:anchor-as-button` | shared-helper | 1 | 1 | 1 | `views/bmid/export/index.html.erb:44-45` |
| `oneoff:back-slot-cross-interface` | shared-helper | 1 | 3 | 1 | `views/person/_hero.html.erb:26` |
| `oneoff:back-to-dashboard` | shared-helper | 1 | 2 | 1 | `views/people/create_account/new.html.erb:11` |
| `oneoff:back-to-first-page-button` | shared-helper | 1 | 1 | 1 | `views/admin/legacy_log/index.html.erb:99-106` |
| `oneoff:bare-text-label` | one-off-markup | 1 | 4 | 1 | `views/people/unified_flagging/index.html.erb:96` |
| `oneoff:in-page-anchor` | rails-helper | 1 | 1 | 1 | `views/communication/surveys/index.html.erb:14` |
| `oneoff:jump-link-buttons` | shared-helper | 1 | 7 | 1 | `views/me/feedback/index.html.erb:42` |
| `oneoff:no-back-link` | not-handled | 1 | 4 | 1 | `views/shift_operations/bulk_sign_in_out/preview.html.erb:19` |
| `oneoff:page-switch-button` | area-helper | 1 | 1 | 1 | `views/scheduling/hq_forecast/index.html.erb:25` |
| `oneoff:preset-button-toggle` | shared-helper | 1 | 10 | 1 | `views/vc/applications/index.html.erb:52` |
| `oneoff:prev-next-pager` | one-off-markup | 1 | 8 | 1 | `views/training/completed_training/_pager.html.erb:5` |
| `oneoff:print-back-link` | shared-helper | 1 | 1 | 1 | `views/scheduling/shift_lead/print_sheet.html.erb:56-65` |
| `ui_pager top and bottom` | shared-helper | 1 | 5 | 1 | `views/communication/rbs_messages/index.html.erb:67` |
| `class:drawer` | daisyui-class | 2 | 5 | 0 | `helpers/sidebar_helper.rb:62` `views/layouts/application.html.erb:76` |
| `class:navbar` | daisyui-class | 2 | 7 | 0 | `views/application/_public_menu.html.erb:7` `views/application/_top_menu.html.erb:7` |
| `content_tag/tag.nav` | rails-helper | 2 | 2 | 0 | `helpers/register_helper.rb:29` `views/application/_top_menu.html.erb:7` |
| `css:mega-menu-cat-btn` | custom-css(mega-menu.css) | 1 | 1 | 0 | `helpers/mega_menu_helper.rb:116` |
| `css:mega-menu-cat-chevron` | custom-css(mega-menu.css) | 1 | 1 | 0 | `helpers/mega_menu_helper.rb:113` |
| `css:mega-menu-cat-text` | custom-css(mega-menu.css) | 1 | 1 | 0 | `helpers/mega_menu_helper.rb:109` |
| `css:mega-menu-dialog` | custom-css(mega-menu.css) | 1 | 1 | 0 | `views/application/_mega_menu.html.erb:5` |
| `css:mega-menu-frame` | custom-css(mega-menu.css) | 1 | 1 | 0 | `views/application/_mega_menu.html.erb:40` |
| `css:mega-menu-panel` | custom-css(mega-menu.css) | 1 | 1 | 0 | `helpers/mega_menu_helper.rb:88` |
| `css:mega-menu-star` | custom-css(mega-menu.css) | 1 | 1 | 0 | `helpers/mega_menu_helper.rb:134` |
| `dropdown_item_disabled` | shared-helper | 1 | 1 | 0 | `helpers/navigation_helper.rb:99` |
| `oneoff:responsive-duplicate-controls` | shared-helper | 1 | 4 | 0 | `views/application/_top_menu.html.erb:47` |
| `oneoff:step-chips` | shared-helper | 1 | 11 | 0 | `helpers/register_helper.rb:29` |
| `partial:common/dropdown_scroll_list` | shared-partial | 1 | 1 | 0 | `helpers/application_helper.rb:77` |
| `ui_pager_meta` | shared-helper | 1 | 2 | 0 | `helpers/ui_components/ui_pager_helper.rb:30` |

### cards (52 variants)

| Variant | Impl | Files | Uses | Pages | Examples |
|---|---|---|---|---|---|
| `ui_section` | shared-helper | 293 | 513 | 280 | `helpers/application_helper.rb:337` `helpers/ui_components/ui_section_helper.rb:10` `views/admin/action_logs/_live.html.erb:34` |
| `ui_stat_box` | shared-helper | 144 | 444 | 147 | `helpers/admin/jobs_helper.rb:60` `helpers/scheduling/sandman_qualified_helper.rb:98` `helpers/training/mentoring_helper.rb:64` |
| `ui_disclosure` | shared-helper | 133 | 153 | 138 | `helpers/ui_components/ui_disclosure_helper.rb:23` `views/admin/action_logs/_live.html.erb:21` `views/admin/action_logs/index.html.erb:56` |
| `ui_stat_row` | shared-helper | 122 | 122 | 127 | `helpers/ui_components/ui_stat_row_helper.rb:26` `views/admin/jobs/index.html.erb:7` `views/admin/mail_log/index.html.erb:5` |
| `helper-class-override` | shared-helper, area-helper | 72 | 97 | 85 | `views/common/_dashboard_group.html.erb:3` `views/common/_dashboard_step.html.erb:13` `views/common/_event_summary_breakdown.html.erb:62` |
| `oneoff:div-card` | one-off-markup, custom-css | 26 | 123 | 58 | `views/admin/documents/body.html.erb:4` `views/common/_timesheet_notes.html.erb:6-11` `views/common/_trophies.html.erb:15` |
| `ui_card` | shared-helper | 12 | 15 | 20 | `helpers/ui_components/ui_card_helper.rb:37` `views/common/available_sign_ups/_training_months.html.erb:10` `views/common/mentoring/_mentee_card.html.erb:10` |
| `ui_accent_card` | shared-helper | 14 | 53 | 19 | `helpers/ui_components/ui_accent_card_helper.rb:62` `views/common/_dashboard_step.html.erb:7` `views/common/available_sign_ups/show.html.erb:15` |
| `ui_card_body` | shared-helper | 8 | 8 | 13 | `helpers/ui_components/ui_card_helper.rb:66` `views/common/mentoring/_mentee_card.html.erb:24` `views/common/mentoring/_shift_card.html.erb:13` |
| `oneoff:review-pane` | custom-css | 2 | 2 | 13 | `views/common/messages/_pane.html.erb:22-24` `views/common/unified_flagging/_review_pane.html.erb:15-16` |
| `css:card-standard` | custom-css(cards.css) | 12 | 12 | 12 | `views/alerts/_alert_group.html.erb:8` `views/common/schedule/_signed_up_row.html.erb:6` `views/me/dashboard/_announcements_section.html.erb:9` |
| `ui_icon_item` | shared-helper | 10 | 29 | 11 | `helpers/person/permissions_helper.rb:21` `helpers/ui_components/ui_icon_item_helper.rb:26` `views/common/_timesheet_confirm.html.erb:17` |
| `ui_card_footer` | shared-helper | 6 | 6 | 11 | `helpers/ui_components/ui_card_helper.rb:93` `views/common/mentoring/_mentee_card.html.erb:28` `views/common/mentoring/_shift_card.html.erb:33` |
| `css:box` | custom-css(boxes.css) | 4 | 4 | 9 | `views/common/timesheet/_listing.html.erb:4` `views/common/timesheet/_listing_with_actions.html.erb:4` `views/common/unified_flagging/_review_pane.html.erb:15` |
| `css:box-default` | custom-css(boxes.css) | 4 | 4 | 9 | `views/common/timesheet/_listing.html.erb:4` `views/common/timesheet/_listing_with_actions.html.erb:4` `views/common/unified_flagging/_review_pane.html.erb:15` |
| `action_box` | shared-helper | 4 | 9 | 8 | `helpers/ui_components/action_box_helper.rb:49` `views/common/schedule/index.html.erb:163` `views/common/timesheet/index.html.erb:124` |
| `ui_accordion` | shared-helper | 8 | 25 | 7 | `helpers/ui_components/ui_accordion_helper.rb:22` `views/common/_timesheet_confirm.html.erb:36` `views/person/_permissions.html.erb:17` |
| `ui_stat_link` | shared-helper | 8 | 8 | 6 | `helpers/admin/jobs_helper.rb:58` `helpers/scheduling/sandman_qualified_helper.rb:103` `helpers/ui_components/ui_stat_box_helper.rb:99` |
| `oneoff:grid-layout` | one-off-markup | 5 | 9 | 5 | `views/me/operational_summary/_training.html.erb:2` `views/scheduling/sandman_qualified/index.html.erb:33-37` `views/scheduling/shift_lead/_status_band.html.erb:27-31` |
| `shared-partial` | shared-partial | 3 | 15 | 5 | `views/common/available_sign_ups/_slot.html.erb:84-94` `views/training/mentoring/assignments/_shift_card.html.erb:26` `views/training/mentoring/assignments/_upcoming_card.html.erb:3` |
| `css:review-pane` | custom-css(review-pane.css) | 1 | 1 | 5 | `views/common/unified_flagging/_review_pane.html.erb:15` |
| `oneoff:tinted-info-box` | one-off-markup | 6 | 25 | 4 | `views/dashboard_tasks/_attend_alpha_shift_pending.html.erb:4` `views/dashboard_tasks/_attend_cheetah_cub_shift_pending.html.erb:4` `views/dashboard_tasks/_attend_training_pending.html.erb:27` |
| `ui_card_title` | shared-helper | 3 | 3 | 4 | `helpers/ui_components/ui_card_helper.rb:73` `views/common/mentoring/_mentee_card.html.erb:18` `views/ticketing/maintenance/index.html.erb:31` |
| `class:card-standard` | custom-css | 6 | 8 | 3 | `views/me/dashboard/_announcements_section.html.erb:9` `views/me/vehicles_dashboard/_pvr_requests.html.erb:6` `views/person/memberships/_team_card.html.erb:1` |
| `oneoff:bordered-text-box` | one-off-markup | 3 | 19 | 3 | `views/communication/rbs_messages/index.html.erb:112` `views/communication/rbs_history/show.html.erb:70` `views/communication/rbs_broadcasts/review.html.erb:36` |
| `oneoff:instruction-list-in-section` | custom-css | 3 | 3 | 3 | `views/admin/permissions/edit.html.erb:6-25` `views/admin/permissions/new_art.html.erb:6-21` `views/admin/rbs_alerts/edit.html.erb:6-29` |
| `oneoff:scroll-box` | one-off-markup | 3 | 7 | 3 | `views/communication/announcements/_announcement.html.erb:43` `views/communication/surveys/show.html.erb:45` `views/communication/rbs_broadcasts/_position_checkboxes.html.erb:16` |
| `ui_card_section` | shared-helper | 3 | 5 | 3 | `helpers/ui_components/ui_card_helper.rb:86` `views/common/mentoring/_art_section.html.erb:39` `views/common/mentoring/index.html.erb:58` |
| `oneoff:bordered-box` | one-off-markup | 2 | 4 | 3 | `views/me/tickets/_item_details.html.erb:14` `views/me/tickets/_ticket_gift_conditions.html.erb:2` |
| `ui_card_image` | shared-helper | 2 | 3 | 3 | `helpers/ui_components/ui_card_helper.rb:53` `views/common/mentoring/_mentee_card.html.erb:12` |
| `mentor_card_row / mentor_tally_row` | shared-helper | 1 | 2 | 3 | `views/common/mentoring/_art_section.html.erb:23-31` |
| `class:stat` | daisyui-class | 2 | 6 | 2 | `views/ticketing/statistics/_pipeline_card.html.erb:31` `views/timesheets/correction_stats/_decision_card.html.erb:29` |
| `oneoff:instruction-list-in-fieldset` | custom-css | 1 | 1 | 2 | `views/admin/oauth_clients/_form.html.erb:6-16` |
| `oneoff:left-rule-indent` | one-off-markup | 1 | 1 | 2 | `views/common/_dashboard_step.html.erb:15` |
| `content_tag/tag.details` | rails-helper | 4 | 5 | 1 | `helpers/navigation_helper.rb:47` `helpers/ui_components/ui_accordion_helper.rb:30` `helpers/ui_components/ui_disclosure_helper.rb:46` |
| `class:collapse` | daisyui-class | 1 | 3 | 1 | `views/hq/shift_manage/_section.html.erb:27` |
| `css:instruction-list` | custom-css | 1 | 4 | 1 | `views/vc/applications/edit_details.html.erb:16` |
| `oneoff:callout-as-container` | shared-helper | 1 | 1 | 1 | `views/mentoring/alpha_pods/people/new.html.erb:21-26` |
| `oneoff:card-header-bar` | one-off-markup | 1 | 3 | 1 | `views/timesheets/on_duty/index.html.erb:137` |
| `oneoff:card-section-divider` | one-off-markup | 1 | 1 | 1 | `views/mentoring/alpha_pods/_pod_card.html.erb:24` |
| `oneoff:custom-accordion` | daisyui-class | 1 | 7 | 1 | `views/hq/shift_manage/_section.html.erb:25` |
| `oneoff:custom-list-row` | one-off-markup | 1 | 4 | 1 | `views/training/sessions/_trainee_card.html.erb:7` |
| `oneoff:disclosure-stack` | one-off-markup | 1 | 1 | 1 | `views/admin/permissions/index.html.erb:53-77` |
| `oneoff:divider-block` | one-off-markup | 1 | 1 | 1 | `views/hq/shift_manage/_other_entries.html.erb:11` |
| `oneoff:message-box` | one-off-markup | 1 | 3 | 1 | `views/communication/person_banners/_banner.html.erb:32` |
| `oneoff:rich-disclosure-summary` | shared-helper | 1 | 1 | 1 | `views/bmid/export/_buckets.html.erb:17-23` |
| `oneoff:status-medallion-block` | one-off-markup | 1 | 6 | 1 | `views/me/vehicles_dashboard/index.html.erb:30` |
| `card_disclosure` | shared-helper | 1 | 2 | 0 | `helpers/ui_components/ui_disclosure_helper.rb:34` |
| `css:me-hero-panel` | custom-css(hero-panel.css) | 1 | 1 | 0 | `helpers/ui_components/ui_hero_panel_helper.rb:245` |
| `inline_disclosure` | shared-helper | 1 | 2 | 0 | `helpers/ui_components/ui_disclosure_helper.rb:33` |
| `oneoff:clickable-stat-filter` | area-helper | 1 | 2 | 0 | `helpers/scheduling/sandman_qualified_helper.rb:52-83` |
| `oneoff:variant-by-status` | area-helper | 1 | 9 | 0 | `helpers/dashboard_helper.rb:100` |

### toasts-alerts (37 variants)

| Variant | Impl | Files | Uses | Pages | Examples |
|---|---|---|---|---|---|
| `ui_callout_box` | shared-helper | 284 | 989 | 256 | `helpers/form_helper.rb:1202` `helpers/ui_components/notice_box_helper.rb:15` `views/admin/action_logs/_live.html.erb:17` |
| `helper-class-override` | shared-helper | 21 | 27 | 33 | `views/common/unified_flagging/_personnel_warning.html.erb:10` `views/common/unified_flagging/_review_pane.html.erb:34` `views/common/schedule/signup_summary.html.erb:84` |
| `oneoff:plain-text-alert` | one-off-markup | 29 | 105 | 31 | `views/common/schedule/_people_signed_up.html.erb:9-11` `views/common/scheduling/_alpha_shift_info.html.erb:16-19` `views/common/shift_manage/_blocked_modal.html.erb:4-7` |
| `ui_alert_banner` | shared-helper | 4 | 6 | 10 | `helpers/ui_components/notice_box_helper.rb:66` `views/common/_timesheet_confirm.html.erb:4` `views/common/scheduling/_signup_blockers.html.erb:5` |
| `oneoff:callout-wrapper` | one-off-markup | 8 | 9 | 8 | `views/scheduling/position_credits/position.html.erb:12-17` `views/scheduling/position_credits/timeline.html.erb:8-12` `views/scheduling/position_credits/new.html.erb:8-13` |
| `oneoff:inline-error-text` | one-off-markup | 5 | 16 | 6 | `views/me/surveys/_question.html.erb:23` `views/me/tickets/_claimed_overview.html.erb:27` `views/me/tickets/_section_detail.html.erb:37` |
| `ui_callout_box+list-bulleted` | shared-helper | 3 | 3 | 4 | `views/ticketing/trs_export/_skipped.html.erb:8-14` `views/bmid/export/_skipped.html.erb:6-13` `views/bmid/export/unsubmit.html.erb:41-50` |
| `oneoff:icon-heading-row` | one-off-markup | 1 | 3 | 4 | `views/common/scheduling/_signup_blockers.html.erb:8-17` |
| `flash-read-in-view` | one-off | 4 | 9 | 3 | `helpers/ui_components/flash_helper.rb:6` `views/admin/sms_management/twilio.html.erb:4` `views/hq/site_registration/_radios_step.html.erb:10` |
| `oneoff:status-callout` | shared-helper | 1 | 1 | 3 | `views/common/missing_requests/_entry.html.erb:4-28` |
| `ui_alert_banner / ui_callout_box` | shared-helper | 1 | 4 | 3 | `views/common/shift_manage/_alerts.html.erb:10-13` |
| `oneoff:inline-personnel-warning` | shared-helper | 2 | 2 | 2 | `views/mentoring/alpha_status/index.html.erb:33-38` `views/mentoring/convert_prospectives/index.html.erb:48-53` |
| `oneoff:outcome-banner-on-page` | shared-helper | 2 | 19 | 2 | `views/teams_positions/bulk_teams/index.html.erb:8` `views/teams_positions/bulk_positions/index.html.erb:8` |
| `errors-via-flash` | shared-helper | 1 | 1 | 2 | `views/admin/sms_management/twilio.html.erb:4-9` |
| `oneoff:conditional-variant` | shared-helper | 1 | 2 | 2 | `views/common/bmids/_warnings.html.erb:15` |
| `ui_toast_render` | shared-helper | 5 | 11 | 1 | `helpers/ui_components/toast_helper.rb:34` `views/layouts/application.html.erb:111` `views/me/dashboard/_onboarding.html.erb:88` |
| `attribute` | attribute | 1 | 10 | 1 | `views/person/passkeys/new.html.erb:26` |
| `oneoff:callout-title` | shared-helper | 1 | 5 | 1 | `views/mentoring/alpha_mentor_assignments/index.html.erb:33` |
| `oneoff:callout-wrapping-form` | shared-helper | 1 | 27 | 1 | `views/alerts/edit.html.erb:119` |
| `oneoff:confirm-in-callout` | shared-helper | 1 | 8 | 1 | `views/people/search/index.html.erb:24` |
| `oneoff:custom-notice-box` | one-off-markup | 1 | 1 | 1 | `views/common/qualifications/index.html.erb:91-96` |
| `oneoff:div-card` | one-off-markup | 1 | 9 | 1 | `views/me/announcements/index.html.erb:11` |
| `oneoff:print-callout` | custom-css | 1 | 9 | 1 | `views/training/sessions/trainers_report.html.erb:78` |
| `oneoff:success-callout-for-result` | shared-helper | 1 | 1 | 1 | `views/admin/oauth_clients/index.html.erb:25-36` |
| `ui_callout_box icon` | shared-helper | 1 | 1 | 1 | `views/bmid/manage/index.html.erb:36` |
| `ui_callout_box replaces list` | shared-helper | 1 | 6 | 1 | `views/communication/surveys/index.html.erb:18` |
| `ui_callout_box status` | shared-helper | 1 | 11 | 1 | `views/communication/surveys/show.html.erb:14` |
| `ui_callout_box truncation` | shared-helper | 1 | 7 | 1 | `views/communication/rbs_history/index.html.erb:47` |
| `ui_callout_box variant mapping` | shared-helper | 1 | 10 | 1 | `views/communication/rbs_broadcasts/_notices.html.erb:5` |
| `ui_callout_box+list-numbered` | shared-helper | 1 | 1 | 1 | `views/ticketing/trs_export/index.html.erb:25-33` |
| `ui_toast_stream` | shared-helper | 3 | 5 | 0 | `helpers/ui_components/toast_helper.rb:65` `views/common/available_sign_ups/create.turbo_stream.erb:13` `views/common/available_sign_ups/destroy.turbo_stream.erb:13` |
| `oneoff:live-region-append` | one-off-markup | 1 | 1 | 0 | `views/common/messages/_arrival.turbo_stream.erb:6-8` |
| `oneoff:nested-rule` | one-off-markup | 1 | 1 | 0 | `views/me/vehicles_dashboard/_pvr_status_agreement_needed.html.erb:17` |
| `oneoff:toast-stack` | one-off-markup | 1 | 7 | 0 | `views/layouts/application.html.erb:107` |
| `partial:common/toast` | shared-partial | 1 | 1 | 0 | `helpers/ui_components/toast_helper.rb:59` |
| `ui_flash_successful` | shared-helper | 1 | 1 | 0 | `helpers/ui_components/flash_helper.rb:5` |
| `ui_success_text` | shared-helper | 1 | 2 | 0 | `helpers/ui_components/flash_helper.rb:6` |

### empty-loading (62 variants)

| Variant | Impl | Files | Uses | Pages | Examples |
|---|---|---|---|---|---|
| `ui_empty_state` | shared-helper | 281 | 892 | 291 | `helpers/ui_components/notice_box_helper.rb:106` `views/admin/action_logs/_live.html.erb:37` `views/admin/action_logs/index.html.erb:79` |
| `oneoff:plain-text-empty` | one-off-markup, area-helper | 74 | 154 | 87 | `views/common/_trophies.html.erb:3-6` `views/common/_years_breakdown.html.erb:17` `views/common/unified_flagging/_history.html.erb:50` |
| `empty-not-handled` | not-handled | 44 | 69 | 66 | `views/common/_dashboard_progress.html.erb:11` `views/common/_timesheet_confirm.html.erb:15-31` `views/common/messages/_find_recipient_form.html.erb:12` |
| `value_or_dash` | shared-helper | 65 | 127 | 58 | `helpers/admin/jobs_helper.rb:190` `helpers/application_helper.rb:84` `helpers/link_helper.rb:28` |
| `turbo_frame_tag` | rails-helper | 44 | 62 | 55 | `helpers/bmid/manage_helper.rb:256` `helpers/modal_helper.rb:74` `views/admin/documents/body.html.erb:3` |
| `lazy-turbo-frame-or-image` | attribute | 11 | 12 | 17 | `helpers/ui_components/ui_card_helper.rb:60` `views/admin/documents/index.html.erb:81` `views/admin/online_courses/enrollment.html.erb:9` |
| `oneoff:plain-text-loading` | one-off-markup, custom-css | 5 | 10 | 13 | `views/admin/documents/index.html.erb:80-83` `views/common/unified_flagging/_detail_frame.html.erb:16-18` `views/common/mail_log/_table.html.erb:56-58` |
| `oneoff:custom-spinner` | one-off-markup | 4 | 22 | 13 | `views/hq/tickets_provisions/show.html.erb:13` `views/application/_mega_menu.html.erb:42` `views/shared/_frame_spinner.html.erb:2` |
| `partial:shared/frame_spinner` | shared-partial | 4 | 5 | 11 | `views/admin/online_courses/enrollment.html.erb:10` `views/admin/online_courses/moodle_catalog.html.erb:10` `views/admin/sms_management/index.html.erb:95` |
| `turbo_stream_from` | rails-helper | 5 | 5 | 10 | `views/admin/action_logs/_live.html.erb:12` `views/admin/request_logs/_live.html.erb:12` `views/common/messages/_messages_panel.html.erb:39` |
| `helper-class-override` | shared-helper | 3 | 7 | 10 | `views/common/messages/_conversation_list.html.erb:14` `views/me/awards/index.html.erb:18` `views/people/retention_report/index.html.erb:67` |
| `shared/frame_spinner` | shared-partial | 3 | 4 | 10 | `views/admin/online_courses/enrollment.html.erb:8-11` `views/admin/sms_management/index.html.erb:94-96` `views/common/messages/_list_frame.html.erb:20-23` |
| `submit-busy-text` | attribute | 11 | 15 | 9 | `views/admin/salesforce_query/index.html.erb:16` `views/me/surveys/show.html.erb:82` `views/mentoring/alpha_mentor_assignments/index.html.erb:300` |
| `oneoff:imported-marker` | one-off-markup | 3 | 3 | 9 | `views/person/status_history/index.html.erb:48` `views/person/unified_flagging/_note.html.erb:14` `views/person/unified_flagging/_training_notes.html.erb:40` |
| `spinner-icon` | one-off | 2 | 2 | 9 | `views/shared/_autocomplete.html.erb:49` `views/sso/hand_back.html.erb:11` |
| `oneoff:dash-empty-cell` | hard-coded-value | 7 | 12 | 5 | `views/person/awards/_awards_table.html.erb:32` `views/person/missing_requests/show.html.erb:25` `views/person/scheduling/_log_changes.html.erb:4` |
| `oneoff:dash-placeholder` | one-off-markup, hard-coded-value | 4 | 6 | 5 | `helpers/survey_report_helper.rb:33` `views/common/assets/_table.html.erb:27` `views/dashboard_tasks/_dashboard_arts.html.erb:37` |
| `oneoff:submit-busy-text` | attribute | 4 | 14 | 4 | `views/mentoring/alpha_mentor_assignments/index.html.erb:300` `views/vc/bpguid/index.html.erb:27` `views/vc/create_prospectives/index.html.erb:70` |
| `ui_callout_box` | shared-helper | 3 | 15 | 4 | `views/me/tickets/gift.html.erb:22` `views/me/tickets/provisions.html.erb:27` `views/person/swag/_form.html.erb:5` |
| `oneoff:dash-empty-value` | area-helper, one-off-markup | 6 | 18 | 3 | `helpers/communication/rbs_helper.rb:141` `helpers/training/all_notes_helper.rb:29` `helpers/training/online_course_progress_helper.rb:16` |
| `oneoff:table-row-empty` | shared-helper, one-off-markup | 4 | 16 | 3 | `views/hq/shift_manage/_asset_table.html.erb:42` `views/hq/shift_manage/_pogs.html.erb:119` `views/mentoring/alpha_schedule/apparel.html.erb:84-85` |
| `oneoff:callout-instead-of-empty` | shared-helper | 3 | 19 | 3 | `views/teams_positions/bulk_teams/preview.html.erb:26` `views/teams_positions/bulk_positions/preview.html.erb:26` `views/teams_positions/membership_report/show.html.erb:44` |
| `oneoff:empty-not-handled` | not-handled | 3 | 19 | 3 | `views/dashboard_tasks/_take_student_survey.html.erb:4` `views/dashboard_tasks/_trainer_survey.html.erb:4` `views/dashboard_tasks/_upload_photo_rejected.html.erb:3` |
| `ui_empty_state no icon` | shared-helper | 3 | 7 | 3 | `views/communication/rbs_history/show.html.erb:109` `views/communication/rbs_history/retried.html.erb:21` `views/communication/rbs_broadcasts/_position_checkboxes.html.erb:18` |
| `none_stated` | shared-helper | 6 | 17 | 2 | `helpers/application_helper.rb:80` `views/profile/_camp.html.erb:11` `views/profile/_clothing.html.erb:10` |
| `oneoff:italic-none` | one-off-markup | 4 | 9 | 2 | `views/person/_contact_details.html.erb:9` `views/person/_summary_strip.html.erb:25` `views/person/_timestamp_value.html.erb:8` |
| `attribute` | attribute | 3 | 4 | 2 | `views/person/passkeys/new.html.erb:57` `views/training/mentoring/assignments/_general_notes_list.html.erb:9` `views/training/mentoring/assignments/_promote_dialog.html.erb:26` |
| `oneoff:dashed-empty-box` | one-off-markup | 2 | 14 | 2 | `views/me/agreements/index.html.erb:57` `views/me/announcements/index.html.erb:46` |
| `oneoff:plain-text-alert` | one-off-markup | 2 | 3 | 2 | `views/training/sessions/graduations/_dialog.html.erb:78` `views/training/sessions/rosters/_dialog.html.erb:82` |
| `oneoff:em-dash-cell` | hard-coded-value | 1 | 1 | 2 | `views/common/work_history/_matrix.html.erb:39` |
| `oneoff:js-filled-empty-div` | one-off-markup | 1 | 2 | 2 | `views/bookmarks/_document.html.erb:18` |
| `oneoff:plain-text-dash` | one-off-markup | 3 | 3 | 1 | `views/ticketing/access_documents/_summary_notes.html.erb:10-11` `views/ticketing/access_documents/_summary_special.html.erb:6-7` `views/ticketing/access_documents/_summary_value.html.erb:12-13` |
| `css:empty-state` | custom-css(empty-state.css) | 1 | 1 | 1 | `views/common/_trophies.html.erb:4` |
| `oneoff:all-done-message` | one-off-markup | 1 | 2 | 1 | `views/hq/shift_manage/_todo_list.html.erb:58` |
| `oneoff:blocked-row-empty` | shared-helper | 1 | 5 | 1 | `views/people/people_by_status/index.html.erb:22` |
| `oneoff:client-toggled-empty` | attribute | 1 | 4 | 1 | `views/people/languages_known/index.html.erb:69` |
| `oneoff:dash-empty` | hard-coded-value | 1 | 2 | 1 | `views/mentoring/alpha_mentor_assignments/print_sheet.html.erb:47` |
| `oneoff:em-empty-value` | rails-helper | 1 | 1 | 1 | `views/alerts/edit.html.erb:70` |
| `oneoff:empty-hidden` | not-handled | 1 | 1 | 1 | `views/vc/application_import/_failures_table.html.erb:6` |
| `oneoff:filtered-empty-not-handled` | not-handled | 1 | 3 | 1 | `views/certificates/certificates_report/show.html.erb:9` |
| `oneoff:italic-blank-marker` | rails-helper | 1 | 1 | 1 | `views/training/online_course_progress/index.html.erb:95` |
| `oneoff:italic-empty-value` | rails-helper | 1 | 2 | 1 | `views/communication/surveys/show.html.erb:46` |
| `oneoff:italic-imported` | one-off-markup | 1 | 1 | 1 | `views/person/certifications/show.html.erb:27` |
| `oneoff:italic-unknown` | one-off-markup | 1 | 1 | 1 | `views/person/callsigns/edit.html.erb:113` |
| `oneoff:lazy-detail-row` | shared-partial | 1 | 2 | 1 | `views/mentoring/convert_prospectives/index.html.erb:149` |
| `oneoff:muted-deleted-label` | one-off-markup | 1 | 2 | 1 | `views/person/scheduling/log.html.erb:70` |
| `oneoff:pending-label` | attribute | 1 | 1 | 1 | `views/me/passkeys/new.html.erb:55` |
| `oneoff:render-nothing` | not-handled | 1 | 1 | 1 | `views/bmid/export/_buckets.html.erb:10-11` |
| `oneoff:success-callout-empty` | shared-helper | 1 | 4 | 1 | `views/vc/photos_review/index.html.erb:7` |
| `oneoff:timer-refresh-frame` | rails-helper | 1 | 4 | 1 | `views/bookmarks/show.html.erb:16` |
| `oneoff:turbo-submits-with` | attribute | 1 | 1 | 1 | `views/me/surveys/show.html.erb:82` |
| `shared-partial empty_message` | shared-partial | 1 | 1 | 1 | `views/bmid/provisions/_list.html.erb:28` |
| `ui_callout_box as empty` | shared-helper | 1 | 1 | 1 | `views/bmid/export/unsubmit.html.erb:33-39` |
| `ui_empty_state as 404` | shared-helper | 1 | 2 | 1 | `views/bookmarks/not_found.html.erb:9` |
| `ui_empty_state inside form` | shared-helper | 1 | 3 | 1 | `views/communication/rbs_broadcasts/_audience_fields.html.erb:28` |
| `oneoff:empty-message-helper` | area-helper | 2 | 7 | 0 | `helpers/asset_management/asset_history_helper.rb:46` `helpers/asset_management/radio_checkout_helper.rb:32` |
| `turbo_empty_frame` | shared-helper | 2 | 2 | 0 | `helpers/modal_helper.rb:89` `helpers/turbo_helper.rb:4` |
| `oneoff:disabled-while-submitting` | attribute | 1 | 3 | 0 | `views/register/_form.html.erb:122` |
| `oneoff:empty-message-builder` | area-helper | 1 | 4 | 0 | `helpers/timesheets/early_late_checkins_helper.rb:79` |
| `oneoff:hidden-placeholder` | one-off-markup | 1 | 2 | 0 | `views/application/_navbar_messages.html.erb:21` |
| `oneoff:muted-placeholder` | area-helper | 1 | 2 | 0 | `helpers/person/membership_history_helper.rb:22` |
| `shared-partial` | shared-partial | 1 | 4 | 0 | `views/application/_mega_menu.html.erb:22` |

### typography (181 variants)

| Variant | Impl | Files | Uses | Pages | Examples |
|---|---|---|---|---|---|
| `hero_panel` | shared-helper | 402 | 405 | 439 | `helpers/ui_components/ui_hero_panel_helper.rb:242` `views/admin/action_logs/index.html.erb:1` `views/admin/bug_reports/index.html.erb:1` |
| `date-format-call` | detail | 397 | 976 | 282 | `helpers/admin/action_logs_helper.rb:60` `helpers/admin/error_logs_helper.rb:27` `helpers/admin/jobs_helper.rb:34` |
| `tw-font-and-text-style` | utility | 344 | 750 | 273 | `helpers/admin/action_logs_helper.rb:147` `helpers/admin/log_styles_helper.rb:29` `helpers/application_helper.rb:117` |
| `number-format-call` | detail | 312 | 666 | 245 | `helpers/admin/action_logs_helper.rb:169` `helpers/admin/jobs_helper.rb:69` `helpers/admin/permissions_helper.rb:8` |
| `tw-text-size` | utility | 246 | 444 | 212 | `helpers/admin/sms_management_helper.rb:124` `helpers/application_helper.rb:232` `helpers/form_helper.rb:792` |
| `<strong>` | raw-html | 225 | 528 | 203 | `views/admin/bug_reports/index.html.erb:11` `views/admin/documents/_form.html.erb:5` `views/admin/documents/index.html.erb:8` |
| `oneoff:utility-heading` | one-off-markup, custom-css | 52 | 122 | 84 | `views/admin/action_logs/_table.html.erb:57` `views/admin/error_logs/index.html.erb:81` `views/admin/jobs/_job.html.erb:25` |
| `<b>` | raw-html | 75 | 131 | 78 | `views/common/_hours_not_eligible.html.erb:12` `views/common/_preferred_name_disclaimer.html.erb:2` `views/common/scheduling/_alpha_shift_info.html.erb:25` |
| `oneoff:raw-heading-with-utilities` | raw-html, custom-css | 51 | 139 | 64 | `views/common/_dashboard_section_header.html.erb:6` `views/common/_timesheet_confirm.html.erb:14` `views/common/_trophies.html.erb:2` |
| `css:heading-title` | custom-css(headings.css) | 40 | 55 | 48 | `helpers/ui_components/notice_box_helper.rb:55` `helpers/vehicles/paperwork_helper.rb:133` `views/common/_timesheet_confirm.html.erb:14` |
| `<h3>` | raw-html | 34 | 58 | 38 | `views/common/_timesheet_confirm.html.erb:14` `views/common/_trophies.html.erb:2` `views/common/mentoring/_shift_card.html.erb:15` |
| `oneoff:muted-meta` | one-off-markup | 9 | 14 | 28 | `views/common/messages/_conversation_summary.html.erb:49-50` `views/common/messages/_message_card.html.erb:33` `views/common/unified_flagging/_list_row.html.erb:29-42` |
| `<h2>` | raw-html | 23 | 35 | 23 | `views/common/_dashboard_section_header.html.erb:13` `views/communication/announcements/_announcement.html.erb:10` `views/hq/site_registration/show.html.erb:9` |
| `oneoff:intro-paragraph` | one-off-markup, raw-html | 19 | 40 | 21 | `views/admin/documents/index.html.erb:20-23` `views/admin/rbs_alerts/_group.html.erb:2` `views/scheduling/position_credits/timeline.html.erb:22-25` |
| `css:heading-section` | custom-css(headings.css) | 19 | 22 | 19 | `views/common/_dashboard_section_header.html.erb:13` `views/communication/announcements/_announcement.html.erb:10` `views/hq/site_registration/show.html.erb:9` |
| `oneoff:count-line` | one-off-markup | 15 | 41 | 18 | `views/admin/online_courses/index.html.erb:30` `views/admin/salesforce_query/_results.html.erb:16-21` `views/admin/settings/index.html.erb:25-27` |
| `<h1>` | raw-html | 14 | 14 | 18 | `views/bookmarks/_document.html.erb:10` `views/bookmarks/not_found.html.erb:7` `views/me/dashboard/index.html.erb:4` |
| `<h4>` | raw-html | 8 | 12 | 16 | `views/common/qualifications/index.html.erb:92` `views/common/scheduling/_signup_blockers.html.erb:13` `views/common/unified_flagging/_history.html.erb:46` |
| `class:instruction-list` | custom-css | 13 | 64 | 13 | `views/timesheets/correction_requests/index.html.erb:38` `views/timesheets/correction_stats/index.html.erb:42` `views/timesheets/early_late_checkins/index.html.erb:23` |
| `ui_section_title` | shared-helper | 6 | 14 | 13 | `helpers/ui_components/ui_section_helper.rb:30` `views/common/available_sign_ups/show.html.erb:61` `views/common/schedule/index.html.erb:110` |
| `oneoff:inline-label` | one-off-markup | 4 | 4 | 13 | `views/common/scheduling/_slot_additional_info.html.erb:12` `views/common/training/_online_course_status.html.erb:6` `views/mentoring/post_season_summary/_row_extras_meta.html.erb:9-17` |
| `ui_subheading` | shared-helper | 8 | 19 | 11 | `helpers/ui_components/ui_section_helper.rb:39` `views/admin/sms_management/twilio.html.erb:66` `views/common/available_sign_ups/_training_months.html.erb:11` |
| `oneoff:bare-text-fragment` | one-off-markup | 10 | 18 | 10 | `views/dashboard_tasks/_attend_alpha_shift_not_available.html.erb:2` `views/dashboard_tasks/_attend_alpha_shift_sign_up.html.erb:2` `views/dashboard_tasks/_attend_training_art.html.erb:2` |
| `<em>` | raw-html | 12 | 18 | 9 | `views/bmid/titles/set.html.erb:34` `views/hq/shift_manage/_missing_request_modal.html.erb:8` `views/hq/shift_manage/_pog_guidelines.html.erb:73` |
| `oneoff:muted-meta-line` | one-off-markup, custom-css | 9 | 27 | 9 | `views/admin/documents/body.html.erb:5-9` `views/me/feedback/_survey.html.erb:12` `views/training/all_notes/_notes.html.erb:12` |
| `<i>` | raw-html | 3 | 5 | 9 | `views/common/unified_flagging/_history.html.erb:59` `views/common/mail_log/_table.html.erb:35` `views/dashboard_tasks/_dashboard_arts.html.erb:34` |
| `oneoff:em-dash-placeholder` | hard-coded-value, area-helper | 10 | 21 | 8 | `views/hq/shift_manage/_asset_table.html.erb:25` `helpers/asset_management/asset_history_helper.rb:65` `views/quartermaster/potential_swag/index.html.erb:150` |
| `helper-class-override` | shared-helper, area-helper | 7 | 14 | 8 | `views/common/timesheet/index.html.erb:93` `views/hq/shared/_header.html.erb:6` `views/me/surveys/show.html.erb:5` |
| `oneoff:block-strong` | one-off-markup | 1 | 1 | 8 | `views/common/messages/_thread.html.erb:20-22` |
| `class:me-muted` | custom-css | 7 | 17 | 7 | `views/person/access_documents/_form.html.erb:58` `views/person/applications/index.html.erb:26` `views/person/bmids/show.html.erb:55` |
| `oneoff:lead-sentence-text-lg` | one-off-markup | 7 | 40 | 7 | `views/teams_positions/roster_management/index.html.erb:6` `views/teams_positions/team_documents/index.html.erb:12` `views/certificates/certificates_report/index.html.erb:25` |
| `oneoff:weight-by-value` | one-off-markup | 1 | 2 | 7 | `views/common/_entry_card_grid.html.erb:13` |
| `oneoff:summary-line` | one-off-markup | 6 | 6 | 6 | `views/scheduling/sandman_qualified/index.html.erb:22-27` `views/scheduling/no_shows_report/index.html.erb:18-23` `views/scheduling/flake_report/index.html.erb:18-24` |
| `oneoff:dash-placeholder` | hard-coded-value | 6 | 11 | 5 | `views/admin/bug_reports/index.html.erb:36` `views/admin/request_logs/index.html.erb:144` `views/admin/sms_management/_lookup.html.erb:22-23` |
| `oneoff:muted-subline` | one-off-markup, area-helper | 6 | 15 | 5 | `helpers/vehicles/registry_helper.rb:95` `views/mentoring/convert_prospectives/index.html.erb:115` `views/mentoring/alpha_mentor_assignments/index.html.erb:210-217` |
| `oneoff:muted-note` | one-off-markup, custom-css | 5 | 12 | 5 | `views/admin/request_logs/index.html.erb:168-170` `views/dashboard_tasks/_online_course_waiting.html.erb:4` `views/mentoring/alpha_pods/unavailable.html.erb:11` |
| `hard-coded-value` | one-off-markup, area-helper | 5 | 6 | 4 | `helpers/scheduling/schedule_by_callsign_helper.rb:51` `views/scheduling/position_credits/position.html.erb:89-90` `views/scheduling/shift_lead/_roster.html.erb:58-59` |
| `oneoff:muted-placeholder` | custom-css | 4 | 4 | 4 | `views/admin/online_courses/enrollment_roster.html.erb:42` `views/admin/online_courses/moodle_catalog_courses.html.erb:25` `views/admin/permissions/_row.html.erb:22` |
| `oneoff:summary-count-line` | one-off-markup | 4 | 4 | 4 | `views/ticketing/unsubmit_provisions/results.html.erb:28-30` `views/ticketing/trs_export/mark_submitted.html.erb:30-32` `views/ticketing/maintenance/preview.html.erb:34-37` |
| `oneoff:plain-text-empty` | one-off-markup | 2 | 2 | 4 | `views/scheduling/hq_forecast/_people_dialog.html.erb:45` `views/scheduling/shift_signups/_fill_meter.html.erb:8` |
| `oneoff:section-title-wrapper` | one-off-markup | 1 | 2 | 4 | `views/common/schedule/index.html.erb:109-111` |
| `oneoff:secondary-text` | one-off-markup, area-helper | 5 | 7 | 3 | `views/scheduling/no_shows_report/position.html.erb:52-54` `views/scheduling/schedule_by_position/position.html.erb:58` `helpers/scheduling/shift_coverage_helper.rb:50` |
| `oneoff:padded-note-p` | one-off-markup | 4 | 22 | 3 | `views/communication/rbs_history/show.html.erb:103` `views/communication/rbs_history/retried.html.erb:18` `views/communication/rbs_broadcasts/review.html.erb:66` |
| `oneoff:centred-note` | one-off-markup | 3 | 5 | 3 | `views/sessions/_sso_door.html.erb:14` `views/sso/hand_back.html.erb:14` `views/profile_photos/crop.html.erb:134` |
| `oneoff:count-paragraph` | one-off-markup | 3 | 20 | 3 | `views/teams_positions/membership_report/show.html.erb:42` `views/teams_positions/position_grants/show.html.erb:51` `views/people/search/index.html.erb:158` |
| `oneoff:footer-summary` | one-off-markup | 3 | 3 | 3 | `views/scheduling/no_shows_report/position.html.erb:62-65` `views/scheduling/flake_report/position.html.erb:86-90` `views/scheduling/shift_drop_report/position.html.erb:80-84` |
| `oneoff:print-masthead` | custom-css | 2 | 2 | 3 | `views/mentoring/alpha_schedule/_sheet_masthead.html.erb:6-11` `views/mentoring/alpha_pods/print_sheet.html.erb:42-48` |
| `oneoff:bare-count-text` | one-off-markup | 1 | 2 | 3 | `views/common/missing_requests/index.html.erb:14` |
| `oneoff:bold-count` | one-off-markup | 1 | 1 | 3 | `views/person/vehicles/_eligibility_list.html.erb:4` |
| `oneoff:br-separated-list` | raw-html | 1 | 2 | 3 | `views/common/mentoring/index.html.erb:58-62` |
| `oneoff:italic-fallback` | raw-html | 1 | 4 | 3 | `views/vc/photos_review/_attribution.html.erb:3` |
| `oneoff:muted-annotation` | one-off-markup | 1 | 1 | 3 | `views/common/_event_summary_breakdown.html.erb:51` |
| `content_tag/tag.em` | rails-helper | 2 | 3 | 2 | `views/alerts/edit.html.erb:70` `views/vc/applications/_audit_log_section.html.erb:29` |
| `css:lexxy-content` | custom-css(lexxy.css) | 2 | 3 | 2 | `views/communication/announcements/_announcement.html.erb:43` `views/communication/surveys/show.html.erb:45` |
| `oneoff:cell-typography-by-hand` | one-off-markup | 2 | 2 | 2 | `views/admin/error_logs/index.html.erb:66` `views/admin/permissions/_row.html.erb:7` |
| `oneoff:form-note` | one-off-markup | 2 | 7 | 2 | `views/shift_operations/payroll_export/index.html.erb:75` `views/shift_operations/bulk_sign_in_out/index.html.erb:44` |
| `oneoff:lead-paragraph` | one-off-markup | 2 | 8 | 2 | `views/teams_positions/bulk_teams/index.html.erb:62` `views/teams_positions/bulk_positions/index.html.erb:54` |
| `oneoff:muted-count` | one-off-markup | 2 | 6 | 2 | `views/person/pogs/index.html.erb:20` `views/person/swag/index.html.erb:36` |
| `oneoff:muted-note-in-row` | one-off-markup | 2 | 6 | 2 | `views/timesheets/sanity_checker/index.html.erb:72` `views/timesheets/timesheet_by_position/index.html.erb:75` |
| `oneoff:plain-count-line` | one-off-markup | 2 | 2 | 2 | `views/training/capacity/index.html.erb:57` `views/training/trainer_attendance/index.html.erb:42` |
| `oneoff:plain-intro` | one-off-markup | 2 | 4 | 2 | `views/person/missing_requests/new.html.erb:15` `views/person/pogs/index.html.erb:9` |
| `oneoff:section-count-line` | one-off-markup | 2 | 2 | 2 | `views/scheduling/flake_report/position.html.erb:53` `views/scheduling/shift_drop_report/position.html.erb:47` |
| `oneoff:two-line-cell` | one-off-markup | 2 | 8 | 2 | `views/teams_positions/roster_management/show.html.erb:146` `views/vc/bpguid/_results.html.erb:65` |
| `oneoff:utility-label` | one-off-markup | 2 | 3 | 2 | `views/training/sessions/_session_table.html.erb:44` `views/training/mentoring/verdicts/_mentor_shifts.html.erb:13` |
| `oneoff:cell-typography-by-helper` | area-helper | 1 | 4 | 2 | `views/admin/action_logs/_table.html.erb:26` |
| `oneoff:count-note` | one-off-markup | 1 | 1 | 2 | `views/common/rbs/_delivery_table.html.erb:5-10` |
| `oneoff:fieldset-intro-paragraph` | one-off-markup | 1 | 3 | 2 | `views/admin/event_dates/_form.html.erb:4-6` |
| `oneoff:html-in-help-text` | hard-coded-value | 1 | 1 | 2 | `views/communication/survey_groups/_form.html.erb:15` |
| `oneoff:inline-label-value` | one-off-markup | 1 | 2 | 2 | `views/vehicles/registry/_form.html.erb:35` |
| `oneoff:manual-pluralize` | hard-coded-value | 1 | 2 | 2 | `views/common/_dashboard_progress.html.erb:14` |
| `oneoff:mono-inline` | one-off-markup | 1 | 4 | 2 | `views/common/resource_documents/_document.html.erb:30` |
| `oneoff:plain-text-alert` | one-off-markup | 1 | 1 | 2 | `views/admin/sms_management/twilio.html.erb:113` |
| `oneoff:middot-join` | area-helper, one-off-markup | 4 | 13 | 1 | `views/timesheets/early_late_checkins/_section.html.erb:61` `helpers/timesheets/on_duty_helper.rb:42` `helpers/shift_operations/payroll_export_helper.rb:56` |
| `content_tag/tag.strong` | rails-helper | 3 | 4 | 1 | `helpers/application_helper.rb:314` `helpers/form_helper.rb:636` `views/vc/applications/_audit_log_section.html.erb:18` |
| `oneoff:plain-paragraph-lede` | one-off-markup | 3 | 11 | 1 | `views/register/_intent.html.erb:2` `views/register/_form.html.erb:13` `views/register/_questions.html.erb:4` |
| `oneoff:pre-line-notes` | area-helper, one-off-markup | 2 | 7 | 1 | `helpers/training/mentoring_helper.rb:85` `views/training/mentoring/verdicts/index.html.erb:133` |
| `oneoff:stacked-cell` | one-off-markup, area-helper | 2 | 2 | 1 | `views/scheduling/early_arrivals/index.html.erb:189-192` `helpers/scheduling/early_arrivals_helper.rb:126-133` |
| `page_title` | shared-helper | 2 | 4 | 1 | `helpers/page_layout_helper.rb:9` `views/sessions/reset_token.html.erb:5` |
| `<code>` | raw-html | 1 | 2 | 1 | `views/vc/maintenance/index.html.erb:24` |
| `<p class=mb-2> + <strong> lead` | one-off-markup | 1 | 2 | 1 | `views/bug_reports/new.html.erb:21` |
| `<p class=mb-3>` | one-off-markup | 1 | 2 | 1 | `views/alerts/edit.html.erb:86` |
| `<p class=mb-3> + <strong> lead` | one-off-markup | 1 | 4 | 1 | `views/communication/mail_templates/index.html.erb:14` |
| `<small>` | raw-html | 1 | 1 | 1 | `views/mentoring/alpha_acceptance_sheets/print_sheets.html.erb:50` |
| `class:sr-only` | attribute | 1 | 2 | 1 | `views/timesheets/hours_credits/index.html.erb:140` |
| `hero_panel description block` | shared-helper | 1 | 6 | 1 | `views/communication/announcements/index.html.erb:1` |
| `oneoff:address-block` | one-off-markup | 1 | 1 | 1 | `views/profile/_mailing_address.html.erb:14` |
| `oneoff:bold-intro` | one-off-markup | 1 | 3 | 1 | `views/person/intake_notes/new.html.erb:16` |
| `oneoff:bold-total-cell` | one-off-markup | 1 | 2 | 1 | `views/timesheets/correction_stats/index.html.erb:143` |
| `oneoff:br-muted-note` | one-off-markup | 1 | 1 | 1 | `views/training/mentoring/assignments/_roster.html.erb:189` |
| `oneoff:br-separated-lines` | raw-html | 1 | 3 | 1 | `views/hq/tickets_provisions/_row.html.erb:8` |
| `oneoff:bullet-glyph` | hard-coded-value | 1 | 1 | 1 | `views/hq/shift_manage/_section.html.erb:41` |
| `oneoff:callout-body-utilities` | one-off-markup | 1 | 10 | 1 | `views/alerts/edit.html.erb:150` |
| `oneoff:class-string-variable` | one-off-markup | 1 | 4 | 1 | `views/common/qualifications/index.html.erb:59` |
| `oneoff:code-in-callout` | rails-helper | 1 | 4 | 1 | `views/communication/mail_templates/edit.html.erb:16` |
| `oneoff:code-inline` | one-off-markup | 1 | 9 | 1 | `views/shift_operations/bulk_sign_in_out/_formats.html.erb:7` |
| `oneoff:code-tag` | raw-html | 1 | 1 | 1 | `views/admin/sms_management/index.html.erb:66` |
| `oneoff:count-in-section-title` | shared-helper | 1 | 2 | 1 | `views/communication/rbs_phone_numbers/index.html.erb:60` |
| `oneoff:custom-heading-class` | custom-css | 1 | 7 | 1 | `views/me/menu/_content.html.erb:40` |
| `oneoff:em-dash-title` | hard-coded-value | 1 | 2 | 1 | `views/shift_operations/rollcall/sign_in.html.erb:9` |
| `oneoff:emphasis-span` | one-off-markup | 1 | 2 | 1 | `views/person/training/_moodle_account.html.erb:40` |
| `oneoff:fill-in-caption` | custom-css | 1 | 2 | 1 | `views/mentoring/alpha_schedule/signup_sheet.html.erb:50-88` |
| `oneoff:font-weight-reset` | one-off-markup | 1 | 2 | 1 | `views/training/sessions/_session_table.html.erb:29` |
| `oneoff:help-note` | one-off-markup | 1 | 1 | 1 | `views/scheduling/slot_copies/new.html.erb:66-68` |
| `oneoff:help-note-paragraph` | one-off-markup | 1 | 7 | 1 | `views/people/search/index.html.erb:113` |
| `oneoff:html-entity-quotes` | hard-coded-value | 1 | 1 | 1 | `views/communication/rbs/index.html.erb:15` |
| `oneoff:id-fallback-label` | hard-coded-value | 1 | 1 | 1 | `views/timesheets/sanity_checker/_entries.html.erb:42` |
| `oneoff:inline-emphasis` | one-off-markup | 1 | 3 | 1 | `views/profile/show.html.erb:45` |
| `oneoff:inline-example` | one-off-markup | 1 | 1 | 1 | `views/profile/identity_info_edit.html.erb:59` |
| `oneoff:inline-meta-span` | one-off-markup | 1 | 3 | 1 | `views/people/unified_flagging/_line_training_note.html.erb:10` |
| `oneoff:italic-note` | one-off-markup | 1 | 1 | 1 | `views/person/timesheets/_entries_table.html.erb:35` |
| `oneoff:italic-pronunciation` | one-off-markup | 1 | 1 | 1 | `views/person/_hero.html.erb:22` |
| `oneoff:label-as-heading` | rails-helper | 1 | 1 | 1 | `views/training/mentoring/assignments/_general_notes_list.html.erb:10` |
| `oneoff:label-leading-mismatch` | one-off-markup | 1 | 3 | 1 | `views/alerts/_alert_group.html.erb:57` |
| `oneoff:label-value-by-hand` | one-off-markup | 1 | 1 | 1 | `views/admin/online_courses/edit.html.erb:6-12` |
| `oneoff:meter-label-row` | one-off-markup | 1 | 1 | 1 | `views/common/qualifications/_track.html.erb:10-13` |
| `oneoff:mobile-column-label` | one-off-markup | 1 | 2 | 1 | `views/alerts/_alert_group.html.erb:44` |
| `oneoff:mono-tag-with-badge` | one-off-markup | 1 | 6 | 1 | `views/communication/mail_templates/index.html.erb:29` |
| `oneoff:muted-bracket-range` | one-off-markup | 1 | 4 | 1 | `views/person/_summary_strip.html.erb:49` |
| `oneoff:muted-contact-block` | one-off-markup | 1 | 4 | 1 | `views/dashboard_tasks/_attend_alpha_shift_pending.html.erb:34` |
| `oneoff:muted-intro` | one-off-markup | 1 | 1 | 1 | `views/person/agreements/index.html.erb:31` |
| `oneoff:muted-italic-log` | one-off-markup | 1 | 2 | 1 | `views/training/sessions/scores/_dialog.html.erb:32` |
| `oneoff:name-concat` | hard-coded-value | 1 | 1 | 1 | `views/shift_operations/payroll_missing_id/_section.html.erb:24` |
| `oneoff:note-meta-line` | one-off-markup | 1 | 6 | 1 | `views/timesheets/correction_requests/index.html.erb:118` |
| `oneoff:paragraph-in-callout` | one-off-markup | 1 | 1 | 1 | `views/admin/oauth_clients/index.html.erb:11-21` |
| `oneoff:plain-label-text` | one-off-markup | 1 | 1 | 1 | `views/admin/settings/edit.html.erb:6-8` |
| `oneoff:plain-paragraph-spacing` | one-off-markup | 1 | 5 | 1 | `views/teams_positions/roster_management/show.html.erb:18` |
| `oneoff:plain-text-count-notice` | one-off-markup | 1 | 1 | 1 | `views/admin/bug_reports/index.html.erb:10-13` |
| `oneoff:pre-line-text` | one-off-markup | 1 | 1 | 1 | `views/vehicles/registry/permit.html.erb:74` |
| `oneoff:print-title` | custom-css | 1 | 1 | 1 | `views/mentoring/alpha_schedule/info_sheet.html.erb:39-42` |
| `oneoff:rank-prefix` | one-off-markup | 1 | 1 | 1 | `views/timesheets/top_hour_earners/index.html.erb:81` |
| `oneoff:raw-inline-emphasis` | raw-html | 1 | 4 | 1 | `views/mentoring/alpha_acceptance_sheets/print_sheets.html.erb:50` |
| `oneoff:raw-legend` | raw-html | 1 | 3 | 1 | `views/vc/thank_you_cards/index.html.erb:31` |
| `oneoff:section-aside` | one-off-markup | 1 | 2 | 1 | `views/timesheets/timesheet_slot_repair/index.html.erb:51` |
| `oneoff:simple-format-cell` | rails-helper | 1 | 1 | 1 | `views/timesheets/forced_shift_start/index.html.erb:124` |
| `oneoff:stacked-date-and-person` | one-off-markup | 1 | 1 | 1 | `views/admin/documents/index.html.erb:50-57` |
| `oneoff:sub-note` | one-off-markup | 1 | 1 | 1 | `views/common/work_history/entire_year.html.erb:29` |
| `oneoff:subtitle-line` | one-off-markup | 1 | 9 | 1 | `views/teams_positions/position_records/index.html.erb:76` |
| `oneoff:summary-paragraph` | one-off-markup | 1 | 1 | 1 | `views/admin/error_logs/index.html.erb:94` |
| `oneoff:summary-text` | one-off-markup | 1 | 10 | 1 | `views/person/work_history/index.html.erb:37` |
| `oneoff:tabular-nums` | one-off-markup | 1 | 2 | 1 | `views/mentoring/shift_report/_people_table.html.erb:20` |
| `oneoff:tbody-text-class` | area-helper | 1 | 1 | 1 | `views/admin/action_logs/_live.html.erb:48` |
| `oneoff:text-base-paragraph` | one-off-markup | 1 | 16 | 1 | `views/me/tickets/sap.html.erb:57` |
| `oneoff:text-tones` | one-off-markup | 1 | 5 | 1 | `views/scheduling/shift_lead/_roster.html.erb:97` |
| `oneoff:title-plus-description-cell` | one-off-markup | 1 | 1 | 1 | `views/admin/rbs_alerts/_group.html.erb:21-22` |
| `oneoff:truncation-note` | one-off-markup | 1 | 1 | 1 | `views/asset_management/radio_checkout/index.html.erb:142` |
| `oneoff:utility-bold` | one-off-markup | 1 | 1 | 1 | `views/training/sessions/signup_sheet.html.erb:50` |
| `oneoff:utility-emphasis` | one-off-markup | 1 | 2 | 1 | `views/mentoring/alpha_schedule/signup_sheet.html.erb:24` |
| `oneoff:word-placeholder` | one-off-markup | 1 | 2 | 1 | `views/admin/passkeys/index.html.erb:67` |
| `content_tag/tag.h3` | rails-helper | 3 | 3 | 0 | `helpers/modal_helper.rb:181` `helpers/ui_components/action_box_helper.rb:70` `helpers/ui_components/ui_section_helper.rb:42` |
| `oneoff:bullet-join` | area-helper | 3 | 8 | 0 | `helpers/timesheets/timesheet_by_position_helper.rb:7` `helpers/timesheets/timesheet_totals_report_helper.rb:7` `helpers/timesheets/timesheets_by_callsign_helper.rb:10` |
| `content_tag/tag.h6` | rails-helper | 2 | 2 | 0 | `helpers/sidebar_helper.rb:113` `helpers/ui_components/ui_card_helper.rb:88` |
| `oneoff:copy-table` | area-helper | 2 | 7 | 0 | `helpers/timesheets/sanity_checker_helper.rb:19` `helpers/timesheets/slot_repair_helper.rb:11` |
| `oneoff:html-label` | one-off-markup | 2 | 2 | 0 | `helpers/mentoring/alpha_acceptance_sheets_helper.rb:43-47` `helpers/mentoring/alpha_mentor_assignments_helper.rb:75-79` |
| `oneoff:meta-bullets` | area-helper | 2 | 4 | 0 | `helpers/scheduling/schedule_by_position_helper.rb:22-24` `helpers/scheduling/schedule_by_callsign_helper.rb:14-15` |
| `<br>` | raw-html | 1 | 7 | 0 | `views/vc/applications/_personal_info_stage.html.erb:27` |
| `<h6>` | raw-html | 1 | 1 | 0 | `views/me/vehicles_dashboard/_eligible_positions.html.erb:8` |
| `content_tag/tag.h1` | rails-helper | 1 | 1 | 0 | `helpers/page_layout_helper.rb:10` |
| `content_tag/tag.h2` | rails-helper | 1 | 1 | 0 | `helpers/ui_components/ui_progress_box_helper.rb:90` |
| `content_tag/tag.h4` | rails-helper | 1 | 1 | 0 | `helpers/vehicles/paperwork_helper.rb:133` |
| `oneoff:axis-labels` | one-off-markup | 1 | 3 | 0 | `helpers/scheduling/position_credits_helper.rb:70-71` |
| `oneoff:bare-text-label` | one-off-markup | 1 | 2 | 0 | `views/hq/shift_manage/_pog_guidelines.html.erb:6` |
| `oneoff:body-text-on-main` | one-off-markup | 1 | 2 | 0 | `views/layouts/application.html.erb:82` |
| `oneoff:card-heading-markup` | area-helper | 1 | 8 | 0 | `helpers/shift_operations/payroll_export_helper.rb:62` |
| `oneoff:cell-year-and-date` | area-helper | 1 | 4 | 0 | `helpers/teams_positions/roster_management_helper.rb:184` |
| `oneoff:class-constants` | area-helper | 1 | 3 | 0 | `helpers/admin/log_styles_helper.rb:11` |
| `oneoff:dot-separated-detail` | area-helper | 1 | 2 | 0 | `helpers/scheduling/flake_report_helper.rb:12-16` |
| `oneoff:error-text-span` | one-off-markup | 1 | 1 | 0 | `helpers/admin/sms_management_helper.rb:123-124` |
| `oneoff:glyph-separator` | hard-coded-value | 1 | 3 | 0 | `helpers/survey_report_helper.rb:37` |
| `oneoff:inline-label-span` | one-off-markup | 1 | 1 | 0 | `helpers/admin/action_logs_helper.rb:201-207` |
| `oneoff:legend-row` | area-helper | 1 | 1 | 0 | `helpers/scheduling/hq_forecast_helper.rb:296-310` |
| `oneoff:mail-warning-class` | custom-css | 1 | 5 | 0 | `views/mail/layouts/mailer.html.erb:78` |
| `oneoff:manual-date-format` | hard-coded-value | 1 | 10 | 0 | `helpers/communication/rbs_helper.rb:105` |
| `oneoff:middot-separator` | area-helper | 1 | 1 | 0 | `helpers/vehicles/registry_helper.rb:105` |
| `oneoff:muted-italic-text` | one-off-markup | 1 | 1 | 0 | `helpers/mentor_helper.rb:97` |
| `oneoff:muted-label-span` | custom-css | 1 | 1 | 0 | `helpers/admin/shift_coverage_management_helper.rb:20` |
| `oneoff:null-dash-sr-only` | one-off-markup | 1 | 1 | 0 | `helpers/admin/salesforce_query_helper.rb:57-59` |
| `oneoff:srcdoc-pre` | inline-style | 1 | 6 | 0 | `helpers/mail_log_helper.rb:35` |
| `oneoff:status-inline-text` | area-helper | 1 | 4 | 0 | `helpers/timesheets/timesheet_entry_helper.rb:12` |
| `oneoff:text-placeholders` | hard-coded-value | 1 | 4 | 0 | `helpers/admin/sms_management_helper.rb:80` |
| `oneoff:text-size` | one-off-markup | 1 | 1 | 0 | `views/mentoring/post_season_summary/_list_extra.html.erb:6` |
| `oneoff:zero-width-space` | hard-coded-value | 1 | 1 | 0 | `helpers/admin/jobs_helper.rb:127` |

### color (40 variants)

| Variant | Impl | Files | Uses | Pages | Examples |
|---|---|---|---|---|---|
| `css:text-stone-muted` | custom-css(text-colors.css) | 226 | 418 | 199 | `helpers/application_helper.rb:81` `helpers/form_helper.rb:813` `helpers/mentor_helper.rb:97` |
| `tw-bridge-token` | token | 214 | 458 | 197 | `helpers/admin/action_logs_helper.rb:203` `helpers/application_helper.rb:117` `helpers/button_helper.rb:63` |
| `tw-semantic-token` | token | 171 | 284 | 161 | `helpers/application_helper.rb:287` `helpers/button_helper.rb:63` `helpers/communication/rbs_helper.rb:227` |
| `oneoff:status-by-color` | one-off-markup, shared-helper | 105 | 341 | 90 | `views/admin/online_courses/enrollment_roster.html.erb:30` `views/common/messages/_message_card.html.erb:47` `views/common/unified_flagging/_history.html.erb:89-98` |
| `css:text-stone-subtle` | custom-css(text-colors.css) | 49 | 78 | 45 | `helpers/admin/salesforce_query_helper.rb:48` `helpers/admin/shift_coverage_management_helper.rb:20` `helpers/application_helper.rb:338` |
| `css:me-muted` | custom-css(hero-panel.css) | 15 | 20 | 26 | `views/admin/documents/body.html.erb:6` `views/common/provisions/_form.html.erb:40` `views/common/resource_documents/_document.html.erb:20` |
| `css:text-stone-icon` | custom-css(text-colors.css) | 15 | 21 | 21 | `helpers/application_helper.rb:289` `helpers/communication/rbs_helper.rb:351` `helpers/person/permissions_helper.rb:42` |
| `css:text-stone-emphasis` | custom-css(text-colors.css) | 10 | 19 | 15 | `helpers/page_layout_helper.rb:71` `helpers/ui_components/ui_progress_completed_bar_helper.rb:70` `views/common/_entry_card_grid.html.erb:39` |
| `ui_stat_box` | shared-helper | 12 | 77 | 12 | `views/scheduling/schedule_by_callsign/person.html.erb:22-25` `views/timesheets/early_late_checkins/index.html.erb:51` `views/timesheets/on_duty/index.html.erb:31` |
| `tw-transparent-or-current` | token | 5 | 6 | 9 | `helpers/button_helper.rb:63` `views/application/_search_bar_placeholder.html.erb:167` `views/common/messages/_search_field.html.erb:29` |
| `oneoff:status-by-weight` | one-off-markup | 1 | 2 | 8 | `views/common/messages/_conversation_summary.html.erb:21-22` |
| `literal-color-value` | hard-coded | 9 | 25 | 6 | `helpers/button_helper.rb:63` `views/layouts/print.html.erb:41` `views/mail/layouts/mailer.html.erb:17` |
| `css:text-heading-primary` | custom-css(text-colors.css) | 3 | 4 | 5 | `views/common/_hours_not_eligible.html.erb:12` `views/me/vehicles_dashboard/_pvr_status_ineligible.html.erb:3` `views/person/_summary_group_heading.html.erb:4` |
| `class:text-stone-muted` | custom-css | 4 | 14 | 4 | `views/alerts/_alert_group.html.erb:13` `views/communication/surveys/index.html.erb:54` `views/communication/surveys/_group.html.erb:13` |
| `oneoff:colored-bold` | one-off-markup | 1 | 1 | 4 | `views/common/_hours_not_eligible.html.erb:12-13` |
| `oneoff:muted-italic-placeholder` | one-off-markup | 3 | 5 | 3 | `views/teams_positions/team_records/index.html.erb:97` `views/teams_positions/position_records/index.html.erb:97` `views/teams_positions/position_lineups/index.html.erb:43` |
| `oneoff:row-tint-state` | shared-helper | 3 | 3 | 3 | `views/mentoring/convert_prospectives/index.html.erb:94-101` `views/mentoring/alphas_convert/_section.html.erb:44-45` `views/mentoring/alpha_signout/_on_duty_table.html.erb:26-33` |
| `class:me-muted` | custom-css | 2 | 2 | 3 | `views/common/timesheet/_listing.html.erb:20` `views/common/timesheet/_entry_with_action.html.erb:91` |
| `oneoff:plain-text-alert` | one-off-markup, area-helper | 3 | 7 | 2 | `views/scheduling/early_arrivals/index.html.erb:195` `helpers/scheduling/early_arrivals_helper.rb:86-90` `views/shift_operations/rollcall/_set_time_dialog.html.erb:13` |
| `oneoff:error-colour-for-live-data` | shared-helper | 2 | 2 | 2 | `views/mentoring/shift_report/index.html.erb:54-57` `views/mentoring/alpha_signout/index.html.erb:97-100` |
| `oneoff:html-safe-coloured-string` | hard-coded-value | 2 | 6 | 2 | `views/me/tickets/_claimed_overview.html.erb:132` `views/me/tickets/_section_detail.html.erb:25` |
| `oneoff:inline-error-text` | one-off-markup | 1 | 2 | 2 | `views/common/_time_warnings.html.erb:12` |
| `tw-palette-color` | hard-coded | 2 | 3 | 1 | `views/layouts/print.html.erb:59` `views/profile_photos/crop.html.erb:95` |
| `oneoff:badge-in-sentence` | shared-helper | 1 | 24 | 1 | `views/person/vehicles/index.html.erb:65` |
| `oneoff:callout-variant-by-condition` | shared-helper | 1 | 3 | 1 | `views/teams_positions/bulk_teams/preview.html.erb:54` |
| `oneoff:highlight-span` | one-off-markup | 1 | 1 | 1 | `views/profile_photos/crop.html.erb:21` |
| `oneoff:muted-opacity` | one-off-markup | 1 | 2 | 1 | `views/vc/thank_you_cards/index.html.erb:65` |
| `oneoff:muted-placeholder-text` | one-off-markup | 1 | 2 | 1 | `views/teams_positions/roster_management/preview.html.erb:44` |
| `oneoff:muted-span` | one-off-markup | 1 | 1 | 1 | `views/dashboard_tasks/_sign_up_for_alpha_shift_waiting.html.erb:7` |
| `oneoff:palette-colors` | hard-coded-value | 1 | 3 | 1 | `views/profile_photos/crop.html.erb:95` |
| `oneoff:stat-variant-by-condition` | shared-helper | 1 | 6 | 1 | `views/teams_positions/membership_report/show.html.erb:23` |
| `oneoff:forced-theme` | attribute | 2 | 2 | 0 | `views/layouts/print.html.erb:16` `views/layouts/photo_board.html.erb:11` |
| `hard-coded-value` | hard-coded-value | 1 | 1 | 0 | `helpers/bmid/manage_helper.rb:81` |
| `oneoff:chrome-bar` | one-off-markup | 1 | 1 | 0 | `views/application/_top_menu.html.erb:7` |
| `oneoff:inline-style-block` | inline-style | 1 | 3 | 0 | `views/layouts/print.html.erb:39` |
| `oneoff:literal-color` | hard-coded-value | 1 | 2 | 0 | `views/pwa/manifest.json.erb:20` |
| `oneoff:mail-literal-colours` | hard-coded-value | 1 | 17 | 0 | `views/mail/layouts/mailer.html.erb:6` |
| `oneoff:me-muted-outside-me` | custom-css | 1 | 2 | 0 | `helpers/people/languages_known_helper.rb:15` |
| `oneoff:row-accent-border` | hard-coded-value | 1 | 1 | 0 | `helpers/bmid/manage_helper.rb:430-438` |
| `oneoff:severity-variant-table` | hard-coded-value | 1 | 62 | 0 | `helpers/communication/rbs_helper.rb:7` |

### spacing (60 variants)

| Variant | Impl | Files | Uses | Pages | Examples |
|---|---|---|---|---|---|
| `tw-spacing-scale` | utility | 752 | 2198 | 500 | `helpers/admin/action_logs_helper.rb:155` `helpers/application_helper.rb:110` `helpers/bmid/manage_helper.rb:457` |
| `tw-radius-shadow` | utility | 82 | 109 | 96 | `helpers/button_helper.rb:63` `helpers/scheduling/hq_forecast_helper.rb:187` `helpers/scheduling/position_credits_helper.rb:59` |
| `oneoff:page-width-wrapper` | one-off-markup, hard-coded-value | 36 | 44 | 40 | `views/common/available_sign_ups/index.html.erb:12` `views/common/available_sign_ups/show.html.erb:5` `views/common/qualifications/index.html.erb:61` |
| `<br>` | raw-html | 32 | 48 | 35 | `helpers/application_helper.rb:185` `helpers/mentoring/alpha_acceptance_sheets_helper.rb:45` `helpers/mentoring/alpha_mentor_assignments_helper.rb:78` |
| `oneoff:grid-layout` | one-off-markup, custom-css | 24 | 56 | 32 | `views/common/schedule/index.html.erb:102` `views/common/timesheet/index.html.erb:87-89` `views/hq/shared/_provision_info.html.erb:9` |
| `css:flex-center-gap-2` | custom-css(flex-patterns.css) | 21 | 31 | 29 | `views/admin/shift_coverage_groups/index.html.erb:52` `views/admin/shift_coverage_groups/show.html.erb:50` `views/alerts/_alert_group.html.erb:11` |
| `helper-class-override` | shared-helper | 17 | 38 | 17 | `views/admin/sms_management/_lookup.html.erb:30` `views/common/shift_manage/_on_duty.html.erb:20` `views/mentoring/alpha_acceptance_sheets/index.html.erb:31` |
| `tw-arbitrary-value` | hard-coded | 14 | 17 | 16 | `helpers/button_helper.rb:63` `helpers/form_helper.rb:883` `helpers/sidebar_helper.rb:100` |
| `css:two-column-lg` | custom-css(layout-patterns.css), custom-css | 15 | 19 | 15 | `views/hq/training/index.html.erb:36` `views/me/operational_summary/index.html.erb:15` `views/me/tickets/_claimed_overview.html.erb:11` |
| `css:flex-center` | custom-css(flex-patterns.css) | 6 | 6 | 15 | `views/application/_mega_menu.html.erb:42` `views/hq/tickets_provisions/show.html.erb:13` `views/person/banners/index.html.erb:47` |
| `oneoff:hero-wrapper` | one-off-markup | 3 | 6 | 12 | `views/common/messages/index.html.erb:9` `views/common/messages/show.html.erb:9` `views/common/messages/new.html.erb:5` |
| `inline-style` | inline-style | 14 | 23 | 11 | `helpers/button_helper.rb:83` `helpers/icon_helper.rb:81` `helpers/mailer_helper.rb:7` |
| `css:inline-flex-center-gap-2` | custom-css(flex-patterns.css) | 13 | 21 | 11 | `helpers/admin/jobs_helper.rb:144` `helpers/application_helper.rb:252` `helpers/scheduling/hq_forecast_helper.rb:307` |
| `css:stack-to-row-lg` | custom-css(layout-patterns.css) | 11 | 11 | 10 | `views/communication/rbs_broadcasts/review.html.erb:30` `views/communication/rbs_history/show.html.erb:66` `views/communication/rbs_phone_numbers/index.html.erb:59` |
| `oneoff:action-row-wrapper` | one-off-markup | 9 | 10 | 9 | `views/asset_management/records/index.html.erb:12` `views/asset_management/records/show.html.erb:7` `views/asset_management/records/type.html.erb:16` |
| `oneoff:button-row-wrapper` | one-off-markup | 8 | 34 | 8 | `views/teams_positions/position_grants/show.html.erb:42` `views/teams_positions/team_records/index.html.erb:15` `views/teams_positions/position_records/index.html.erb:14` |
| `oneoff:off-grid-padding` | one-off-markup | 1 | 1 | 8 | `views/common/messages/_message_card.html.erb:59` |
| `class:two-column-lg` | custom-css | 6 | 12 | 7 | `views/pogs/dashboard/index.html.erb:126` `views/me/operational_summary/index.html.erb:15` `views/me/tickets/_claimed_overview.html.erb:11` |
| `oneoff:spacing-wrapper-div` | one-off-markup | 5 | 24 | 5 | `views/training/capacity/index.html.erb:46` `views/training/completed_training/index.html.erb:35` `views/training/sessions/_trainees_section.html.erb:35` |
| `<hr>` | raw-html | 4 | 4 | 5 | `views/alerts/_alert_group.html.erb:29` `views/hq/site_registration/show.html.erb:46` `views/person/vehicles/index.html.erb:35` |
| `oneoff:negative-margin` | one-off-markup | 1 | 1 | 5 | `views/common/unified_flagging/_review_list.html.erb:7` |
| `oneoff:toolbar-row` | one-off-markup | 5 | 8 | 4 | `views/scheduling/shift_lead/_roster.html.erb:25-28` `views/scheduling/shift_lead/_status_band.html.erb:15-23` `views/timesheets/sanity_checker/check.html.erb:34` |
| `oneoff:rule-divider` | one-off-markup | 1 | 1 | 4 | `views/common/scheduling/_signup_blockers.html.erb:58` |
| `oneoff:wrapped-button-row` | one-off-markup | 3 | 3 | 3 | `views/admin/event_dates/index.html.erb:16-21` `views/admin/online_courses/index.html.erb:20-27` `views/admin/permissions/index.html.erb:23-28` |
| `oneoff:wrapper-around-button-row` | one-off-markup | 3 | 13 | 3 | `views/vc/reserved_handles/index.html.erb:31` `views/vc/shiny_penny_report/index.html.erb:16` `views/vc/spigot_flow_report/index.html.erb:49` |
| `oneoff:hard-coded-label-width` | hard-coded-value | 2 | 2 | 3 | `views/admin/action_logs/_table.html.erb:58` `views/admin/jobs/_job.html.erb:26` |
| `oneoff:card-padding` | one-off-markup | 1 | 1 | 3 | `views/common/timesheet/_entry_with_action.html.erb:25` |
| `class:stack-to-row-lg` | custom-css | 2 | 5 | 2 | `views/me/vehicles_dashboard/index.html.erb:21` `views/training/mentoring/assignments/_roster.html.erb:204` |
| `oneoff:card-footer-rule` | one-off-markup | 2 | 8 | 2 | `views/communication/announcements/_announcement.html.erb:47` `views/communication/person_banners/_banner.html.erb:36` |
| `oneoff:div-my-4-button-row` | one-off-markup | 2 | 7 | 2 | `views/communication/surveys/index.html.erb:28` `views/communication/surveys/show.html.erb:58` |
| `oneoff:divider-section` | one-off-markup | 2 | 6 | 2 | `views/shift_operations/cruise_direction/pods/_dialog.html.erb:30` `views/shift_operations/cruise_direction/people/edit.html.erb:35` |
| `oneoff:grow-spacer` | one-off-markup | 2 | 4 | 2 | `views/communication/rbs/_type_card.html.erb:10` `views/communication/rbs_broadcasts/_position_checkboxes.html.erb:6` |
| `oneoff:message-under-badge` | one-off-markup | 2 | 2 | 2 | `views/teams_positions/bulk_teams/preview.html.erb:87` `views/teams_positions/bulk_positions/preview.html.erb:78` |
| `oneoff:mt-3-wrapper` | one-off-markup | 1 | 6 | 2 | `views/teams_positions/position_records/_form.html.erb:57` |
| `oneoff:row-stack` | one-off-markup | 1 | 2 | 2 | `views/admin/shift_coverage_positions/_position_rows.html.erb:18` |
| `content_tag/tag.br` | rails-helper | 2 | 2 | 1 | `helpers/application_helper.rb:176` `views/person/permissions/edit.html.erb:57` |
| `oneoff:action-row-divider` | one-off-markup | 2 | 2 | 1 | `views/me/announcements/_announcement.html.erb:70` `views/me/vehicles_dashboard/_pvr_requests.html.erb:63` |
| `oneoff:arbitrary-width-constant` | hard-coded-value | 2 | 2 | 1 | `views/admin/action_logs/_live_rows.html.erb:15` `helpers/admin/action_logs_helper.rb:5` |
| `custom-css` | custom-css | 1 | 1 | 1 | `views/bmid/manage/_edit_grid.html.erb:68` |
| `oneoff:badge-wrapper` | one-off-markup | 1 | 3 | 1 | `views/teams_positions/position_sanity_checker/check.html.erb:37` |
| `oneoff:disclosure-stack` | one-off-markup | 1 | 1 | 1 | `views/timesheets/early_late_checkins/index.html.erb:94` |
| `oneoff:disclosure-stack-wrapper` | one-off-markup | 1 | 1 | 1 | `views/ticketing/bulk_access_documents/_formats.html.erb:12` |
| `oneoff:drill-down-wrapper` | one-off-markup | 1 | 1 | 1 | `views/communication/rbs/index.html.erb:41` |
| `oneoff:export-wrapper` | one-off-markup | 1 | 3 | 1 | `views/timesheets/timesheet_by_position/position.html.erb:51` |
| `oneoff:filter-bar-wrapper` | one-off-markup | 1 | 2 | 1 | `views/people/languages_known/show.html.erb:12` |
| `oneoff:form-margin-by-html-class` | attribute | 1 | 1 | 1 | `views/alerts/edit.html.erb:141` |
| `oneoff:page-wrapper` | one-off-markup | 1 | 1 | 1 | `views/person/timesheets/index.html.erb:91` |
| `oneoff:paragraph-spacing` | one-off-markup | 1 | 1 | 1 | `views/mentoring/alpha_schedule/no_alphas.html.erb:5` |
| `oneoff:responsive-action-stack` | one-off-markup | 1 | 1 | 1 | `views/person/_actions.html.erb:54` |
| `oneoff:space-y-wrapper` | one-off-markup | 1 | 1 | 1 | `views/people/search/index.html.erb:70` |
| `oneoff:subsection-divider` | one-off-markup | 1 | 2 | 1 | `views/profile/identity_info_edit.html.erb:54` |
| `oneoff:subsection-rule` | one-off-markup | 1 | 4 | 1 | `views/communication/rbs_broadcasts/_audience_fields.html.erb:13` |
| `oneoff:summary-export-row` | one-off-markup | 1 | 10 | 1 | `views/teams_positions/special_teams_hours/index.html.erb:116` |
| `oneoff:wrapped-button` | one-off-markup | 1 | 1 | 1 | `views/admin/sms_management/index.html.erb:86-89` |
| `oneoff:wrapper-div` | one-off-markup | 1 | 2 | 1 | `views/person/training/index.html.erb:18` |
| `css:app-edge-pad` | custom-css(safe-area.css) | 1 | 2 | 0 | `views/layouts/application.html.erb:78` |
| `hard-coded-value` | area-helper | 1 | 1 | 0 | `helpers/scheduling/sandman_qualified_helper.rb:88-91` |
| `oneoff:arbitrary-values` | hard-coded-value | 1 | 1 | 0 | `views/application/_search_bar_placeholder.html.erb:87` |
| `oneoff:mail-container` | inline-style | 1 | 21 | 0 | `views/mail/layouts/mailer.html.erb:11` |
| `oneoff:sticky-lane-label` | one-off-markup | 1 | 2 | 0 | `helpers/scheduling/hq_forecast_helper.rb:156-157` |

### icons (49 variants)

| Variant | Impl | Files | Uses | Pages | Examples |
|---|---|---|---|---|---|
| `icon-option-on-helper` | shared-helper | 689 | 2375 | 463 | `helpers/admin/jobs_helper.rb:8` `helpers/admin/sms_management_helper.rb:59` `helpers/application_helper.rb:242` |
| `fa_icon` | shared-helper, area-helper | 203 | 463 | 161 | `helpers/agreement_helper.rb:70` `helpers/application_helper.rb:110` `helpers/bmid/manage_helper.rb:188` |
| `html-entity-or-glyph` | hard-coded | 64 | 133 | 48 | `helpers/admin/error_logs_helper.rb:91` `helpers/admin/jobs_helper.rb:190` `helpers/admin/permissions_helper.rb:10` |
| `css:icon-error` | custom-css(icons.css) | 22 | 29 | 22 | `helpers/application_helper.rb:112` `helpers/bmid/manage_helper.rb:446` `helpers/person/timesheets_helper.rb:68` |
| `css:icon-warning` | custom-css(icons.css) | 21 | 25 | 20 | `helpers/bmid/manage_helper.rb:451` `helpers/scheduling/hq_forecast_helper.rb:21` `helpers/shirt_helper.rb:16` |
| `oneoff:icon-only-control` | shared-helper, area-helper | 12 | 46 | 18 | `views/common/_move_buttons.html.erb:12-15` `views/common/_toast.html.erb:9-11` `views/communication/rbs_history/index.html.erb:79` |
| `oneoff:glyph-separator` | hard-coded-value | 4 | 8 | 11 | `helpers/admin/action_logs_helper.rb:72` `views/common/_entry_card_grid.html.erb:20-22` `views/common/schedule/_signed_up_row.html.erb:14-16` |
| `css:icon-success` | custom-css(icons.css) | 15 | 28 | 10 | `helpers/application_helper.rb:110` `helpers/communication/rbs_helper.rb:216` `helpers/person/permissions_helper.rb:11` |
| `fa-class-literal` | one-off | 6 | 8 | 10 | `views/common/_photo_none.html.erb:3` `views/hq/shift_manage/_todo_chip.html.erb:20` `views/hq/shift_manage/_todo_list.html.erb:65` |
| `oneoff:arrow-glyph` | hard-coded-value | 9 | 9 | 9 | `views/dashboard_tasks/_attend_training_cheetah.html.erb:2` `views/dashboard_tasks/_online_course_blocked.html.erb:2` `views/dashboard_tasks/_sign_motor_pool_protocol_blocked.html.erb:2` |
| `helper-class-override` | shared-helper, area-helper | 7 | 10 | 7 | `views/mentoring/alpha_schedule/info_sheet.html.erb:58-61` `views/mentoring/alpha_mentor_assignments/index.html.erb:283-288` `views/timesheets/timesheet_slot_repair/_results.html.erb:28` |
| `oneoff:glyph-arrow` | hard-coded-value, one-off-markup | 4 | 9 | 5 | `views/person/timesheets/_log_entry_data.html.erb:11` `views/scheduling/slot_copies/new.html.erb:123-131` `views/scheduling/position_credit_copies/new.html.erb:81-90` |
| `image_tag` | rails-helper | 9 | 9 | 4 | `helpers/application_helper.rb:153` `helpers/mailer_helper.rb:8` `helpers/sidebar_helper.rb:98` |
| `content_tag/tag.i` | rails-helper | 6 | 6 | 4 | `helpers/application_helper.rb:81` `helpers/icon_helper.rb:118` `helpers/scheduling/position_credits_helper.rb:59` |
| `oneoff:asterisk-footnote` | hard-coded-value | 1 | 2 | 4 | `views/common/_event_summary_counts.html.erb:16` |
| `css:icon-info` | custom-css(icons.css) | 3 | 4 | 3 | `views/dashboard_tasks/_after_event_status_advisory.html.erb:9` `views/dashboard_tasks/_sign_motor_pool_protocol_needed.html.erb:10` `views/me/announcements/index.html.erb:14` |
| `oneoff:icon-legend` | one-off-markup, shared-helper | 2 | 6 | 3 | `views/common/bmids/_flag_legend.html.erb:8-18` `views/person/timesheets/index.html.erb:142` |
| `oneoff:tinted-icon-tile` | one-off-markup | 2 | 5 | 3 | `views/common/_dashboard_section_header.html.erb:3-5` `views/common/_trophies.html.erb:8-12` |
| `oneoff:glyph-bullet` | hard-coded-value | 4 | 10 | 2 | `views/mentoring/alpha_acceptance_sheets/print_sheets.html.erb:216` `views/mentoring/alpha_schedule/info_sheet.html.erb:124` `views/autocomplete/_person_item.html.erb:16` |
| `<i>` | raw-html | 3 | 3 | 2 | `views/hq/shift_manage/_todo_chip.html.erb:32` `views/hq/shift_manage/_todo_list.html.erb:65` `views/person/timesheets/log.html.erb:34` |
| `emoji-or-symbol-character` | hard-coded | 2 | 3 | 2 | `views/mentoring/alpha_schedule/signup_sheet.html.erb:48` `views/training/sessions/trainers_report.html.erb:48` |
| `oneoff:glyph-icon` | hard-coded-value | 2 | 3 | 2 | `views/mentoring/alpha_schedule/signup_sheet.html.erb:48` `views/training/sessions/trainers_report.html.erb:48` |
| `oneoff:icon-with-sr-only` | shared-helper, one-off-markup | 2 | 8 | 2 | `views/teams_positions/position_grants/show.html.erb:111` `views/vc/applications/_applications_table.html.erb:29` |
| `fa_icon+sr-only` | one-off-markup | 1 | 1 | 2 | `views/ticketing/trs_export/_rows_table.html.erb:43-46` |
| `oneoff:tinted-icon-medallion` | one-off-markup | 1 | 1 | 2 | `views/common/_status_medallion.html.erb:8-22` |
| `oneoff:raw-i-icon` | raw-html | 2 | 5 | 1 | `views/hq/shift_manage/_todo_list.html.erb:65` `views/hq/shift_manage/_todo_chip.html.erb:20` |
| `fa_icon label` | shared-helper | 1 | 1 | 1 | `views/bmid/manage/_edit_grid.html.erb:70-72` |
| `oneoff:drag-grip` | one-off-markup | 1 | 4 | 1 | `views/shift_operations/cruise_direction/_pod.html.erb:26` |
| `oneoff:fixed-icon-varying-variant` | shared-helper | 1 | 1 | 1 | `views/teams_positions/roster_management/preview.html.erb:21` |
| `oneoff:glyph-brackets` | hard-coded-value | 1 | 1 | 1 | `views/person/unified_flagging/_training_notes.html.erb:19` |
| `oneoff:glyph-breadcrumb` | hard-coded-value | 1 | 1 | 1 | `views/admin/sms_management/index.html.erb:76` |
| `oneoff:glyph-checkbox` | shared-helper | 1 | 1 | 1 | `views/mentoring/alpha_acceptance_sheets/print_sheets.html.erb:198-199` |
| `oneoff:icon-as-colour-dot` | shared-helper | 1 | 2 | 1 | `views/dashboard_tasks/_green_dot_mentee_shift_needed.html.erb:2` |
| `oneoff:icon-only-marker` | shared-helper | 1 | 1 | 1 | `views/person/timesheets/_entries_table.html.erb:40` |
| `oneoff:row-icon-on-some-rows` | shared-helper | 1 | 2 | 1 | `views/teams_positions/position_sanity_checker/index.html.erb:60` |
| `oneoff:status-by-color` | shared-helper | 1 | 12 | 1 | `views/profile/_alerts.html.erb:44` |
| `fa_icon direction` | area-helper | 1 | 6 | 0 | `helpers/communication/rbs_helper.rb:347` |
| `fa_icon title + sr-only` | area-helper | 1 | 1 | 0 | `helpers/bmid/manage_helper.rb:442-458` |
| `oneoff:dash-aria-label-span` | area-helper | 1 | 5 | 0 | `helpers/people/status_change_recommendations_helper.rb:38` |
| `oneoff:dual-icon-toggle` | shared-helper | 1 | 2 | 0 | `views/application/_theme_toggle.html.erb:17` |
| `oneoff:glyph-ellipsis` | hard-coded-value | 1 | 1 | 0 | `helpers/admin/sms_management_helper.rb:68` |
| `oneoff:icon-by-status` | area-helper | 1 | 24 | 0 | `helpers/dashboard_helper.rb:14` |
| `oneoff:icon-by-title-regex` | area-helper | 1 | 15 | 0 | `helpers/dashboard_helper.rb:83` |
| `oneoff:icon-flag` | area-helper | 1 | 1 | 0 | `helpers/scheduling/sandman_qualified_helper.rb:109-117` |
| `oneoff:icon-in-disclosure-title` | area-helper | 1 | 3 | 0 | `helpers/people/search_helper.rb:22` |
| `oneoff:icon-lookup` | area-helper | 1 | 6 | 0 | `helpers/shift_operations/cruise_direction_helper.rb:10` |
| `oneoff:legend-swatch` | one-off-markup | 1 | 1 | 0 | `helpers/scheduling/position_credits_helper.rb:55-63` |
| `oneoff:unused-status-icons` | area-helper | 1 | 2 | 0 | `helpers/person/timesheets_helper.rb:60` |
| `ui_icon_item` | shared-helper | 1 | 6 | 0 | `helpers/person/permissions_helper.rb:21` |

### other (449 variants)

| Variant | Impl | Files | Uses | Pages | Examples |
|---|---|---|---|---|---|
| `ui_badge` | shared-helper, area-helper | 195 | 740 | 137 | `helpers/admin/jobs_helper.rb:86` `helpers/admin/online_courses_helper.rb:22` `helpers/admin/request_logs_helper.rb:60` |
| `area-badge-helper` | area-helper | 56 | 74 | 60 | `views/admin/jobs/_job.html.erb:12` `views/admin/jobs/index.html.erb:118` `views/admin/online_courses/index.html.erb:45` |
| `helper-class-override` | shared-helper, area-helper | 50 | 82 | 45 | `views/common/messages/_conversation_summary.html.erb:54` `views/common/qualifications/_track.html.erb:14-19` `views/communication/rbs/index.html.erb:45` |
| `stimulus:scroll-to-top` | stimulus-controller | 29 | 29 | 29 | `views/admin/oauth_clients/index.html.erb:26` `views/bmid/export/create.html.erb:8` `views/bmid/export/unsubmit.html.erb:4` |
| `class:instruction-list` | custom-css | 17 | 104 | 23 | `views/alerts/edit.html.erb:43` `views/communication/mail_templates/edit.html.erb:44` `views/communication/announcements/_form.html.erb:4` |
| `oneoff:grid-layout` | one-off-markup, custom-css | 11 | 13 | 22 | `views/admin/permissions/_row.html.erb:35-44` `views/admin/sms_management/index.html.erb:26-98` `views/common/messages/_workspace.html.erb:23-24` |
| `ui_stat_box` | shared-helper, area-helper | 20 | 65 | 18 | `views/common/rbs/_delivery_summary.html.erb:33-43` `views/hq/timesheets/event_summary.html.erb:9` `views/asset_management/assets_outstanding/index.html.erb:34` |
| `oneoff:section-divider` | one-off-markup | 4 | 5 | 18 | `views/common/_timesheet_confirm.html.erb:35` `views/common/messages/_messages_panel.html.erb:47` `views/common/unified_flagging/_history.html.erb:21` |
| `stimulus:toggle` | stimulus-controller | 7 | 7 | 16 | `helpers/table_helper.rb:385` `helpers/ui_components/filter_bar_helper.rb:218` `views/common/available_sign_ups/_slot.html.erb:109` |
| `oneoff:utility-badge` | one-off-markup, custom-css | 7 | 15 | 14 | `views/me/dashboard/_announcements_section.html.erb:15` `views/me/vehicles_dashboard/_pvr_requests.html.erb:15` `views/scheduling/shift_lead/print_sheet.html.erb:215-218` |
| `oneoff:avatar` | custom-css, one-off-markup | 6 | 22 | 13 | `views/common/messages/_conversation_summary.html.erb:25-44` `views/common/messages/_find_recipient_form.html.erb:17-21` `views/common/messages/_messages_panel_header.html.erb:11-27` |
| `oneoff:hidden-behaviour-div` | one-off-markup, attribute | 6 | 9 | 13 | `views/common/messages/_thread.html.erb:15-18` `views/common/bulk_upload/index.html.erb:13` `views/common/bulk_upload/preview.html.erb:5` |
| `css:review-line` | custom-css(messages.css) | 2 | 2 | 13 | `views/common/messages/_conversation_summary.html.erb:21` `views/common/unified_flagging/_list_row.html.erb:23` |
| `stimulus:review-pane` | stimulus-controller | 2 | 2 | 13 | `views/common/messages/_workspace.html.erb:23` `views/common/unified_flagging/_review_workspace.html.erb:13` |
| `ui_progress_bar` | shared-helper | 10 | 20 | 12 | `helpers/survey_report_helper.rb:124` `helpers/ui_components/ui_progress_bar_helper.rb:52` `views/common/mentoring/_shift_card.html.erb:30` |
| `stimulus:read-more` | stimulus-controller | 3 | 3 | 10 | `helpers/admin/action_logs_helper.rb:137` `views/common/scheduling/_slot_additional_info.html.erb:14` `views/hq/shift_manage/_pog_guideline.html.erb:7` |
| `stimulus:scroll-to-element` | stimulus-controller | 3 | 3 | 10 | `views/common/messages/_thread.html.erb:16` `views/communication/surveys/show.html.erb:4` `views/vc/bpguid/_link_refused.html.erb:6` |
| `oneoff:read-more-truncation` | one-off-markup | 1 | 1 | 10 | `views/common/scheduling/_slot_additional_info.html.erb:13-32` |
| `stimulus:conditional-show` | stimulus-controller | 6 | 7 | 9 | `views/bmid/titles/_cell.html.erb:15` `views/profile/identity_info_edit.html.erb:80` `views/profile_languages/_form.html.erb:9` |
| `yes_no_badge` | shared-helper | 10 | 18 | 8 | `helpers/application_helper.rb:270` `helpers/teams_positions/position_sanity_checker_helper.rb:171` `views/people/bulk_lookup/index.html.erb:107` |
| `css:link` | custom-css(base.css) | 10 | 11 | 8 | `helpers/vc/handle_checker_helper.rb:69` `views/bmid/export/_buckets.html.erb:38` `views/me/dashboard/_onboarding.html.erb:31` |
| `css:messages-avatar-placeholder` | custom-css(messages.css) | 3 | 5 | 8 | `views/common/messages/_conversation_summary.html.erb:35` `views/common/messages/_find_recipient_form.html.erb:20` `views/common/messages/_messages_panel_header.html.erb:19` |
| `oneoff:avatar-placeholder` | inline-style, one-off-markup | 3 | 13 | 8 | `views/common/_photo_none.html.erb:1-5` `views/me/directory/index.html.erb:45` `views/training/sessions/_trainee_card.html.erb:9` |
| `css:messages-avatar-rbs` | custom-css(messages.css) | 2 | 2 | 8 | `views/common/messages/_conversation_summary.html.erb:38` `views/common/messages/_messages_panel_header.html.erb:22` |
| `css:messages-avatar-team` | custom-css(messages.css) | 2 | 4 | 8 | `views/common/messages/_conversation_summary.html.erb:28` `views/common/messages/_messages_panel_header.html.erb:13` |
| `stimulus:autocomplete` | stimulus-controller | 2 | 2 | 8 | `helpers/form_helper.rb:265` `views/shared/_autocomplete.html.erb:19` |
| `stimulus:message-search` | stimulus-controller | 2 | 3 | 8 | `views/common/messages/_search_field.html.erb:21` `views/common/messages/_workspace.html.erb:40` |
| `css:messages-conversation-avatar` | custom-css(messages.css) | 1 | 1 | 8 | `views/common/messages/_conversation_summary.html.erb:25` |
| `css:messages-conversation-item` | custom-css(messages.css) | 1 | 1 | 8 | `views/common/messages/_conversation_summary.html.erb:21` |
| `css:messages-reply-editor` | custom-css(messages.css) | 1 | 1 | 8 | `views/common/messages/_reply_form.html.erb:32` |
| `css:messages-workspace` | custom-css(hq-window.css) | 1 | 1 | 8 | `views/common/messages/_workspace.html.erb:22` |
| `oneoff:chat-bubble` | one-off-markup | 1 | 1 | 8 | `views/common/messages/_message_card.html.erb:59-63` |
| `oneoff:frame-as-header` | rails-helper | 1 | 1 | 8 | `views/common/messages/_messages_panel.html.erb:15` |
| `oneoff:kbd-footer` | custom-css | 1 | 8 | 8 | `views/shared/_autocomplete.html.erb:66` |
| `oneoff:landing-ring` | one-off-markup | 1 | 1 | 8 | `views/common/messages/_message_card.html.erb:29-31` |
| `oneoff:search-status-line` | one-off-markup | 1 | 1 | 8 | `views/common/messages/_conversation_list.html.erb:8-12` |
| `stimulus:thread-live` | stimulus-controller | 1 | 1 | 8 | `views/common/messages/_messages_panel.html.erb:42` |
| `ui_section` | shared-helper | 7 | 13 | 7 | `views/timesheets/early_late_checkins/_section.html.erb:15` `views/timesheets/forced_shift_start/index.html.erb:76` `views/timesheets/timesheet_unconfirmed/_group.html.erb:7` |
| `stimulus:form` | stimulus-controller | 7 | 8 | 6 | `helpers/page_layout_helper.rb:42` `views/scheduling/shift_lead/_picker.html.erb:37` `views/scheduling/shift_lead/_sort_control.html.erb:16` |
| `css:login-panel` | custom-css(login.css) | 6 | 6 | 6 | `views/sessions/forgot.html.erb:6` `views/sessions/new.html.erb:10` `views/sessions/reset_password_confirmation.html.erb:3` |
| `oneoff:scroll-to-top-marker` | attribute | 6 | 6 | 6 | `views/mentoring/convert_prospectives/index.html.erb:23` `views/mentoring/alphas_convert/index.html.erb:22` `views/mentoring/alpha_signout/index.html.erb:31` |
| `oneoff:status-by-color` | shared-helper, area-helper | 6 | 55 | 6 | `views/common/_dashboard_progress.html.erb:23-33` `views/communication/announcements/index.html.erb:12` `views/communication/rbs_phone_numbers/index.html.erb:16` |
| `ui_disclosure` | shared-helper | 5 | 12 | 6 | `views/asset_management/asset_history/index.html.erb:49` `views/vehicles/paperwork/index.html.erb:26` `views/vehicles/registry/_form.html.erb:74` |
| `css:instruction-list` | custom-css | 4 | 32 | 6 | `views/teams_positions/special_teams_hours/index.html.erb:22` `views/teams_positions/team_records/_form.html.erb:7` `views/teams_positions/position_records/_form.html.erb:39` |
| `ui_stat_row` | shared-helper | 4 | 20 | 6 | `views/common/timesheet/index.html.erb:23-34` `views/person/awards/index.html.erb:9` `views/person/bmids/show.html.erb:19` |
| `oneoff:stat-grid` | one-off-markup | 3 | 5 | 6 | `views/common/schedule/signup_summary.html.erb:8-26` `views/ticketing/statistics/index.html.erb:63` `views/bmid/sanity_check/index.html.erb:10-20` |
| `oneoff:inline-badge-legend` | one-off-markup | 1 | 1 | 6 | `views/common/unified_flagging/_rank_legend.html.erb:16-21` |
| `oneoff:year-chip-line` | one-off-markup | 1 | 1 | 6 | `views/common/unified_flagging/_history.html.erb:23-37` |
| `tooltip-or-title-attribute` | attribute | 10 | 18 | 5 | `helpers/form_helper.rb:810` `helpers/scheduling/hq_forecast_helper.rb:264` `helpers/scheduling/position_credits_helper.rb:87` |
| `css:alpha-sheet` | custom-css(alpha-sheets.css) | 5 | 7 | 5 | `views/mentoring/alpha_mentor_assignments/print_sheet.html.erb:21` `views/mentoring/alpha_pods/print_sheet.html.erb:41` `views/mentoring/alpha_schedule/apparel.html.erb:17` |
| `stimulus:unsaved-changes` | stimulus-controller | 5 | 5 | 5 | `views/bmid/badges/edit.html.erb:105` `views/bmid/manage/_edit_grid.html.erb:25` `views/mentoring/alpha_mentor_assignments/index.html.erb:137` |
| `ui_stat_link` | shared-helper | 4 | 15 | 5 | `views/common/unified_flagging/_group_tiles.html.erb:10-19` `views/quartermaster/swag_distribution/index.html.erb:42` `views/mentoring/post_season_summary/index.html.erb:24-34` |
| `oneoff:icon-beside-block` | one-off-markup | 1 | 1 | 5 | `views/common/_icon_block.html.erb:14-21` |
| `oneoff:meter-label-row` | one-off-markup | 1 | 1 | 5 | `views/common/mentoring/_shift_card.html.erb:26-30` |
| `css:login-submit-button` | custom-css(login.css) | 5 | 5 | 4 | `views/sessions/_password_form.html.erb:64` `views/sessions/_sso_door.html.erb:11` `views/sessions/forgot.html.erb:36` |
| `oneoff:legend-line` | one-off-markup | 1 | 2 | 4 | `views/common/schedule/signup_summary.html.erb:28-31` |
| `stimulus:disclosure-fields` | stimulus-controller | 1 | 1 | 4 | `views/common/messages/_compose.html.erb:40` |
| `oneoff:plain-dash` | hard-coded-value | 5 | 5 | 3 | `views/bmid/manage/_edit_grid.html.erb:105` `views/bmid/manage/_showers_cell.html.erb:19` `views/bmid/manage/_table.html.erb:43` |
| `css:alpha-callsign` | custom-css(alpha-sheets.css) | 3 | 3 | 3 | `views/mentoring/alpha_schedule/apparel.html.erb:49` `views/mentoring/alpha_schedule/info_sheet.html.erb:65` `views/mentoring/alpha_schedule/signup_sheet.html.erb:51` |
| `css:alpha-running-head` | custom-css(alpha-sheets.css) | 3 | 4 | 3 | `views/mentoring/alpha_schedule/apparel.html.erb:32` `views/mentoring/alpha_schedule/info_sheet.html.erb:48` `views/mentoring/alpha_schedule/signup_sheet.html.erb:32` |
| `css:alpha-subline` | custom-css(alpha-sheets.css) | 3 | 5 | 3 | `views/mentoring/alpha_pods/print_sheet.html.erb:51` `views/mentoring/alpha_schedule/apparel.html.erb:25` `views/mentoring/alpha_schedule/signup_sheet.html.erb:22` |
| `css:login-field` | custom-css(login.css) | 3 | 5 | 3 | `views/sessions/_password_form.html.erb:20` `views/sessions/forgot.html.erb:27` `views/sessions/reset_token.html.erb:43` |
| `css:login-input` | custom-css(base.css) | 3 | 5 | 3 | `views/sessions/_password_form.html.erb:19` `views/sessions/forgot.html.erb:26` `views/sessions/reset_token.html.erb:42` |
| `data-controller:scroll-to-top` | attribute | 3 | 3 | 3 | `views/timesheets/timesheet_slot_repair/_results.html.erb:6` `views/shift_operations/bulk_sign_in_out/index.html.erb:20` `views/shift_operations/bulk_sign_in_out/preview.html.erb:12` |
| `inline-style` | inline-style | 3 | 31 | 3 | `views/scheduling/shift_lead/print_sheet.html.erb:33-52` `views/training/sessions/signup_sheet.html.erb:21` `views/training/sessions/trainers_report.html.erb:15` |
| `oneoff:badge-row` | one-off-markup | 3 | 12 | 3 | `views/training/sessions/_trainee_card.html.erb:41` `views/training/trainer_attendance/_session_line.html.erb:13` `views/training/mentoring/assignments/_shift_card.html.erb:15` |
| `oneoff:badge-stat-row` | one-off-markup | 3 | 3 | 3 | `views/common/work_history/entire_year.html.erb:10-14` `views/common/work_history/position_all.html.erb:7-10` `views/common/work_history/position_summary.html.erb:10-14` |
| `oneoff:meta-line` | one-off-markup | 3 | 26 | 3 | `views/communication/announcements/_announcement.html.erb:19` `views/communication/person_banners/_banner.html.erb:21` `views/me/surveys/show.html.erb:23` |
| `stimulus:passkey` | stimulus-controller | 3 | 3 | 3 | `views/me/passkeys/new.html.erb:12` `views/person/passkeys/new.html.erb:21` `views/sessions/_passkey_door.html.erb:8` |
| `stimulus:position-picker` | stimulus-controller | 3 | 3 | 3 | `views/communication/rbs_broadcasts/_position_checkboxes.html.erb:5` `views/shift_operations/payroll_export/index.html.erb:43` `views/teams_positions/special_teams_hours/index.html.erb:63` |
| `css:alpha-doc-label` | custom-css(alpha-sheets.css) | 2 | 2 | 3 | `views/mentoring/alpha_pods/print_sheet.html.erb:43` `views/mentoring/alpha_schedule/_sheet_masthead.html.erb:7` |
| `css:alpha-masthead` | custom-css(alpha-sheets.css) | 2 | 2 | 3 | `views/mentoring/alpha_pods/print_sheet.html.erb:42` `views/mentoring/alpha_schedule/_sheet_masthead.html.erb:6` |
| `css:alpha-shift` | custom-css(alpha-sheets.css) | 2 | 2 | 3 | `views/mentoring/alpha_pods/print_sheet.html.erb:45` `views/mentoring/alpha_schedule/_sheet_masthead.html.erb:9` |
| `css:alpha-when` | custom-css(alpha-sheets.css) | 2 | 2 | 3 | `views/mentoring/alpha_pods/print_sheet.html.erb:46` `views/mentoring/alpha_schedule/_sheet_masthead.html.erb:10` |
| `oneoff:inline-key-value` | one-off-markup | 2 | 14 | 3 | `views/person/provisions/_section.html.erb:19` `views/person/timesheets/index.html.erb:124` |
| `stimulus:list-filter` | stimulus-controller | 2 | 2 | 3 | `views/people/languages_known/index.html.erb:11` `views/shift_operations/rollcall/_roster.html.erb:14` |
| `oneoff:aria-hidden-toggle` | attribute | 1 | 2 | 3 | `views/common/timesheet/_entry_with_action.html.erb:124-129` |
| `oneoff:badge-hash-list` | one-off-markup | 1 | 2 | 3 | `views/common/timesheet/_entry_with_action.html.erb:4-22` |
| `oneoff:centered-badge` | one-off-markup | 1 | 1 | 3 | `views/common/mentoring/_mentee_card.html.erb:20-22` |
| `ui_card_image / photo_none` | shared-partial | 1 | 1 | 3 | `views/common/mentoring/_mentee_card.html.erb:11-17` |
| `<iframe>` | raw-html | 2 | 7 | 2 | `views/common/mail_log/body.html.erb:13` `views/vc/applications/_mail_log_section.html.erb:20` `views/common/mail_log/body.html.erb:13-14` |
| `attribute` | attribute, area-helper | 4 | 24 | 2 | `views/timesheets/on_duty/index.html.erb:156` `helpers/shift_operations/rollcall_helper.rb:199` `helpers/shift_operations/mass_signout_helper.rb:40` |
| `stimulus:copy-to-clipboard` | stimulus-controller | 3 | 3 | 2 | `helpers/ui_components/clipboard_helper.rb:28` `views/training/sessions/_trainees_section.html.erb:49` `views/training/untrained_people/index.html.erb:54` |
| `css:alpha-block-end` | custom-css(alpha-sheets.css) | 2 | 3 | 2 | `views/mentoring/alpha_schedule/info_sheet.html.erb:96` `views/mentoring/alpha_schedule/signup_sheet.html.erb:85` |
| `css:alpha-fill` | custom-css(alpha-sheets.css) | 2 | 28 | 2 | `views/mentoring/alpha_schedule/info_sheet.html.erb:64` `views/mentoring/alpha_schedule/signup_sheet.html.erb:50` |
| `css:alpha-flag-cell` | custom-css(alpha-sheets.css) | 2 | 3 | 2 | `views/mentoring/alpha_schedule/info_sheet.html.erb:58` `views/mentoring/alpha_schedule/signup_sheet.html.erb:48` |
| `css:alpha-value` | custom-css(alpha-sheets.css) | 2 | 12 | 2 | `views/mentoring/alpha_schedule/info_sheet.html.erb:69` `views/mentoring/alpha_schedule/signup_sheet.html.erb:55` |
| `oneoff:custom-progress` | inline-style | 2 | 6 | 2 | `views/ticketing/statistics/_pipeline_card.html.erb:31` `views/timesheets/correction_stats/_decision_card.html.erb:29` |
| `oneoff:hr-divider` | raw-html | 2 | 2 | 2 | `views/hq/site_registration/show.html.erb:46` `views/person/vehicles/index.html.erb:35` |
| `oneoff:html-comments` | raw-html | 2 | 9 | 2 | `views/profile_photos/new.html.erb:118` `views/profile_photos/crop.html.erb:93` |
| `oneoff:live-count` | attribute | 2 | 4 | 2 | `views/communication/rbs_broadcasts/_position_checkboxes.html.erb:8` `views/shift_operations/payroll_export/index.html.erb:55` |
| `oneoff:page-rules-style` | inline-style | 2 | 2 | 2 | `views/mentoring/alpha_schedule/info_sheet.html.erb:18-30` `views/mentoring/alpha_pods/print_sheet.html.erb:18-31` |
| `oneoff:plain-yes-no` | one-off-markup | 2 | 2 | 2 | `views/ticketing/provisions/index.html.erb:68` `views/bmid/badges/edit.html.erb:80-81` |
| `oneoff:print-sheet` | custom-css | 2 | 2 | 2 | `views/mentoring/alpha_acceptance_sheets/print_sheets.html.erb:29-267` `views/scheduling/shift_lead/print_sheet.html.erb:67-99` |
| `oneoff:scroll-to-top` | attribute | 2 | 2 | 2 | `views/vc/maintenance/reset_pnvs.html.erb:10` `views/vc/maintenance/reset_past_prospectives.html.erb:10` |
| `oneoff:status-line` | one-off-markup | 2 | 7 | 2 | `views/me/tickets/ticket.html.erb:19` `views/me/tickets/vehicle_pass.html.erb:26` |
| `stimulus:live-log` | stimulus-controller | 2 | 2 | 2 | `views/admin/action_logs/_live.html.erb:6` `views/admin/request_logs/_live.html.erb:6` |
| `ui_progress_box` | shared-helper | 2 | 2 | 2 | `helpers/ui_components/ui_progress_box_helper.rb:97` `views/common/_dashboard_progress.html.erb:12` |
| `class:lexxy-content` | custom-css | 1 | 2 | 2 | `views/bookmarks/_document.html.erb:30` |
| `css:photo-board-badge` | custom-css(photo-board.css) | 1 | 1 | 2 | `views/shift_operations/roc_photo_board/_board.html.erb:20` |
| `css:photo-board-callsign` | custom-css(photo-board.css) | 1 | 2 | 2 | `views/shift_operations/roc_photo_board/_board.html.erb:31` |
| `css:photo-board-card` | custom-css(photo-board.css) | 1 | 2 | 2 | `views/shift_operations/roc_photo_board/_board.html.erb:28` |
| `css:photo-board-card-body` | custom-css(photo-board.css) | 1 | 2 | 2 | `views/shift_operations/roc_photo_board/_board.html.erb:30` |
| `css:photo-board-cards` | custom-css(photo-board.css) | 1 | 1 | 2 | `views/shift_operations/roc_photo_board/_board.html.erb:26` |
| `css:photo-board-countdown` | custom-css(photo-board.css) | 1 | 1 | 2 | `views/shift_operations/roc_photo_board/_board.html.erb:10` |
| `css:photo-board-empty` | custom-css(photo-board.css) | 1 | 1 | 2 | `views/shift_operations/roc_photo_board/_board.html.erb:38` |
| `css:photo-board-group` | custom-css(photo-board.css) | 1 | 1 | 2 | `views/shift_operations/roc_photo_board/_board.html.erb:18` |
| `css:photo-board-group-count` | custom-css(photo-board.css) | 1 | 1 | 2 | `views/shift_operations/roc_photo_board/_board.html.erb:22` |
| `css:photo-board-group-header` | custom-css(photo-board.css) | 1 | 1 | 2 | `views/shift_operations/roc_photo_board/_board.html.erb:19` |
| `css:photo-board-group-title` | custom-css(photo-board.css) | 1 | 1 | 2 | `views/shift_operations/roc_photo_board/_board.html.erb:21` |
| `css:photo-board-groups` | custom-css(photo-board.css) | 1 | 1 | 2 | `views/shift_operations/roc_photo_board/_board.html.erb:16` |
| `css:photo-board-header` | custom-css(photo-board.css) | 1 | 1 | 2 | `views/shift_operations/roc_photo_board/_board.html.erb:7` |
| `css:photo-board-heading` | custom-css(photo-board.css) | 1 | 1 | 2 | `views/shift_operations/roc_photo_board/_board.html.erb:9` |
| `css:photo-board-host` | custom-css(photo-board.css) | 1 | 1 | 2 | `views/shift_operations/roc_photo_board/_board.html.erb:62` |
| `css:photo-board-layout` | custom-css(photo-board.css) | 1 | 1 | 2 | `views/shift_operations/roc_photo_board/_board.html.erb:15` |
| `css:photo-board-loaded` | custom-css(photo-board.css) | 1 | 1 | 2 | `views/shift_operations/roc_photo_board/_board.html.erb:8` |
| `css:photo-board-no-host` | custom-css(photo-board.css) | 1 | 1 | 2 | `views/shift_operations/roc_photo_board/_board.html.erb:70` |
| `css:photo-board-no-host-next` | custom-css(photo-board.css) | 1 | 1 | 2 | `views/shift_operations/roc_photo_board/_board.html.erb:72` |
| `css:photo-board-photo` | custom-css(photo-board.css) | 1 | 2 | 2 | `views/shift_operations/roc_photo_board/_photo.html.erb:5` |
| `css:photo-board-photo-missing` | custom-css(photo-board.css) | 1 | 1 | 2 | `views/shift_operations/roc_photo_board/_photo.html.erb:8` |
| `css:photo-board-position` | custom-css(photo-board.css) | 1 | 1 | 2 | `views/shift_operations/roc_photo_board/_board.html.erb:32` |
| `css:photo-board-rail` | custom-css(photo-board.css) | 1 | 1 | 2 | `views/shift_operations/roc_photo_board/_board.html.erb:47` |
| `css:photo-board-rail-count` | custom-css(photo-board.css) | 1 | 1 | 2 | `views/shift_operations/roc_photo_board/_board.html.erb:54` |
| `css:photo-board-rail-dot` | custom-css(photo-board.css) | 1 | 1 | 2 | `views/shift_operations/roc_photo_board/_board.html.erb:52` |
| `css:photo-board-rail-heading` | custom-css(photo-board.css) | 1 | 2 | 2 | `views/shift_operations/roc_photo_board/_board.html.erb:48` |
| `css:photo-board-rail-item` | custom-css(photo-board.css) | 1 | 1 | 2 | `views/shift_operations/roc_photo_board/_board.html.erb:51` |
| `css:photo-board-rail-list` | custom-css(photo-board.css) | 1 | 1 | 2 | `views/shift_operations/roc_photo_board/_board.html.erb:49` |
| `css:photo-board-rail-title` | custom-css(photo-board.css) | 1 | 1 | 2 | `views/shift_operations/roc_photo_board/_board.html.erb:53` |
| `oneoff:custom-collapse` | one-off-markup | 1 | 10 | 2 | `views/person/provisions/_section.html.erb:7` |
| `oneoff:hero-progress-labels` | shared-helper | 1 | 2 | 2 | `views/me/tickets/_landing.html.erb:56` |
| `oneoff:inert-status-row` | attribute | 1 | 3 | 2 | `views/shift_operations/rollcall/_row.html.erb:45` |
| `oneoff:plain-text-status` | one-off-markup | 1 | 1 | 2 | `views/person/_photo.html.erb:15` |
| `oneoff:raw-html-body` | one-off-markup | 1 | 1 | 2 | `views/admin/documents/body.html.erb:15-17` |
| `oneoff:readonly-badge-list` | shared-helper | 1 | 6 | 2 | `views/teams_positions/team_records/_form.html.erb:80` |
| `oneoff:status-line-grid` | one-off-markup | 1 | 10 | 2 | `views/bookmarks/_document.html.erb:6` |
| `oneoff:sticky-toolbar` | one-off-markup | 1 | 2 | 2 | `views/shift_operations/rollcall/_roster.html.erb:15` |
| `photo_tag` | shared-helper | 1 | 1 | 2 | `views/person/_photo.html.erb:4` |
| `stimulus:asset-form` | stimulus-controller | 1 | 1 | 2 | `views/asset_management/records/_form.html.erb:4` |
| `stimulus:dropdown-fit` | stimulus-controller | 1 | 1 | 2 | `views/common/_dropdown_scroll_list.html.erb:2` |
| `stimulus:link-options` | stimulus-controller | 1 | 1 | 2 | `views/scheduling/slots/_form.html.erb:3` |
| `class:divider` | daisyui-class | 1 | 2 | 1 | `views/sessions/_passkey_door.html.erb:11` `views/sessions/_passkey_door.html.erb:11` |
| `oneoff:avatar-photo` | one-off-markup, shared-helper | 2 | 6 | 1 | `views/hq/shared/_summary_column.html.erb:8` `views/profile/_bmid.html.erb:10` |
| `oneoff:hidden-beacon` | one-off-markup | 2 | 2 | 1 | `views/hq/shift_manage/_signal.html.erb:5` `views/hq/site_registration/_advance_signal.html.erb:5` |
| `oneoff:status-badges` | area-helper | 2 | 5 | 1 | `views/admin/sms_management/index.html.erb:30-80` `helpers/admin/sms_management_helper.rb:57-63` |
| `oneoff:status-medallion-block` | one-off-markup | 2 | 14 | 1 | `views/me/vehicles_dashboard/_mvr_status_approved.html.erb:1` `views/me/vehicles_dashboard/_pvr_status_agreement_needed.html.erb:2` |
| `stimulus:checkbox-select-all` | stimulus-controller | 2 | 2 | 1 | `helpers/ui_components/bulk_select_helper.rb:14` `views/ticketing/trs_export/index.html.erb:89` |
| `<canvas>` | raw-html | 1 | 1 | 1 | `views/profile_photos/new.html.erb:288` |
| `<video>` | raw-html | 1 | 1 | 1 | `views/profile_photos/new.html.erb:279` |
| `clipboard_button` | shared-helper | 1 | 2 | 1 | `views/person/_contact_details.html.erb:40` |
| `css:acceptance-alert` | custom-css(acceptance-sheet.css) | 1 | 1 | 1 | `views/mentoring/alpha_acceptance_sheets/print_sheets.html.erb:235` |
| `css:acceptance-band` | custom-css(acceptance-sheet.css) | 1 | 5 | 1 | `views/mentoring/alpha_acceptance_sheets/print_sheets.html.erb:38` |
| `css:acceptance-band-note` | custom-css(acceptance-sheet.css) | 1 | 1 | 1 | `views/mentoring/alpha_acceptance_sheets/print_sheets.html.erb:40` |
| `css:acceptance-blank` | custom-css(acceptance-sheet.css) | 1 | 6 | 1 | `views/mentoring/alpha_acceptance_sheets/print_sheets.html.erb:84` |
| `css:acceptance-columns` | custom-css(acceptance-sheet.css) | 1 | 1 | 1 | `views/mentoring/alpha_acceptance_sheets/print_sheets.html.erb:43` |
| `css:acceptance-details` | custom-css(acceptance-sheet.css) | 1 | 1 | 1 | `views/mentoring/alpha_acceptance_sheets/print_sheets.html.erb:44` |
| `css:acceptance-fka` | custom-css(acceptance-sheet.css) | 1 | 1 | 1 | `views/mentoring/alpha_acceptance_sheets/print_sheets.html.erb:61` |
| `css:acceptance-handle` | custom-css(acceptance-sheet.css) | 1 | 1 | 1 | `views/mentoring/alpha_acceptance_sheets/print_sheets.html.erb:48` |
| `css:acceptance-headshot` | custom-css(acceptance-sheet.css) | 1 | 1 | 1 | `views/mentoring/alpha_acceptance_sheets/print_sheets.html.erb:108` |
| `css:acceptance-label` | custom-css(acceptance-sheet.css) | 1 | 10 | 1 | `views/mentoring/alpha_acceptance_sheets/print_sheets.html.erb:46` |
| `css:acceptance-label-auto` | custom-css(acceptance-sheet.css) | 1 | 1 | 1 | `views/mentoring/alpha_acceptance_sheets/print_sheets.html.erb:196` |
| `css:acceptance-legend` | custom-css(acceptance-sheet.css) | 1 | 1 | 1 | `views/mentoring/alpha_acceptance_sheets/print_sheets.html.erb:186` |
| `css:acceptance-line` | custom-css(acceptance-sheet.css) | 1 | 10 | 1 | `views/mentoring/alpha_acceptance_sheets/print_sheets.html.erb:45` |
| `css:acceptance-logo` | custom-css(acceptance-sheet.css) | 1 | 1 | 1 | `views/mentoring/alpha_acceptance_sheets/print_sheets.html.erb:31` |
| `css:acceptance-masthead` | custom-css(acceptance-sheet.css) | 1 | 1 | 1 | `views/mentoring/alpha_acceptance_sheets/print_sheets.html.erb:30` |
| `css:acceptance-no-photo` | custom-css(acceptance-sheet.css) | 1 | 1 | 1 | `views/mentoring/alpha_acceptance_sheets/print_sheets.html.erb:112` |
| `css:acceptance-note-line` | custom-css(acceptance-sheet.css) | 1 | 4 | 1 | `views/mentoring/alpha_acceptance_sheets/print_sheets.html.erb:216` |
| `css:acceptance-notes` | custom-css(acceptance-sheet.css) | 1 | 3 | 1 | `views/mentoring/alpha_acceptance_sheets/print_sheets.html.erb:209` |
| `css:acceptance-pair` | custom-css(acceptance-sheet.css) | 1 | 2 | 1 | `views/mentoring/alpha_acceptance_sheets/print_sheets.html.erb:122` |
| `css:acceptance-photo` | custom-css(acceptance-sheet.css) | 1 | 1 | 1 | `views/mentoring/alpha_acceptance_sheets/print_sheets.html.erb:107` |
| `css:acceptance-rank-legend` | custom-css(acceptance-sheet.css) | 1 | 1 | 1 | `views/mentoring/alpha_acceptance_sheets/print_sheets.html.erb:203` |
| `css:acceptance-sheet` | custom-css(acceptance-sheet.css) | 1 | 1 | 1 | `views/mentoring/alpha_acceptance_sheets/print_sheets.html.erb:29` |
| `css:acceptance-signoff` | custom-css(acceptance-sheet.css) | 1 | 1 | 1 | `views/mentoring/alpha_acceptance_sheets/print_sheets.html.erb:165` |
| `css:acceptance-signoff-number` | custom-css(acceptance-sheet.css) | 1 | 1 | 1 | `views/mentoring/alpha_acceptance_sheets/print_sheets.html.erb:178` |
| `css:acceptance-signoff-rule` | custom-css(acceptance-sheet.css) | 1 | 4 | 1 | `views/mentoring/alpha_acceptance_sheets/print_sheets.html.erb:179` |
| `css:acceptance-title` | custom-css(acceptance-sheet.css) | 1 | 1 | 1 | `views/mentoring/alpha_acceptance_sheets/print_sheets.html.erb:32` |
| `css:acceptance-training-entry` | custom-css(acceptance-sheet.css) | 1 | 1 | 1 | `views/mentoring/alpha_acceptance_sheets/print_sheets.html.erb:228` |
| `css:acceptance-value` | custom-css(acceptance-sheet.css) | 1 | 8 | 1 | `views/mentoring/alpha_acceptance_sheets/print_sheets.html.erb:47` |
| `css:alpha-apparel-row` | custom-css(alpha-sheets.css) | 1 | 1 | 1 | `views/mentoring/alpha_schedule/apparel.html.erb:48` |
| `css:alpha-info-gender` | custom-css(alpha-sheets.css) | 1 | 1 | 1 | `views/mentoring/alpha_schedule/info_sheet.html.erb:67` |
| `css:alpha-info-handle` | custom-css(alpha-sheets.css) | 1 | 1 | 1 | `views/mentoring/alpha_schedule/info_sheet.html.erb:63` |
| `css:alpha-info-home` | custom-css(alpha-sheets.css) | 1 | 1 | 1 | `views/mentoring/alpha_schedule/info_sheet.html.erb:80` |
| `css:alpha-info-table` | custom-css(alpha-sheets.css) | 1 | 1 | 1 | `views/mentoring/alpha_schedule/info_sheet.html.erb:44` |
| `css:alpha-info-title` | custom-css(alpha-sheets.css) | 1 | 1 | 1 | `views/mentoring/alpha_schedule/info_sheet.html.erb:39` |
| `css:alpha-info-training` | custom-css(alpha-sheets.css) | 1 | 1 | 1 | `views/mentoring/alpha_schedule/info_sheet.html.erb:71` |
| `css:alpha-initial` | custom-css(alpha-sheets.css) | 1 | 2 | 1 | `views/mentoring/alpha_schedule/signup_sheet.html.erb:69` |
| `css:alpha-note-line` | custom-css(alpha-sheets.css) | 1 | 1 | 1 | `views/mentoring/alpha_schedule/info_sheet.html.erb:123` |
| `css:alpha-note-source` | custom-css(alpha-sheets.css) | 1 | 1 | 1 | `views/mentoring/alpha_schedule/info_sheet.html.erb:125` |
| `css:alpha-pod-band` | custom-css(alpha-sheets.css) | 1 | 1 | 1 | `views/mentoring/alpha_pods/print_sheet.html.erb:74` |
| `css:alpha-pod-empty` | custom-css(alpha-sheets.css) | 1 | 1 | 1 | `views/mentoring/alpha_pods/print_sheet.html.erb:85` |
| `css:alpha-pod-table` | custom-css(alpha-sheets.css) | 1 | 1 | 1 | `views/mentoring/alpha_pods/print_sheet.html.erb:64` |
| `css:alpha-separator` | custom-css(alpha-sheets.css) | 1 | 1 | 1 | `views/mentoring/alpha_schedule/info_sheet.html.erb:135` |
| `css:alpha-sheet--wide` | custom-css(alpha-sheets.css) | 1 | 1 | 1 | `views/mentoring/alpha_pods/print_sheet.html.erb:41` |
| `css:alpha-total-count` | custom-css(alpha-sheets.css) | 1 | 2 | 1 | `views/mentoring/alpha_schedule/apparel.html.erb:80` |
| `css:alpha-totals` | custom-css(alpha-sheets.css) | 1 | 1 | 1 | `views/mentoring/alpha_schedule/apparel.html.erb:72` |
| `css:alpha-write-row` | custom-css(alpha-sheets.css) | 1 | 6 | 1 | `views/mentoring/alpha_schedule/signup_sheet.html.erb:46` |
| `css:hq-forecast-pane` | custom-css(hq-forecast.css) | 1 | 1 | 1 | `views/scheduling/hq_forecast/_periods_table.html.erb:4` |
| `css:hq-forecast-table` | custom-css(hq-forecast.css) | 1 | 1 | 1 | `views/scheduling/hq_forecast/_periods_table.html.erb:4` |
| `css:login-backdrop` | custom-css(login.css) | 1 | 1 | 1 | `views/sessions/new.html.erb:5` |
| `css:login-columns` | custom-css(login.css) | 1 | 1 | 1 | `views/sessions/new.html.erb:9` |
| `css:login-door-lead` | custom-css(login.css) | 1 | 4 | 1 | `views/sessions/new.html.erb:51` |
| `css:login-doors` | custom-css(login.css) | 1 | 1 | 1 | `views/sessions/new.html.erb:44` |
| `css:login-doors-list` | custom-css(login.css) | 1 | 1 | 1 | `views/sessions/new.html.erb:46` |
| `css:login-doors-title` | custom-css(login.css) | 1 | 1 | 1 | `views/sessions/new.html.erb:45` |
| `css:login-input--reveal` | custom-css(login.css) | 1 | 1 | 1 | `views/sessions/_password_form.html.erb:45` |
| `css:login-label-link` | custom-css(login.css) | 1 | 1 | 1 | `views/sessions/_password_form.html.erb:30` |
| `css:login-label-row` | custom-css(login.css) | 1 | 1 | 1 | `views/sessions/_password_form.html.erb:28` |
| `css:login-reveal` | custom-css(login.css) | 1 | 1 | 1 | `views/sessions/_password_form.html.erb:54` |
| `css:login-status` | custom-css(login.css) | 1 | 1 | 1 | `views/sessions/new.html.erb:17` |
| `css:login-tagline` | custom-css(login.css) | 1 | 1 | 1 | `views/sessions/new.html.erb:13` |
| `css:login-title` | custom-css(login.css) | 1 | 1 | 1 | `views/sessions/new.html.erb:12` |
| `css:photo-board` | custom-css(photo-board.css) | 1 | 1 | 1 | `views/shift_operations/roc_photo_board/index.html.erb:7` |
| `css:report-band` | custom-css(trainers-report.css) | 1 | 1 | 1 | `views/training/sessions/trainers_report.html.erb:102` |
| `css:report-callout` | custom-css(trainers-report.css) | 1 | 1 | 1 | `views/training/sessions/trainers_report.html.erb:79` |
| `css:report-callsign` | custom-css(trainers-report.css) | 1 | 1 | 1 | `views/training/sessions/trainers_report.html.erb:120` |
| `css:report-checkbox` | custom-css(trainers-report.css) | 1 | 1 | 1 | `views/training/sessions/trainers_report.html.erb:119` |
| `css:report-chip` | custom-css(trainers-report.css) | 1 | 1 | 1 | `views/training/sessions/trainers_report.html.erb:135` |
| `css:report-detail-row` | custom-css(trainers-report.css) | 1 | 1 | 1 | `views/training/sessions/trainers_report.html.erb:139` |
| `css:report-doc-label` | custom-css(trainers-report.css) | 1 | 1 | 1 | `views/training/sessions/trainers_report.html.erb:39` |
| `css:report-empty-row` | custom-css(trainers-report.css) | 1 | 1 | 1 | `views/training/sessions/trainers_report.html.erb:109` |
| `css:report-fka` | custom-css(trainers-report.css) | 1 | 1 | 1 | `views/training/sessions/trainers_report.html.erb:143` |
| `css:report-full-day` | custom-css(trainers-report.css) | 1 | 1 | 1 | `views/training/sessions/trainers_report.html.erb:132` |
| `css:report-legend` | custom-css(trainers-report.css) | 1 | 1 | 1 | `views/training/sessions/trainers_report.html.erb:159` |
| `css:report-legend-cols` | custom-css(trainers-report.css) | 1 | 1 | 1 | `views/training/sessions/trainers_report.html.erb:161` |
| `css:report-legend-title` | custom-css(trainers-report.css) | 1 | 1 | 1 | `views/training/sessions/trainers_report.html.erb:160` |
| `css:report-masthead` | custom-css(trainers-report.css) | 1 | 1 | 1 | `views/training/sessions/trainers_report.html.erb:38` |
| `css:report-num` | custom-css(trainers-report.css) | 1 | 4 | 1 | `views/training/sessions/trainers_report.html.erb:93` |
| `css:report-pass` | custom-css(trainers-report.css) | 1 | 2 | 1 | `views/training/sessions/trainers_report.html.erb:94` |
| `css:report-session` | custom-css(trainers-report.css) | 1 | 1 | 1 | `views/training/sessions/trainers_report.html.erb:41` |
| `css:report-session-row` | custom-css(trainers-report.css) | 1 | 1 | 1 | `views/training/sessions/trainers_report.html.erb:40` |
| `css:report-stat` | custom-css(trainers-report.css) | 1 | 4 | 1 | `views/training/sessions/trainers_report.html.erb:55` |
| `css:report-stat-label` | custom-css(trainers-report.css) | 1 | 4 | 1 | `views/training/sessions/trainers_report.html.erb:55` |
| `css:report-stat-max` | custom-css(trainers-report.css) | 1 | 1 | 1 | `views/training/sessions/trainers_report.html.erb:55` |
| `css:report-stats` | custom-css(trainers-report.css) | 1 | 1 | 1 | `views/training/sessions/trainers_report.html.erb:54` |
| `css:report-status` | custom-css(trainers-report.css) | 1 | 1 | 1 | `views/training/sessions/trainers_report.html.erb:148` |
| `css:report-subline` | custom-css(trainers-report.css) | 1 | 1 | 1 | `views/training/sessions/trainers_report.html.erb:46` |
| `css:report-trainers` | custom-css(trainers-report.css) | 1 | 2 | 1 | `views/training/sessions/trainers_report.html.erb:65` |
| `css:report-when` | custom-css(trainers-report.css) | 1 | 1 | 1 | `views/training/sessions/trainers_report.html.erb:42` |
| `css:report-years` | custom-css(trainers-report.css) | 1 | 1 | 1 | `views/training/sessions/trainers_report.html.erb:121` |
| `css:report-years-pill` | custom-css(trainers-report.css) | 1 | 2 | 1 | `views/training/sessions/trainers_report.html.erb:123` |
| `css:sandman-qualified-pane` | custom-css(sandman-qualified.css) | 1 | 1 | 1 | `views/scheduling/sandman_qualified/index.html.erb:109` |
| `css:sheet-band` | custom-css(shift-lead-sheet.css) | 1 | 3 | 1 | `views/scheduling/shift_lead/print_sheet.html.erb:103` |
| `css:sheet-callsign` | custom-css(shift-lead-sheet.css) | 1 | 1 | 1 | `views/scheduling/shift_lead/print_sheet.html.erb:213` |
| `css:sheet-chip` | custom-css(shift-lead-sheet.css) | 1 | 3 | 1 | `views/scheduling/shift_lead/print_sheet.html.erb:215` |
| `css:sheet-col-callsign` | custom-css(shift-lead-sheet.css) | 1 | 1 | 1 | `views/scheduling/shift_lead/print_sheet.html.erb:173` |
| `css:sheet-col-count` | custom-css(shift-lead-sheet.css) | 1 | 1 | 1 | `views/scheduling/shift_lead/print_sheet.html.erb:112` |
| `css:sheet-col-flag` | custom-css(shift-lead-sheet.css) | 1 | 2 | 1 | `views/scheduling/shift_lead/print_sheet.html.erb:175` |
| `css:sheet-col-gender` | custom-css(shift-lead-sheet.css) | 1 | 1 | 1 | `views/scheduling/shift_lead/print_sheet.html.erb:174` |
| `css:sheet-col-position` | custom-css(shift-lead-sheet.css) | 1 | 1 | 1 | `views/scheduling/shift_lead/print_sheet.html.erb:173` |
| `css:sheet-col-pronouns` | custom-css(shift-lead-sheet.css) | 1 | 1 | 1 | `views/scheduling/shift_lead/print_sheet.html.erb:174` |
| `css:sheet-col-shortfall` | custom-css(shift-lead-sheet.css) | 1 | 1 | 1 | `views/scheduling/shift_lead/print_sheet.html.erb:111` |
| `css:sheet-col-time` | custom-css(shift-lead-sheet.css) | 1 | 1 | 1 | `views/scheduling/shift_lead/print_sheet.html.erb:177` |
| `css:sheet-col-window` | custom-css(shift-lead-sheet.css) | 1 | 1 | 1 | `views/scheduling/shift_lead/print_sheet.html.erb:111` |
| `css:sheet-col-years` | custom-css(shift-lead-sheet.css) | 1 | 1 | 1 | `views/scheduling/shift_lead/print_sheet.html.erb:175` |
| `css:sheet-ctr` | custom-css(shift-lead-sheet.css) | 1 | 6 | 1 | `views/scheduling/shift_lead/print_sheet.html.erb:192` |
| `css:sheet-doc-label` | custom-css(shift-lead-sheet.css) | 1 | 1 | 1 | `views/scheduling/shift_lead/print_sheet.html.erb:69` |
| `css:sheet-filters` | custom-css(shift-lead-sheet.css) | 1 | 1 | 1 | `views/scheduling/shift_lead/print_sheet.html.erb:86` |
| `css:sheet-headline` | custom-css(shift-lead-sheet.css) | 1 | 1 | 1 | `views/scheduling/shift_lead/print_sheet.html.erb:74` |
| `css:sheet-legend` | custom-css(shift-lead-sheet.css) | 1 | 1 | 1 | `views/scheduling/shift_lead/print_sheet.html.erb:251` |
| `css:sheet-legend-cols` | custom-css(shift-lead-sheet.css) | 1 | 1 | 1 | `views/scheduling/shift_lead/print_sheet.html.erb:253` |
| `css:sheet-legend-title` | custom-css(shift-lead-sheet.css) | 1 | 1 | 1 | `views/scheduling/shift_lead/print_sheet.html.erb:252` |
| `css:sheet-masthead` | custom-css(shift-lead-sheet.css) | 1 | 1 | 1 | `views/scheduling/shift_lead/print_sheet.html.erb:68` |
| `css:sheet-mode` | custom-css(shift-lead-sheet.css) | 1 | 1 | 1 | `views/scheduling/shift_lead/print_sheet.html.erb:76` |
| `css:sheet-none` | custom-css(shift-lead-sheet.css) | 1 | 1 | 1 | `views/scheduling/shift_lead/print_sheet.html.erb:130` |
| `css:sheet-num` | custom-css(shift-lead-sheet.css) | 1 | 12 | 1 | `views/scheduling/shift_lead/print_sheet.html.erb:118` |
| `css:sheet-running-head` | custom-css(shift-lead-sheet.css) | 1 | 1 | 1 | `views/scheduling/shift_lead/print_sheet.html.erb:185` |
| `css:sheet-shift` | custom-css(shift-lead-sheet.css) | 1 | 1 | 1 | `views/scheduling/shift_lead/print_sheet.html.erb:75` |
| `css:sheet-stat` | custom-css(shift-lead-sheet.css) | 1 | 1 | 1 | `views/scheduling/shift_lead/print_sheet.html.erb:94` |
| `css:sheet-stat-label` | custom-css(shift-lead-sheet.css) | 1 | 1 | 1 | `views/scheduling/shift_lead/print_sheet.html.erb:96` |
| `css:sheet-stats` | custom-css(shift-lead-sheet.css) | 1 | 1 | 1 | `views/scheduling/shift_lead/print_sheet.html.erb:92` |
| `css:sheet-subline` | custom-css(shift-lead-sheet.css) | 1 | 1 | 1 | `views/scheduling/shift_lead/print_sheet.html.erb:78` |
| `css:shift-lead-sheet` | custom-css(shift-lead-sheet.css) | 1 | 1 | 1 | `views/scheduling/shift_lead/print_sheet.html.erb:67` |
| `css:signup-callsign` | custom-css(signup-sheet.css) | 1 | 2 | 1 | `views/training/sessions/signup_sheet.html.erb:68` |
| `css:signup-contact-row` | custom-css(signup-sheet.css) | 1 | 1 | 1 | `views/training/sessions/signup_sheet.html.erb:115` |
| `css:signup-doc-label` | custom-css(signup-sheet.css) | 1 | 2 | 1 | `views/training/sessions/signup_sheet.html.erb:38` |
| `css:signup-fill` | custom-css(signup-sheet.css) | 1 | 7 | 1 | `views/training/sessions/signup_sheet.html.erb:73` |
| `css:signup-id-row` | custom-css(signup-sheet.css) | 1 | 2 | 1 | `views/training/sessions/signup_sheet.html.erb:66` |
| `css:signup-masthead` | custom-css(signup-sheet.css) | 1 | 2 | 1 | `views/training/sessions/signup_sheet.html.erb:37` |
| `css:signup-name` | custom-css(signup-sheet.css) | 1 | 2 | 1 | `views/training/sessions/signup_sheet.html.erb:69` |
| `css:signup-notes-cell` | custom-css(signup-sheet.css) | 1 | 2 | 1 | `views/training/sessions/signup_sheet.html.erb:73` |
| `css:signup-num` | custom-css(signup-sheet.css) | 1 | 2 | 1 | `views/training/sessions/signup_sheet.html.erb:67` |
| `css:signup-running-head` | custom-css(shift-lead-sheet.css) | 1 | 2 | 1 | `views/training/sessions/signup_sheet.html.erb:54` |
| `css:signup-session` | custom-css(signup-sheet.css) | 1 | 2 | 1 | `views/training/sessions/signup_sheet.html.erb:40` |
| `css:signup-sheet` | custom-css(signup-sheet.css) | 1 | 2 | 1 | `views/training/sessions/signup_sheet.html.erb:36` |
| `css:signup-sig` | custom-css(signup-sheet.css) | 1 | 2 | 1 | `views/training/sessions/signup_sheet.html.erb:70` |
| `css:signup-subline` | custom-css(signup-sheet.css) | 1 | 2 | 1 | `views/training/sessions/signup_sheet.html.erb:48` |
| `css:signup-when` | custom-css(signup-sheet.css) | 1 | 2 | 1 | `views/training/sessions/signup_sheet.html.erb:41` |
| `css:sticky-progress-container` | custom-css(progress.css) | 1 | 1 | 1 | `views/vc/applications/_action_bar.html.erb:2` |
| `css:trainers-report` | custom-css(shift-lead-sheet.css) | 1 | 1 | 1 | `views/training/sessions/trainers_report.html.erb:37` |
| `css:vc-stage` | custom-css(vc-applications.css) | 1 | 1 | 1 | `views/vc/applications/_stage_card.html.erb:10` |
| `css:vc-stage-body` | custom-css(vc-applications.css) | 1 | 1 | 1 | `views/vc/applications/_stage_card.html.erb:11` |
| `css:vc-stage-chevron` | custom-css(vc-applications.css) | 1 | 1 | 1 | `views/vc/applications/_stage_card.html.erb:7` |
| `css:vc-stage-summary` | custom-css(vc-applications.css) | 1 | 1 | 1 | `views/vc/applications/_stage_card.html.erb:11` |
| `hero_panel description:` | shared-helper | 1 | 5 | 1 | `views/shift_operations/payroll_missing_id/index.html.erb:8` |
| `hero_panel progress` | shared-helper | 1 | 1 | 1 | `views/communication/rbs_broadcasts/new.html.erb:15` |
| `hero_panel.progress` | shared-helper | 1 | 5 | 1 | `views/training/online_course_progress/index.html.erb:13` |
| `image_tag` | rails-helper | 1 | 3 | 1 | `views/me/surveys/_trainer_photo.html.erb:5` |
| `membership_status_cell` | area-helper | 1 | 6 | 1 | `views/person/membership_history/show.html.erb:50` |
| `oneoff:badge-or-plain-text` | area-helper | 1 | 1 | 1 | `views/admin/rbs_alerts/_group.html.erb:25-26` |
| `oneoff:badge-vs-plain-text` | one-off-markup | 1 | 5 | 1 | `views/communication/surveys/_group.html.erb:42` |
| `oneoff:badge-with-pluralized-text` | shared-helper | 1 | 1 | 1 | `views/mentoring/surveys/index.html.erb:25` |
| `oneoff:badge-wrap` | one-off-markup | 1 | 1 | 1 | `views/mentoring/shift_report/_people_table.html.erb:28-32` |
| `oneoff:conditional-class` | one-off-markup | 1 | 1 | 1 | `views/mentoring/alpha_schedule/apparel.html.erb:17` |
| `oneoff:conditional-reveal` | one-off-markup | 1 | 1 | 1 | `views/bmid/titles/_cell.html.erb:15-19` |
| `oneoff:count-badges` | shared-helper | 1 | 5 | 1 | `views/training/sessions/graduations/_dialog.html.erb:17` |
| `oneoff:count-with-button` | one-off-markup | 1 | 5 | 1 | `views/person/timesheets/index.html.erb:157` |
| `oneoff:countdown-box` | one-off-markup | 1 | 7 | 1 | `views/me/vehicles_dashboard/_mvr_status_eligible.html.erb:5` |
| `oneoff:custom-chip` | one-off-markup | 1 | 2 | 1 | `views/hq/shift_manage/_todo_chip.html.erb:18-27` |
| `oneoff:custom-display-page` | custom-css | 1 | 5 | 1 | `views/shift_operations/roc_photo_board/index.html.erb:7` |
| `oneoff:custom-popover` | inline-style | 1 | 14 | 1 | `views/vc/spigot_flow_report/_callsign_cell.html.erb:4` |
| `oneoff:dash-stat-value` | hard-coded-value | 1 | 4 | 1 | `views/communication/rbs_history/show.html.erb:52` |
| `oneoff:decorative-backdrop` | custom-css | 1 | 1 | 1 | `views/sessions/new.html.erb:5` |
| `oneoff:div-card` | one-off-markup | 1 | 15 | 1 | `views/person/tickets_provisions/show.html.erb:21` |
| `oneoff:empty-branch` | one-off-markup | 1 | 2 | 1 | `views/dashboard_tasks/_online_course_needed.html.erb:5` |
| `oneoff:indentation-mismatch` | one-off-markup | 1 | 1 | 1 | `views/admin/action_logs/index.html.erb:15-97` |
| `oneoff:inline-flag-list` | one-off-markup | 1 | 1 | 1 | `views/mentoring/alpha_schedule/show.html.erb:79-88` |
| `oneoff:inline-icon-legend` | one-off-markup | 1 | 13 | 1 | `views/person/memberships/edit.html.erb:5` |
| `oneoff:inline-label-value` | one-off-markup | 1 | 7 | 1 | `views/person/timesheets/edit.html.erb:56` |
| `oneoff:inline-style-block` | inline-style | 1 | 83 | 1 | `views/profile_photos/crop.html.erb:98` |
| `oneoff:inline-width` | inline-style | 1 | 1 | 1 | `views/mentoring/alpha_pods/print_sheet.html.erb:68` |
| `oneoff:labelled-progress` | one-off-markup | 1 | 1 | 1 | `views/scheduling/event_stats/_share_bar.html.erb:15-25` |
| `oneoff:legend-extra` | custom-css | 1 | 1 | 1 | `views/bmid/manage/index.html.erb:108-114` |
| `oneoff:legend-grid` | one-off-markup | 1 | 1 | 1 | `views/ticketing/access_documents/_summary_legend.html.erb:13-48` |
| `oneoff:legend-in-callout` | shared-helper | 1 | 13 | 1 | `views/teams_positions/roster_management/show.html.erb:71` |
| `oneoff:muted-instruction-list` | one-off-markup | 1 | 2 | 1 | `views/profile/_languages.html.erb:7` |
| `oneoff:no-export` | not-handled | 1 | 1 | 1 | `views/timesheets/timesheet_totals_report/person.html.erb:30` |
| `oneoff:notice-slot` | one-off-markup | 1 | 1 | 1 | `views/vc/bpguid/_results.html.erb:3` |
| `oneoff:photo-placeholder` | one-off-markup | 1 | 1 | 1 | `views/mentoring/alpha_acceptance_sheets/print_sheets.html.erb:107-116` |
| `oneoff:plain-paragraph-link` | one-off-markup | 1 | 8 | 1 | `views/person/applications/index.html.erb:17` |
| `oneoff:print-checkbox` | custom-css | 1 | 1 | 1 | `views/training/sessions/trainers_report.html.erb:119` |
| `oneoff:print-stat-tiles` | custom-css | 1 | 8 | 1 | `views/training/sessions/trainers_report.html.erb:54` |
| `oneoff:progress-status-line` | one-off-markup | 1 | 11 | 1 | `views/me/agreements/index.html.erb:9` |
| `oneoff:quoted-note` | raw-html | 1 | 3 | 1 | `views/vc/applications/dialogs/note_delete.html.erb:8` |
| `oneoff:ranger-only-box` | one-off-markup | 1 | 5 | 1 | `views/me/announcements/index.html.erb:11` |
| `oneoff:section-badge-status-color` | shared-helper | 1 | 1 | 1 | `views/admin/jobs/index.html.erb:95-96` |
| `oneoff:section-badge-warning` | shared-helper | 1 | 1 | 1 | `views/admin/salesforce_query/index.html.erb:21-22` |
| `oneoff:stale-results-swap` | attribute | 1 | 9 | 1 | `views/vc/reserved_handles/upload.html.erb:14` |
| `oneoff:stat-box-as-status` | shared-helper | 1 | 5 | 1 | `views/vc/reserved_handles/edit.html.erb:7` |
| `oneoff:stat-tiles-as-filter-links` | area-helper | 1 | 1 | 1 | `views/admin/jobs/index.html.erb:7-11` |
| `oneoff:sticky-action-bar` | custom-css | 1 | 5 | 1 | `views/vc/applications/_action_bar.html.erb:2` |
| `oneoff:sticky-checklist-panel` | one-off-markup | 1 | 1 | 1 | `views/hq/shift_manage/_todo_list.html.erb:23` |
| `oneoff:stream-target-wrapper` | one-off-markup | 1 | 2 | 1 | `views/training/sessions/show.html.erb:16` |
| `oneoff:strftime-date` | hard-coded-value | 1 | 1 | 1 | `views/dashboard_tasks/_attend_cheetah_cub_shift_pending.html.erb:5` |
| `oneoff:text-marker` | hard-coded-value | 1 | 1 | 1 | `views/mentoring/alpha_pods/print_sheet.html.erb:92-94` |
| `oneoff:text-stat-value` | shared-helper | 1 | 2 | 1 | `views/communication/rbs_broadcasts/_simple_fields.html.erb:9` |
| `oneoff:value-state-badges` | shared-helper | 1 | 1 | 1 | `views/admin/settings/index.html.erb:43-48` |
| `permission_status` | area-helper | 1 | 2 | 1 | `views/person/_permissions.html.erb:29` |
| `qualification_section` | shared-helper | 1 | 4 | 1 | `views/common/qualifications/index.html.erb:62` |
| `schedule_log_override_badge` | area-helper | 1 | 1 | 1 | `views/person/scheduling/_log_changes.html.erb:21` |
| `stimulus:bookmark` | stimulus-controller | 1 | 1 | 1 | `views/bookmarks/show.html.erb:16` |
| `stimulus:bulk-edit` | stimulus-controller | 1 | 1 | 1 | `views/bmid/manage/_edit_grid.html.erb:25` |
| `stimulus:hq-shift` | stimulus-controller | 1 | 1 | 1 | `views/hq/shift_manage/index.html.erb:20` |
| `stimulus:hq-wizard` | stimulus-controller | 1 | 1 | 1 | `views/hq/site_registration/show.html.erb:58` |
| `stimulus:mark-result` | stimulus-controller | 1 | 1 | 1 | `views/mentoring/alpha_mentor_assignments/index.html.erb:137` |
| `stimulus:membership-editor` | stimulus-controller | 1 | 1 | 1 | `views/person/memberships/edit.html.erb:26` |
| `stimulus:onboarding` | stimulus-controller | 1 | 1 | 1 | `views/me/dashboard/_onboarding.html.erb:7` |
| `stimulus:password-reveal` | stimulus-controller | 1 | 1 | 1 | `views/sessions/_password_form.html.erb:33` |
| `stimulus:permission-editor` | stimulus-controller | 1 | 1 | 1 | `views/person/permissions/edit.html.erb:15` |
| `stimulus:photo-board` | stimulus-controller | 1 | 1 | 1 | `views/shift_operations/roc_photo_board/index.html.erb:8` |
| `stimulus:photo-cropper` | stimulus-controller | 1 | 1 | 1 | `views/profile_photos/crop.html.erb:67` |
| `stimulus:pod-people` | stimulus-controller | 1 | 1 | 1 | `views/shift_operations/cruise_direction/_pod.html.erb:57` |
| `stimulus:sortable` | stimulus-controller | 1 | 1 | 1 | `views/shift_operations/cruise_direction/_board.html.erb:25` |
| `stimulus:stale-results` | stimulus-controller | 1 | 1 | 1 | `views/vc/reserved_handles/upload.html.erb:14` |
| `stimulus:status-warning` | stimulus-controller | 1 | 1 | 1 | `views/person/statuses/edit.html.erb:15` |
| `stimulus:table-sort` | stimulus-controller | 1 | 1 | 1 | `views/admin/salesforce_query/index.html.erb:25` |
| `ui_badge as note` | shared-helper | 1 | 1 | 1 | `views/ticketing/maintenance/index.html.erb:35` |
| `ui_badge in place of control` | shared-helper | 1 | 4 | 1 | `views/alerts/_alert_group.html.erb:47` |
| `ui_badge size xs` | shared-helper | 1 | 1 | 1 | `views/bmid/titles/set.html.erb:55` |
| `ui_label_value label_width` | shared-helper | 1 | 1 | 1 | `views/communication/surveys/show.html.erb:30` |
| `ui_section badge + action partial` | shared-helper | 1 | 4 | 1 | `views/communication/surveys/_group.html.erb:4` |
| `oneoff:static-error-template` | inline-style | 5 | 70 | 0 | `public/404.html:10` `public/400.html:10` `public/422.html:10` |
| `stimulus:local-time` | stimulus-controller | 4 | 4 | 0 | `views/layouts/application.html.erb:58` `views/layouts/bookmark.html.erb:36` `views/layouts/photo_board.html.erb:35` |
| `class:tooltip` | daisyui-class | 2 | 4 | 0 | `helpers/scheduling/hq_forecast_helper.rb:271` `helpers/scheduling/position_credits_helper.rb:87` `helpers/scheduling/position_credits_helper.rb:86-97` |
| `oneoff:status-badge-map` | area-helper | 3 | 5 | 0 | `helpers/admin/jobs_helper.rb:7-20` `helpers/admin/rbs_alerts_helper.rb:10-16` `helpers/admin/request_logs_helper.rb:20-25` |
| `severity_style` | shared-helper | 3 | 3 | 0 | `helpers/scheduling/shift_signups_helper.rb:28` `helpers/severity_style_helper.rb:20` `helpers/shift_operations/mass_signout_helper.rb:31` |
| `oneoff:fixture-markup` | one-off-markup | 2 | 15 | 0 | `views/test_harness/autocomplete_fixture.html.erb:10` `views/test_harness/search_bar_fixture.html.erb:10` |
| `oneoff:kbd-chip` | one-off-markup | 2 | 11 | 0 | `views/application/_top_menu.html.erb:48` `views/application/_search_bar_placeholder.html.erb:63` |
| `stimulus:theme` | stimulus-controller | 2 | 2 | 0 | `views/application/_public_menu.html.erb:7` `views/layouts/bookmark.html.erb:36` |
| `class:indicator` | daisyui-class | 1 | 2 | 0 | `views/application/_navbar_messages.html.erb:14` |
| `css:ct` | custom-css(credit-chart.css) | 1 | 1 | 0 | `helpers/scheduling/position_credits_helper.rb:32` |
| `css:ct-axis-day` | custom-css(credit-chart.css) | 1 | 1 | 0 | `helpers/scheduling/position_credits_helper.rb:111` |
| `css:ct-axis-month` | custom-css(credit-chart.css) | 1 | 1 | 0 | `helpers/scheduling/position_credits_helper.rb:118` |
| `css:ct-layer` | custom-css(credit-chart.css) | 1 | 1 | 0 | `helpers/scheduling/position_credits_helper.rb:84` |
| `css:ct-seg` | custom-css(credit-chart.css) | 1 | 1 | 0 | `helpers/scheduling/position_credits_helper.rb:87` |
| `css:ct-swatch` | custom-css(credit-chart.css) | 1 | 1 | 0 | `helpers/scheduling/position_credits_helper.rb:59` |
| `css:ct-tick` | custom-css(credit-chart.css) | 1 | 1 | 0 | `helpers/scheduling/position_credits_helper.rb:69` |
| `css:hq-gantt` | custom-css(hq-forecast.css) | 1 | 1 | 0 | `helpers/scheduling/hq_forecast_helper.rb:85` |
| `css:hq-gantt-bar` | custom-css(hq-forecast.css) | 1 | 1 | 0 | `helpers/scheduling/hq_forecast_helper.rb:226` |
| `css:hq-gantt-bar-text` | custom-css(hq-forecast.css) | 1 | 1 | 0 | `helpers/scheduling/hq_forecast_helper.rb:225` |
| `css:hq-gantt-chart` | custom-css(hq-forecast.css) | 1 | 1 | 0 | `helpers/scheduling/hq_forecast_helper.rb:91` |
| `css:hq-gantt-fill` | custom-css(hq-forecast.css) | 1 | 1 | 0 | `helpers/scheduling/hq_forecast_helper.rb:187` |
| `css:hq-gantt-hit` | custom-css(hq-forecast.css) | 1 | 1 | 0 | `helpers/scheduling/hq_forecast_helper.rb:234` |
| `css:hq-gantt-lane` | custom-css(hq-forecast.css) | 1 | 1 | 0 | `helpers/scheduling/hq_forecast_helper.rb:158` |
| `css:hq-gantt-mark` | custom-css(hq-forecast.css) | 1 | 1 | 0 | `helpers/scheduling/hq_forecast_helper.rb:271` |
| `css:hq-gantt-swatch` | custom-css(hq-forecast.css) | 1 | 1 | 0 | `helpers/scheduling/hq_forecast_helper.rb:308` |
| `css:hq-shell` | custom-css(hq-window.css) | 1 | 1 | 0 | `views/hq/shared/_shell.html.erb:11` |
| `css:hq-shell-content` | custom-css(hq-window.css) | 1 | 1 | 0 | `views/hq/shared/_shell.html.erb:16` |
| `css:hq-summary` | custom-css(hq-window.css) | 1 | 1 | 0 | `views/hq/shared/_summary_column.html.erb:6` |
| `css:login-column` | custom-css(login.css) | 1 | 1 | 0 | `views/layouts/sessions.html.erb:13` |
| `oneoff:avatar-fallback` | shared-helper | 1 | 4 | 0 | `views/application/_recipient_avatar.html.erb:2` |
| `oneoff:badge-chip-row` | area-helper | 1 | 7 | 0 | `helpers/training/mentoring_helper.rb:157` |
| `oneoff:badge-nowrap-wrapper` | area-helper | 1 | 1 | 0 | `helpers/training/all_notes_helper.rb:31` |
| `oneoff:check-chip` | custom-css | 1 | 19 | 0 | `helpers/vc/applications_helper.rb:67` |
| `oneoff:count-badge` | area-helper | 1 | 8 | 0 | `helpers/communication/rbs_helper.rb:254` |
| `oneoff:disabled-feature-text` | attribute | 1 | 3 | 0 | `views/vc/applications/_callsign_stage.html.erb:71` |
| `oneoff:flex-row-helper` | one-off-markup | 1 | 2 | 0 | `helpers/mentor_helper.rb:101` |
| `oneoff:gantt-chart` | custom-css | 1 | 4 | 0 | `helpers/scheduling/hq_forecast_helper.rb:76-96` |
| `oneoff:heartbeat-badge` | area-helper | 1 | 1 | 0 | `helpers/admin/jobs_helper.rb:165-176` |
| `oneoff:inline-theme-script` | raw-html | 1 | 7 | 0 | `views/layouts/application.html.erb:39` |
| `oneoff:mail-header-image` | inline-style | 1 | 7 | 0 | `helpers/mailer_helper.rb:7` |
| `oneoff:mail-important` | inline-style | 1 | 4 | 0 | `views/mail/layouts/mailer.html.erb:62` |
| `oneoff:page-width-wrapper` | custom-css | 1 | 4 | 0 | `views/hq/shared/_shell.html.erb:11` |
| `oneoff:print-mark-letters` | area-helper | 1 | 5 | 0 | `helpers/training/sessions_helper.rb:14` |
| `oneoff:prose-block` | one-off-markup | 1 | 2 | 0 | `views/common/scheduling/_missing_requirements.html.erb:3-17` |
| `oneoff:rating-meter` | shared-helper | 1 | 1 | 0 | `helpers/survey_report_helper.rb:116-127` |
| `oneoff:read-more-disclosure` | one-off-markup | 1 | 4 | 0 | `views/hq/shift_manage/_pog_guideline.html.erb:7` |
| `oneoff:read-more-toggle` | one-off-markup | 1 | 1 | 0 | `helpers/admin/action_logs_helper.rb:134-162` |
| `oneoff:reused-helper-internals` | area-helper | 1 | 4 | 0 | `helpers/person/permissions_helper.rb:41` |
| `oneoff:search-mark` | custom-css | 1 | 3 | 0 | `helpers/messages_helper.rb:18-19` |
| `oneoff:stacked-step-chart` | custom-css | 1 | 3 | 0 | `helpers/scheduling/position_credits_helper.rb:31-35` |
| `oneoff:status-tuple` | area-helper | 1 | 3 | 0 | `helpers/shift_operations/cruise_direction_helper.rb:53` |
| `oneoff:text-or-badge` | one-off-markup | 1 | 1 | 0 | `helpers/intake_helper.rb:208-215` |
| `oneoff:text-placeholders` | hard-coded-value | 1 | 4 | 0 | `helpers/admin/error_logs_helper.rb:11` |
| `oneoff:title-tooltip` | area-helper | 1 | 1 | 0 | `helpers/scheduling/slots_helper.rb:46` |
| `oneoff:toast-progress` | custom-css | 1 | 1 | 0 | `views/common/_toast.html.erb:12-14` |
| `oneoff:unlinked-stamp` | area-helper | 1 | 2 | 0 | `helpers/training/session_link_helper.rb:37` |
| `oneoff:year-strip` | area-helper | 1 | 11 | 0 | `helpers/people/retention_report_helper.rb:51` |
| `oneoff:yes-no-flag` | area-helper | 1 | 4 | 0 | `helpers/vehicles/paperwork_helper.rb:61` |
| `person_status_exception_badges` | shared-helper | 1 | 1 | 0 | `helpers/timesheets/timesheet_totals_report_helper.rb:12` |
| `stat-variants` | area-helper | 1 | 17 | 0 | `helpers/vc/applications_helper.rb:37` |
| `stimulus:#{form_data[:controller]}` | stimulus-controller | 1 | 1 | 0 | `views/register/_form.html.erb:25` |
| `stimulus:active-links` | stimulus-controller | 1 | 1 | 0 | `views/layouts/application.html.erb:58` |
| `stimulus:autofocus` | stimulus-controller | 1 | 1 | 0 | `views/common/messages/_find_recipient_form.html.erb:8` |
| `stimulus:callsign-chips` | stimulus-controller | 1 | 1 | 0 | `views/shared/_callsign_chips.html.erb:8` |
| `stimulus:country-state` | stimulus-controller | 1 | 1 | 0 | `helpers/country_state_helper.rb:383` |
| `stimulus:download-confirm` | stimulus-controller | 1 | 1 | 0 | `helpers/shift_operations/payroll_export_helper.rb:97` |
| `stimulus:input-counter` | stimulus-controller | 1 | 1 | 0 | `helpers/form_helper.rb:1214` |
| `stimulus:login-submit` | stimulus-controller | 1 | 1 | 0 | `views/layouts/sessions.html.erb:14` |
| `stimulus:mega-menu` | stimulus-controller | 1 | 4 | 0 | `views/application/_mega_menu.html.erb:22` |
| `stimulus:register-intent` | stimulus-controller | 1 | 1 | 0 | `views/register/_form.html.erb:25` |
| `stimulus:search-bar` | stimulus-controller | 1 | 4 | 0 | `views/application/_search_bar_placeholder.html.erb:38` |
| `stimulus:session-watch` | stimulus-controller | 1 | 1 | 0 | `views/layouts/application.html.erb:71` |
| `stimulus:sidebar` | stimulus-controller | 1 | 1 | 0 | `helpers/sidebar_helper.rb:71` |
| `stimulus:stream-nav` | stimulus-controller | 1 | 1 | 0 | `helpers/sidebar_helper.rb:71` |
| `stimulus:tabs` | stimulus-controller | 1 | 1 | 0 | `helpers/tabs_helper.rb:37` |
| `turbo_frame_tag` | rails-helper | 1 | 1 | 0 | `views/common/_turbo_partial_wrapper.html.erb:2-4` |
| `turbo_stream.replace` | rails-helper | 1 | 1 | 0 | `views/common/messages/_list_reply.turbo_stream.erb:13-16` |
| `ui_badge channel` | area-helper | 1 | 4 | 0 | `helpers/communication/rbs_helper.rb:199` |
| `ui_badge size sm` | shared-helper | 1 | 2 | 0 | `helpers/bmid/manage_helper.rb:378-386` |
| `ui_badge status` | area-helper | 1 | 13 | 0 | `helpers/communication/rbs_helper.rb:323` |

## Same pattern, more than one implementation (reported by the inventory agents)

- **buttons** (admin): Cancel in forms: cancel_link (documents, event_dates, oauth_clients, online_courses, permissions, rbs_alerts, shift_coverage _forms) ; cancel_button (settings/edit.html.erb:48), same helper by alias
- **buttons** (admin): Page-level "Add" button row spacing: button_row class: "my-4" (documents/index.html.erb:13; oauth_clients/index.html.erb:38; shift_coverage_groups/index.html.erb:22; shift_coverage_groups/show.html.erb:17) ; div.my-4 wrapping button_row (event_dates/index.html.erb:16; online_courses/index.html.erb:20; permissions/index.html.erb:23)
- **buttons** (common-a): Delete with confirmation: delete_button + confirm_modal (resource_documents/_form.html.erb:30, provisions/_form.html.erb:94) vs button_link :secondary with data confirm_modal(method: :delete) (missing_requests/_entry.html.erb:58)
- **buttons** (common-a): Buttons built with Rails button_to + button_classes (messages/_find_recipient_form.html.erb:31-36, messages/_messages_panel_header.html.erb:59-84) vs ButtonHelper button_link/button_action elsewhere in the same feature (messages/_compose_buttons.html.erb:8-12)
- **buttons** (common-a): Button groups: button_row (resource_documents/_form.html.erb:26, provisions/_form.html.erb:86, surveys/report.html.erb:17) vs div `flex flex-wrap gap-2` (messages/_compose_buttons.html.erb:5, unified_flagging/_note_buttons.html.erb:11) vs div `ms-auto flex flex-wrap gap-1` (messages/_messages_panel_header.html.erb:55) vs div `flex justify-end` (messages/_reply_form.html.erb:34) vs div `mt-4 mb-2` (missing_requests/index.html.erb:7)
- **buttons** (common-b): Remove from Schedule: icon trash (schedule/_signed_up_row:80) vs calendar-xmark (available_sign_ups/_slot:121); Hide Sign-Ups toggle label plain (schedule/_signed_up_row:69) vs with minus icon HTML (available_sign_ups/_slot:113)
- **buttons** (common-b): Action sets shown twice (phone button stack + desktop action_box rail): schedule/index.html.erb:52-100 & 139-197; timesheet/index.html.erb:50-84 & 116-163. Rail gap md:gap-6 (schedule/index:102) vs md:gap-4 (timesheet/index:87)
- **buttons** (communication): Row "edit" actions: edit_link (mail_templates/index.html.erb:43, surveys/_group.html.erb:50) vs button_link "Manage" :primary (surveys/index.html.erb:63)
- **buttons** (communication): Destructive actions: delete_button with confirm_modal (announcements/_announcement.html.erb:51, person_banners/_banner.html.erb:43, surveys/_form.html.erb:67) vs button_link :secondary trash with confirm_modal variant :error (announcements/index.html.erb:21) vs button_link :error (rbs_history/show.html.erb:32) vs submit_button variant :error (rbs_broadcasts/review.html.erb:80-81)
- **buttons** (communication): Submit size: f.submit size "sm" (alerts/edit.html.erb:110,138,143) vs default (alerts/edit.html.erb:64,206 and all communication forms)
- **buttons** (helpers-components): Icon default style differs by helper: button_action/button_link default icon_type "regular" (button_helper.rb:254); ui_badge default :solid (badge_helper.rb:43); ui_empty_state default :regular (notice_box_helper.rb:108); ui_section icon default "regular" (ui_section_helper.rb:84); ui_accent_card, ui_stat_box, ui_icon_item, action_box default :solid; sidebar_item/sidebar_submenu default "regular" (sidebar_helper.rb:119,129); fa_icon itself defaults "regular" (icon_helper.rb:81)
- **buttons** (helpers-components): Destructive action as a link vs a button: delete_button renders <a data-turbo-method="delete" class="btn btn-error"> (button_helper.rb:217-234); confirm_modal_dialog's Confirm is a <button> (modal_helper.rb:142); submit_button renders <input type="submit"> (button_helper.rb:246); dropdown_button and clipboard_button and the toast close are raw tag.button outside ButtonHelper (navigation_helper.rb:82, clipboard_helper.rb:21, common/_toast.html.erb:9)
- **buttons** (hq-assets): Row action layout: raw div "flex flex-wrap justify-end gap-2" (asset_management/records/type.html.erb:100, vehicles/registry/index.html.erb:136) vs button_row (hq/shift_manage/_pogs.html.erb:94, _verification.html.erb:76) vs single edit_link (pogs/administration/index.html.erb:90) vs icon-only edit_link btn-square (quartermaster/swag/type.html.erb:54)
- **buttons** (hq-assets): Export placement: filter_bar actions: (asset_history:60, quartermaster/events_rangered:86, vehicles/registry/index.html.erb:43) vs inside a standalone div.my-4 button_row (quartermaster/alpha_shirts:41, freaking_years/index:25, freaking_years/show:20, potential_shirts:56, asset_management/records/index.html.erb:19) vs in button_row beside view buttons (asset_management/radio_checkout/index.html.erb:108)
- **buttons** (js): Busy/submitting state done differently: login-submit disables and sets value "Working…" or data-pending-label (app/javascript/controllers/login_submit_controller.js:25); passkey disables and swaps value only when data-pending-label exists (app/javascript/controllers/passkey_controller.js:104); photo-cropper disables and sets textContent "Saving…" (app/javascript/controllers/photo_cropper_controller.js:255, 281); photo-upload hides the whole form and shows a loading target (app/javascript/controllers/photo_upload_controller.js:106); camera shows a loading target (app/javascript/controllers/camera_controller.js:192)
- **buttons** (me): Colour of the main confirm/claim action: :success (tickets/review:89, tickets/sap:91) versus :primary (tickets/vehicle_pass:57, provisions:77,80, _claim_buttons:39, agreements/show:23) versus :warning/:error (vehicles_dashboard/_pvr_status_agreement_needed:27, vehicles_dashboard/index:44)
- **buttons** (me): Full-width CTA: button_link class "w-full text-center" (vehicles_dashboard/_mvr_status_eligible:36, _pvr_status_agreement_needed:28, _pvr_status_eligible:11) versus class "w-full justify-center" (_pvr_status_potential:19) versus submit_button full_width: true (online_course/index:29)
- **buttons** (me): State-changing actions: button_link with method: :post/:patch (announcements/_announcement:72,79, timesheet/final_confirmation:17, tickets/_claim_buttons:38,47, gift:69-120, provisions:77,80, review:89, sap:81,91, ticket:87,91,118,145, vehicle_pass:57,86); button_to with button_classes (agreements/show:21); delete_button (passkeys/index:36); button_link with confirm_modal data method delete (vehicles_dashboard/_pvr_requests:70-74)
- **buttons** (mentoring): Lone action button above a shift picker: div.print:hidden > button_row (shift_report/index.html.erb:26-33) vs classless div > button_row (alpha_signout/index.html.erb:70-75)
- **buttons** (person): Table row actions: edit_link + delete_button in div "flex-center gap-2 justify-end" (banners/index:47, callsigns/edit:117); in button_row (pogs/index:43, swag/index:62, certifications/index:34); in div "flex flex-wrap gap-1" with size sm (timesheets/_entries_table:46); bare default-size button_link (timesheets/_missing_requests_table:20); div "mt-1 flex flex-wrap gap-2" (unified_flagging/_note:19)
- **buttons** (person): Row Edit/View buttons: timesheets/_entries_table uses size "sm" and :secondary for Edit/View; timesheets/_missing_requests_table uses default size and :primary for Edit/View (both on timesheets/index)
- **buttons** (person): Cancel control three ways: cancel_link (access_documents/_form:76, awards/_form:51, banners/_form:36, bmids/show:63, callsigns/edit:85, certifications/_form:24, external_ids/show:38, fka/_form:14, intake_notes/edit:21, memberships/edit:54, passkeys/new:58, passwords/edit:27, permissions/edit:72, statuses/edit:26); cancel_button (agreements/index:43, missing_requests/new:56, missing_requests/edit:140, timesheets/backfill:35, timesheets/edit:178); button_link "Cancel" :secondary (pogs/_form:13, swag/_form:35)
- **buttons** (person): Delete in a form footer: delete_button (access_documents/_form:78, awards/_form:54, banners/_form:38, certifications/_form:26, pogs/_form:15, swag/_form:37) vs button_link :error class "ms-auto" + confirm_modal (missing_requests/edit:146, timesheets/edit:180)
- **buttons** (person): Lone page action button wrapper: div "my-4" (access_documents/edit:9, awards/_awards_table:4, certifications/index:8, passkeys/index:17, tickets_provisions/show:55); div "mb-3" (awards/index:32, banners/index:19, callsigns/edit:94); p "mb-4" (pogs/index:14); div "my-3" (timesheets/_desired_changes:42); div "mt-3" (unified_flagging/_team_notes:55)
- **buttons** (scheduling): Page action row: div.my-4 > button_row (position_credits/index:9, position_credits/position:23, slots/index:24, slots/position:15) vs div "my-4 flex flex-wrap gap-2" without button_row (schedule_by_position/position:31, schedule_by_callsign/person:32, shift_signups/position:46) vs div.my-4 export only (no_shows_report/position:33) vs tag.div "mb-4" (hq_forecast_helper:119) vs export in filter_bar actions: (sandman_qualified/index:89, shift_coverage/index:54) vs ui_section link: (position_credits/timeline:30)
- **buttons** (scheduling): Row edit action: edit_link "" icon-only + class btn-square (position_credits/position:94) vs edit_link "Edit Slot" with text (slots/position:119); icon-only button_link with fa_icon label (slots/position:112)
- **buttons** (shell-auth-profile): Destructive action: button_link + confirm_modal(method: :delete) with :warning (profile/_bmid.html.erb:20), :secondary (profile_languages/index.html.erb:39) and :error (profile_photos/crop.html.erb:142); delete_button helper not used in scope
- **buttons** (shell-auth-profile): Button groups: button_row (profile edit pages, register) vs div "my-2 flex flex-wrap gap-2" (profile/show.html.erb:19) vs div "flex flex-wrap justify-center gap-2 mt-3" (profile/_bmid.html.erb:18) vs div "flex flex-wrap justify-center gap-2 lg:gap-3" (profile_photos/crop.html.erb:80)
- **buttons** (shell-auth-profile): Submit on door pages: f.submit (sessions/_password_form.html.erb:61, sessions/new.html.erb:90) vs submit_button (sessions/forgot.html.erb:33, sessions/reset_token.html.erb:64) with identical classes
- **buttons** (teams-people): CSV export placement: filter_bar actions: (certificates_report/show:24, retention_report:48, status_change_recommendations/show:57, unified_flagging:58, people_by_location index:30, search:59) / div.my-4 > button_row (position_grants/show:42, certificates_report/index:17) / flex row beside summary (special_teams_hours/index:116) / ui_form submit (bulk_lookup/_export_form:7)
- **buttons** (teams-people): filter_bar Apply submit: variant :secondary (teams_positions pages, certificates show:34, languages_known index:49/show:23) / default variant (status_change_recommendations/show:67, retention_report:62, unified_flagging:82, people_by_location index:37 and country:64)
- **buttons** (ticketing-bmid): CSV export placement: filter_bar actions: (access_documents/records.html.erb:26, unclaimed_with_signups/index.html.erb:46, expiring/index.html.erb:61, provisions/index.html.erb:27, claimed_with_no_signups/index.html.erb:54, bmid/manage/index.html.erb:105) vs standalone button_row (unsubmit_provisions/index.html.erb:38-40, sap_candidates/index.html.erb:44-48)
- **buttons** (ticketing-bmid): Cancel beside submit: cancel_button (trs_export/export.html.erb:61, unsubmit_provisions/index.html.erb:97, maintenance/preview.html.erb:60, bmid/titles/_form.html.erb:38, bmid/titles/set.html.erb:76) vs cancel_link (bmid/badges/edit.html.erb:120)
- **buttons** (ticketing-bmid): Filter bar Apply button: default variant (ticketing/*/_filter_bar.html.erb e.g. expiring/_filter_bar.html.erb:53, trs_export/index.html.erb:78, bmid/sanity_check/index.html.erb:58) vs variant :secondary (bmid/manage/_filter_bar.html.erb:70, bmid/export/_filter_bar.html.erb:32)
- **buttons** (timesheets-shiftops): Confirm before destructive action: turbo_confirm confirm_modal_dialog on submit (timesheet_slot_repair/index.html.erb:61, mass_signout/index.html.erb:121, bulk_sign_in_out/preview.html.erb:137) vs delete_button confirm_modal: hash (cruise_direction/pods/_dialog.html.erb:53) vs download-confirm Stimulus controller (payroll_export_helper.rb:97) vs none (cruise_direction/people/edit.html.erb:37)
- **buttons** (timesheets-shiftops): CSV export placement: filter_bar actions: (correction_requests/index.html.erb:51, early_late_checkins/index.html.erb:68, hours_credits/index.html.erb:72, timesheets_by_callsign/index.html.erb:38) vs bare <div class="my-4"> (timesheet_by_position/position.html.erb:51) vs button_row in div.my-4 (timesheet_unconfirmed/index.html.erb:65, payroll_missing_id/index.html.erb:42) vs flex toolbar with badge (sanity_checker/check.html.erb:34) vs button toolbar (timesheets_by_callsign/person.html.erb:53) vs right-aligned button_row (payroll_export/index.html.erb:154)
- **buttons** (training): Copy email list: clipboard_button in multiple_enrollments/index.html.erb:51 and completed_training/_people_table.html.erb:10; button_action controller "copy-to-clipboard" in sessions/_trainees_section.html.erb:49 and untrained_people/index.html.erb:54
- **buttons** (training): CSV export placement: filter_bar actions: "Export All to CSV" in mentees, all_notes, trained_no_work, online_course_progress, untrained_people; filter_bar actions with active filters in mentoring/verdicts/index.html.erb:80 and multiple_shifts/index.html.erb:57; div.my-4 > button_row > export_csv_link in capacity/index.html.erb:46, completed_training/index.html.erb:35, multiple_enrollments/index.html.erb:31, trainer_attendance/index.html.erb:30
- **links** (admin): Person/record link in a table: person_display_link (bug_reports/index.html.erb:36; documents/index.html.erb:52; action_logs_helper.rb:60) ; link_to class "underline" (passkeys/index.html.erb:53) ; link_to class LinkHelper::TABLE_LINK_CLASSES (shift_coverage_groups/index.html.erb:43) ; external: ext_link (documents/index.html.erb:67) vs link_to target _blank (sms_management_helper.rb:166)
- **links** (communication): Email address link: link_to "mailto:..." class underline (alerts/edit.html.erb:93,157) vs mail_to (bug_reports/new.html.erb:28); underlined link_to (rbs_history/index.html.erb:72, rbs_helper.rb:366, surveys/index.html.erb:14 with font-semibold) vs plain link_to (bug_reports/new.html.erb:24)
- **links** (helpers-components): Link styling: TABLE_LINK_CLASSES "link link-primary inline-flex min-h-5 items-center" (link_helper.rb:7); back_to "inline-flex-center-gap-2 min-h-9 text-body no-decoration hover:text-stone-emphasis" (application_helper.rb:252); dropdown_item "no-decoration dropdown-link" (navigation_helper.rb:64); sidebar_item "sidebar-nav-item ... no-decoration" (sidebar_helper.rb:132-152); hyperlink_text plain <a> with no class (application_helper.rb:368); ui_stat_link "no-decoration block rounded-lg" + focus ring (ui_stat_box_helper.rb:31)
- **links** (me): External links: ext_link (dashboard_tasks/_missing_bpguid:11, _online_course_needed:11, _ranger_interest_signup:4, me/dashboard/_dashboard_bonked:21) versus raw <a target="_blank" rel="noopener noreferrer"> (dashboard_tasks/_attend_alpha_shift_pending:2)
- **links** (me): Inline link styling: link_to/mail_to class "underline font-semibold" (operational_summary/_basic_driving:24, _mvr:16, passkeys/index:7, tickets/_contact_ticketing:15); hand-styled text-warning link (vehicles_dashboard/_eligible_positions:30); tap-target-link "Go To ..." CTAs (dashboard_tasks/*, e.g. _burn_weekend_shift_needed:6); plain link_to (dashboard_tasks/_attend_training_pending:33, _verify_personal_info:19)
- **links** (mentoring): Inline text links: "link link-primary" (alphas_convert/index.html.erb:54,63), "underline font-semibold" (alpha_mentor_assignments/index.html.erb:53,102), LinkHelper::TABLE_LINK_CLASSES (post_season_summary/_row_extras_meta.html.erb:13), "link link-primary inline-flex min-h-8 items-center" (alpha_pods/_pod_card.html.erb:54), callsign_link elsewhere
- **links** (person): Person name links in logs: person_display_link (mail_log/index:53, assets/_history:15, scheduling/_log_changes:15); callsign_link (status_history/index:46); link_to class "underline" (certifications/show:23, timesheets/_log_table:14); action_log_person_label (access_documents/history:21); plain callsign text (unified_flagging/_note:12)
- **links** (teams-people): person link: person_display_link (bulk previews 78/69, roster show 147, team_records 88, certificates show 59, sanity _findings_table 40) / callsign_link (membership _roster 13, position_grants/show 69, status_change _table_row 22, languages show 56, retention 93, bulk_lookup 95, search 177, _people_table 27)
- **links** (ticketing-bmid): Row edit link: text link_to "Edit" with TABLE_LINK_CLASSES (bmid/manage/_table.html.erb:35) vs icon-only edit_link btn-square (bmid/titles/index.html.erb:48) vs the record id as link (ticketing/provisions/index.html.erb:52)
- **links** (training): Session time link: training_session_link helper (all_notes/_session.html.erb:3, multiple_enrollments:79, untrained_people:116, trainer_attendance/_session_line:15); inline link_to TABLE_LINK_CLASSES + STAMP_CLASSES in trained_no_work/index.html.erb:109; link_to TABLE_LINK_CLASSES in completed_training/index.html.erb:58; link_to class "font-medium" in sessions/_session_table.html.erb:22
- **links** (vc): Inline link styling: class "underline font-semibold" (_banners.html.erb:22,28; applications_helper.rb:13; create_prospectives_helper.rb:112) vs "underline" (_callsign_stage.html.erb:62; create_prospectives/index.html.erb:97,102; application_import/index.html.erb:80) vs "link font-semibold" (handle_checker_helper.rb:69) vs plain link_to (photos_review/_attribution.html.erb:4, maintenance/_results_table.html.erb:29, spigot _callsign_cell:14); external Salesforce link via link_to target _blank (_admin_section.html.erb:7) vs ext_link (create_prospectives_helper.rb:118)
- **forms** (admin): Field help text: help_text: option (most forms) ; f.help_text_tag (shift_coverage_groups/_form.html.erb:19; shift_coverage_positions/_position_rows.html.erb:14) ; raw p#id "text-sm mt-1" + aria describedby (rbs_alerts/edit.html.erb:41) ; raw p.my-2 under fieldset legend (event_dates/_form.html.erb:4,14,25)
- **forms** (admin): Search forms: filter_bar with chips (action_logs, error_logs, jobs, legacy_log, mail_log, passkeys, request_logs, sms_management) ; ui_form method :get with horizontal field and inline submit, no chips (settings/index.html.erb:14)
- **forms** (common-a): Field width set by width: option (bmids/_fields.html.erb:22-32, _legal_name_fields.html.erb:10-15) vs html class on select (bmids/_fields.html.erb:8,13, provisions/_form.html.erb:16-30, bulk_upload/index.html.erb:58)
- **forms** (common-a): Checkbox lists: bordered tile label (_checkbox_tile.html.erb:15, label text-sm via _checkbox_grid.html.erb:17), borderless row label text-base (_checkbox_row.html.erb:15), builder f.check_box in a flex row (provisions/_form.html.erb:44-48)
- **forms** (common-a): Required marker: builder required: true (provisions/_form.html.erb:16) vs hand-built label with ui_badge "required" (assets/_checkout_form.html.erb:13-16)
- **forms** (common-b): Submit: f.submit (timesheet/edit:85, mentoring/index:36) vs submit_button (shift_manage/_start_shift:78) vs modal_form_footer (shift_manage/_blocked_modal:29, _correct_position_modal:22)
- **forms** (communication): Select width: width: "w-full" in the builder options (announcements/index.html.erb:44, person_banners/index.html.erb:34, surveys/_form.html.erb:22) vs html { class: "w-full" } (rbs_messages/index.html.erb:37, rbs_history/index.html.erb:36-40, rbs_broadcasts/_audience_fields.html.erb:9,21,27, _simple_fields.html.erb:26)
- **forms** (communication): Checkbox-group legend: <label class=LABEL_CLASSES> (rbs_messages/index.html.erb:41,53; rbs_broadcasts/_audience_fields.html.erb:37) vs <span class=LABEL_CLASSES> (rbs_broadcasts/_audience_fields.html.erb:64; _position_checkboxes.html.erb:7 with mb-0)
- **forms** (css): Focus indicator done several ways: ring-2 ring-primary ring-offset-2 (ac-filter-chip autocomplete.css:137, lexxy-editor lexxy.css:75, hq-gantt-hit hq-forecast.css:117, driver close driver.css:91), ring-2 ring-inset ring-primary (messages-conversation-item messages.css:15), ring-2 no offset (mega-menu-item-link mega-menu.css:113), outline 2px warning (login.css:426-430), box-shadow 3px warning ring (login-input login.css:230-236), outline-color overrides on ghost buttons (navbar.css:23, sidebar.css:76)
- **forms** (css): Fieldset styling twice: bare `form fieldset` element rule and opt-in .form-fieldset class share one declaration block (forms.css:7-20)
- **forms** (css): Select styling: daisyUI .select (overridden in forms.css:23,36) vs hand-rolled camera-select (camera.css:28-32)
- **forms** (helpers-forms): Label column width: horizontal layout lg:w-1/4 (form_helper.rb:118) vs auto layout lg:w-1/8 (form_helper.rb:127); horizontal wrapper has no bottom margin while vertical and auto use mb-3 (form_helper.rb:70, 117, 126)
- **forms** (helpers-forms): Select placeholder wording: "Choose Country" (app/helpers/country_state_helper.rb:7) vs "Not Selected" (app/helpers/shirt_helper.rb:39) vs filter "All" (app/helpers/ui_components/filter_bar_helper.rb:22)
- **forms** (helpers-forms): Form wrapper built two ways: ui_form (app/helpers/ui_components/ui_form_helper.rb:21-38, adds data-controller="form", summary above form, opt-out no_error_summary) vs common/_form_wrapper partial (app/views/common/_form_wrapper.html.erb:1-4, plain form_with + AppFormBuilder, no form controller, summary inside)
- **forms** (helpers-forms): Required marker two ways in one helper: "(required)" text span "ml-2 text-xs text-error" vs bare red asterisk icon when required_label: "" (app/helpers/form_helper.rb:788-794); check_box and radio_button accept required: but render neither marker nor required attribute (form_helper.rb:454-477, 862-875)
- **forms** (helpers-forms): Autocomplete markup built two ways: AppFormBuilder#autocomplete_field (app/helpers/form_helper.rb:246-344: loading div text only "Searching…", no delay value, hidden field always present, no aria-label) vs shared/_autocomplete (app/views/shared/_autocomplete.html.erb:17-74: loading div with spinning fa spinner, delay 300, optional hidden field, aria-label "Search" default, keyboard-help footer, many extra modes); placeholder "Search…" (ellipsis char, form_helper.rb:303) vs "Search..." (three dots, _autocomplete.html.erb:1)
- **forms** (helpers-forms): Group label for radios: <fieldset role="radiogroup"><legend> for vertical and :stacked (form_helper.rb:963-971, 986-991, 1023-1028) vs a plain <span> with no group semantics for horizontal/auto inline (form_helper.rb:997-1008, 1034-1045); horizontal/auto checkbox labels are also <span> not <label> (form_helper.rb:881-883, 906-908)
- **forms** (helpers-forms): Toggle label wiring: check_box wraps input and text in one <label class="inline-flex items-center min-h-9 cursor-pointer"> (form_helper.rb:933-937) vs radio_button with sibling <label for> (form_helper.rb:947-951) vs collection radio b.label sibling (form_helper.rb:1063-1067)
- **forms** (hq-assets): filter_bar submit: f.submit "Apply Filters" default (asset_history:82, assets_outstanding:62, radio_assets:122, quartermaster pages, vehicles pages) vs variant: :secondary (asset_management/records/type.html.erb:71, pogs/administration/index.html.erb:47)
- **forms** (mentoring): Form construction: ui_form with builder fields (alpha_acceptance_sheets/index.html.erb:69, convert_prospectives:74, alphas_convert/_section:19, alpha_signout:130) vs form_with builder: AppFormBuilder with hand-built labels and *_tag fields (rosters/_dialog.html.erb:11-24, alpha_pods/people/edit.html.erb:12-30, alpha_pods/people/new.html.erb:17-23) vs raw select_tag inside a ui_form (alpha_mentor_assignments/index.html.erb:172,249,258)
- **forms** (person): Field width set three ways: width: builder option (awards/_form:20, callsigns/edit:47, external_ids/show:17); html-options class: (access_documents/_form:17-43); wrapper_class "flex-1" in form_row (certifications/_form:15, site_log/index:41); one uses lg: instead of sm: (access_documents/_form:43)
- **forms** (person): Checkbox: f.check_box via builder (agreements/_agreement_row:3, vehicles/index, timesheets/edit) vs raw check_box_tag + raw label with CHECKBOX_CLASSES (memberships/_position_checkbox:6, _team_card:11,40, permissions/edit:30, timesheets/backfill:24)
- **forms** (scheduling): Filter-bar Apply button: default f.submit (sandman_qualified/index:100, schedule_by_callsign/index:44, shift_coverage/index:66, hq_forecast/index:71, burn_perimeters:39, shift_signups/index:56, _window_filter:20) vs variant: :secondary (position_credits/position:60, shift_lead/_filters:51, slot_copies/new:49, early_arrivals/index:164, slots/position:59, slot_bulk_edits/new:45)
- **forms** (scheduling): GET filter controls: filter_bar (most pages) vs raw form_tag + select_tag with SELECT_CLASSES and auto-submit (shift_lead/_picker:37, shift_lead/_sort_control:16)
- **forms** (scheduling): Filter select sizing: width "w-full" + wrapper_class "flex-1" (sandman_qualified/index:95, schedule_by_callsign/index:32, shift_lead/_filters:24, hq_forecast/_interval_field:5, early_arrivals/index:134) vs fixed "w-full sm:w-40/44/56/64" (position_credits/position:57, slot_copies/new:34, slots/position:48, slot_bulk_edits/new:26) vs no width (shift_coverage/index:62-63)
- **forms** (scheduling): Filter chips: filter_chips helper (sandman, schedule_by_callsign, shift_signups, shift_lead, hq_forecast, shift_coverage, slots, early_arrivals helpers) vs hand-built {label:, url:} hashes (position_credits_helper:15, shift_drop_report_helper:17)
- **forms** (shell-auth-profile): Form wrappers: ui_form everywhere vs raw form_with (profile_photos/crop.html.erb:62) vs form_tag (application/_mega_menu.html.erb:18); field rows via form_row (identity_info_edit:36, register/_form:61) vs hand flex rows (identity_info_edit:74,91,126; clothing_edit:34)
- **forms** (teams-people): grouping heading in a form: f.fieldset with icon (special_teams_hours:64) / raw fieldset + legend.font-medium (people_by_location/_filter_fields:10) / p.font-semibold label (search/index:80)
- **forms** (teams-people): select width: builder width: option (roster_management/show:50, special_teams_hours:54, create_account:28) / html { class: } option (bulk_teams/index:45, team_records/_form:25, position_records/_form:19,79,83,184) ; breakpoint sm: (forms) vs lg: (roster_management/show:50, certificates_report/show:30)
- **forms** (ticketing-bmid): Select-all wrapper: bulk_select helper (trs_export/export.html.erb:47, unsubmit_provisions/index.html.erb:44, bmid/export/index.html.erb:64) vs raw div data-controller="checkbox-select-all" (trs_export/index.html.erb:89)
- **forms** (timesheets-shiftops): Form wrapper: ui_form (mass_signout/index.html.erb:65, bulk_sign_in_out/index.html.erb:29, timesheet_slot_repair/index.html.erb:41, rollcall/_set_time_dialog.html.erb:26, payroll_export/index.html.erb:28) vs form_with builder: AppFormBuilder (cruise_direction/pods/_form.html.erb:9, people/_dialog.html.erb:18, people/edit.html.erb:16)
- **forms** (timesheets-shiftops): "All" first select option: literal ["All callsigns", ""] / ["All positions", ""] / ["Everyone", ""] (correction_requests_helper.rb:10, early_late_checkins_helper.rb:24,34, payroll_export_helper.rb:77) vs shared ALL_FILTER_OPTION constant (forced_shift_start_helper.rb:45, hours_credits_helper.rb:25)
- **forms** (timesheets-shiftops): Picker/filter selects: filter_bar + f.select (timesheets pages, e.g. early_late_checkins/index.html.erb:73) vs raw form_tag + label_tag + select_tag with AppFormBuilder::SELECT_CLASSES (rollcall/_pickers.html.erb:16, cruise_direction/_pickers.html.erb:19) vs form_tag + raw <label> + select_tag (payroll_export/index.html.erb:141) vs form_with AppFormBuilder + raw <label> + select_tag (cruise_direction/people/edit.html.erb:19)
- **forms** (training): Form wrapper: ui_form in scores, notes, general_notes dialogs and _roster; form_with builder: AppFormBuilder in sessions/_trainer_section:15, graduations/_dialog:24, rosters/_dialog:17 and _blocked:34
- **forms** (training): Fields outside the builder styled with AppFormBuilder constants: select_tag in _trainer_section:39, rosters/_dialog:24, _roster:172 and 211; text_field_tag in rosters/_dialog:40; text_area_tag in _general_notes:14 and _roster:217; labels via label_tag LABEL_CLASSES (_roster:210) vs raw <label class="font-medium block mb-1"> (rosters/_dialog:23)
- **forms** (vc): Form construction: form_with url: + builder: AppFormBuilder (applications/index.html.erb:27,64; search.html.erb:9; _personal_info_stage.html.erb:11; _paragraph_stage.html.erb:21; every applications/dialogs/*.erb; extract_handles.html.erb:18) vs ui_form (edit_details.html.erb:12, edit_personal_info.html.erb:12, reserved_handles, bpguid, handle_checker, photos_review/reject_dialog.html.erb:2, create_prospectives, application_import, maintenance previews)
- **forms** (vc): Application search form laid out three ways: form_row + div "lg:mt-6" + :secondary submit (applications/index.html.erb:29-34); flex "items-end" + default submit (applications/search.html.erb:10-14); flex-col sm:flex-row sm:items-end with wrapper_class mb-0 and button_row mb-1 (handle_checker/index.html.erb:18-29)
- **forms** (vc): Raw checkboxes outside the builder: check_box_tag class "checkbox checkbox-sm" in a label grid (applications/edit_details.html.erb:25-27) vs check_box_tag class AppFormBuilder::CHECKBOX_CLASSES in common/_checkbox_tile (handle_checker/index.html.erb:66-68) vs common/_checkbox_grid (handle_checker:51,76; thank_you_cards:33) vs f.check_box multiple (photos_review/reject_dialog.html.erb:13)
- **forms** (vc): Filters: hand-rolled auto-submit select row without chips (applications/index.html.erb:64-79) vs filter_bar with chips and Apply button (reserved_handles/index.html.erb:52-75, thank_you_cards/index.html.erb:21-43)
- **validation** (common-a): Error summaries: common/_error_summary callout with list (_error_summary.html.erb:2-9, via _form_wrapper) vs ui_form's own summary (messages/_compose.html.erb:8, missing_requests/_form.html.erb:14) vs no summary plus flash (bulk_upload/index.html.erb:50) vs no summary at all (messages/_find_recipient_form.html.erb:2, assets/_change_attachment_modal.html.erb:10)
- **validation** (common-b): Requirement labels: REQUIREMENT_LABELS[req].html_safe (scheduling/_missing_requirements:24) vs REQUIREMENT_LABELS[req] with "Unknown status" fallback, not html_safe (scheduling/_signup_blockers:51)
- **validation** (helpers-forms): Error summary built three ways: form_error_summary (app/helpers/form_helper.rb:1184-1205: id form-error-summary, tabindex -1, "Please fix the following error(s):" font-semibold, bullet spans in ul.mt-2.space-y-1, rendered outside the <form> by ui_form at app/helpers/ui_components/ui_form_helper.rb:31-37) vs common/_error_summary (app/views/common/_error_summary.html.erb:2-8: "The following errors were found:" font-medium, ul.list-bulleted, no id/tabindex, rendered inside the form by app/views/common/_form_wrapper.html.erb:2)
- **validation** (js): Client-side errors shown three ways: an error box target unhidden with message text (photo-upload app/javascript/controllers/photo_upload_controller.js:96, passkey app/javascript/controllers/passkey_controller.js:87, camera error boxes app/javascript/controllers/camera_controller.js:198); window.alert (photo-cropper app/javascript/controllers/photo_cropper_controller.js:238, 245, 251, 270); dialog callouts by kind (dialog base app/javascript/controllers/dialog_controller.js:95, search-bar, mega-menu); plus role=alert text inside the autocomplete list (app/javascript/controllers/autocomplete_controller.js:932)
- **validation** (me): Required fields: form builder required: true (passkeys/new:40, surveys/_question:7) versus ui_badge "required" with asterisk in the label (surveys/_question:17) versus a warning callout "All fields are required." (personal_vehicles/_form:5)
- **validation** (scheduling): Form errors: ui_form(model) builder errors/summary (position_credits/_form:1, slots/_form:1) vs flash.now[:error] from the controller on ui_form(nil) pages (slot_copies/new:54, position_credit_copies/new:27, slot_bulk_edits/new:51)
- **validation** (shell-auth-profile): Notice titles in callouts: title: option (profile/show.html.erb:41,57,73; sessions/_sso_door:5) vs strong first line inside body (profile_photos/new.html.erb:213,222,236,246; register/_acknowledge:4; identity_info_edit:18,23)
- **validation** (teams-people): bulk form refusal: flash.now[:error] with no in-view markup (bulk_teams/index.html.erb:39, bulk_positions/index.html.erb:31) / @refusal in ui_callout_box :error (people/bulk_lookup/index.html.erb:12) / @error in ui_callout_box :error (people/search/index.html.erb:20) / form-builder summary on model forms (team_records/_form.html.erb:3, create_account/new.html.erb:16)
- **validation** (ticketing-bmid): Error display: form builder inline (bmid/titles/_form.html.erb, bmid/badges/edit.html.erb) vs hand-built p "text-error font-medium" role=alert (maintenance/preview.html.erb:49) vs ui_callout_box error with ul (bmid/manage/index.html.erb:44) vs ui_callout_box error count + flagged ledger rows (maintenance/results.html.erb:21, unsubmit_provisions/results.html.erb:22, trs_export/mark_submitted.html.erb:22) vs inline div "text-error" Problem lines (trs_export/_rows_table.html.erb:55)
- **validation** (training): Dialog errors: ui_callout_box :error from local_assigns[:error] in graduations/_dialog:6 and notes/_dialog:5; none in general_notes/_dialog (controller sends an error toast); roster page uses a callout summary plus inline error rows (_roster:33, 231)
- **validation** (vc): Inline error text: <span class="text-error font-semibold"> (reserved_handles/upload.html.erb:93, application_import/_failures_table.html.erb:25, _callsign_stage.html.erb:46) vs div "text-error font-semibold" first-of-list (create_prospectives/_group.html.erb:50) vs colspan row "text-error font-medium" with icon and "Error:" (maintenance/_results_table.html.erb:38-41) vs icon + <span class="text-error"> word (applications/_applications_table.html.erb:31,38,40)
- **modals** (admin): Destructive confirm: delete_button confirm_modal: hash (documents/_form.html.erb:31; event_dates/_form.html.erb:39; permissions/edit.html.erb:37) ; with explicit variant: :error (bug_reports/index.html.erb:79; shift_coverage_groups/_form.html.erb:49; shift_coverage_positions/_form.html.erb:22) ; delete_button confirm_message: string (error_logs/index.html.erb:116; request_logs/index.html.erb:185) ; data: confirm_modal(...) on button_link (jobs_helper.rb:73) ; data turbo_confirm: confirm_modal_dialog on f.submit (oauth_clients/_form.html.erb:42; sms_management/twilio.html.erb:103)
- **modals** (common-b): Modal helpers: modal (scheduling/_missing_requirements_modal:2, _multiple_enrollment_modal:10, _slot_additional_info_modal:1, shift_manage/_converted_modal:6, _too_short_modal:3) vs modal_dialog (shift_manage/_blocked_modal:3, _correct_position_modal:3); close control as m.footer modal_close_button, button_row > modal_close_button (_blocked_modal:36), or none in template (_multiple_enrollment_modal, _slot_additional_info_modal, _converted_modal)
- **modals** (common-b): Confirm wiring: data: confirm_modal(...) on button_link (schedule/index:85, schedule/_signed_up_row:81, available_sign_ups/_slot:122) vs confirm_modal: {...} option on delete_button (shift_manage/_too_short_modal:36)
- **modals** (helpers-components): Disclosure done four ways: ui_accordion daisyUI collapse collapse-arrow (ui_accordion_helper.rb:6); ui_disclosure :inline native triangle (ui_disclosure_helper.rb:11) and :card custom chevron with group-open:rotate-180 (ui_disclosure_helper.rb:15-21); dropdown_menu <details class="dropdown"> (navigation_helper.rb:47); filter_bar and detail_row_toggle use a button + toggle_controller + hidden panel with aria-expanded (filter_bar_helper.rb:218, table_helper.rb:376)
- **modals** (helpers-components): Close controls in four forms: modal title icon button button_action(xmark + sr-only "Close modal", :ghost, class btn-circle) (modal_helper.rb:179-185); auto-appended footer "Close" secondary button (modal_helper.rb:50, 205); backdrop <form method="dialog"><button>close</button> (modal_helper.rb:56-58); toast raw <button class="btn-toast-close" aria-label="Close"> (common/_toast.html.erb:9); sidebar button_action("Close", :ghost, icon xmark, aria-label "Close sidebar") (sidebar_helper.rb:85)
- **modals** (helpers-components): Confirmation wiring in three forms: delete_button confirm_message: -> data-turbo-confirm = confirm_modal_dialog(variant: :error) (button_helper.rb:228-229); confirm_modal hash with turbo_method + turbo (modal_helper.rb:96-104), which delete_button also accepts as confirm_modal: (button_helper.rb:226-227); menu_item_confirm_data builds confirm_modal with title "Confirm {title}" and message "{description}?" (menu_helper.rb:93-99)
- **modals** (hq-assets): HQ dialogs three ways: modal helper auto-open (hq/shared/_warning_modals.html.erb:10, hq/shift_manage/index.html.erb:163, hq/site_registration/_no_radio_modal.html.erb:8, hq/tickets_provisions/show.html.erb:7); modal_dialog frame:false + ui_form (hq/shift_manage/_correction_modal.html.erb:7, _pog_issue_modal.html.erb:5, _pog_cancel_modal.html.erb:5, _pog_edit_modal.html.erb:4, _missing_request_modal.html.erb:5); raw <dialog class="modal modal-middle"> with modal-header-bar/modal-body-content (hq/site_registration/show.html.erb:70-82)
- **modals** (js): Confirmation done two ways: the app's styled <dialog> via Turbo.config.forms.confirm (status-warning app/javascript/controllers/status_warning_controller.js:32, download-confirm app/javascript/controllers/download_confirm_controller.js:22, application.js:112) versus native window.confirm (unsaved-changes app/javascript/controllers/unsaved_changes_controller.js:84, hq-shift guards via the same, confirm_checkbox.js:3 used by membership-editor and permission-editor, permission-editor submit app/javascript/controllers/permission_editor_controller.js:42)
- **modals** (js): Four ways to open a native <dialog>: modal controller auto-shows on connect and removes itself on close, Escape blockable (app/javascript/controllers/modal_controller.js:25); dialog base opens on demand, closes other open modals first, backdrop click closes (app/javascript/controllers/dialog_controller.js:38, 84); hq-wizard calls showModal itself with its own step machine (app/javascript/controllers/hq_wizard_controller.js:44); the Turbo confirm handler injects and shows the dialog itself (app/javascript/application.js:122)
- **modals** (person): Confirmation wiring four ways: delete_button confirm_modal: hash (banners/index:49, pogs/index:45); delete_button confirm_message: string (passkeys/index:47, sessions/index:50); data: confirm_modal(...) (awards/index:35, timesheets/index:72, _actions:22); data: { turbo_confirm: confirm_modal_dialog(...) } (training/index:57,74, email_suppression_helper.rb:21)
- **modals** (ticketing-bmid): Provision dialog size: modal size :xl for the list (bmid/provisions/_list.html.erb:14) vs :lg for the form (bmid/provisions/_modal.html.erb:9), same id
- **modals** (training): Dialog shell: modal_dialog in sessions/graduations, notes, rosters, scores, work_histories and mentoring/general_notes; modal with m.title/m.body in mentoring/assignments/_pass_dialog.html.erb:21 and _promote_dialog.html.erb:11
- **modals** (training): Dialog footer: modal_form_footer in graduations/_dialog:75, notes/_dialog:15, rosters/_blocked:43, general_notes/_dialog:11; button_row with f.submit + modal_close_button in scores/_dialog.html.erb:83; button_row of button_action submits in _pass_dialog:57 and _promote_dialog:25
- **modals** (vc): Dialog shell: modal_dialog (all applications/dialogs, extract_handles, photos_review/reject_dialog.html.erb:1) vs turbo_frame_tag "modal" + modal builder with m.title/m.body (photos_review/info.html.erb:1-4)
- **modals** (vc): Confirm before a destructive action: delete_button confirm_modal: hash (applications/_admin_section.html.erb:14, reserved_handles/_form.html.erb:44) vs button_link data: confirm_modal(...) (reserved_handles/index.html.erb:38-46, photos_review/_photo.html.erb:44-49, bpguid/_results.html.erb:101-112) vs f.submit data turbo_confirm: confirm_modal_dialog (create_prospectives/index.html.erb:76, application_import/index.html.erb:47) vs a separate preview page with no confirm (maintenance previews)
- **modals** (vc): Dialog footer: modal_form_footer (adjust_status, approve_callsign, assign, edit_approved_handle, edit_handles, note_delete, note_form, problem_review, extract_handles) vs button_row + submit_button + modal_close_button "Cancel" when a Preview Email button is present (more_handles.html.erb:14-20, send_email.html.erb:13-19, status_message.html.erb:35-43, photos_review/reject_dialog.html.erb:24-30)
- **tables-lists** (admin): Action buttons in a table cell: div "flex items-center gap-1 whitespace-nowrap" (documents/index.html.erb:59) ; div "flex flex-wrap items-center gap-2" (online_courses/index.html.erb:58) ; div.flex-center-gap-2 (shift_coverage_groups/index.html.erb:52; show.html.erb:50) ; tag.div "inline-flex-center-gap-2" (jobs_helper.rb:144)
- **tables-lists** (admin): Truncated cell text: log_truncated helper with title (request_logs/index.html.erb:130; action_logs/_table.html.erb:33) ; div "truncate max-w-64" with title (error_logs/index.html.erb:74) ; div log_text_class("truncate") without title (bug_reports/index.html.erb:41)
- **tables-lists** (admin): Empty-value placeholder: value_or_dash (event_dates/index.html.erb:40,49; documents/index.html.erb:48; online_courses/index.html.erb:54; jobs/_job.html.erb:28) ; literal "-" (bug_reports/index.html.erb:36,43,58; request_logs/index.html.erb:144; action_logs_helper.rb:60,131; request_logs_helper.rb:52) ; literal "—" (sms_management/twilio.html.erb:36; _lookup.html.erb:22-23; sms_management_helper.rb:164,198) ; "— none —" muted (moodle_catalog_courses.html.erb:25) ; "not yet"/"Never"/"Self" words (enrollment_roster.html.erb:42; passkeys/index.html.erb:67,70) ; blank cell (passkeys/index.html.erb:58)
- **tables-lists** (admin): detail_row_toggle styling: default (error_logs/index.html.erb:61; action_logs/_table.html.erb:21; permissions/_row.html.erb:19; documents/index.html.erb:60) ; class "justify-start px-1 text-left normal-case" (bug_reports/index.html.erb:33; request_logs/index.html.erb:114) ; class "font-mono text-sm break-words lg:whitespace-nowrap" (jobs/_job.html.erb:9)
- **tables-lists** (common-b): Definition lists: dl.instruction-list (scheduling/_burn_weekend_shift_recommendation:4, scheduling/_mvr_eligible:10, timesheet/edit:15) vs dl "space-y-2 text-body" with dt "font-bold text-heading" (scheduling/_linked_slots_full:5)
- **tables-lists** (common-b): Right-aligned ui_table columns: class "text-end" on heading/cell (schedule/signup_summary:52-78) vs right: true (work_history/_matrix, entire_year, position_all, position_summary)
- **tables-lists** (common-b): Label/value pairs: ui_label_value (shift_manage/_on_duty:6), flex rows with icon + muted label (scheduling/_confirm_signup_removal:4-21), spans "font-medium text-heading" (training/_education_detail:13-42), inline lg:hidden labels in a grid (schedule/_signed_up_row:31-50)
- **tables-lists** (communication): Side-by-side sections: div "stack-to-row-lg" (rbs_phone_numbers/index.html.erb:59, rbs_history/show.html.erb:66, rbs_broadcasts/review.html.erb:30) vs div "flex flex-col lg:flex-row gap-4 mt-4" + ui_section column: option (rbs/index.html.erb:25,33) vs div "grid grid-cols-1 lg:grid-cols-2" (surveys/show.html.erb:28)
- **tables-lists** (css): Frozen first column implemented four times with different z-index and breakpoint: roster-col-* z-10/heading z-30 (roster-matrix.css:14-34), hours-credits-callsign z-10/z-30 (hours-credits.css:17,54), top-hour-earners-person z-0 all widths (top-hour-earners.css:17), shift-coverage-period z-10 lg only (shift-coverage.css:14)
- **tables-lists** (css): Bounded scroll pane with pinned heading spelled three times with the same 70vh: roster-grid-pane (roster-matrix.css:49), hours-credits-pane (hours-credits.css:30), sandman-qualified-pane lg only (sandman-qualified.css:22); hq-forecast pins to the page instead (hq-forecast.css:161-173)
- **tables-lists** (helpers-components): Label/value lists: ui_label_value builder on <dl class="ui-label-value"> (ui_label_value_helper.rb:36) vs the hand-written <dl class="ui-label-value"> in common/_years_breakdown.html.erb:10-37, whose first <dt> alone carries "font-medium text-heading"
- **tables-lists** (hq-assets): Label/value displays: ui_label_value (asset_management/records/show.html.erb:21, search/index.html.erb:97); raw <dl> grid with flex pairs (vehicles/registry/permit.html.erb:27,51); raw <dl> stacked dt/dd (hq/shared/_summary_column.html.erb:14); flex divs with font-semibold label (hq/shift_manage/_pog_edit_modal.html.erb:5-12); label div + ms-4 value lines (helpers/vehicles/paperwork_helper.rb:174)
- **tables-lists** (js): Empty state handled two ways in JS: list-filter unhides a server-rendered empty target only when a term matches nothing (app/javascript/controllers/list_filter_controller.js:69); live-log swaps table/empty targets by row count (app/javascript/controllers/live_log_controller.js:69); autocomplete builds its own div.ac-empty with server or default "No results found" text (app/javascript/controllers/autocomplete_controller.js:712, 924)
- **tables-lists** (js): Selection count wording differs by controller: "N selected" (app/javascript/controllers/checkbox_select_all_controller.js:48), "N of M selected" (app/javascript/controllers/position_picker_controller.js:34), "No rows changed" / "1 row changed" / "N rows changed" (app/javascript/controllers/bulk_edit_controller.js:86)
- **tables-lists** (me): Multi-column name lists: ul columns-2 lg:columns-3 (operational_summary/_teams_and_positions:18) versus div columns-2 lg:columns-3 (_teams_and_positions:47) versus grid grid-cols-2 lg:grid-cols-3 (_certifications:3)
- **tables-lists** (me): Whole-row link lists: divide-y rows with hover:bg-base-200 (dashboard/_announcements_section:28-61, tickets/_landing:193-220) versus ui_drill_down_row (agreements/index:74)
- **tables-lists** (me): Icon lists: ui_icon_item (announcements/index:18, tickets/review:22,34, _item_details:17, _ticket_gift_conditions:4, _claimed_overview:160,180, _section_detail:112,155) versus li "flex items-center gap-3" + fa_icon w-5 (tickets/provisions:48-51) versus icon-prefixed <p> lines (dashboard_tasks/* throughout)
- **tables-lists** (me): Definition lists: dl.instruction-list (dashboard/_dashboard_past_prospective:12, feedback/index:29, online_course/index:7, passkeys/index:49, passkeys/new:31, tickets/_announce:39,61, provisions:91, sap:35, sap_so:59, work_history/index:12) versus dl "space-y-2" with dt "font-bold" (tickets/_announce:49) versus uppercase label grid (vehicles_dashboard/_pvr_requests:43)
- **tables-lists** (mentoring): Paper tables: raw <table> styled by .alpha-sheet (signup_sheet.html.erb:30, apparel.html.erb:30, info_sheet.html.erb:44, alpha_pods/print_sheet.html.erb:64) and acceptance-signoff (print_sheets.html.erb:165) vs ui_table (alpha_mentor_assignments/print_sheet.html.erb:30)
- **tables-lists** (person): Label-value display: ui_label_value (_summary_strip, _contact_details with 7rem vs 9rem widths); hand-built dl grid grid-cols-[8rem_1fr] (certifications/show:10); dl.instruction-list holding values (unified_flagging/show:93); strong labels with middots (provisions/_section:19); span labels "font-semibold text-heading" (timesheets/index:124, timesheets/edit:57); span "me-2 text-stone-muted" labels (timesheets/_log_entry_data)
- **tables-lists** (scheduling): Position index drill-down: ui_drill_down_row in div.lg:w-3/4 (no_shows_report/index:45, flake_report/index:52, schedule_by_position/index:26, schedule_by_callsign/index:58, position_credits/index:25, slots/index:39, shift_drop_report/index:43) vs ui_table rows with link_to TABLE_LINK_CLASSES (shift_signups/index:61-76)
- **tables-lists** (shell-auth-profile): Label/value display: ui_label_value (profile/show.html.erb:93) vs ui_table body-only (profile/_clothing.html.erb:6) vs hand-built divs (profile/_identity_info.html.erb:18-55) vs instruction-list dl (everywhere)
- **tables-lists** (teams-people): empty table cell: value_or_dash (team_records/index:92, certificates_report/show:65, bulk_lookup/index:98, retention_report:96) / literal "—" (bulk_teams/preview:83, bulk_positions/preview:74, _people_table:29) / span.text-stone-muted "—" (position_grants/show:115) / dash + sr-only (roster_management_helper.rb:209) / dash + aria-label span (status_change_recommendations_helper.rb:41) / italic muted words ("No team" position_records/index:97, "No email" team_records/index:97) / <em>never</em> (bulk_lookup/index:104)
- **tables-lists** (teams-people): read-only role list: ui_badge chips (team_records/_form:81) / plain stacked divs (position_records/_form:162); cell lists: value_list (team_records/index:80) / div.flex-col of divs (position_lineups/index:38)
- **tables-lists** (ticketing-bmid): Person identity column: t.row_header with callsign_link (most tables) vs t.cell with callsign_link + muted subline (bmid/titles/apply.html.erb:41, bmid/titles/set.html.erb:52, bmid/sanity_check/index.html.erb:88); secondary line styled "text-stone-muted font-normal" (expiring:92), "text-sm text-stone-muted" (titles/apply:43, set:57, sanity_check:90), "text-stone-muted" (export/_selection_table:42), "mt-1 text-stone-muted" (sap_candidates:76), unstyled div (claimed_with_no_signups:97)
- **tables-lists** (ticketing-bmid): Right-aligned numeric cell: right: true (provisions/index.html.erb:42,67; bmid/export/_previous_exports.html.erb:21) vs class: "text-right" (expiring/index.html.erb:98-99)
- **tables-lists** (timesheets-shiftops): Bulk-select checkbox column heading: sr-only "Apply" (timesheet_slot_repair/_group.html.erb:8-9) vs visible "Select" (mass_signout/index.html.erb:73)
- **tables-lists** (vc): Label/value display: ui_label_value with label_width 8rem (_rail.html.erb:3), 12rem (all stage partials, _admin_section), 9rem (bpguid/index.html.erb:37) vs raw <dl class="space-y-2"> with dt font-semibold (photos_review/_photo.html.erb:82, info.html.erb:15) vs a one-row ui_table (photos_review/_photo.html.erb:14)
- **navigation** (admin): Pager placement: above+below only when rows (jobs/index.html.erb:68-91; action_logs/index.html.erb:86-94) ; below always, above when rows (error_logs/index.html.erb:44,113; mail_log/index.html.erb:68,79; request_logs/index.html.erb:89,182) ; below only (passkeys/index.html.erb:76) ; empty page adds "Back to the First Page" button (legacy_log/index.html.erb:103) or pager only if previous (action_logs/index.html.erb:80)
- **navigation** (common-a): Tab-like switching: daisyUI `tabs tabs-lift` via messages_folder_tab (messages/_folder_selector.html.erb:5, messages_helper.rb:35) vs button_link :primary/:secondary with aria-current as a report switcher (surveys/report.html.erb:16-25)
- **navigation** (communication): hero_panel back link: back_to: kwarg array (alerts/edit.html.erb:4, mail_templates/edit.html.erb:7, surveys/show.html.erb:11, rbs_history/show.html.erb:9) vs panel.back_to block with back_to helper (announcements/new.html.erb:6-8, announcements/edit.html.erb:6-8)
- **navigation** (css): Dropdown menus: dropdown-panel applies daisyUI `menu` (dropdowns.css:9) while dropdown-link re-declares its own padding/hover/radius (dropdowns.css:14) instead of daisyUI menu item styling
- **navigation** (helpers-components): Back navigation: back_to text link with arrow-left and aria-label "Back to {label}" (application_helper.rb:245-261); page_title block slot above the h1 (page_layout_helper.rb:14-16); hero_panel back_to slot rendered twice by breakpoint (ui_hero_panel_helper.rb:131-135, 204); cancel_button as a btn-secondary link (button_helper.rb:169)
- **navigation** (helpers-components): Panel switching: tab_navigation daisyUI "tabs tabs-border" with role=tab/tabpanel and aria-selected (tabs_helper.rb:23-133) vs mega menu chrome buttons (button_action :ghost with aria-current true/false, sections toggled by hidden) (mega_menu_helper.rb:86-101)
- **navigation** (helpers-components): Active-link marking: nav_link_to adds "active" + aria-current="true" by fullpath prefix (link_helper.rb:10-13); sidebar_item adds "active" + aria-current via menu_item_active? exact or prefix (sidebar_helper.rb:133-152); mega_chrome_button uses aria-current "true"/"false" strings on buttons (mega_menu_helper.rb:99)
- **navigation** (helpers-components): Year selector in two forms: year_selector label "Select the year to view:" with AppFormBuilder horizontal classes (page_layout_helper.rb:44-53) vs year_selector_compact label "Year to view:" text-lg font-medium plus aria-label "Select year to view" and select select-sm w-auto (page_layout_helper.rb:68-77); hero_panel renders both on one page, one per breakpoint (ui_hero_panel_helper.rb:215-231)
- **navigation** (hq-assets): View toggles: one button whose label flips (asset_management/radio_assets/index.html.erb:67-77) vs two always-visible buttons with current one primary + sr-only text (asset_management/radio_checkout/index.html.erb:91-106 via helpers/asset_management/radio_checkout_helper.rb:16)
- **navigation** (hq-assets): Back link on hero: back_to: [label, path] array (asset_management/records/edit.html.erb:4, pogs/administration/edit.html.erb:6, quartermaster/swag/new.html.erb:3, hq/assets/index.html.erb:7) vs panel.back_to block calling back_to helper (vehicles/registry/edit.html.erb:4-5, new.html.erb:4-5, permit.html.erb:6-7, hq/shared/_header.html.erb:16-17) vs back_link local passed to common template (hq/scheduling/index.html.erb:7, hq/messages/index.html.erb:4)
- **navigation** (js): Tabs done three ways: tabs controller with class lists from the helper, aria-selected, tabindex and "hidden" class on panels (app/javascript/controllers/tabs_controller.js:56); camera controller's own Upload/Camera tabs with "tab-active", aria-selected, tabIndex and hidden attribute (app/javascript/controllers/camera_controller.js:55); mega-menu panels switched by hidden attribute with aria-current on the chrome buttons rather than aria-selected (app/javascript/controllers/mega_menu_controller.js:217)
- **navigation** (me): Back to the dashboard: back_to: :dashboard (agreements/index:3, announcements/index:3, awards/index:3, directory/index:2, online_course/index:4, shift_manage/index:2, tickets/_landing:49, vehicles_dashboard/index:6); back_to: ["Clubhouse Dashboard", me_root_path] (operational_summary/index:3); back_to: ["Dashboard", me_root_path] (surveys/show:3); panel.back_to block with back_to_dashboard (feedback/index:8); back_link: back_to_dashboard local (mentoring/index:2, schedule/index:3)
- **navigation** (mentoring): Print-sheet back link and print hint: shared partial alpha_schedule/_print_screen_nav.html.erb:2-7 vs inline copies in alpha_acceptance_sheets/print_sheets.html.erb:16-21, alpha_mentor_assignments/print_sheet.html.erb:9-14, alpha_pods/print_sheet.html.erb:33-39
- **navigation** (person): Bottom back link duplicating the hero back_to: missing_requests/show:37 and timesheets/edit:62 put back_to in a button_row; other read-only pages (certifications/show, status_history) do not
- **navigation** (scheduling): Year selector floor: year_floor (report pages) vs min_year 2012 (position_credits/index:6) vs 2008 (slots/index:6); report detail pages carry a year_selector while position_credits/position and slots/position do not
- **navigation** (shell-auth-profile): Way back: hero_panel back_to (profile edit pages, profile_languages) vs button_link "Back to Start" (register/_acknowledge:19, _volunteer:22) vs sessions/_footer_link (forgot, reset_token, invalid_request) vs cancel_link on a list page (profile_languages/index:57)
- **navigation** (teams-people): leaving a preview: f.submit formaction "Go Back and Edit" (bulk_teams/preview.html.erb:119, bulk_positions/preview.html.erb:110) / hero back_to + cancel_link (roster_management/preview.html.erb:10,87) / hero back_to + button_link "Back to the Board" (position_sanity_checker/check.html.erb:14,67)
- **navigation** (timesheets-shiftops): Hero back link: hero_panel back_to: keyword array (sanity_checker/check.html.erb:11, timesheet_by_position/position.html.erb:10, timesheet_totals_report/person.html.erb:10, timesheets_by_callsign/person.html.erb:10) vs panel.back_to block with back_to helper (rollcall/sign_in.html.erb:17, rollcall/sign_out.html.erb:19) vs a "Back to Timesheets" button_link in the form's button_row (timesheet_slot_repair/index.html.erb:67)
- **navigation** (vc): Leaving a preview: cancel_button (maintenance/preview_pnvs.html.erb:33) vs button_link "Back to Maintenance Tasks" :secondary in the empty case (preview_pnvs.html.erb:42) vs hero back_to (all edit/preview pages) vs hero back_to plus a second back_to at page bottom (applications/show.html.erb:4,52)
- **cards** (admin): Explanatory Q&A text: ui_disclosure card with dl.instruction-list (jobs/index.html.erb:13; legacy_log/index.html.erb:5; mail_log/index.html.erb:13; request_logs/index.html.erb:25; sms_management/index.html.erb:7; shift_coverage_groups/index.html.erb:7; passkeys/index.html.erb:16) ; always-open ui_section with dl (permissions/edit.html.erb:6; permissions/new_art.html.erb:6; rbs_alerts/edit.html.erb:6) ; bare dl in a fieldset (oauth_clients/_form.html.erb:6) ; ui_callout_box :info prose (event_dates/index.html.erb:7; permissions/index.html.erb:7; rbs_alerts/index.html.erb:7; oauth_clients/index.html.erb:7)
- **cards** (common-a): Left-rule indented blocks: `border-s-2 border-base-300 ps-3` (surveys/_answers.html.erb:8) vs `border-l-2 border-line ms-1 pl-6` (_dashboard_step.html.erb:15)
- **cards** (common-a): Hand-made bordered boxes: `border border-body-subtle rounded p-2` (_timesheet_notes.html.erb:9), `border rounded p-2` (_trophies.html.erb:15), `border border-line rounded-lg p-3` (messages/_find_recipient_form.html.erb:15), `overflow-hidden rounded-lg border border-line` (messages/_compose.html.erb:7), `my-2 shadow-lg` (missing_requests/_entry.html.erb:3), `bg-default rounded-lg` (messages/_workspace.html.erb:48)
- **cards** (common-b): Record cards: card-standard div (schedule/_signed_up_row:6), box/box-accent div with border-l-4 (available_sign_ups/_slot:6-14), box box-default + rounded-xl border shadow-sm on a div (timesheet/_listing:4) or on the turbo-frame (timesheet/_listing_with_actions:4), ui_card (training_months:10, mentoring cards)
- **cards** (communication): Bordered text boxes: "lexxy-content text-body bg-default rounded-base border border-line p-3 max-h-64 overflow-y-auto" (announcements/_announcement.html.erb:43, surveys/show.html.erb:45,51); "rounded-base border border-line bg-default p-3" with max-h-96 (rbs_history/show.html.erb:74) or without (rbs_broadcasts/review.html.erb:46); "... p-3 my-1" (rbs_messages/index.html.erb:112); "text-body bg-default max-w-prose p-2" with no border (person_banners/_banner.html.erb:32)
- **cards** (css): Bordered container done three ways: card-standard (cards.css:24, flat, border-line), box + box-default (boxes.css:15,28, arbitrary 6px/4px shadow + border-line), table-container (tables.css:23, shadow-xs + border-base-300 + rounded-box); radii differ (card daisyUI box radius, box rounded-lg = 16px, table rounded-box = 0.75rem)
- **cards** (helpers-components): Card surfaces with differing radius/padding/shadow: ui_card "card-standard" + shadow-xs default (ui_card_helper.rb:42); ui_section "box box-default mb-4" with rounded-xl body (ui_section_helper.rb:5-7); action_box "bg-base-100 border border-line rounded-lg p-4" (action_box_helper.rb:10); ui_stat_box "border rounded-lg p-3" (ui_stat_box_helper.rb:55-61); ui_progress_box "rounded-xl border border-line shadow-sm px-4 py-2" (ui_progress_box_helper.rb:14); ui_accent_card "rounded-lg border-l-4 px-4 py-2 hover:shadow-sm" (ui_accent_card_helper.rb:73-81); ui_drill_down_row "box box-default px-4 py-2 my-2" (ui_drill_down_row_helper.rb:24); disclosure card "rounded-base border border-line" (ui_disclosure_helper.rb:15); filter panel "rounded-base border border-line p-4" (filter_bar_helper.rb:14); ui_data_block "rounded-base border border-base-300 shadow-inner p-3" (ui_data_block_helper.rb:20); hero stat tile "rounded-lg px-3 py-2 ring-1" (ui_hero_panel_helper.rb:18)
- **cards** (me): Help/FAQ blocks: ui_disclosure variant :card (feedback/index:28, tickets/sap:34) versus ui_section with dl (online_course/index:6, passkeys/index:48, tickets/provisions:90) versus ui_callout_box (tickets/_faqs_section:1)
- **cards** (me): Hand-rolled cards: bg-base-200 border-base-300 rounded-lg p-4 (me/announcements/_announcement:17); border border-line rounded-lg p-4 (announcements/index:11, tickets/_landing:152, tickets/ticket:62); article rounded-lg border-l-4 p-4 coloured by helper (agreements/index:30); card-standard p-3 (dashboard/_announcements_section:9); card-standard shadow-sm hover:shadow-md (vehicles_dashboard/_pvr_requests:6); border rounded-lg shadow-sm hover:shadow-md photo card (directory/index:40)
- **cards** (me): Small inset boxes: border border-line rounded p-2 (tickets/_item_details:14, tickets/_ticket_gift_conditions:2, identical); bg-default rounded p-2/p-3, with or without dark:bg-default (dashboard_tasks/_attend_alpha_shift_pending:4, _attend_cheetah_cub_shift_pending:4, _attend_training_pending:27); bg-default p-4 rounded-lg (vehicles_dashboard/_eligible_positions:16); bg-default p-3 rounded border (vehicles_dashboard/_pvr_requests:37); rounded-box bg-base-200 px-3 py-2 (operational_summary/_teams_and_positions:30)
- **cards** (person): Q&A explainer: ui_disclosure "About This Report" card with dl.instruction-list (mail_log, membership_history, scheduling/log, sessions, site_log, status_history, work_history) vs always-open dl.instruction-list in a section (awards/_form:8, backfill:11, missing_requests/edit:120, training/_moodle_account:62) vs plain p (missing_requests/new:15)
- **cards** (scheduling): Stat tile layout: ui_stat_row (12 pages, e.g. no_shows_report/position:21) vs hand grids of ui_stat_box (sandman_qualified/index:33, shift_lead/_status_band:27, event_stats/index:102,137)
- **cards** (scheduling): Below-minimum block: ui_section with "0" badge when staffed (shift_lead/_below_min:24) vs ui_disclosure with warning icon when short (shift_lead/_below_min:40)
- **cards** (shell-auth-profile): Boxed content: ui_section (most) vs div.card-standard p-4 + raw h2 heading-section (profile_photos/new.html.erb:24, crop.html.erb:27) vs ui_accent_card (sessions/forgot.html.erb:3) vs login-panel (sessions/*)
- **cards** (ticketing-bmid): Explanations block: ui_disclosure card "About This Report"/"How This Page Works" (10 pages) vs bare dl.instruction-list on the page (bmid/titles/index.html.erb:7) vs dl in a form fieldset (bmid/titles/_form.html.erb:4) vs ui_callout_box info (trs_export/index.html.erb:25, bmid/sanity_check/index.html.erb:5)
- **cards** (timesheets-shiftops): Instruction block: ui_disclosure "About This Report" variant: :card class: "my-4" (most timesheets pages, e.g. on_duty/index.html.erb:71) vs ui_disclosure "How This Page Works" (cruise_direction/index.html.erb:38, rollcall/sign_in.html.erb:64) vs always-open ui_section "How This Page Is Used" (rollcall/index.html.erb:27) vs inline ui_disclosure "Supported Line Formats" (bulk_sign_in_out/index.html.erb:37) vs standing ui_callout_box :info (timesheet_slot_repair/index.html.erb:23)
- **cards** (timesheets-shiftops): Card containers: ui_card + ui_card_body (on_duty/index.html.erb:136, cruise_direction/_pod.html.erb:17) vs <div class="card-standard p-4"> (correction_stats/_decision_card.html.erb:16, _top_list.html.erb:19) vs utility div "bg-base-100 border border-line rounded-base px-4 py-3" (payroll_export/index.html.erb:168)
- **cards** (training): ui_section framing: border: false (often with class "mt-6") on all mentoring pages (landing:69, verdicts:99, assignments/index:43); default bordered ui_section on every other training report
- **cards** (vc): Page help Q&A: ui_disclosure variant :card class my-4 (applications/index.html.erb:17, reserved_handles/index.html.erb:20, photos/index.html.erb:16, shiny_penny_report/index.html.erb:8, spigot_flow_report/index.html.erb:25) vs ui_section "How This Page Behaves" (create_prospectives/index.html.erb:92) vs ui_accent_card :info (application_import/index.html.erb:61) vs instruction-list dropped into a section/fieldset (edit_details.html.erb:16, handle_checker/index.html.erb:39, reserved_handles/_form.html.erb:6, upload.html.erb:107)
- **toasts-alerts** (common-b): Overlap warning: accent callout with divs (scheduling/_overlapping_sign_ups_list:3-19) vs non-accent callout class my-1 with p's (scheduling/_overlapping_sign_ups:4-25)
- **toasts-alerts** (css): Status-tinted containers in four families with different alpha steps: box-theme-* (boxes.css:36-93; success/error /5 bg /20 border, warning /10 bg full border, info /10 /30 with body ink), toast-* via daisyUI alert-soft (toasts.css:31-48), vc-progress-* (vc-applications.css:11-25; /10 bg /30 or /40 border), review-line / review-line-flagged (review-pane.css:44-50; /10 bg + border-s-4), login-beta warning 10%/26% (login.css:95-98)
- **toasts-alerts** (helpers-components): Notices done five ways: ui_callout_box "box box-{type}" or "box-accent box-accent-{type}" with p-2 mb-2 (notice_box_helper.rb:25-30); ui_alert_banner "box box-accent-{type}" with a bold header and an inner bg-base-100 body (notice_box_helper.rb:68-80); ui_accent_card border-l-4 tinted article (ui_accent_card_helper.rb:73-83); hour_not_counted_disclaimer plain <div class="my-2 text-sm">Note: (application_helper.rb:232); toasts (toast_helper.rb:34)
- **toasts-alerts** (helpers-components): ARIA role for notices: ui_callout_box defaults role="alert" for every type including success/info/secondary (notice_box_helper.rb:31); ui_alert_banner uses alert only for warning/danger/error and region + aria-label otherwise (notice_box_helper.rb:70-75); toasts use status for success/info and alert for warning/error (toast_helper.rb:16-24); ui_empty_state role="status" (notice_box_helper.rb:111); ui_accent_card no role
- **toasts-alerts** (js): Short confirmations: toast with 6s countdown bar (app/javascript/controllers/toast_controller.js:7) versus the clipboard's 2s in-control "Copied" tip with live-region announcement (app/javascript/controllers/copy_to_clipboard_controller.js:5, 53); onboarding appends a server-rendered toast template to #toast-container (app/javascript/controllers/onboarding_controller.js:155)
- **toasts-alerts** (me): Warnings/errors inside task text: p text-error font-bold or font-semibold + icon-error (dashboard_tasks/_attend_alpha_shift_pending:8, _attend_cheetah_cub_shift_pending:2, _attend_training_fail:3,12, _attend_training_no_show:2, _attend_training_pending:11, _dashboard_tickets:5,9,12,30, _missing_bpguid:26, _sign_nda_needed:2, _upload_photo_rejected:2, _vehicle_requests_denied:2, _verify_personal_info:4) versus ui_callout_box (dashboard_tasks/_attend_training_fail:14, _sign_up_for_alpha_shift_needed:1, _verify_timesheets:9)
- **toasts-alerts** (me): "Contact the Ranger Ticketing Team" for missing data: shared _contact_ticketing callout (tickets/gift:135, sap:69,104,134,151,175, sap_so:34,102, ticket:31,152) versus inline p/span "font-bold text-error" (tickets/_claimed_overview:27,33,42,167, tickets/_section_detail:37,162) versus html_safe strong text-error strings (_claimed_overview:134, _section_detail:138)
- **toasts-alerts** (mentoring): Personnel flag warning: shared partial common/unified_flagging/personnel_warning (potential_alphas/index.html.erb:36, post_season_summary/index.html.erb:36) vs inline ui_callout_box :error accent (alpha_status/index.html.erb:33-38, convert_prospectives/index.html.erb:48-53)
- **toasts-alerts** (mentoring): Callout heading: title: argument (alpha_mentor_assignments/index.html.erb:33,41,50,57,87) vs a leading <strong> sentence in the body (convert_prospectives/index.html.erb:28, alpha_signout/index.html.erb:38, alpha_pods/show.html.erb:21, alpha_mentor_assignments/index.html.erb:100)
- **toasts-alerts** (scheduling): Callout spacing: ui_callout_box wrapped in div.my-2 (position_credits/position:12, position_credits/timeline:8, position_credits/new:8, slot_copies/new:10, position_credit_copies/new:10,19, slots/index:16, slots/new:8, slots/_form:47) vs unwrapped with <p> body (early_arrivals/index:21,32) vs warning as red paragraph (slots/_link_fieldsets:20)
- **toasts-alerts** (teams-people): callout headline: title: param (_results:14, special_teams_hours:109, _status_notice:7, _privacy_notice:6, check:29) / inline <strong> lead (bulk pages, roster, position_records/_form); icon_type :solid (most) vs omitted (search:21, bulk_lookup:13, _privacy_notice:6, special_teams_hours:108)
- **toasts-alerts** (teams-people): bulk-apply outcome: on-page callout with three-way variant from helper (bulk_teams/index.html.erb:14) / two-way inline ternary (bulk_positions/index.html.erb:11) / redirect with flash (roster_management controller line 55) / callout list (position_sanity_checker/_results.html.erb:11, status_change_recommendations/show.html.erb:21,30)
- **toasts-alerts** (ticketing-bmid): Skipped-items list: partial ticketing/trs_export/_skipped.html.erb:8 vs duplicate partial bmid/export/_skipped.html.erb:6 vs inline copy bmid/export/unsubmit.html.erb:42-49
- **toasts-alerts** (timesheets-shiftops): Action outcome after POST: in-page ui_callout_box (timesheet_slot_repair/_results.html.erb:11, bulk_sign_in_out/index.html.erb:22) vs toast streams (cruise_direction controllers, rollcall controller)
- **empty-loading** (admin): Lazy frame placeholder: shared/frame_spinner (online_courses/enrollment.html.erb:10; moodle_catalog.html.erb:10; sms_management/index.html.erb:95,132) ; p "Loading preview…" (documents/index.html.erb:82)
- **empty-loading** (common-a): Missing-value dash: literal "—" (assets/_table.html.erb:27,48,61; bulk_upload/preview.html.erb:71; rbs/_delivery_summary.html.erb:34-40) vs value_or_dash (assets/_checkout_history.html.erb:25; ticketing_maintenance/_results_table.html.erb:36,39) vs muted span "—" (survey_report_helper.rb:33)
- **empty-loading** (common-a): Lazy-frame placeholder three ways: shared/frame_spinner (messages/_list_frame.html.erb:22); plain <p class="text-body my-2">Loading…</p> (unified_flagging/_detail_frame.html.erb:17); plain <p class="my-2">Loading message…</p> (mail_log/_table.html.erb:57)
- **empty-loading** (common-a): Empty text: ui_empty_state (e.g. provisions/_list.html.erb:37, messages/_pane.html.erb:32, unified_flagging/index.html.erb:17) vs div `mt-4` plain text (missing_requests/index.html.erb:30-32) vs div `.empty-state text-lg` (_trophies.html.erb:4) vs <p> in three colours (unified_flagging/_history.html.erb:50, 102, 130, 139) vs p me-muted (provisions/_form.html.erb:67) vs span italic muted (_years_breakdown.html.erb:17, ticketing_maintenance/_results_table.html.erb:33)
- **empty-loading** (common-b): Empty list text: ui_empty_state (schedule/index:121,135; timesheet/_listing:27; work_history/_matrix:5; mentoring/index:88); red text div (available_sign_ups/index:33, show:75,90); bare or bold text (schedule/_people_signed_up:42,56,73,98; training/_education_detail:22,40); not handled (work_history drill-downs, mentoring mentors list)
- **empty-loading** (communication): Empty value: content_tag(:em, "none on file") (alerts/edit.html.erb:70); tag.span("None given.", class "italic text-stone-muted") (surveys/show.html.erb:46,52); tag.i("empty message") (rbs_messages/index.html.erb:113); "—" plain (rbs_helper.rb:141,176; rbs_history/show.html.erb:87,89) vs "—" in span text-stone-subtle (rbs_helper.rb:239,364,451,495,517)
- **empty-loading** (communication): Filtered-list empty states: two branches (none at all vs none matched) in announcements/index.html.erb:65-70, person_banners/index.html.erb:55-60, rbs_messages/index.html.erb:71-77 vs one "matched filters" message in rbs_history/index.html.erb:56; ui_empty_state with icon (most) vs without icon (rbs_history/show.html.erb:110, rbs_history/retried.html.erb:22, rbs_broadcasts/_position_checkboxes.html.erb:19)
- **empty-loading** (css): Empty state styled five ways: .empty-state dashed box (empty-state.css:5), ac-empty centred muted text (autocomplete.css:158), photo-board-empty flex column text-xl (photo-board.css:141), report-empty-row italic body-subtle (trainers-report.css:212), alpha-pod-empty italic #888 (alpha-sheets.css:330)
- **empty-loading** (helpers-components): Empty or missing values: value_or_dash "—" (application_helper.rb:85); person_display_name blank "—" (link_helper.rb:36); none_stated <i class="text-stone-muted">None stated</i> (application_helper.rb:81); year_range <span class="text-stone-muted">none</span> (year_helper.rb:9); _years_breakdown <span class="text-stone-muted italic">none</span> (common/_years_breakdown.html.erb:17,34); ui_section badge "0" shown as "none" (ui_section_helper.rb:129); ui_empty_state div.empty-state for lists (notice_box_helper.rb:106); ui_table has no empty case
- **empty-loading** (helpers-forms): Missing value shown as "Not set" badge (event_date_window, app/helpers/event_dates_helper.rb:17) vs "Not specified" text (gender_format, app/helpers/gender_helper.rb:9-11) vs empty string (pronouns_format app/helpers/pronouns_helper.rb:19, all date formatters) vs "invalid date [x]" (full_datetime_format date_time_helper.rb:126,131)
- **empty-loading** (hq-assets): Empty list inside a table: colspan row wrapping ui_empty_state (hq/shift_manage/_asset_table.html.erb:42-47, _pogs.html.erb:119-125) vs ui_empty_state instead of the table (hq/assets/index.html.erb:28, asset_management/records/type.html.erb:114) vs plain <p> (quartermaster/alpha_shirts/index.html.erb:53) vs "- none -" italic div (helpers/vehicles/paperwork_helper.rb:157) vs bare "none" (helpers/vehicles/registry_helper.rb:189) vs not handled (quartermaster/swag/index.html.erb:19, potential_shirts/index.html.erb:75)
- **empty-loading** (hq-assets): Empty state inside border:false ui_section: wrapped in div "px-4 pb-2" (quartermaster/alpha_shirts/index.html.erb:102, events_rangered:106, potential_shirts:119, potential_swag:57,118, swag_distribution:56) vs unwrapped (pogs/dashboard/_top_list.html.erb:13, pogs/dashboard/index.html.erb:94)
- **empty-loading** (js): Loading indicators: autocomplete builds a "Searching…" row with fa-spinner animate-spin and a 10s slow message (app/javascript/controllers/autocomplete_controller.js:887); mega-menu and search-bar use server-rendered callouts with a "slow" kind after 10s (app/javascript/controllers/mega_menu_controller.js:106); camera/photo-upload unhide a server-rendered loading target; link-options, stream-nav, tabs (remote) and pod-people show nothing while fetching
- **empty-loading** (me): Submit busy label: submit_button data turbo_submits_with "Submitting…" (surveys/show:82) versus f.submit data pending_label "Waiting for Your Device…" (passkeys/new:55)
- **empty-loading** (me): Empty states: ui_empty_state (awards/index:18, feedback/index:53,56, menu/_content:48,55,122, operational_summary/_certifications:9, _teams_and_positions:16,45, passkeys/index:44, team_documents/show:18, tickets/_off_season:25, vehicles_dashboard/_pvr_requests:2); hand-rolled dashed box (agreements/index:57-63 with status_medallion; announcements/index:46-52 with inbox icon); ui_callout_box :secondary/:info (tickets/gift:23, provisions:27, vehicle_pass:18, ticket:158, sap_so:30); plain text (tickets/review:45, directory/index:32, dashboard_tasks/_no_things_at_the_moment:1); red alert text (dashboard_tasks/_dashboard_tickets:30)
- **empty-loading** (mentoring): Absent cell value: muted "None" span (alpha_acceptance_sheets/index:111, alpha_schedule/show:101, alpha_mentor_assignments/index:221), muted &mdash; (shift_report/_people_table:34), bare &mdash; and literal "—" (alpha_mentor_assignments/print_sheet:47,55), muted "No" (alpha_schedule/show:96), ui_badge "no" :secondary (alpha_mentor_assignments/index:236), <em>None</em> (info_sheet:101,116)
- **empty-loading** (mentoring): Empty list/section: ui_empty_state (most pages) vs p.text-stone-muted inside ui_section (alpha_status/index:97, post_season_summary/index:100, potential_alphas/index:84-87, shift_report/_group_positions:8,27) vs error-coloured p "No one matched" (rosters/_dialog:62)
- **empty-loading** (person): Empty list: ui_empty_state (most pages); plain p "No X notes yet." beside ui_empty_state in the same partial chosen by permission (unified_flagging/_team_notes:6 vs 8); p "No training notes." (_training_notes:48); bare text (vehicles/_eligibility_list:41); div "text-error" (missing_requests/edit:89); warning callout for pre-2018 (timesheets/log:15)
- **empty-loading** (person): Imported/no-author marker: <i class="me-muted">— imported —</i> (certifications/show:27); span "me-muted" "* imported *" (status_history/index:48); <i>*imported*</i> (unified_flagging/_note:14, _training_notes:40); plain "*imported*" (_team_notes:41)
- **empty-loading** (person): Missing value placeholder: <i class="text-stone-muted">None</i> (_summary_strip:25, _contact_details:9); span "text-stone-muted italic" (permissions/edit:59, callsigns/edit:113); em dash (awards/_awards_table:32, certifications/show:12, scheduling/_log_changes:4, site_log_helper:52); hyphen "-" (swag/index:56, missing_requests/show:25, timesheets/_log_table:17, mail_log/index:53, swag_helper:13); "Never"/"Not yet"/"Unknown" words (passkeys/index:45, tickets_provisions/show:27,35)
- **empty-loading** (scheduling): Shift lead empty roster: ui_empty_state on screen (shift_lead/_roster:129-133) vs plain <p> on paper (shift_lead/print_sheet:163-169)
- **empty-loading** (shell-auth-profile): Spinner: shared/_frame_spinner.html.erb:3 and application/_mega_menu.html.erb:43 (border-b-2 border-primary div, duplicated inline) vs profile_photos/new.html.erb:197,255 (border-[3px] border-t-transparent div) vs shared/_autocomplete.html.erb:49 and sso/hand_back.html.erb:11 (fa_icon spinner animate-spin)
- **empty-loading** (shell-auth-profile): Empty text "No languages have been stated.": profile/_languages.html.erb:33 (plain muted span) vs profile_languages/index.html.erb:50 (ui_empty_state); other profile empties via none_stated (_camp:11, _clothing:10, _mailing_address:25) vs italic spans (_identity_info:29,37,47; _alerts:18) vs <i> (show:99,107)
- **empty-loading** (ticketing-bmid): Empty-value dash: value_or_dash (records.html.erb:56, provisions/index.html.erb:61, many) vs span "text-stone-muted" &mdash; (_summary_value.html.erb:13, _summary_special.html.erb:7, _summary_notes.html.erb:11) vs literal "—" text (bmid/manage/_table.html.erb:43, _edit_grid.html.erb:105, _showers_cell.html.erb:19, export/_selection_table.html.erb:48-49, export/create.html.erb:65, tickets_provisions_helper.rb:85)
- **empty-loading** (ticketing-bmid): Empty state on results pages: ui_empty_state + back button_row (unsubmit_provisions/results.html.erb:34-38, maintenance/preview.html.erb:28-32) vs ui_empty_state alone (maintenance/results.html.erb:33, bmid/titles/apply.html.erb:29) vs ui_callout_box warning (bmid/export/unsubmit.html.erb:34)
- **empty-loading** (timesheets-shiftops): Section-level empty state as ui_empty_state (shift_operations/payroll_missing_id/_section.html.erb:34, cruise_direction/people/_dialog.html.erb:54) vs plain muted/italic <p> (timesheets/early_late_checkins/_section.html.erb:19,24, timesheets/correction_stats/_top_list.html.erb:23, correction_stats/_decision_card.html.erb:60, cruise_direction/people/_dialog.html.erb:32, cruise_direction/_pod.html.erb:51)
- **empty-loading** (training): "No notes" text: span "text-stone-muted italic" "no notes" in all_notes/_notes.html.erb:6; span "No notes yet." in sessions/_trainee_card.html.erb:59; <p class="text-stone-muted italic mb-2"> in sessions/scores/_dialog.html.erb:56
- **empty-loading** (training): No-filter-match empty state icon: magnifying-glass in mentees:74, all_notes:73, trained_no_work:81, online_course_progress:74, untrained_people:90; filter icon in mentoring/verdicts:103, multiple_shifts:81
- **empty-loading** (training): Empty dash: value_or_dash in verdicts, multiple_shifts, _other_shifts, online_course_progress; literal "—" span text-stone-muted in all_notes_helper.rb:29, untrained_people/index.html.erb:120, work_histories/show.html.erb:114; plain "—" cell in capacity/index.html.erb:93; "None yet" text in mentoring/landing/index.html.erb:127
- **empty-loading** (training): Nothing found shown in error colour vs neutral: <p class="text-error font-semibold"> in rosters/_dialog.html.erb:83, graduations/_dialog.html.erb:78, sessions/_session_table.html.erb:57; ui_empty_state elsewhere (e.g. mentees/index.html.erb:74)
- **empty-loading** (vc): Missing-value text: content_tag span text-stone-muted "none stated"/"not stated" (_rail, _personal_info_stage, _paragraph_stage) vs none_stated helper (bpguid/index.html.erb:40,55,59,65) vs tag.i text-stone-muted (bpguid/index.html.erb:67) vs bare <i>unknown</i>/<i>never</i>/<i>none given</i> (photos_review/_attribution.html.erb:4,6; _photo.html.erb:90; info.html.erb:23,38,46) vs text-stone-subtle span (bpguid/_results.html.erb:76) vs text-base-content/70 (thank_you_cards/index.html.erb:66) vs value_or_dash (reserved_handles, create_prospectives, maintenance)
- **empty-loading** (vc): Empty list: ui_empty_state (most pages) vs plain <p class="text-stone-muted"> (applications/_notes_list.html.erb:7) vs muted span inside a label/value row (_callsign_stage.html.erb:19,94) vs bold <div class="font-semibold"> (photos_review/_photo.html.erb:78) vs success callout (photos_review/index.html.erb:8) vs section omitted (application_import/_failures_table.html.erb:6)
- **typography** (admin): Detail block label: div log_heading_class "mb-2 text-sm font-semibold text-heading" (action_logs/_table.html.erb:57; error_logs/index.html.erb:81; jobs/_job.html.erb:25; request_logs/index.html.erb:157) ; div "mb-1 text-sm font-semibold text-heading" (permissions/_row.html.erb:37) ; div "font-semibold text-heading" (rbs_alerts/_group.html.erb:21) ; ui_subheading (sms_management/twilio.html.erb:66)
- **typography** (admin): List count line: ui_section title pluralize (documents/index.html.erb:19; event_dates/index.html.erb:27; oauth_clients/index.html.erb:44; shift_coverage_groups/index.html.erb:28) ; div "text-lg my-2" (online_courses/index.html.erb:30) ; p "mb-2 text-base text-body" (settings/index.html.erb:25) ; filter_bar count: (jobs/index.html.erb:38; passkeys/index.html.erb:26) ; p.mb-3 strong (bug_reports/index.html.erb:10) ; ui_pager summary (action_logs, error_logs, legacy_log)
- **typography** (admin): Live table text style: set once on tbody (action_logs/_live.html.erb:48) ; set per cell (request_logs/_live_rows.html.erb:8-12)
- **typography** (common-a): Sub-headings: raw <h3 class="heading-title"> with and without text-heading (_timesheet_confirm.html.erb:14, 98; _trophies.html.erb:2; surveys/_question.html.erb:39), raw <h4 class="heading-title"> (unified_flagging/_history.html.erb:46,112), raw <h2 class="heading-section"> (_dashboard_section_header.html.erb:13), utility divs `text-xl font-semibold` (missing_requests/_form.html.erb:3), `font-semibold` (_event_summary_counts.html.erb:35), p `font-medium text-heading` (provisions/_form.html.erb:39)
- **typography** (common-b): Credits formatting: credit_format (schedule/signup_summary, schedule/_signed_up_row:48, shift_manage/_on_duty:9) vs "%.2f" literal (work_history/entire_year:13,34; position_summary:13,32; position_all:37)
- **typography** (common-b): Long-word wrapping: "wrap-break-word" (mentoring/index:60) vs "break-words" (mentoring/index:73, mentoring/_mentee_card:18)
- **typography** (communication): Group/sub headings by hand: div "font-semibold text-heading mb-1/mb-2" (alerts/_alert_group.html.erb:9,38; surveys/show.html.erb:42,48; _position_checkboxes.html.erb:22) vs <h3 heading-title text-heading mb-1> (rbs_history/show.html.erb:69,73; rbs_broadcasts/review.html.erb:33,42)
- **typography** (communication): Card-list headings: <h2 heading-section> in announcements/_announcement.html.erb:10 vs <h3 heading-title> in person_banners/_banner.html.erb:9; both pages have no h2 above the cards except via ui_section in person_banners/index.html.erb:64,70
- **typography** (communication): hero_panel description: description: kwarg (mail_templates/index.html.erb:5, rbs/index.html.erb:10) vs panel.description block (announcements/index.html.erb:3, person_banners/index.html.erb:3, rbs_broadcasts/new.html.erb:12); title via panel.title block only in surveys/index.html.erb:4
- **typography** (communication): Count in a section heading: in the title text "(n)" (rbs_phone_numbers/index.html.erb:60,66; rbs_history/show.html.erb:102; rbs_broadcasts/review.html.erb:65; sent.html.erb:24) vs ui_section badge: (surveys/_group.html.erb:5) vs pluralized title (mail_templates/index.html.erb:13, surveys/index.html.erb:36)
- **typography** (css): Heading ink and emphasis aliases: text-heading (theme token) and text-heading-primary (text-colors.css:34) both = --color-heading; text-body and text-stone-emphasis (text-colors.css:49) both = --color-body
- **typography** (css): Heading sizes set per component: heading-section text-base/lg:text-lg (headings.css:11), modal-title-text text-xl (modals.css:14), form legend text-lg (forms.css:18), mega-menu-panel-title text-lg muted (mega-menu.css:85), driver-popover-title text-lg (driver.css:24), login-title 1.625rem (login.css:79), login-doors-title text-lg (login.css:342), lexxy h1 text-xl / h2 text-lg (lexxy.css:125,129), photo-board text-3xl (photo-board.css:41,101)
- **typography** (css): Muted/secondary ink spelled five ways: text-stone-muted utility (text-colors.css:58), me-muted alias (hero-panel.css:17), text-base-content/60 (progress.css:24, vc-applications.css:28), text-body-subtle (login.css:88,349, while text-colors.css:19-23 calls it a retired spelling), text-stone-subtle and text-stone-icon (text-colors.css:66,71, identical declarations)
- **typography** (helpers-components): Headings by eight treatments: page_title <h1 class="text-3xl font-normal"> (page_layout_helper.rb:10); hero_panel <h1|h2 class="text-2xl|text-xl font-semibold text-heading"> (ui_hero_panel_helper.rb:9-12); ui_section_title <div role="heading" aria-level="2" class="heading-section text-heading-primary"> (ui_section_helper.rb:62-64); ui_progress_box <h2 class="heading-section text-heading"> (ui_progress_box_helper.rb:90); ui_subheading <h3 class="heading-title text-heading"> (ui_section_helper.rb:42); modal title <h3 class="modal-title-text"> (modal_helper.rb:181); action_box <h3 class="heading-title text-heading mb-1"> (action_box_helper.rb:70); ui_callout_box title <h4 class="my-1 heading-title"> (notice_box_helper.rb:55); ui_card_section and sidebar_section <h6> (ui_card_helper.rb:88, sidebar_helper.rb:113); ui_card_title <div class="text-lg text-heading text-center p-2"> with no heading role (ui_card_helper.rb:78)
- **typography** (helpers-forms): Date/time output wrapped in a titled <span data-local-time-target> (datetime_format, zoned_datetime_format via format_date, date_time_helper.rb:257-262) vs plain strings with no span/tooltip (log_time_format, full_datetime_format, short_datetime_format, mdy_format, wday_month_day_format, month_day_format, ymd_format, date_time_helper.rb:115-239)
- **typography** (hq-assets): Result counts: filter_bar count: (most filtered pages) vs div "text-lg" line (asset_management/records/index.html.erb:26, quartermaster/freaking_years/index.html.erb:29) vs plain div/p sentence (hq/shift_manage/_pogs.html.erb:63, hq/site_registration/_radios_step.html.erb:25)
- **typography** (hq-assets): Page titles: hero_panel on every page in scope except hq/site_registration/show.html.erb:9 (raw <h2 class="heading-section text-heading mb-4">); hero title set via title: (asset_management/records/edit.html.erb:2) vs panel.title block (quartermaster/swag/edit.html.erb:4, hq/training/index.html.erb:6, hq/timesheets/event_summary.html.erb:6) vs panel.title with flex class override (hq/shared/_header.html.erb:6)
- **typography** (me): Page title on /me: hero_panel (most pages, dashboard/_welcome_hero_stats:1) versus raw h1 "text-2xl font-bold text-heading mb-4" (dashboard/index:4)
- **typography** (me): Sub-headings: raw h3 heading-title (announcements/_announcement:27, tickets/_landing:156, gift:56, ticket:65, operational_summary/_training:39, vehicles_dashboard/*); h3/h4 "text-base font-semibold" (agreements/index:32, vehicles_dashboard/_pvr_requests:10); h6 font-semibold (vehicles_dashboard/_eligible_positions:8); div "font-semibold text-heading" (operational_summary/_provisions_and_radios:5, _teams_and_positions:14,41); p/b font-semibold labels (dashboard_tasks/_after_event_status_advisory:4, _attend_alpha_shift_pending:17, _missing_bpguid:8); ui_subheading (feedback/_survey:17)
- **typography** (mentoring): Print sheet title: _sheet_masthead partial (signup_sheet.html.erb:20, apparel.html.erb:18) vs hand copy (alpha_pods/print_sheet.html.erb:42-48) vs h1.alpha-info-title (info_sheet.html.erb:39) vs h1 "text-2xl font-semibold" (alpha_mentor_assignments/print_sheet.html.erb:22) vs acceptance-masthead/acceptance-title divs (print_sheets.html.erb:30-35)
- **typography** (person): "Showing N items" count line: p "mb-3 me-muted" with period (applications/index:26, certifications/index:20, status_history/index:28, provisions/_section:42); div "mb-2 text-base-content/80" no period (pogs/index:20, swag/index:36); div "me-muted" (tickets_provisions/show:62); plain span (timesheets/index:158)
- **typography** (person): Muted secondary text through three tokens: text-stone-muted (_summary_strip, callsigns/edit:54, memberships/*, timesheets/*), me-muted (access_documents/_form:58, bmids/show:55, applications/index:26, status_history:48), text-base-content/70 or /80 (agreements/index:31, pogs/index:20, swag/index:36)
- **typography** (person): Hero title set by title: keyword (agreements, applications, assets, awards/index, certifications/index, intake_notes, mail_log, membership_history, memberships/edit, permissions/edit, scheduling/log, unified_flagging, work_history) vs panel.title block (most others); separators "—" literal vs &mdash; entity
- **typography** (scheduling): Index count line: div "my-4 text-lg" (sandman_qualified/index:22, no_shows_report/index:18, flake_report/index:18, shift_signups/index:25) vs div "text-lg" no margin (position_credits/index:22, slots/index:36) vs filter_bar count: (schedule_by_callsign/index:25, shift_drop_report/index:39) vs footer p "mt-2 text-base text-body" (no_shows_report/position:62, flake_report/position:86, shift_drop_report/position:80)
- **typography** (scheduling): Missing-value placeholder: value_or_dash (schedule_by_position/position:58, schedule_by_callsign/person:59, shift_signups/position:76, shift_coverage_helper:50) vs literal "—" (shift_signups/index:82, schedule_by_callsign_helper:51) vs "-" (shift_lead/_roster:58,59,64, shift_lead_helper:190) vs "n/a" (event_stats/index:101)
- **typography** (scheduling): Hero title/description: title: kwarg + panel.description block (report pages) vs panel.title block + description: kwarg (position_credits/position:1-4, edit, new, slots/position:1-4, edit, new, slot_copies/new:3-6, position_credit_copies/new:3-6); slot_bulk_edits/new mixes panel.title with panel.description
- **typography** (scheduling): Meta-line separators: " • " (schedule_by_position_helper:22-23, schedule_by_callsign_helper:14-15) vs " · " / &middot; (sandman_qualified/index:23-26, no_shows_report/index:20, shift_drop_report/index:48, flake_report_helper:14, slots/position:92)
- **typography** (scheduling): Secondary line in a cell: div "text-sm text-stone-subtle" (schedule_by_position/position:58) vs div "text-stone-muted" (slots/position:92) vs span "block text-base text-stone-muted mt-1" (no_shows_report/position:52) vs div "text-sm text-stone-muted" (early_arrivals/index:192) vs div "text-stone-subtle" (slot_copies/new:123)
- **typography** (scheduling): Dates in admin tables: strftime(MONTH_DAY_TIME_YEAR) (position_credits/position:89-90, slot_copies/new:122, position_credit_copies/new:81) vs datetime_format (position_credits/timeline:43, slot_bulk_edits/new:102, slots/position:90) vs slot_shift_time (no_shows_report/position:47, schedule_by_callsign/person:56)
- **typography** (shell-auth-profile): Door-page heading: sessions/_heading.html.erb:6 (h1 text-3xl sm:text-4xl font-bold) vs sessions/new.html.erb:12 (h1.login-title custom CSS) vs register/show.html.erb:9 (hero_panel) on the public door pages
- **typography** (teams-people): section heading: ui_section (most pages) / raw section > div.border-b > h2.heading-section (position_sanity_checker/index:52,68) / ui_section_title class mt-4 (_language_group:5, _country_group:4)
- **typography** (teams-people): result-count summary line: div.text-lg (roster_management/index:6, team_documents/index:12, certificates_report/index:25, people_by_status/index:12, people_by_status/show:12, status_change_recommendations/index:35, languages_known/index:56) / filter_bar count: (membership_report/index:31, position_grants/index:31, team_records/index:26) / p.text-base.text-body (membership_report/show:42, position_grants/show:51) / p.text-body.font-semibold (search/index:159) / plain p (special_teams_hours/index:118)
- **typography** (ticketing-bmid): hero_panel title: title: kwarg (trs_export/index.html.erb:10, access_documents/records.html.erb:6, maintenance/index.html.erb:10, expiring, unclaimed, claimed, sap_candidates, provisions, bmid/titles/index.html.erb:3, bmid/sanity_check/index.html.erb:2, bmid/manage/index.html.erb:5) vs panel.title block (statistics/index.html.erb:17, access_documents/index.html.erb:14, maintenance/preview.html.erb:10, bmid/badges/edit.html.erb:18); description by kwarg vs panel.description block mixed the same way
- **typography** (ticketing-bmid): Count headline above a ledger: div "text-lg my-4" (ticketing/unsubmit_provisions/results.html.erb:28, ticketing/trs_export/mark_submitted.html.erb:30, ticketing/maintenance/results.html.erb:27) vs p "text-lg my-4" (ticketing/maintenance/preview.html.erb:34) vs ui_stat_row (bmid/export/create.html.erb:17, bmid/export/unsubmit.html.erb:14, bmid/titles/apply.html.erb:14)
- **typography** (timesheets-shiftops): Missing value in tables: literal "—" (timesheet_by_position/position.html.erb:92, timesheets_by_callsign/person.html.erb:112, sanity_checker/_entries.html.erb:68, correction_requests/index.html.erb:98, bulk_sign_in_out/preview.html.erb:115) vs value_or_dash (bulk_sign_in_out/preview.html.erb:105,118, mass_signout/index.html.erb:110) vs muted italic words "Not recorded"/"No phone"/"None given" (forced_shift_start/index.html.erb:109, timesheet_unconfirmed/_group.html.erb:31, correction_requests_helper.rb:45)
- **typography** (timesheets-shiftops): Text separators: " · " middot (on_duty_helper.rb:65, early_late_checkins/_section.html.erb:62, rollcall_helper.rb:153, payroll_export_helper.rb:57, cruise_direction/_pod.html.erb:84) vs " • " bullet (timesheet_by_position_helper.rb:8, timesheet_totals_report_helper.rb:8, timesheets_by_callsign_helper.rb:11)
- **typography** (timesheets-shiftops): Section headings: ui_section (forced_shift_start, early_late_checkins/_section, payroll_missing_id/_section) vs hand-built border-b div + <h2 class="heading-section text-heading"> (sanity_checker/index.html.erb:55-57) vs <h2 class="heading-section"> inside a ui_card (on_duty/index.html.erb:138, cruise_direction/_pod.html.erb:29) vs <h2 class="heading-section mt-4 mb-2"> without text-heading (bulk_sign_in_out/_formats.html.erb:31) vs <h3 class="heading-title text-heading"> in card-standard divs (correction_stats/_decision_card.html.erb:18, _top_list.html.erb:20)
- **typography** (training): Result count: filter_bar count: "Showing N of M" in filtered reports; <p class="mb-4">Showing N ...</p> in capacity/index.html.erb:57 and trainer_attendance/index.html.erb:42; ui_section badge count in multiple_enrollments, surveys, completed_training/show
- **typography** (vc): Fieldset legends: <legend class="font-medium mb-2"> (applications/edit_details.html.erb:21) vs <legend class="mb-2 text-base font-medium text-heading"> (thank_you_cards/index.html.erb:32) vs f.fieldset helper (reserved_handles/_form.html.erb:5, upload.html.erb:106, photos_review/reject_dialog.html.erb:10)
- **typography** (vc): Result count line: <p class="mb-0 text-stone-muted"> (applications/index.html.erb:84), <div class="text-lg mb-2"> (shiny_penny_report:22, spigot_flow_report:55), <p class="text-lg my-4"> (maintenance previews:18), <div class="text-lg my-4"> (maintenance reset pages:19), <p class="mt-3"> (reserved_handles/upload.html.erb:61), <p class="mb-3"> (application_import/_results.html.erb:65), filter_bar count: (reserved_handles/index.html.erb:55, thank_you_cards/index.html.erb:24), ui_section title (applications/search.html.erb:18)
- **color** (admin): Muted text: text-stone-muted (permissions/_row.html.erb:22; settings/index.html.erb:55; request_logs/index.html.erb:168; action_logs/_table.html.erb:45) ; text-stone-subtle (enrollment_roster.html.erb:42; moodle_catalog_courses.html.erb:25; shift_coverage_management_helper.rb:20; salesforce_query_helper.rb:58) ; me-muted (documents/body.html.erb:6)
- **color** (css): Dark-mode selectors mixed: [data-theme="dark"] only (buttons.css:13, badges.css:17,31), .dark only (hero-panel.css:52, credit-chart.css:27), both (application.css:225, login.css:35), dark: variant (hero-panel.css:12)
- **color** (helpers-components): Status colour sets restated per helper: SeverityStyleHelper text "text-error font-semibold" (severity_style_helper.rb:14); ui_label_value variants text-success/text-warning/text-error/text-primary/text-info (ui_label_value_helper.rb:5-12); ui_stat_box text-success etc. plus bg-*/10 border-*/30 (ui_stat_box_helper.rb:16-21); ui_accent_card bg-*/10 border-*/30 but border-info at full opacity (ui_accent_card_helper.rb:18-35); sidebar badge bg-*/10 border-*/30 (sidebar_helper.rb:41); table ROW_STATES !bg-success/10, !bg-base-300 (table_helper.rb:54)
- **color** (helpers-forms): Status colour on icons: custom classes icon-success / icon-warning (agreement_helper.rb:65-66, shirt_helper.rb:16) vs Tailwind text-secondary (agreement_helper.rb:67) vs text-error / text-stone-muted utilities in the form builder (form_helper.rb:49-50, 790)
- **color** (hq-assets): Status lines carried by colour: raw heading tags coloured text-success/error/warning (hq/site_registration/_radio_authorization_status.html.erb:10-35, show.html.erb:26,30) vs <p>/<div> text-success/error (hq/site_registration/_radios_step.html.erb:16,30, hq/shift_manage/_verification.html.erb:59-67, index.html.erb:143) vs <strong class="text-error"> (hq/shift_manage/_pogs.html.erb:15,20) vs ui_callout_box (vehicles/registry/permit.html.erb:13-21) vs ui_badge (hq/shift_manage/_verification.html.erb:48)
- **color** (mentoring): Status as coloured text with icon (alpha_acceptance_sheets/index:128-139, post_season_summary_helper:150-156, intake_helper:103-108, alpha_mentor_assignments/index:270,283) vs ui_badge for the same kind of state (alpha_signout_helper:14-17, alpha_schedule/show:94)
- **color** (person): Inactive marker: ui_badge "inactive" :error xs (memberships/_team_card:36) vs span "text-error font-medium" "[inactive]" (memberships/_position_checkbox:24)
- **color** (person): Same review state, different colour: timesheet "Correction Requested" :error and "Correction Rejected" :warning (timesheets_helper:85,87) vs missing request "Review needed" :warning and "Request rejected" :error (timesheets_helper:105,109)
- **color** (scheduling): Alarm text: span "text-error font-semibold" (early_arrivals/index:195, early_arrivals_helper:90,113) vs span "font-bold text-error" (shift_lead/_below_min:58, shift_lead_helper:188,247) vs span "text-error" (schedule_by_position_helper:65) vs ui_badge :error (shift_signups/position:80, flake_report_helper:5) vs p "text-error" (slots/_link_fieldsets:20)
- **color** (teams-people): muted text class: text-stone-muted (throughout) / text-stone-subtle (roster_management_helper.rb:210) / me-muted (languages_known_helper.rb:15,49)
- **color** (ticketing-bmid): "Missing" arrival alarm: shared partial ticketing/access_documents/_summary_missing.html.erb:5 vs inline copy ticketing/access_documents/records.html.erb:66-68 (no whitespace-nowrap)
- **color** (training): Pending status badge: :secondary hourglass-half in sessions_helper.rb:13; :warning clock in trainer_attendance/_session_line.html.erb:10; trainer attendance on the session page is a plain select_tag (sessions/_trainer_section.html.erb:39)
- **spacing** (common-a): Callout spacing set by caller class: `mt-4` (_event_summary_breakdown.html.erb:62, _event_summary_counts.html.erb:34), `my-4` (unified_flagging/_personnel_warning.html.erb:10), `mt-3` (unified_flagging/_review_pane.html.erb:34)
- **spacing** (common-b): Content width wrappers: lg:w-3/4 (available_sign_ups/index:12), max-w-[900px] (available_sign_ups/show:5), lg:w-7/10 (qualifications/index:61), none (schedule, timesheet)
- **spacing** (communication): Page wrappers: bookmarks/show.html.erb:15 max-w-[90rem] vs bookmarks/not_found.html.erb:6 max-w-lg px-4 pt-16; both raw h1 "text-xl font-semibold" with different spacing (px-3 pt-3 vs mb-3)
- **spacing** (communication): Button row spacing: wrapped in div "my-4" (surveys/index.html.erb:28, surveys/show.html.erb:58) vs button_row class: "mt-4" (rbs_messages/index.html.erb:62) vs bare button_row (most pages)
- **spacing** (hq-assets): Wrapper around page-level button_row: div "my-4" (asset_management/records/index.html.erb:12, quartermaster/swag/index.html.erb:11, radio_assets:65) vs "mb-4" (vehicles/registry/index.html.erb:23, asset_management/records/show.html.erb:7) vs button_row class: "mb-2"/"mt-4" (hq/shift_manage/_pogs.html.erb:47, hq/site_registration/_radios_step.html.erb:50)
- **spacing** (mentoring): Callout margins: class "my-4" (most pages, e.g. alpha_schedule/show.html.erb:22), "mb-4" (alpha_signout/index.html.erb:166, alpha_pods/_board.html.erb:26), "mb-3" (alpha_pods/people/new.html.erb:21), none (alpha_mentor_assignments/index.html.erb:33-93,144; rosters/_blocked.html.erb:22)
- **spacing** (ticketing-bmid): Vertical spacing around a button_row: button_row class: "my-4" (bmid/titles/index.html.erb:12, bmid/export/create.html.erb:40, bmid/export/unsubmit.html.erb:73) vs wrapper div "my-4" (bmid/titles/apply.html.erb:19, bmid/export/index.html.erb:39, bmid/manage/index.html.erb:80, ticketing/sap_candidates/index.html.erb:44) vs div "mt-4" (bmid/provisions/_list.html.erb:32) vs none (most ticketing pages)
- **spacing** (timesheets-shiftops): Width-capped list wrapper: <div class="lg:w-3/4"> (timesheet_by_position/index.html.erb:61, timesheet_totals_report/index.html.erb:43, timesheets_by_callsign/index.html.erb:70) vs "lg:w-3/4 flex flex-col gap-6" (sanity_checker/index.html.erb:53) vs "grid ... lg:w-3/4" (rollcall/index.html.erb:16)
- **spacing** (timesheets-shiftops): Card-board grids: "grid-cols-1 md:grid-cols-2 xl:grid-cols-3 items-start gap-4" (on_duty/index.html.erb:134) vs "grid-cols-1 lg:grid-cols-2 xl:grid-cols-3 gap-4" (cruise_direction/_board.html.erb:24) vs "... gap-2" (rollcall/_roster.html.erb:27)
- **spacing** (vc): export/action button rows wrapped in <div class="my-4"> (reserved_handles/index.html.erb:31, shiny_penny_report:16, spigot_flow_report:49) vs export_csv_link inline in a count line (applications/index.html.erb:89) vs in a "mt-3" div below a table (application_import tables) vs filter_bar actions: (thank_you_cards/index.html.erb:25)
- **icons** (common-a): Tinted icon containers: square `w-9 h-9 rounded-lg bg-*/10 ring-1 ring-*/30` (_dashboard_section_header.html.erb:10), circle `rounded-full h-16 w-16 bg-*/10 text-*` (_status_medallion.html.erb:20), unsized `bg-warning/10 icon-warning ring-1 ring-signature-edge` (_trophies.html.erb:9)
- **icons** (common-b): Icon wrapper colour for alert rows: "icon-error"/"icon-warning" (scheduling/_signup_blockers:9,20) vs "text-error" (scheduling/_signup_blockers:40); FA alias names info-circle (_signup_blockers:21) and exclamation-circle (available_sign_ups/_slot:47,54) vs circle-info / circle-exclamation elsewhere
- **icons** (helpers-components): aria-hidden passed twice: fa_icon always sets "aria-hidden" (icon_helper.rb:94), while action_box (action_box_helper.rb:67), ui_stat_box (ui_stat_box_helper.rb:110), modal title icon (modal_helper.rb:179) and mega_category_index_button (mega_menu_helper.rb:108,113) also pass aria: { hidden: true } or "aria-hidden": "true"
- **icons** (hq-assets): Icons: fa_icon helper throughout vs raw <i class="fa-..."> with classes chosen in Ruby (hq/shift_manage/_todo_chip.html.erb:20-32, _todo_list.html.erb:65)
- **icons** (js): Icons set from JS as raw <i> class strings instead of fa_icon: autocomplete spinner "fa-solid fa-spinner animate-spin me-1" (app/javascript/controllers/autocomplete_controller.js:894); hq-shift chip icons "fa-solid fa-ban" / "fa-solid fa-check" / "fa-regular fa-circle" (app/javascript/controllers/hq_shift_controller.js:230-238); table-sort "fa-solid fa-sort text-stone-subtle" / "fa-solid fa-caret-up" / "fa-solid fa-caret-down" (app/javascript/controllers/table_sort_controller.js:17)
- **icons** (me): Button icons: icon:/icon_type: options on button_link (most of tickets/*, passkeys/index:11) versus fa_icon inside the block (vehicles_dashboard/_mvr_status_eligible:38, _pvr_requests:66,73, _pvr_status_agreement_needed:30, _pvr_status_eligible:13, _pvr_status_potential:21, vehicles_dashboard/index:47, agreements/show:24)
- **icons** (mentoring): Flag marker: ui stat/badge in screens, fa_icon flag text-2xl (info_sheet.html.erb:60) vs literal "⚑" glyph (signup_sheet.html.erb:48) on sibling print sheets
- **icons** (person): Old-to-new arrow: fa_icon arrow-right class "me-muted mx-1" (access_documents/history:28) vs &rarr; entity (timesheets/_log_entry_data:11,17,25,30,33)
- **icons** (teams-people): success icon colour: class "icon-success" (position_grants/show:112) / class "text-success" (position_sanity_checker/_results:30)
- **icons** (timesheets-shiftops): Error-coloured icon: fa_icon class "icon-error" (bulk_sign_in_out/preview.html.erb:92) / "icon-warning" (timesheets_by_callsign/person.html.erb:37,93) vs class "text-error" / "text-success" (mass_signout_helper.rb:24, timesheet_slot_repair/_results.html.erb:28) vs colour inherited from parent span "text-error" (timesheet_slot_repair/_results.html.erb:21, rollcall/_blocked_dialog.html.erb:11)
- **other** (common-a): List-plus-pane layout written twice: messages/_workspace.html.erb:23-24 and unified_flagging/_review_workspace.html.erb:13-14 (same `flex flex-col lg:flex-row gap-4` / `lg:w-2/5 lg:shrink-0`); panes messages/_pane.html.erb:22 and unified_flagging/_review_pane.html.erb:15 (same review-pane box classes, messages adds scroll-my-4)
- **other** (common-a): Avatars: same sender-type case copied with fa size lg (messages/_conversation_summary.html.erb:26-43) and size xl (messages/_messages_panel_header.html.erb:11-27); search result avatar (messages/_find_recipient_form.html.erb:17-21); inline-style placeholder box (_photo_none.html.erb:1-5)
- **other** (common-a): Checked-out state badge: ui_badge "checked out" lowercase :warning (assets/_table.html.erb:65) vs "Still checked out" :warning (assets/_checkout_history.html.erb:42); button_row inside a cell (assets/_table.html.erb:77) vs comment-avoided button_row in a cell (assets/_checkout_history.html.erb:43-46)
- **other** (common-b): Summary figures: ui_stat_box in a hand grid (schedule/signup_summary.html.erb:8-26), ui_stat_box in ui_stat_row with capitalised labels (timesheet/index.html.erb:23-34), ui_badge rows (work_history/entire_year.html.erb:10-14, position_all.html.erb:7-10, position_summary.html.erb:10-14)
- **other** (common-b): Overlap badge: ui_badge "overlapping shift" :error, no icon (schedule/_signed_up_row:23) vs ui_badge "Overlapping shift" :warning with circle-exclamation (available_sign_ups/_slot:70-73)
- **other** (communication): Status display: ui_badge (rbs_helper.rb:328,457-460; surveys_helper.rb:20-36; announcements_helper.rb:38-44) vs icon + coloured text spans "icon-success"/"text-error"/"text-stone-subtle" (rbs_helper.rb:216-239, 494-507) vs badge-or-muted-text pair (surveys/_group.html.erb:42-46)
- **other** (css): Hover fill uses base-200 in dropdown-link (dropdowns.css:14), ac-option (autocomplete.css:66), mega-menu-item-link (mega-menu.css:113) but base-300 in table-row-hover (tables.css:70), box-hover (boxes.css:24), callsign-list (callsign-list.css:21), ac-filter-chip (autocomplete.css:135), messages-conversation-item via default-strong (messages.css:14)
- **other** (css): Two progress bars: custom progress-container/progress-bar gradient primary->warning (progress.css:11-21) and stat-meter stacked bar (stat-meter.css:16-22); daisyUI progress not overridden here
- **other** (css): Five print sheets restate the same skeleton (paper preview max-width 8.5in, padding 0.5in, margin-bottom 1.5rem, border-line; masthead 2.5pt #111 rule; doc-label 8.5pt 0.14em uppercase; subline flex text-stone-muted; th 8pt 0.1em uppercase 1.25pt #111 rule; zebra base-200 with print-color-adjust): signup-sheet.css:24-119, trainers-report.css:20-163, shift-lead-sheet.css:25-210, alpha-sheets.css:22-116, acceptance-sheet.css:16-31
- **other** (helpers-components): Two progress bars: ui_progress_bar utility-built bar with role="progressbar" on the inner fill, heights h-1.5..h-6, variant bg colours (ui_progress_bar_helper.rb:52-108) vs render_progress_bar custom classes progress-container/progress-bar/progress-bar-pulse with a 5% floor (ui_progress_completed_bar_helper.rb:12-53); the hero panel and ui_progress_box use the second
- **other** (helpers-components): Badges and pills: ui_badge daisyUI "badge badge-{v} badge-soft" (badge_helper.rb:47); sidebar_badge hand-tinted "text-error bg-error/10 border border-error/30" etc. (sidebar_helper.rb:41-47, unreachable); filter chips hand-rolled "rounded-full border border-line px-3 text-sm" links (filter_bar_helper.rb:10-13); hero stat_badge tiles (ui_hero_panel_helper.rb:96); match stepper count as a btn-styled span (ui_match_stepper_helper.rb:26)
- **other** (helpers-components): Touch targets: TABLE_LINK_CLASSES min-h-5 (20px, link_helper.rb:7); back_to, bulk-select labels, filter chips, accordion and inline disclosure summaries min-h-9 (application_helper.rb:252, bulk_select_helper.rb:10, filter_bar_helper.rb:10, ui_accordion_helper.rb:11, ui_disclosure_helper.rb:11); clipboard button grows its hit area with before:-inset-3.5 instead (clipboard_helper.rb:25); detail_row_toggle min-h-9 h-auto py-1.5 over btn-sm (table_helper.rb:378)
- **other** (helpers-forms): Pill/chip shape hand-built twice with different classes: filter chip link "inline-flex min-h-9 items-center gap-2 rounded-full border border-line px-3 text-sm text-body ... hover:bg-default-strong" (app/helpers/ui_components/filter_bar_helper.rb:10-13) vs callsign chip span "inline-flex min-h-9 items-center gap-1 rounded-full border border-line bg-base-200 ps-3 pe-1 text-sm text-body" (app/views/shared/_callsign_chip.html.erb:7); remove control is an xmark inside the link vs a ghost btn-square btn-circle button
- **other** (hq-assets): ui_stat_box icons: icon: with icon_type: :solid (asset_management pages) vs icon: without icon_type (vehicles/paperwork/index.html.erb:15-23, vehicles/registry/index.html.erb:11-17) vs no icon (quartermaster, pogs dashboard); labels in uppercase literals only in hq/timesheets/event_summary.html.erb:10-12
- **other** (hq-assets): Help Q&A instruction-list: inside ui_disclosure card (most report pages, e.g. asset_management/asset_history/index.html.erb:49) vs bare in a form section (quartermaster/swag/_form.html.erb:4, vehicles/registry/_form.html.erb:6)
- **other** (hq-assets): Progress bars as charts: ui_progress_bar :secondary (quartermaster/events_rangered/index.html.erb:66) vs :primary (pogs/dashboard/index.html.erb:83,117)
- **other** (js): Disclosure/expand done several ways: toggle (aria-expanded + aria-hidden + "hidden"/"hidden!" + optional innerHTML label swap, app/javascript/controllers/toggle_controller.js:41); read-more (aria-expanded + "hidden" + "more"/"less" text + rotate-180 icon, app/javascript/controllers/read_more_controller.js:21); conditional-show (select value reveals by id, no ARIA, app/javascript/controllers/conditional_show_controller.js:19); disclosure-fields on native <details> (app/javascript/controllers/disclosure_fields_controller.js:13)
- **other** (js): Show/hide done with two mechanisms: the hidden attribute (autocomplete results, list-filter, live-log, kiosk-free panels in mega-menu, camera, hq-shift, hq-wizard, passkey, photo-upload, dialog callouts) versus toggling the Tailwind class "hidden" (conditional-show :20, password-reveal :20, read-more :23, register-intent :30, stale-results :14, tabs :69, review-pane :225, toggle :55 which also toggles "hidden!")
- **other** (me): Centered status block: common/status_medallion + h3 in dashed box (agreements/index:57-63); status_medallion + h3 + p (vehicles_dashboard/_pvr_status_agreement_needed:2-10,33-41); status_medallion size lg in bg-error/10 panel with h2 (vehicles_dashboard/index:30-49); fa_icon size 4x in rounded-full div + h3 text-success (vehicles_dashboard/_mvr_status_approved:1-15)
- **other** (me): Status chips: _status_chip partial (tickets/_landing:158,203, gift:54,100, provisions:63,66,69, sap via _section_header, ticket:21, vehicle_pass:26,39,68) versus inline ui_badge with the same meanings (tickets/ticket:69,71,73 "In use"/"Banked"/"Ready to claim"; _section_detail:65 "banked")
- **other** (me): ART status badges: lowercase, no icons, "done"/"pending" (dashboard_tasks/_dashboard_arts:19-25) versus title case with icons, "Completed"/"Pending" (operational_summary/_training:52-58); teaching shown as <i>(teaching)</i> (_dashboard_arts:34) versus ui_badge "Teaching" (_training:67)
- **other** (me): ui_stat_box labels: ALL CAPS without icons (event_summary/index:7-9, work_history/index:6-8) versus title case with icons (feedback/index:22-25)
- **other** (me): Dates in dashboard tasks: datetime_format with tz: (dashboard_tasks/_attend_alpha_shift_pending:6, _attend_training_pending:28) versus Time.zone.parse(...).strftime (_attend_cheetah_cub_shift_pending:5) versus mdy_format full: (_attend_training_fail:4)
- **other** (me): Same "Alpha shifts: Sat-Tue only" note as ui_callout_box :info accent (dashboard_tasks/_sign_up_for_alpha_shift_needed:1) versus muted icon text (dashboard_tasks/_sign_up_for_alpha_shift_blocked:2, _sign_up_for_alpha_shift_waiting:9)
- **other** (mentoring): Training status: TRAINING_STATUS_BADGE (intake_helper.rb:56-62, "none" :secondary, no icons) vs TRAINING_STATUS_CHIP (intake_helper.rb:80-85, "none" :error with icon) vs intake_training_status_text coloured word (intake_helper.rb:103-108)
- **other** (mentoring): Mentor verdict badge: mentor_result_badge (mentor_helper.rb:58, self-bonk :error, label "Self-bonked") vs alpha_verdict_badge (alphas_convert_helper.rb:15-28, self-bonk :warning) vs MENTEE_STATUS_BADGE (intake_helper.rb:66-71, "mentor passed", no icons) vs post_season_verdict_chip (post_season_summary_helper.rb:163-167, Passed only)
- **other** (person): Stat tiles: ui_stat_row/ui_stat_box (awards/index:9, bmids/show:19, mail_log/index:9, timesheets/index:10, timesheets/breakdown:10) vs hand-built "border rounded px-2 py-1" boxes (tickets_provisions/show:22-53); stat labels Title Case (awards, breakdown) vs ALL CAPS (timesheets/index:11-16)
- **other** (scheduling): "Inactive" marker: ui_badge :secondary circle-pause (slots_helper:31, schedule_by_position_helper:34, schedule_by_callsign_helper:55) vs ui_badge :warning sm (slots/position:95) vs "N inactive" :warning base (slots/index:44) vs stat tile :warning (slots/position:11)
- **other** (scheduling): On-site status: "On Site"/"Off Site" badges person-walking/moon regular (hq_forecast/_people_dialog:30-32) vs "On site"/"Off site" location-dot/location-crosshairs solid (early_arrivals/index:203-205) vs fa_icon ban text-error for not on site (shift_lead/_callsign:7)
- **other** (shell-auth-profile): Static error pages: 400/404/422/500 share one oklch template with theme script and action button; 406-unsupported-browser.html has a separate hex template without either
- **other** (shell-auth-profile): kbd chip: application/_top_menu.html.erb:48-52 vs application/_search_bar_placeholder.html.erb:63-67 (near-identical utilities, comment says extract on third) vs _search_bar_placeholder.html.erb:149 (esc chip, base-200) vs shared/_autocomplete.html.erb:70-72 (bare kbd)
- **other** (teams-people): person status in cells: plain text (bulk_teams/preview:83, certificates_report/show:61, bulk_lookup:96, _people_table:28) / person_status_label (special_teams_hours:154, membership_report/_roster:14, position_grants/show:71) / person_status_badge (search_helper.rb:158) / muted second line (roster_management/show:149)
- **other** (teams-people): hero_panel title/description: keyword args (most) / block form panel.title/panel.description (membership_report/index:7, team_documents/show:3, position_sanity_checker/index:8, retention_report:9)
- **other** (teams-people): yes/no or vintage display: yes_no_badge (bulk_lookup/index:107, _people_table:40) / ui_badge Vintage or dash (status_change_recommendations_helper.rb:39) / fa_icon circle-check or dash (position_grants/show:112) / ui_badge "On site" (position_grants/show:73)
- **other** (teams-people): Inactive badge colour: :warning (team_records/index:74, position_records/index:87, position_grants_helper.rb:129) / :secondary (team_documents_helper.rb:25)
- **other** (teams-people): stat_box variants for the same "Will Change/Unchanged" pair: success/secondary (bulk_teams/preview:12,15, bulk_positions/preview:12,15) / default/warning (roster_management/preview:14,16)
- **other** (ticketing-bmid): "Any time" access label wording: "Anytime" (ticketing/access_documents_helper.rb:13) vs "Any" (tickets_provisions_helper.rb:80, bmid_helper.rb:38, ticketing/trs_export/index.html.erb:59) vs lowercase "any" (bmid/manage_helper.rb:420); missing date as "Missing" (access_documents_helper.rb:14), "(no date)" (manage_helper.rb:421), "Unspecified" (bmid_helper.rb:42), "—" (tickets_provisions_helper.rb:85)
- **other** (ticketing-bmid): Boolean display: yes_no_badge (unsubmit_provisions/index.html.erb:70, unclaimed_with_signups/index.html.erb:80, claimed_with_no_signups/index.html.erb:102-105, sap_candidates/index.html.erb:74) vs plain "Yes"/"No" (ticketing/provisions/index.html.erb:68, bmid/badges/edit.html.erb:80) vs "Yes"/"—" (bmid/manage/_table.html.erb:43, export/_selection_table.html.erb:48)
- **other** (ticketing-bmid): Stat tiles: ui_stat_row (most pages) vs hand grids of ui_stat_box (statistics/index.html.erb:67,78) vs grid of ui_stat_link wrapping ui_stat_box (bmid/sanity_check/index.html.erb:10)
- **other** (timesheets-shiftops): Hero description: panel.description block (all timesheets pages) vs description: keyword (payroll_missing_id/index.html.erb:11, payroll_export/index.html.erb:15, bulk_sign_in_out/preview.html.erb:22)
- **other** (timesheets-shiftops): Avatar markup: Tailwind "w-11 h-11 rounded-full" photo_tag + placeholder span duplicated (rollcall/_row.html.erb:21-27, cruise_direction/_pod.html.erb:67-73) vs custom photo-board-photo classes (roc_photo_board/_photo.html.erb:4-11)
- **other** (training): Disclosure title: "How This Page Works" in mentees/index.html.erb:34 and mentoring/assignments/_roster.html.erb:64; "About This Report" on every other training report
- **other** (training): Stat tiles: ui_stat_box everywhere on screen; hand-built div.report-stat with <b> in sessions/trainers_report.html.erb:54 (print)
- **other** (vc): Stat boxes: ui_stat_row (applications/index.html.erb:40, reserved_handles/index.html.erb:10, photos/index.html.erb:8, photos_review/_stats.html.erb:2, thank_you_cards/index.html.erb:13) vs hand-rolled "grid grid-cols-2 lg:grid-cols-4 gap-2 lg:gap-4 my-4" (create_prospectives/_results.html.erb:41, application_import/_results.html.erb:38); ui_stat_box also used as a status badge (reserved_handles/edit.html.erb:8-10)

## Shared component implementations

### css (131)

- **`link`** (links, `app/assets/stylesheets/base.css:8-10`)
  - @utility: text-primary underline; applied to every a:not(.no-decoration)
  - none
  - ~147 files (token `link` is common; approximate)
- **`no-decoration`** (links, `app/assets/stylesheets/base.css:67`)
  - opt-out marker, no declarations of its own
  - none
  - 20
- **`tap-target-link`** (links, `app/assets/stylesheets/accessibility.css:32-34`)
  - @utility: inline-flex items-center min-h-9 (36px link floor); also applied by login-label-link
  - none
  - 27
- **`instruction-list`** (typography, `app/assets/stylesheets/accessibility.css:55-105`)
  - dl Q/A list: space-y-1 text-body; dd+dt margin-block-start 2 units; dt font-bold text-heading ps-5 with ::before "Q:" text-primary; dd text-body ps-5 with ::before "A:" text-stone-muted; alt-text content "" for screen readers; unlayered
  - none
  - 179
- **`button-row`** (buttons, `app/assets/stylesheets/components/buttons.css:30-42,63-68`)
  - flex row wrap, row-gap 1.5vh, column-gap 1.5vw; below md: column, align start; fixed-bottom state padding in safe-area.css:59-70
  - 1.5vh, 1.5vw, !important x2 (65,66)
  - 3
- **`button-row-spacer`** (buttons, `app/assets/stylesheets/components/buttons.css:96-121`)
  - height = 1px + 1rem + lines x --size + gaps + pad-bottom; one line from md unless full-width controls; hidden at lg
  - 1px + 1rem restating helper's border-t pt-4
  - 1
- **`btn-copy-success`** (buttons, `app/assets/stylesheets/components/buttons.css:123-155`)
  - keyframes copy-success (color success, scale 0.8->1) 1s and copy-zoom-fade on .fa 500ms; cubic-bezier(0.25,1,0.5,1); no reduced-motion rule
  - 1.5em, scale 2
  - 3
- **`copy-tip`** (toasts-alerts, `app/assets/stylesheets/components/buttons.css:164-211`)
  - "Copied" tip: m-2 rounded-field bg-neutral px-2 py-1 text-sm text-neutral-content; anchored popover position-area top with flip-block; fallback absolute bottom-full centered z-10
  - z-10
  - 1
- **`btn-toast-close`** (buttons, `app/assets/stylesheets/components/buttons.css:213-215`)
  - @apply btn btn-ghost btn-sm btn-circle; lifted to 36px in accessibility.css:21
  - none
  - 1
- **`[data-theme="dark"] .btn-error`** (buttons, `app/assets/stylesheets/components/buttons.css:13-15`)
  - daisyUI override: darker error fill for buttons in dark theme; keyed on data-theme only
  - oklch(42% 0.15 25) literal
  - n/a (daisyUI class)
- **`icon-success / icon-warning / icon-error / icon-info`** (icons, `app/assets/stylesheets/components/icons.css:24-38`)
  - @utility: text-success / text-warning / text-error / text-info; inside .badge they inherit the badge colour (badges.css:39-41)
  - none
  - 25 / 31 / 30 / 5
- **`flex-center`** (spacing, `app/assets/stylesheets/components/flex-patterns.css:5-7`)
  - @utility flex items-center (no justify despite name)
  - none
  - 6
- **`flex-center-gap-2`** (spacing, `app/assets/stylesheets/components/flex-patterns.css:9-11`)
  - @utility flex items-center gap-2
  - none
  - 21
- **`inline-flex-center-gap-2`** (spacing, `app/assets/stylesheets/components/flex-patterns.css:13-15`)
  - @utility inline-flex items-center gap-2
  - none
  - 13
- **`list-bulleted / list-numbered`** (tables-lists, `app/assets/stylesheets/components/lists.css:11-17`)
  - @utility list-disc|list-decimal ps-list-indent
  - none
  - 50 / 9
- **`two-column-lg`** (spacing, `app/assets/stylesheets/components/layout-patterns.css:9-11`)
  - @utility grid 1 col, 2 cols at lg, gap-4
  - none
  - 15
- **`stack-to-row-lg`** (spacing, `app/assets/stylesheets/components/layout-patterns.css:14-16`)
  - @utility flex-col, row at lg, gap-4
  - none
  - 11
- **`card-standard`** (cards, `app/assets/stylesheets/components/cards.css:24-43`)
  - @utility card bg-base-100 border border-line; no padding, no shadow; nested lexxy table-wrapper reset to block overflow-auto rounded-none
  - none
  - 14
- **`table-container`** (tables-lists, `app/assets/stylesheets/components/tables.css:22-24,91-93,120-122`)
  - @utility relative overflow-x-auto bg-base-100 shadow-xs rounded-box border border-base-300; tbody vertical-align top; chevron rotates on aria-expanded
  - none
  - 1 (emitted by TableHelper)
- **`table-header / table-heading / table-row-header / table-cell-td`** (tables-lists, `app/assets/stylesheets/components/tables.css:27-61`)
  - thead text-base-content bg-base-200 border-b base-300; th p-1.5 font-semibold; row th p-1.5 text-heading nowrap (wraps inside responsive-table below lg); td p-1.5
  - none
  - 1 each (TableHelper)
- **`table-row-base / table-row-hover / table-row-striped`** (tables-lists, `app/assets/stylesheets/components/tables.css:64-76`)
  - bg-base-100 border-b base-300; hover:bg-base-300; odd base-100 even base-200
  - none
  - 1 each
- **`table-detail-row / table-detail-cell`** (tables-lists, `app/assets/stylesheets/components/tables.css:106-112,199-201`)
  - expanded detail row bg-base-200 border-b; cell p-3 border-s-4 border-primary; card padding removed when folded
  - none
  - 1 each
- **`responsive-table`** (tables-lists, `app/assets/stylesheets/components/tables.css:140-263`)
  - below lg (layered components): table/rows/cells become blocks, thead sr-only, tr px-3 py-3, cells wrap overflow-wrap anywhere, ::before data-label text-xs font-semibold text-body; rows flex-wrap with 11rem cell floor, column-gap 1.5rem; unlayered text-left on cells
  - 11rem, 1.5rem
  - 1
- **`text-heading-primary`** (typography, `app/assets/stylesheets/components/text-colors.css:34-36`)
  - @utility color var(--color-heading) (same as text-heading)
  - none
  - 4
- **`text-stone-emphasis`** (typography, `app/assets/stylesheets/components/text-colors.css:49-51`)
  - @utility color var(--color-body) (same as text-body)
  - none
  - 12
- **`text-stone-muted`** (typography, `app/assets/stylesheets/components/text-colors.css:58-60`)
  - @utility color-mix(in oklch, base-content 90%, base-100)
  - none
  - 234
- **`text-stone-subtle / text-stone-icon`** (typography, `app/assets/stylesheets/components/text-colors.css:66-73`)
  - both @utility color var(--color-body-subtle)
  - none
  - 56 / 20
- **`heading-section`** (typography, `app/assets/stylesheets/components/headings.css:11-13`)
  - @utility text-base, lg:text-lg, font-semibold (h2 level)
  - none
  - 23
- **`heading-title`** (typography, `app/assets/stylesheets/components/headings.css:16-18`)
  - @utility text-base font-semibold (h3/h4)
  - none
  - 45
- **`modal-header-bar / modal-title-text / modal-body-content / modal-footer-bar`** (modals, `app/assets/stylesheets/components/modals.css:8-25`)
  - flex justify-between pb-2 border-b base-300; text-xl font-semibold text-base-content; py-4; modal-action pt-2 border-t base-300
  - none
  - 2 / 2 / 2 / 1
- **`dropdown-panel`** (navigation, `app/assets/stylesheets/components/dropdowns.css:8-10`)
  - @utility menu bg-base-100 rounded-box shadow-lg w-52 p-2 border base-300
  - z-50
  - 1
- **`dropdown-link / dropdown-disabled-item`** (navigation, `app/assets/stylesheets/components/dropdowns.css:13-20`)
  - block px-4 py-2 text-sm text-base-content hover:bg-base-200 rounded-lg; disabled text-base-content/40 cursor-not-allowed
  - none
  - 1 / 1
- **`toast-base`** (toasts-alerts, `app/assets/stylesheets/components/toasts.css:9-20`)
  - @utility alert flex w-full max-w-md p-4 mb-4 rounded-lg shadow relative overflow-hidden; opacity 0 translateX(100%) 300ms transition; .show slides in (set by toast_controller.js); no reduced-motion rule
  - 300ms, 100%
  - 1
- **`toast-progress`** (toasts-alerts, `app/assets/stylesheets/components/toasts.css:23-28`)
  - absolute bottom bar h-1 bg-current opacity-30, width transition
  - none
  - 1
- **`toast-success / toast-info / toast-warning / toast-error`** (toasts-alerts, `app/assets/stylesheets/components/toasts.css:31-48`)
  - @apply alert-<status> alert-soft
  - none
  - 1 each
- **`sidebar-nav-item`** (navigation, `app/assets/stylesheets/components/sidebar.css:9-10,62-65`)
  - block h-10 flex items-center p-3 text-sm no-underline border-t sidebar-divider; .active: sidebar-active colour + 5px right border (unlayered)
  - 5px
  - 1
- **`sidebar-section-header`** (navigation, `app/assets/stylesheets/components/sidebar.css:14`)
  - px-3 py-1 text-sm uppercase truncation
  - none
  - 1
- **`sidebar-badge`** (other, `app/assets/stylesheets/components/sidebar.css:18-20`)
  - @apply badge badge-sm ms-2
  - none
  - 1
- **`sidebar-link-hq / sidebar-group-title-hq / sidebar-link-default / sidebar-group-title-default`** (navigation, `app/assets/stylesheets/components/sidebar.css:27-44`)
  - chrome token pairs: text-sidebar-content on bg-sidebar-link(-hq) / bg-sidebar-title-hq / bg-chrome
  - none
  - 1 each (sidebar_helper.rb)
- **`.drawer-side .btn-ghost`** (buttons, `app/assets/stylesheets/components/sidebar.css:74-77`)
  - daisyUI override: --btn-rest-fg and outline-color = sidebar-content on the black sidebar
  - none
  - n/a
- **`.navbar .btn-ghost:not(dialog *)`** (buttons, `app/assets/stylesheets/components/navbar.css:21-38`)
  - daisyUI override: --btn-rest-fg and outline-color neutral-content on dark bar; aria-current="true" ghost buttons rest transparent unless hovered
  - none
  - n/a
- **`messages-conversation-item`** (tables-lists, `app/assets/stylesheets/components/messages.css:12-16`)
  - flex gap-3 p-3 min-h-18 rounded-lg text-body hover:bg-default-strong; focus-visible ring-2 ring-inset ring-primary
  - none
  - 1
- **`messages-conversation-unread`** (color, `app/assets/stylesheets/components/messages.css:23-27`)
  - bg-warning/10 unless aria-current="true"
  - none
  - 1
- **`search-hit`** (typography, `app/assets/stylesheets/components/messages.css:35-37`)
  - <mark> tint bg-warning/30 text-inherit rounded-sm
  - none
  - 2
- **`messages-reply-editor`** (forms, `app/assets/stylesheets/components/messages.css:46-48`)
  - --lexxy-editor-rows 6rem (vs 16rem default)
  - 6rem
  - 1
- **`messages-conversation-avatar / messages-avatar-placeholder / messages-avatar-rbs / messages-avatar-team`** (other, `app/assets/stylesheets/components/messages.css:51-73`)
  - 48px (w-12 h-12) boxes; placeholder and team rounded-lg bg-base-300 text-stone-icon; rbs bg-primary/10
  - none
  - 1 / 3 / 2 / 2
- **`mega-menu-dialog`** (modals, `app/assets/stylesheets/components/mega-menu.css:8-27`)
  - native dialog full screen (100dvw x 100dvh) bg-base-100 shadow-xl; backdrop rgb(0 0 0 / 0.5); from 1024px rounded-lg min(90vw,72rem) x 85dvh centred
  - rgb(0 0 0 / 0.5), 1024px, 72rem, 85dvh
  - 1
- **`mega-menu-header / -search / -tabs / -body / -side / -side-divider / -panels / -frame / -content`** (navigation, `app/assets/stylesheets/components/mega-menu.css:30-78`)
  - flex shells with border-line dividers; search min-h-9 text-base; side w-64 p-3 border-r; panels p-4 scroll
  - none
  - 1 each
- **`mega-menu-chrome-btn`** (buttons, `app/assets/stylesheets/components/mega-menu.css:68-74`)
  - justify-start w-full min-h-8 font-normal; aria-current: text-heading bg-secondary/30 font-semibold
  - min-h-8 (32px, under the 36px floor)
  - 1
- **`mega-menu-panel[hidden] / mega-menu-item[hidden]`** (other, `app/assets/stylesheets/components/mega-menu.css:80-82,108-110`)
  - display none to beat unlayered rules
  - !important x2
  - 1 / 3
- **`mega-menu-panel-title / mega-menu-section-title`** (typography, `app/assets/stylesheets/components/mega-menu.css:84-95`)
  - text-lg font-semibold text-stone-muted mb-1; text-sm font-semibold text-stone-muted mt-3 mb-1 (headings in muted ink)
  - none
  - 1 / 1
- **`mega-menu-item / -item-link / -item-title / -item-cat / -item-desc`** (navigation, `app/assets/stylesheets/components/mega-menu.css:102-128`)
  - item link flex-col rounded-lg px-1 py-1 min-h-8 hover:bg-base-200 focus-visible ring-2 ring-primary; title font-semibold text-heading; cat/desc text-stone-muted
  - min-h-8 (32px)
  - 3 / 1 / 2 / 1 / 2
- **`mega-menu-star / -star-on / -star-spacer`** (buttons, `app/assets/stylesheets/components/mega-menu.css:130-140`)
  - btn-square min-h-9 min-w-8; on = text-primary; spacer w-8
  - min-w-8
  - 1 each
- **`mega-menu-cat-btn / -cat-text / -cat-chevron / -back / -close`** (buttons, `app/assets/stylesheets/components/mega-menu.css:142-165`)
  - category button w-full justify-start gap-3 min-h-14 py-2; back/close min-h-8 (close min-w-18)
  - min-h-8 (32px)
  - 1 each
- **`app-edge-pad`** (spacing, `app/assets/stylesheets/components/safe-area.css:30-35`)
  - page scroll container padding 0.75rem each side, max() with safe-area insets
  - 0.75rem
  - 1
- **`box`** (cards, `app/assets/stylesheets/components/boxes.css:14-16`)
  - layered: shadow-[0px_0px_6px_4px_rgba(0,0,0,0.1)] border rounded-lg w-full (border colour from variant)
  - arbitrary shadow with rgba(0,0,0,0.1)
  - 101
- **`box-accent`** (cards, `app/assets/stylesheets/components/boxes.css:18-20`)
  - layered: border-l-4 rounded-lg w-full
  - none
  - 2
- **`box-hover`** (cards, `app/assets/stylesheets/components/boxes.css:23-25`)
  - hover:bg-base-300 hover:text-base-content
  - none
  - 1
- **`box-default`** (cards, `app/assets/stylesheets/components/boxes.css:27-29`)
  - bg-base-100 border-line
  - none
  - 9
- **`box-success / box-accent-success`** (toasts-alerts, `app/assets/stylesheets/components/boxes.css:36-43`)
  - via @utility box-theme-success: bg-success/5 text-success border-success/20
  - none
  - 1 / 2
- **`box-warning / box-accent-warning`** (toasts-alerts, `app/assets/stylesheets/components/boxes.css:45-71`)
  - box-theme-warning: bg-warning/10 border-warning (full) text-warning; unlayered rule forces every descendant except .btn/.badge (and instruction-list ::before) to color inherit opacity 1
  - none
  - 1 / 3
- **`box-error / box-accent-error`** (toasts-alerts, `app/assets/stylesheets/components/boxes.css:73-80`)
  - box-theme-error: bg-error/5 text-error border-error/20
  - none
  - 1 / 1
- **`box-info / box-accent-info`** (toasts-alerts, `app/assets/stylesheets/components/boxes.css:82-89`)
  - box-theme-info: bg-info/10 text-base-content border-info/30 (text stays body ink, unlike other variants)
  - none
  - 1 / 1
- **`box-secondary / box-accent-secondary`** (cards, `app/assets/stylesheets/components/boxes.css:91-98`)
  - box-theme-secondary: bg-base-300/90 text-base-content, no border colour
  - none
  - 1 / 1
- **`box-theme-success / -warning / -error / -info / -secondary`** (color, `app/assets/stylesheets/components/boxes.css:36,45,73,82,91`)
  - @utility sources for the box variants
  - none
  - unused directly (0)
- **`me-hero-panel`** (cards, `app/assets/stylesheets/components/hero-panel.css:5-13`)
  - /me page header: arbitrary shadow, block rounded mb-4, then relative rounded-lg bg-base-200 dark:bg-base-300 ring-1 ring-signature-edge px-4 py-2 (rounded and rounded-lg both applied)
  - shadow-[0px_0px_6px_4px_rgba(0,0,0,0.1)]
  - 1
- **`me-muted`** (typography, `app/assets/stylesheets/components/hero-panel.css:17-19`)
  - @apply text-stone-muted (alias)
  - none
  - 24
- **`hero-stat / hero-stat-flame / hero-stat-award / hero-stat-label / hero-stat-value`** (other, `app/assets/stylesheets/components/hero-panel.css:28-73`)
  - stat badges: padding 0.5rem 0.75rem, radius 0.5rem, min-width 5.5rem, bg mix(hue 10%, base-100), border mix(hue 42%); flame 155deg gradient warning->error; label 0.75rem; value 1.125rem 600 tabular; award dark via .dark only
  - oklch(50% 0.13 85), oklch(83% 0.17 90), 0.5rem/0.75rem/5.5rem/0.75rem/1.125rem literals
  - 1 each
- **`ac-results / ac-results-above / ac-results-inline`** (forms, `app/assets/stylesheets/components/autocomplete.css:10-59`)
  - dropdown list absolute w-full bg-base-100 border-line rounded-lg shadow-lg, max-height 20rem, thin forced scrollbar; above and inline (in-flow, no border/shadow) variants
  - z-50, 20rem, 0.25rem, 0.5rem scrollbar
  - 3 / 1 / 2
- **`ac-option / ac-option-active`** (forms, `app/assets/stylesheets/components/autocomplete.css:62-93`)
  - option min-h-9 text-heading hover:bg-base-200 transition; active = success 18% tint over transparent + inset 3px success bar (26% on hover)
  - 3px, 18%/26%
  - 1 / 1
- **`ac-group / ac-group-header`** (forms, `app/assets/stylesheets/components/autocomplete.css:96-105,195-197`)
  - py-1; header px-3 py-2 text-xs uppercase tracking-wider text-stone-muted; adjacent groups border-t border-line
  - none
  - 1 / 1
- **`ac-filter-bar / ac-searching`** (forms, `app/assets/stylesheets/components/autocomplete.css:114-124`)
  - sticky top-0 flex-wrap gap-2 px-3 py-2 border-b bg-base-100; searching inline-flex min-h-9 text-sm text-stone-muted
  - z-10
  - 1 / 1
- **`ac-filter-chip / ac-filter-chip-active / ac-filter-count`** (forms, `app/assets/stylesheets/components/autocomplete.css:129-155`)
  - pill rounded-full px-3 py-1 text-xs bg-base-200 border-line min-h-9 hover:bg-base-300, focus ring-2 primary offset-2; active bg-primary (hover mix 85% black); count min-w-[1.25rem] h-5 bg-base-300
  - min-w-[1.25rem] arbitrary, color-mix with black
  - 1 / 1 / 1
- **`ac-empty / ac-error / ac-loading`** (empty-loading, `app/assets/stylesheets/components/autocomplete.css:158-177`)
  - px-4 py-6 centred text-sm text-stone-muted / text-error; loading floats absolute top-full mt-1 bg-base-100 border rounded-lg shadow-lg
  - z-50
  - 1 / 1 / 2
- **`ac-keyboard-help (+ kbd)`** (other, `app/assets/stylesheets/components/autocomplete.css:180-192`)
  - footer flex gap-4 border-t text-xs text-stone-subtle; kbd min-w-[1.25rem] h-5 bg-base-200 border-line rounded text-xs font-mono text-stone-muted
  - min-w-[1.25rem]
  - 2
- **`callsign-list`** (tables-lists, `app/assets/stylesheets/components/callsign-list.css:5-23`)
  - CSS multi-column, column-width 18ch gap 1rem; children break-inside avoid, margin-bottom 0.5vh, hover bg base-300
  - 18ch, 0.5vh
  - 2
- **`empty-state`** (empty-loading, `app/assets/stylesheets/components/empty-state.css:5-12`)
  - p-2 my-2 rounded border border-dashed text-base text-stone-muted; border mix(base-content 45%, base-100)
  - none
  - 3
- **`form-fieldset / form-legend`** (forms, `app/assets/stylesheets/components/forms.css:7-20`)
  - explicit-class twin of the form fieldset base rule (see BASE)
  - none
  - 1 / 1
- **`.input.has-icon / .select.has-icon`** (forms, `app/assets/stylesheets/components/forms.css:23-26`)
  - daisyUI override: padding-inline-start 2.5rem for a leading icon
  - 2.5rem
  - 1
- **`.select::picker(select)`** (forms, `app/assets/stylesheets/components/forms.css:36-38`)
  - daisyUI override: customizable select listing min-inline-size 0
  - none
  - n/a
- **`sticky-progress-container`** (other, `app/assets/stylesheets/components/progress.css:7-9`)
  - sticky top-0 full width -mx-3 -mt-3 px-3 pt-3 pb-2 bg-base-100 border-b base-300 shadow-sm (negative margins match app-edge-pad 0.75rem)
  - z-40
  - 1
- **`progress-container / progress-bar / progress-bar-pulse / progress-labels-container`** (other, `app/assets/stylesheets/components/progress.css:11-25`)
  - custom bar: h-3 bg-base-300 rounded-full track; fill gradient primary->warning, transition 500ms; pulse at /50 animate-pulse; labels text-sm text-base-content/60
  - none
  - 1 each
- **`progress-projected`** (other, `app/assets/stylesheets/components/progress.css:36-38`)
  - mask repeating -45deg stripes 4px/8px for an estimate bar
  - #000, 4px, 8px
  - 2
- **`camera-preview / camera-video / camera-capture-btn / camera-select`** (forms, `app/assets/stylesheets/components/camera.css:8-32`)
  - 4:3 max-w-md preview rounded-lg bg-secondary; mirrored video; capture button w-16 h-16 rounded-full border-4 border-line bg-primary hover:brightness-90 active:scale-95; select w-full max-w-md border-line p-2 text-base (hand-rolled, not daisyUI select)
  - none
  - 1 each
- **`ui-label-value`** (tables-lists, `app/assets/stylesheets/components/label-value.css:14-48`)
  - layered dl grid: 1 col row-gap 1; dt font-bold text-heading; dd mb 2 units; from 1024px two columns var(--label-width, auto) / 1fr, column-gap 2 units
  - 1024px literal breakpoint
  - 2
- **`stat-meter / stat-meter-segment`** (other, `app/assets/stylesheets/components/stat-meter.css:16-22`)
  - stacked bar flex h-4 gap-1 rounded-full bg-base-200; segments rounded ends
  - none
  - 2 / 2
- **`vc-progress-item + -success/-danger/-warning/-pending/-neutral`** (other, `app/assets/stylesheets/components/vc-applications.css:7-29`)
  - anchor pills inline-flex min-h-9 px-2 rounded-lg border text-xs no-underline; tints <status>/10 bg, /30 (warning /40) border, hover /20; neutral bg-base-200 text-base-content/60
  - none
  - 1 each
- **`vc-check-chip / vc-stage / vc-stage-summary / vc-stage-chevron / vc-stage-body`** (cards, `app/assets/stylesheets/components/vc-applications.css:32-56`)
  - icon-only chip min-w-10; stage card block mb-3 scroll-mt-24; summary flex-wrap gap-2 px-4 py-3 min-h-9 list-none, webkit marker hidden; chevron rotates when open; body px-4 pb-3
  - none
  - 1 each
- **`signup-sheet (+ signup-* cell classes)`** (other, `app/assets/stylesheets/components/signup-sheet.css:24-174`)
  - print sheet: #fff bg, #111 ink, 12pt; screen paper preview max-w 8.5in pad 0.5in border-line; masthead 2.5pt rule; doc label 8.5pt uppercase; session 17pt; running head; zebra tbody base-200 with print-color-adjust; dotted fill-in rows; widths in inches
  - #fff #111 #222 #ccc #bbb #999, pt and in units throughout
  - 1 each
- **`trainers-report (+ report-* classes)`** (other, `app/assets/stylesheets/components/trainers-report.css:20-322`)
  - print sheet 9pt: masthead, stat tiles (0.9pt #111 border), callout (4pt left rule), roster table zebra, band rows base-300, pills/chips/status in #111 outlines, solid #111 chips with neutral-content ink, legend 4 columns, italic empty row
  - #fff #111 #222 #ccc #999 #888, pt/in units
  - 1 each
- **`shift-lead-sheet (+ sheet-* classes)`** (other, `app/assets/stylesheets/components/shift-lead-sheet.css:25-304`)
  - print sheet 7.5pt portrait: masthead, boxed filters (3pt left rule), stat tiles, bands base-300, running head row, fixed table layout with colgroup widths in inches, chips (solid variant #111), legend 3 columns; resets h1 margin
  - #fff #111 #999, pt/in units
  - 1 each
- **`alpha-sheet (+ alpha-* classes)`** (other, `app/assets/stylesheets/components/alpha-sheets.css:22-334`)
  - three alpha print sheets + pod sheet: 11pt, masthead, running head, zebra tbody, write-in rows dotted, info table with separator bands, apparel totals, pod table bordered 0.5pt #999, ordered list restored; .alpha-sheet .badge forced to print at 8pt; wide variant 11in
  - #fff #111 #222 #ccc #bbb #999 #888, pt/in units
  - 1-5 per class
- **`acceptance-sheet (+ acceptance-* classes)`** (other, `app/assets/stylesheets/components/acceptance-sheet.css:16-287`)
  - acceptance form print sheet: hard page break between sheets (break-before + page-break-before), logo masthead, base-200 section bands, label/value inline-block columns in %, headshot box 132x170pt, sign-off table nth-child % widths, red alert text, .acceptance-sheet .badge forced to print
  - #fff #111 #222 #777 #a3000c, pt units
  - 1 each
- **`roster-col-select / roster-col-callsign / roster-frozen-cell / roster-frozen-heading / roster-grid-pane / roster-grid`** (tables-lists, `app/assets/stylesheets/components/roster-matrix.css:14-82`)
  - frozen columns sticky left-0 w-12 and left-12 w-40; cells z-10 bg inherit, headings z-30; pane overflow-y max-height 70vh; thead th bg-base-200; print unfreezes
  - z-10, z-30, 70vh
  - 1 each
- **`shift-coverage-grid / shift-coverage-period`** (tables-lists, `app/assets/stylesheets/components/shift-coverage.css:12-48`)
  - from lg: period th sticky start-0 z-10 bg inherit, thead bg-base-200, border-e base-300; post columns border-s base-300
  - z-10
  - 1 / 1
- **`top-hour-earners-grid / top-hour-earners-person`** (tables-lists, `app/assets/stylesheets/components/top-hour-earners.css:11-52`)
  - person th sticky start-0 z-0 bg inherit at every width; thead bg-base-200; border-e; print static
  - z-0
  - 1 / 1
- **`hours-credits-callsign / hours-credits-pane / hours-credits-grid / hours-credits-group`** (tables-lists, `app/assets/stylesheets/components/hours-credits.css:10-84`)
  - frozen callsign sticky start-0 w-36 z-10 bg inherit, heading z-30; pane max-height 70vh; thead bg-base-200 printed exact; group border-s-2 border-line; print unfreezes
  - z-10, z-30, 70vh
  - 1 each
- **`sandman-qualified-pane`** (tables-lists, `app/assets/stylesheets/components/sandman-qualified.css:19-34`)
  - from lg overflow-y-auto max-height 70vh; thead th bg-base-200
  - 70vh
  - 1
- **`hq-gantt (+ -chart, -lane, -mark, -fill, -hit, -bar, -bar-text(-long), -swatch, -vacant, -gap)`** (other, `app/assets/stylesheets/components/hq-forecast.css:22-239`)
  - Gantt chart: grid 6.5rem/1fr; hour lines gradient every 12.5%; marks positioned from --start/--span over 1440; tooltip max-w 14rem hidden when closed; hit area min 2.25rem; focus ring-2 primary offset-2; vacant = bg-warning + base-100 hatch; gap = warning hatch; container queries hide bar text; forced-colors outlines
  - z-20, 6.5rem, 14rem, 2.25rem, 1440, brightness(1.15)
  - 1 each
- **`hq-forecast-pane / hq-forecast-table`** (tables-lists, `app/assets/stylesheets/components/hq-forecast.css:151-174`)
  - from lg: pane overflow-x clip; thead th sticky z-20 bg-base-200 top -0.75rem with inset shadow base-300
  - z-20, -0.75rem
  - 1 / 1
- **`.hq-gantt-mark > .tooltip-content`** (other, `app/assets/stylesheets/components/hq-forecast.css:66-73`)
  - daisyUI tooltip override: max-width 14rem, display none (and ::after tail) unless hovered/focused
  - 14rem
  - 1
- **`hq-shell / hq-shell-content / hq-summary`** (other, `app/assets/stylesheets/components/hq-window.css:37-213`)
  - device tiers: md-lg summary laid out as flex row with dl grid; >=112.5rem zoom 1.15 (and HQ sidebar), content max-w 64rem, p max 68ch; >=150rem zoom 1.35; messages-workspace container query <50rem stacks pane under list
  - 112.5rem, 150rem, 64rem, 68ch, 50rem, zoom literals
  - 1 each
- **`messages-workspace`** (other, `app/assets/stylesheets/components/hq-window.css:197-213`)
  - container: messages-workspace inline-size inside hq-shell
  - 50rem
  - 1
- **`photo-board (+ ~30 photo-board-* classes)`** (other, `app/assets/stylesheets/components/photo-board.css:14-206`)
  - ROC wall display: sticky header z-10 border-b-2; headings text-3xl/2xl/xl; groups border-2 rounded-xl, active border-success ring-4 success/25 + badge bg-success text-success-content; cards w-48 photo h-48; rail w-56 sticky from lg with active item success/15; empty and no-host text; padding-bottom 100vh
  - z-10, 100vh, 0.3s transitions
  - 1-2 each
- **`lexxy-editor`** (forms, `app/assets/stylesheets/components/lexxy.css:67-76`)
  - rich-text editor: --lexxy-editor-rows 16rem, text-base leading-relaxed; :focus-within ring-2 ring-primary ring-offset-2 ring-offset-base-100
  - 16rem
  - element, n/a
- **`lexxy-editor p.provisional-paragraph.hidden`** (forms, `app/assets/stylesheets/components/lexxy.css:93-95`)
  - keeps Lexxy caret paragraph visible
  - !important
  - n/a (vendor JS)
- **`lexxy-highlight-dropdown, lexxy-code-language-picker`** (forms, `app/assets/stylesheets/components/lexxy.css:100-103`)
  - hidden (tools turned off)
  - none
  - n/a
- **`lexxy-content`** (typography, `app/assets/stylesheets/components/lexxy.css:111-146`)
  - saved rich text: wrap-break-word; h1 text-xl, h2 text-lg, h3-h6 text-base, all font-semibold text-heading with mt; lists ms-0 ps-list-indent; li mb-1
  - none
  - 14
- **`bookmark-page`** (links, `app/assets/stylesheets/components/bookmark.css:22-28`)
  - kiosk: lines holding links margin-block 0.75rem; links padding-block 0.5rem for touch reach
  - 0.75rem, 0.5rem
  - 1
- **`ct (+ ct-s0..s8, ct-swatch, ct-tick, ct-seg, ct-layer, ct-axis-day, ct-axis-month)`** (other, `app/assets/stylesheets/components/credit-chart.css:15-84`)
  - credit timeline chart: palette vars, swatch/layer fill var(--c), ticks/axis 1px grid border, segment flex by --w, layer height by --h/--ymax, 2px base-100 gap shadow, hover brightness 1.15
  - hex palette (16 hex + #898781)
  - 1 each
- **`disclosure-card`** (other, `app/assets/stylesheets/components/disclosure.css:18-22`)
  - print-only hide rule hook (set by ui_disclosure)
  - none
  - 1
- **`review-pane`** (other, `app/assets/stylesheets/components/review-pane.css:24-31`)
  - from lg (layered) max-height calc((100dvh - 4rem)/zoom - 2rem) overflow-y auto
  - 4rem navbar height, 2rem
  - 11
- **`review-line / review-line-flagged`** (tables-lists, `app/assets/stylesheets/components/review-pane.css:43-51`)
  - layered: aria-current="true" bg-primary/10 border-s-4 border-primary; flagged bg-error/10 border-s-4 border-error/30
  - none
  - 2 / 1
- **`driver-popover (+ title, description, progress-text, arrow sides, footer-btn, navigation-btns, close-btn)`** (modals, `app/assets/stylesheets/components/driver.css:19-92`)
  - re-theme of vendored driver.js tour: bg-base-100 text-body border-line rounded-box p-4 shadow-lg; title text-lg font-semibold text-heading; progress text-sm muted; arrow colours base-100; close button w-9 h-9 muted, focus ring-2 primary offset-2
  - none
  - 0 in views/helpers/app JS (classes written by vendored driver.js; onboarding_controller.js adds btn classes)
- **`.tabs-lift > .tab / .tabs-border > .tab`** (navigation, `app/assets/stylesheets/components/tabs.css:26-37`)
  - daisyUI override: lifted tab outline --tab-border-color body-subtle; idle labels text-stone-muted (both tab styles); active lifted tab text-heading font-medium with 2px primary top border
  - 2px
  - tabs-lift 1, tabs-border 2
- **`[data-theme="dark"] .badge-soft.badge-secondary`** (other, `app/assets/stylesheets/components/badges.css:17-21`)
  - daisyUI override: dark soft-secondary badge painted as neutral chip (neutral bg, neutral-content ink)
  - none
  - n/a
- **`[data-theme="dark"] .badge-soft.badge-error`** (other, `app/assets/stylesheets/components/badges.css:31-33`)
  - daisyUI override: lighter text for dark soft error badge
  - oklch(70% 0.18 28.536) literal
  - n/a
- **`.badge :is(.icon-*)`** (icons, `app/assets/stylesheets/components/badges.css:39-41`)
  - icon inside badge inherits badge colour
  - none
  - n/a
- **`login-panel`** (cards, `app/assets/stylesheets/login.css:26-73`)
  - sessions-page panel: bg-base-200 rounded-2xl pt-8 px-7 pb-6 (sm: larger); transparent 1px border with masked gradient frame (::before warning->line), radial warning wash (::after), drop + warm shadow; dark via .dark and [data-theme=dark]; ::selection warning tint; focus-visible outline 2px warning offset 2px radius 0.5rem
  - oklch black alphas, 26px/52px/-30px/31px/-13px shadow, 62%, 120%/72%
  - 6
- **`login-title / login-tagline`** (typography, `app/assets/stylesheets/login.css:78-89`)
  - 1.625rem 700 line-height 1.12 letter-spacing -0.02em balance text-heading (off the type scale); tagline mt-2 text-body-subtle
  - 1.625rem, -0.02em
  - 1 / 1
- **`login-beta / login-beta-summary / login-beta-body`** (toasts-alerts, `app/assets/stylesheets/login.css:95-107`)
  - amber-tinted disclosure card (warning 10% bg, 26% border), padding 0.5rem 0.75rem
  - 0.5rem/0.75rem
  - unused (0 / 0 / 0)
- **`login-backdrop`** (other, `app/assets/stylesheets/login.css:119-139`)
  - full-area Rangers logo mask (ranger-logo.svg) filled warning 20%; :has(> main .login-backdrop) relative; main isolation
  - z-index -1
  - 1
- **`login-status`** (other, `app/assets/stylesheets/login.css:144-150`)
  - flex centred gap-2 text-body mt-2; strong font-semibold text-warning
  - none
  - 1
- **`login-field / login-label-row / login-label-link`** (forms, `app/assets/stylesheets/login.css:156-189`)
  - field group mb-3; label 0.8125rem font-semibold text-heading mb-2; required asterisk hidden; label row flex justify-between; label link tap-target-link font-semibold text-warning hover:underline 0.8125rem no underline
  - 0.8125rem
  - 3 / 1 / 1
- **`login-reveal`** (buttons, `app/assets/stylesheets/login.css:194-204`)
  - show-password button absolute right 0.5rem, colour body-subtle, hover heading
  - 0.5rem
  - 1
- **`login-input / login-input--reveal`** (forms, `app/assets/stylesheets/login.css:209-255`)
  - @apply input input-lg w-full, radius 0.625rem, height 3.25rem, padding 0 1rem 0 2.75rem, font-size 1rem, bg base-100 at 0.85, border line 50%, inset shadow, caret warning; focus: outline none, border warning + 3px warning 22% ring; webkit-autofill repaint; reveal padding-right 3rem
  - 0.625rem, 3.25rem, 2.75rem, 3rem, 180ms; replaces daisyUI focus outline
  - 3 / 1
- **`login-submit-button`** (buttons, `app/assets/stylesheets/login.css:262-287`)
  - w-full font-bold radius 0.625rem mt 1.5rem min-height 3.25rem font 1rem; warning gradient face and warm shadow layered on the helper's btn variant; hover brightness 1.05; active translateY(1px)
  - 0.625rem, 3.25rem, cubic-bezier, shadow px values
  - 5
- **`login-columns / login-column`** (spacing, `app/assets/stylesheets/login.css:297-312`)
  - grid 1 col gap-4; from lg 28rem + 1fr gap 1.5rem; column max-w 58rem when holding columns
  - 28rem, 58rem
  - 1 / 1
- **`login-foot`** (spacing, `app/assets/stylesheets/login.css:315-317`)
  - mt-6 text-center
  - none
  - unused (0)
- **`login-doors / -doors-title / -doors-lede / -doors-list / -door-lead`** (links, `app/assets/stylesheets/login.css:319-416`)
  - secondary panel bg-base-200 radius 1rem, line 45% border with warning top, radial wash; title text-lg bold heading; lede 0.8125rem body-subtle; list rows grid 1.5rem/1fr border-top line 30%; icon min-h-9 text-warning 1.05rem; lead link inline-flex min-h-9 bold text-warning 0.95rem underline offset 3px thickness 1.5px; description links text-warning
  - 1rem, 1.5rem, 1.05rem, 0.95rem, 0.85rem, 3px, 1.5px
  - 1 / 1 / 0 / 1 / 1
- **`login reduced motion`** (other, `app/assets/stylesheets/login.css:432-439`)
  - all descendants of .login-panel: transition-duration 0.01ms, animation none
  - !important x2
  - n/a

### helpers-components (125)

- **`button_row`** (buttons, `app/helpers/button_helper.rb:52`)
  - button_row(options = {}) { block }; options: sticky: true/false (default false), class: free string, any other HTML attribute passed to the div
  - Returns nil when the captured block is blank. Non-sticky: <div class="button-row {class}">. Sticky: a spacer <div class="button-row-spacer {tallest btn size class found in the row, default btn-sm}" style="--button-row-controls: N" aria-hidden="true"> followed by <div class="button-row fixed bottom-0 left-0 right-0 w-full z-50 bg-base-100 py-4 px-4 border-t border-line shadow-[0_-4px_6px_-1px_rgba(0,0,0,0.1)] dark:shadow-[0_-4px_6px_-1px_rgba(0,0,0,0.3)] lg:static lg:inset-auto lg:w-auto lg:z-auto lg:bg-transparent lg:border-0 lg:shadow-none lg:px-0 lg:py-0 {class}">. N = count of top-level non-hidden elements, parsed from the captured HTML with Nokogiri. No ARIA role on the row
  - Arbitrary shadow values with literal rgba(0,0,0,0.1) and rgba(0,0,0,0.3) (line 63); inline style custom property --button-row-controls (line 83); z-50
- **`button_action`** (buttons, `app/helpers/button_helper.rb:106`)
  - button_action(label, variant, controller: nil, **options); variant positional and required: :primary, :secondary, :tertiary, :success, :error, :warning, :dark, :ghost; size: "xs"/"sm"/"base"/"lg"/"xl" (default "sm"); icon: FA name; icon_type: default "regular"; disabled: bool; full_width: bool; type: default "button"; controller: sets data-controller; class: free string appended; data:/aria:/id and any HTML attribute pass through
  - <button type="button" class="btn {variant class} {size class} [w-full lg:w-auto] {class}">[<i fa icon>]label</button>. Variant map (line 18): primary=btn-primary, secondary="btn-secondary btn-outline", tertiary=btn-ghost, success=btn-success, error=btn-error, warning=btn-warning, dark=btn-neutral, ghost=btn-ghost. Unknown variant falls back to btn-primary (line 310). Size map (line 32): xs=btn-xs, sm=btn-sm, base=btn-md, lg=btn-lg, xl=btn-xl; unknown size falls back to btn-sm (line 281). disabled: replaces the variant class with btn-disabled and adds disabled + aria-disabled="true" (lines 282-290). Icon always rendered before the label, no explicit gap class (relies on btn gap), icon aria-hidden via fa_icon. No icon-only guard: an empty label with no aria-label yields an unnamed button
  - none (classes are whole names from frozen hashes)
- **`button_link`** (buttons, `app/helpers/button_helper.rb:133`)
  - button_link(label, variant, url, options = {}, &block); label or block (both raises); same variant/size/icon/icon_type/disabled/full_width/class options as button_action; method: sets data-turbo-method; params: hash appended as query string
  - <a href="url" class="btn {variant} {size} [w-full lg:w-auto] {class} no-decoration">[icon]label</a> via link_to. Same variant and size maps and fallbacks as button_action. disabled: renders <a role="link" class="btn btn-disabled ... no-decoration" disabled aria-disabled="true"> with no href (line 162). Unknown options (e.g. icon_position) are passed through to link_to as HTML attributes
  - none
- **`cancel_button (alias cancel_link)`** (buttons, `app/helpers/button_helper.rb:169 (alias line 175)`)
  - cancel_button(url), (url, label), (url, options), (url, label, options); label default "Cancel"
  - button_link(label, :secondary, url, options): <a class="btn btn-secondary btn-outline btn-sm no-decoration">Cancel</a>. Variant fixed (a variant: in options would be passed as an HTML attribute, not used)
  - none
- **`edit_link`** (buttons, `app/helpers/button_helper.rb:185`)
  - edit_link(url, [label], [options]); label default "Edit"; icon default "pen-to-square" icon_type :solid, overridable via icon:; other button_link options
  - <a class="btn btn-secondary btn-outline btn-sm no-decoration"><i class="fa-solid fa-pen-to-square" aria-hidden="true"></i>Edit</a>. Variant fixed :secondary
  - none
- **`export_csv_link`** (buttons, `app/helpers/button_helper.rb:204`)
  - export_csv_link(url, [label], [options]); label default "Export CSV"; icon default "file-csv" :solid; variant: default :secondary (only button helper besides delete_button/submit_button that reads variant from options)
  - <a class="btn btn-secondary btn-outline btn-sm no-decoration"><i fa-solid fa-file-csv>Export CSV</a>
  - none
- **`delete_button`** (buttons, `app/helpers/button_helper.rb:217`)
  - delete_button(url, [label], [options]); label default "Delete"; variant: default :error; confirm_message: plain text -> data-turbo-confirm holding confirm_modal_dialog markup with variant :error; confirm_modal: hash -> merges confirm_modal({variant: :error}.merge(hash)) data (turbo_confirm, turbo_method, turbo); method default :delete
  - <a class="btn btn-error btn-sm no-decoration" data-turbo-method="delete" [data-turbo-confirm="<dialog ...>"]>Delete</a>. A link, not a <button>, for a destructive action. With no confirm option there is no confirmation at all
  - none
- **`submit_button`** (buttons, `app/helpers/button_helper.rb:239`)
  - submit_button([label], [options]); label default "Submit"; variant: default :primary; disabled:; size:, full_width:, class:
  - submit_tag: <input type="submit" value="label" class="btn btn-primary btn-sm {class}">. An <input>, so icon:/icon_type: are not extracted and would become HTML attributes; no icon support. Rails submit_tag default data-disable-with behaviour applies (config.load_defaults 8.0; not checked further)
  - none
- **`button_classes`** (buttons, `app/helpers/button_helper.rb:300 (private, callable from views)`)
  - button_classes(options, variant); options size:, full_width:, class:
  - Returns the class string "btn {variant} {size} [w-full lg:w-auto] {class}" for a non-button element (used for <summary> in dropdown_menu and a <span> in ui_match_stepper)
  - none
- **`ui_table`** (tables-lists, `app/helpers/table_helper.rb:99`)
  - ui_table([legacy options hash], full_width: false, striped: true, responsive: true, caption: nil, container_class: nil, size: "base" ("sm"/"base"; other raises KeyError via fetch), **html options incl class:) { |t| ... }
  - <div class="table-container {w-full | w-fit max-w-full} {container_class}"><table class="text-body {text-sm|text-base} table-auto [w-full] [responsive-table] {class}">[<caption class="sr-only">]...</table></div>. Not the daisyUI "table" class: custom classes table-container, table-header etc. (tables.css). responsive: true folds rows into labelled cards below lg via data-label attributes. No empty-state handling: an empty body renders an empty table
  - none
- **`ui_table builder: header / heading / body / row / row_header / cell`** (tables-lists, `app/helpers/table_helper.rb:234, 255, 271, 304, 394, 409`)
  - t.header(**opts); t.heading(value = nil, right: false, center: false, width: nil, **opts); t.body(**opts); t.row(state: nil (:error/:warning/:success/:total), align: nil (:top/:middle), **opts); t.row_header(value = nil, **opts); t.cell(value = nil, right: false, center: false, **opts incl colspan:); each takes a block for content
  - t.header(**opts) {}:<thead class="table-header {class}"><tr>; PINNED_HEADER_CLASSES constant "lg:sticky lg:top-0 lg:z-20 [&_th]:bg-base-200" for callers to pass. t.heading(value, right:, center:, width:, **opts): <th scope="col" class="table-heading {text-end|text-center|text-left}"> with width as inline style "width: X". t.body: <tbody>. t.row(state: nil, align: (:top/:middle; other raises KeyError), **opts): <tr class="table-row-striped table-row-hover | table-row-base table-row-hover {state class} {align-top|align-middle}">. t.row_header: <th scope="row" class="table-row-header" data-label>. t.cell(value, right:, center:, colspan...): <td class="table-cell-td {align}" data-label="{heading text}">; spanning cells get no data-label
  - state: map (line 54 and SeverityStyleHelper): success="!bg-success/10", total="!bg-base-300 font-semibold", error="!bg-error/10", warning="!bg-warning/10"; unknown state paints nothing. !important used (documented reason: beats striping). Left alignment spelled text-left while right is text-end (line 470-476). heading width: is an inline style (line 262)
- **`ui_table builder: detail_row`** (tables-lists, `app/helpers/table_helper.rb:337`)
  - t.detail_row(id:, colspan: nil (defaults to heading count), label: nil, **opts) { block }
  - <tr id class="table-detail-row hidden {class}" aria-hidden="true"><td colspan class="table-detail-cell">[<div class="lg:hidden font-semibold text-heading mb-1">label</div>]content</td></tr>. Opened by toggle_controller
  - none
- **`ui_table builder: detail_row_toggle`** (tables-lists, `app/helpers/table_helper.rb:376`)
  - t.detail_row_toggle(label, id:, describing: nil, name: nil, **opts)
  - button_action(label + chevron-down icon (text-xs), :ghost, controller: "toggle") with class "min-h-9 h-auto py-1.5 {class}", aria-controls=id, aria-expanded="false", aria-label "label — describing" (or name:), data-toggle-dom-id-value=id. Result: <button class="btn btn-ghost btn-sm min-h-9 h-auto py-1.5">
  - none
- **`ui_table_rows`** (tables-lists, `app/helpers/table_helper.rb:149`)
  - ui_table_rows(headings:, striped: true, responsive: true) { |t| }
  - Rows only, no <table>, for turbo_stream replacement; data-label taken from the headings array
  - none
- **`modal`** (modals, `app/helpers/modal_helper.rb:30`)
  - modal(options = {}) { |m| }; id: (default "modal-" + random hex); placement: "top"/"bottom"/other=center; closable: default true; close_button: false suppresses the auto footer; size: :sm/:md/:lg/:xl/:full, default :lg (header comment line 13 says :md is the default; unknown size falls back to :md); class: appended to <dialog>
  - <dialog id class="modal size-auto max-h-none max-w-none overflow-y-auto {modal-top|modal-bottom|modal-middle} {class}" data-controller="modal" data-modal-closable-value="true|false"><div class="modal-box {max-w-sm|max-w-md|max-w-2xl|max-w-4xl|max-w-full}">...</div>[<form method="dialog" class="modal-backdrop"><button>close</button></form>]</dialog>. If the block never calls m.footer and close_button is not false, appends m.footer { "Close" secondary button }. The backdrop <button> has visible text "close" (lowercase), no type, not from ButtonHelper. No aria-labelledby/aria-modal on the dialog
  - Size map: sm=max-w-sm, md=max-w-md, lg=max-w-2xl, xl=max-w-4xl, full=max-w-full (line 22)
- **`ModalBuilder title / body / footer / close_button`** (modals, `app/helpers/modal_helper.rb:176, 190, 197, 205`)
  - m.title(header, options) or block; m.body(options) {}; m.footer(options) {}; m.close_button(label = "Close")
  - title: <div class="modal-header-bar"><h3 class="modal-title-text {class}">title</h3>{button_action(icon xmark class "w-3 h-4" + <span class="sr-only">Close modal</span>, :ghost, class: "btn-circle", data-action modal#hide)}</div>. body: <div class="modal-body-content {class}">. footer: button_row with class "modal-footer-bar {class}". close_button: button_action(label, :secondary, data-action modal#hide)
  - Icon sized with w-3 h-4 utilities (line 179)
- **`modal_dialog`** (modals, `app/helpers/modal_helper.rb:70`)
  - modal_dialog(title:, id: nil, frame: "modal" (false for none), **modal options) { body }
  - turbo_frame_tag(frame) { modal(close_button: false) { m.title(title) + m.body } }. No footer is added; the body supplies one (usually modal_form_footer)
  - none
- **`modal_form_footer`** (modals, `app/helpers/modal_helper.rb:81`)
  - modal_form_footer(form = nil, submit:, close: "Cancel", **submit_options)
  - button_row { form.submit(submit, **opts) or submit_button(submit, **opts) + modal_close_button(close) } -> <div class="button-row">submit + <button class="btn btn-secondary btn-outline btn-sm" data-action="modal#hide">Cancel</button></div>
  - none
- **`modal_close_dialog`** (modals, `app/helpers/modal_helper.rb:88`)
  - modal_close_dialog()
  - turbo_stream.update("modal", "") via turbo_empty_frame
  - none
- **`modal_close_button`** (modals, `app/helpers/modal_helper.rb:92`)
  - modal_close_button(label = "Close")
  - button_action(label, :secondary, data: { action: "modal#hide" })
  - none
- **`confirm_modal`** (modals, `app/helpers/modal_helper.rb:96`)
  - confirm_modal(options); method: default "get"; title:, message:, confirm_label:, cancel_label:, variant: (passed to confirm_modal_dialog)
  - Returns a data hash { turbo_confirm: <dialog markup String>, turbo_method: method, turbo: "true" } for a link's data:
  - none
- **`confirm_modal_dialog`** (modals, `app/helpers/modal_helper.rb:127`)
  - confirm_modal_dialog(options); title default "Confirm"; message default "Continue?"; confirm_label default "Confirm"; cancel_label default "Cancel"; variant: default :primary (destructive callers pass :error)
  - Plain String (not html_safe) of modal { title, body, footer [button_action(confirm_label, variant, id: "turbo-confirm-button"), button_action(cancel_label, :secondary, id: "turbo-cancel-button")] }; default modal size :lg, so the confirm dialog is max-w-2xl, and it carries the backdrop form. Fixed DOM ids
  - none
- **`modal_placement_class`** (modals, `app/helpers/modal_helper.rb:152`)
  - modal_placement_class(placement)
  - "top"=modal-top, "bottom"=modal-bottom, anything else modal-middle
  - none
- **`tab_navigation`** (navigation, `app/helpers/tabs_helper.rb:9`)
  - tab_navigation(id, active_tab = nil, options = {}) { |tabs| tabs.pane(title, target_id, href: nil) { content }; tabs.initial_content(target_id) {} }; options[:remote] is stored but never read (line 31)
  - <div data-controller="tabs" data-tabs-toggle="#id" data-tabs-active-classes-value="tab-active"><div class="tabs tabs-border" role="tablist" aria-label="Tabs">{<button type="button"> or <a href data-remote-tab> per pane, class "tab [tab-active]", role="tab", id "{target}-tab", aria-controls, aria-selected, tabindex 0/-1, data-action click->tabs#show}</div>{<div> or <turbo-frame> per pane: id=target, class "mt-4 [hidden]", role="tabpanel", aria-labelledby, tabindex="0"}</div>. Active pane: active_tab match, else the first pane. Every tablist is named the generic "Tabs"
  - none
- **`fa_icon`** (icons, `app/helpers/icon_helper.rb:80`)
  - fa_icon(name, style = nil ("regular" default; "regular"/"solid"/"brands", other raises in dev/test), html_options = {}, text = nil); name underscores converted to hyphens; html_options: class:, start: 1/2, end: 1/2 (other raises KeyError), size: any string, fixed: bool, label: string, aria-hidden override, any HTML attribute
  - <i class="fa-{style} fa-{name} {class} [ms-1|ms-2] [me-1|me-2] [fa-{size}] [fa-fw]" aria-hidden="true" [title=label]></i>[<span class="sr-only">label.</span>][text]. In development/test raises if the name is missing from the subset/catalog or a regular glyph does not exist. label: is the only way to give an icon an accessible name
  - size: builds a class by interpolation "fa-#{size}" (line 107)
- **`nav_link_to`** (navigation, `app/helpers/link_helper.rb:9`)
  - nav_link_to(name, path, options = {}, is_root = false)
  - link_to with class "{class} [active] no-decoration" and aria-current="true" when the path matches (exact for root, prefix otherwise)
  - none
- **`callsign_link`** (links, `app/helpers/link_helper.rb:20`)
  - callsign_link(person, path = nil, **options); class: merged
  - <a class="link link-primary inline-flex min-h-5 items-center {class}" href="path or person">callsign</a>
  - min-h-5 (20px), documented as deliberately under the 36px floor (line 4-7)
- **`email_link_or_dash`** (links, `app/helpers/link_helper.rb:27`)
  - email_link_or_dash(email)
  - mail_to(email, class: "link link-primary inline-flex min-h-5 items-center") or "—"
  - none
- **`person_display_name`** (other, `app/helpers/link_helper.rb:36`)
  - person_display_name(person, person_id, blank: "—")
  - Text: callsign, or blank: when no id, or "Deleted #<id>"
  - none
- **`person_display_link`** (links, `app/helpers/link_helper.rb:51`)
  - person_display_link(person, person_id, blank: "—", path: nil, in_turbo_frame: false)
  - callsign_link (with data-turbo-frame="_top" when in_turbo_frame) when the person exists and the viewer holds a person-view role; else person_display_name text
  - none
- **`can_view_person_page?`** (other, `app/helpers/link_helper.rb:64`)
  - can_view_person_page?
  - Boolean role check, no markup
  - none
- **`dropdown_menu`** (navigation, `app/helpers/navigation_helper.rb:41`)
  - dropdown_menu(label, variant: :secondary (ButtonHelper variants), summary_class: nil, menu_class: nil, menu_label: label, trigger_label: nil, **details options incl class: e.g. "dropdown-end") { items }
  - <details class="dropdown {class}"><summary class="btn {variant class} btn-sm list-none {summary_class}" [aria-label=trigger_label]>label <i class="fa-solid fa-chevron-down"></i></summary><ul class="dropdown-content dropdown-panel mt-2 {menu_class}" aria-label="menu_label">...</ul></details>. With trigger_label the chevron is dropped (icon-only trigger). No aria-haspopup (deliberate per comment). Closing on outside click is in application.js
  - none
- **`dropdown_item`** (navigation, `app/helpers/navigation_helper.rb:62`)
  - dropdown_item(label, url, options = {})
  - <li><a class="no-decoration dropdown-link {class}" href>label</a></li>
  - none
- **`dropdown_button`** (navigation, `app/helpers/navigation_helper.rb:78`)
  - dropdown_button(label, options = {})
  - <li><button type="button" class="dropdown-link w-full text-start {class}">label</button></li>. A raw tag.button, not ButtonHelper
  - none
- **`dropdown_divider`** (navigation, `app/helpers/navigation_helper.rb:91`)
  - dropdown_divider()
  - <li aria-hidden="true"></li> (daisyUI menu draws it as a line)
  - none
- **`dropdown_item_disabled`** (navigation, `app/helpers/navigation_helper.rb:99`)
  - dropdown_item_disabled(label)
  - <li><span class="dropdown-disabled-item">label</span></li>; no aria-disabled
  - none
- **`page_title`** (typography, `app/helpers/page_layout_helper.rb:9`)
  - page_title(title) { optional back-link block }
  - <div class="mb-4">[<div class="mb-1">block</div>]<h1 class="text-3xl font-normal">title</h1></div>
  - none
- **`render_for_user / render_partial_for_user`** (other, `app/helpers/page_layout_helper.rb:20, 32`)
  - render_for_user(action, locals = {}, status = nil); render_partial_for_user(partial, locals = {})
  - render with locals[:person] = current_user; no markup of their own
  - none
- **`year_selector`** (navigation, `app/helpers/page_layout_helper.rb:37`)
  - year_selector(year, options); options: years:, min_year: (default 1998), skip_pandemic:, include_current_year: (default true), include_year_argument: (default true), year:, include_all: (adds "All" last), keep: hash of params kept as hidden fields
  - <div><form method="get" data-controller="form"><div class="{AppFormBuilder::HORIZONTAL_WRAPPER_CLASSES}"><label for="year-selector" class="{HORIZONTAL_LABEL_CLASSES}">Select the year to view:</label><div><select id="year-selector" name="year" class="{AppFormBuilder::SELECT_CLASSES}" data-action="change->form#submit"></div></div>{hidden keep fields}</form></div>. Auto-submits on change, no submit button. Fixed id "year-selector"
  - min_year 1998 (line 111)
- **`year_selector_compact`** (navigation, `app/helpers/page_layout_helper.rb:62`)
  - year_selector_compact(year, options) (same options as year_selector)
  - <form method="get" data-controller="form" class="flex items-center gap-2"><label for="year-selector-compact" class="text-lg font-medium text-stone-emphasis whitespace-nowrap">Year to view:</label><select id="year-selector-compact" class="select select-sm w-auto" aria-label="Select year to view" data-action="change->form#submit">...</select>{keep fields}</form>. Has both a <label for> and an aria-label that differs from it
  - none
- **`year_selector_keep_fields`** (forms, `app/helpers/page_layout_helper.rb:86`)
  - year_selector_keep_fields(options) reads options[:keep]
  - hidden_field_tag per kept param (name[] per array item, id: nil)
  - none
- **`title_year_selector`** (typography, `app/helpers/page_layout_helper.rb:102`)
  - title_year_selector(title, year, options = {}, &block)
  - page_title("#{year} #{title}") + year_selector(year, options), joined by string interpolation then .html_safe
  - none
- **`turbo_empty_frame`** (other, `app/helpers/turbo_helper.rb:4`)
  - turbo_empty_frame(target_id)
  - turbo_stream.update(target_id, "")
  - none
- **`turbo_response`** (other, `app/helpers/turbo_helper.rb:8`)
  - turbo_response(streams)
  - respond_to turbo_stream render; no markup
  - none
- **`page_redirect`** (other, `app/helpers/turbo_stream_actions_helper.rb:4`)
  - turbo_stream.page_redirect(url) (prepended into Turbo::Streams::TagBuilder)
  - <turbo-stream action="page_redirect" url="...">; handled by Turbo.StreamActions.page_redirect in app/javascript/application.js:54
  - none
- **`severity_style`** (color, `app/helpers/severity_style_helper.rb:20`)
  - severity_style(severity, part); severity :error/:warning; part :row/:text
  - error: row "!bg-error/10", text "text-error font-semibold"; warning: row "!bg-warning/10", text "text-warning font-semibold"; anything else nil
  - !important in the row classes (documented: beats odd/even striping)
- **`menu_build / menu_uses_person? / menu_resolve_path / menu_item_active_prefix? / menu_item_active? / menu_active_prefix_path / menu_item_options / menu_item_confirm_data / menu_each_section / menu_section_has_content?`** (navigation, `app/helpers/menu_helper.rb:16, 24, 34, 51, 65, 76, 84, 93, 106, 117`)
  - Data helpers over Menus definitions: build filtered sections, resolve a Symbol route or String path (with year= carried for year_scoped items), active-state matching (exact, or prefix when active_prefix), strip menu-only keys from an item, and build confirm data
  - No markup. menu_item_confirm_data returns confirm_modal(title: "Confirm {title}", message: "{description}?", method: :delete)
  - none
- **`navbar_render_menu`** (navigation, `app/helpers/navbar_helper.rb:22`)
  - navbar_render_menu(menu_definition, context)
  - dropdown_item per menu item with dropdown_divider between sections and nested sections; confirm: items get confirm_modal data
  - none
- **`kbd_shortcut / kbd_modifier_name / kbd_modifier_filter / mac_client?`** (other, `app/helpers/navbar_helper.rb:79, 86, 95, 100 (private, used from views)`)
  - kbd_shortcut(key, shift: false)
  - Strings: "⌘⇧K" on Mac UA, "⌃⇧K" elsewhere; "Cmd"/"Ctrl"; "meta"/"ctrl"; UA sniff for "Mac"
  - Unicode glyphs ⌘ ⌃ ⇧ used as keyboard symbols
- **`mega_menu_offered? / mega_recent_items / mega_favorite_items / mega_favorite_categories / mega_search_items / mega_labeled / mega_category_groups`** (navigation, `app/helpers/mega_menu_helper.rb:27, 34, 39, 45, 56, 66, 76`)
  - Data accessors over controller-set ivars
  - No markup
  - none
- **`mega_panel`** (navigation, `app/helpers/mega_menu_helper.rb:86`)
  - mega_panel(key) { block }
  - <section class="mega-menu-panel" [hidden] data-mega-menu-target="panel" data-panel=key>
  - none
- **`mega_chrome_button`** (navigation, `app/helpers/mega_menu_helper.rb:95`)
  - mega_chrome_button(label, key, options = {})
  - button_action(label, :ghost, class "mega-menu-chrome-btn {class}", aria-current="true|false", data mega-menu#show) -> <button class="btn btn-ghost btn-sm mega-menu-chrome-btn">. A panel switcher built from buttons with aria-current rather than role=tab
  - none
- **`mega_category_index_button`** (navigation, `app/helpers/mega_menu_helper.rb:106`)
  - mega_category_index_button(category, options = {})
  - button_action(icon + <span class="mega-menu-cat-text"><span class="mega-menu-item-title">title</span><span class="mega-menu-item-desc">description</span></span> + chevron-right, :ghost, class "mega-menu-cat-btn {class}")
  - none
- **`mega_star_button / mega_category_star_button`** (navigation, `app/helpers/mega_menu_helper.rb:125, 141`)
  - mega_star_button(key, label, panel_key); mega_category_star_button(category, panel_key)
  - Icon-only button_action("", :ghost, type submit, form "mega-menu-star-form", formaction, id "mega-star-{panel}-{key}", icon star solid when favorited else regular, class "mega-menu-star [mega-menu-star-on]", aria-label "Favorite {label}", aria-pressed)
  - none
- **`mega_item_link_options`** (navigation, `app/helpers/mega_menu_helper.rb:146`)
  - mega_item_link_options(item)
  - Link options: class "mega-menu-item-link no-decoration", data-action mega-menu#close or confirm data
  - none
- **`sidebar_menu`** (navigation, `app/helpers/sidebar_helper.rb:55`)
  - sidebar_menu(theme = "me", id: "sidebar-drawer", width: "w-65 lg:w-50", **_options ignored) { menu }; comment at line 52 says width default 'w-65 lg:w-55'
  - content_for(:sidebar): <div class="drawer-side z-50 lg:h-full"><label for=id class="drawer-overlay" aria-label="Close sidebar"></label><aside id="{id}-content" class="{width} h-full bg-chrome flex flex-col relative" aria-label="Sidebar navigation" aria-labelledby="{id}-label" data-controller="sidebar stream-nav">[header <div class="flex items-center justify-between h-16 shrink-0 z-10 ps-3 pe-2 bg-chrome border-b border-sidebar-divider lg:hidden"><span id="{id}-label" class="text-base font-semibold text-sidebar-content">Sidebar</span>{button_action "Close", :ghost, icon xmark, aria-label "Close sidebar"}</div>][<div class="flex-1 min-h-0 overflow-y-auto pb-4 z-10">menu</div>][<div class="absolute bottom-0 inset-x-0 border-t border-sidebar-divider text-center"><img ranger-logo.png alt="BRC Ranger Logo" class="h-[140px] w-[140px] mx-auto mb-5 opacity-30"></div>]</aside></div>. aside carries both aria-label and aria-labelledby
  - Arbitrary h-[140px] w-[140px] (line 100); opacity-30
- **`sidebar_section`** (navigation, `app/helpers/sidebar_helper.rb:112`)
  - sidebar_section(title, theme: "me") { block }
  - <h6 class="sidebar-section-header {theme section_bg} {theme section_text}">title</h6> + content. Themes (line 19): me = sidebar-group-title-default text-sidebar-content; admin = sidebar-group-title-hq text-sidebar-content; hq = sidebar-group-title-default with empty section_text; unknown theme -> me
  - none
- **`sidebar_submenu`** (navigation, `app/helpers/sidebar_helper.rb:119`)
  - sidebar_submenu(title, icon: nil, icon_type: "regular", theme: "me")
  - <div class="sidebar-section-header {theme}" aria-expanded="false">[icon class "shrink-0 w-5 h-5 me-2"]<span class="flex-1">title</span></div>. aria-expanded is a fixed "false" on a non-interactive div
  - none
- **`sidebar_item`** (navigation, `app/helpers/sidebar_helper.rb:129`)
  - sidebar_item(title, url, icon: nil, icon_type: "regular", badge: nil, badge_variant: :error, use_turbo: false, active: nil, active_prefix: false, theme: "me", root: false, **html_options)
  - <a class="sidebar-nav-item {sidebar-link-default|sidebar-link-hq} {class} no-decoration [active]" [aria-current="true"] [data-active-prefix] [data-action="click->stream-nav#follow"]>title</a>. icon:, icon_type:, badge: and badge_variant: are accepted but never rendered (the renderer that used them, render_sidebar_content, has no caller)
  - none
- **`sidebar_submenu_item`** (navigation, `app/helpers/sidebar_helper.rb:163`)
  - sidebar_submenu_item(title, url, **options)
  - <li>sidebar_item with class "pl-4"</li>
  - none
- **`sidebar_render_menu`** (navigation, `app/helpers/sidebar_helper.rb:171`)
  - sidebar_render_menu(menu_definition, context, theme: "me")
  - Depth-0 titled sections via sidebar_section (h6), deeper titled or submenu sections via sidebar_submenu, items via sidebar_item
  - none
- **`sidebar_badge (private)`** (other, `app/helpers/sidebar_helper.rb:240`)
  - sidebar_badge(text, variant)
  - <span class="sidebar-badge {variant}">; variants (line 41): error "text-error bg-error/10 border border-error/30", success "text-success bg-success/10 border border-success/30", warning "text-warning bg-warning/10 border border-warning/30", info "bg-primary/10 border border-primary/30" (no text colour), default "text-neutral-content bg-neutral border border-neutral-content/30". Only reachable from render_sidebar_content, which has no caller
  - none
- **`years_breakdown`** (other, `app/helpers/year_helper.rb:4`)
  - years_breakdown(person)
  - Renders common/_years_breakdown: ui_callout_box :warning (6-hour rule text) + hand-written <dl class="ui-label-value"> (not ui_label_value); first <dt> has "font-medium text-heading", the other <dt>s have no class; empty values <span class="text-stone-muted italic">none</span>; year lists in <span class="text-stone-muted">[...]</span>
  - none
- **`year_range`** (typography, `app/helpers/year_helper.rb:8`)
  - year_range(years)
  - Plain string "2019, 2021 - 2023"; empty -> <span class="text-stone-muted">none</span> (not italic, unlike the partial above)
  - none
- **`dropdown_scroll_list`** (navigation, `app/helpers/application_helper.rb:65`)
  - dropdown_scroll_list(items) (items respond to title, id)
  - Renders common/_dropdown_scroll_list: <div class="flex flex-wrap gap-2 my-4" data-controller="dropdown-fit"> with one dropdown_menu per first letter (name "dropdown-scroll-list", data-action toggle->dropdown-fit#fit, menu_class "max-h-96 overflow-y-auto flex-nowrap left-(--dropdown-fit-shift)") and dropdown_item links to "#id" anchors
  - left-(--dropdown-fit-shift) CSS-variable utility; max-h-96
- **`none_stated`** (typography, `app/helpers/application_helper.rb:80`)
  - none_stated()
  - <i class="text-stone-muted">None stated</i>
  - none
- **`value_or_dash`** (typography, `app/helpers/application_helper.rb:84`)
  - value_or_dash(value)
  - value or "—" (em dash, plain text, no sr text)
  - none
- **`record_title`** (tables-lists, `app/helpers/application_helper.rb:108`)
  - record_title(title, active:) { details }
  - <div class="flex items-start gap-2">{fa circle-check solid "icon-success mt-1" | circle-xmark solid "icon-error mt-1"}<div><div class="font-semibold text-heading">title</div>details</div></div>. Icon has no label:, so active/inactive is conveyed by icon shape and colour only (aria-hidden)
  - none
- **`value_list`** (tables-lists, `app/helpers/application_helper.rb:121`)
  - value_list(items)
  - <div class="flex flex-col gap-1"><div>item</div>...</div> or "—"
  - none
- **`expires_on_cell / expires_at_cell`** (other, `app/helpers/application_helper.rb:132, 138 (private expiry_cell :380)`)
  - expires_on_cell(record, fallback:); expires_at_cell(record)
  - <div class="flex flex-wrap items-center gap-2">date [ui_badge "Expired", :warning, icon triangle-exclamation solid]</div> or fallback (default "—")
  - none
- **`photo_tag`** (other, `app/helpers/application_helper.rb:142`)
  - photo_tag(photo, options); width:, height: (px numbers), alt: default ""
  - image_tag with loading="lazy", alt "" by default, width/height written as inline style "width: Npx;"/"height: Npx;"; no photo -> fa_icon "user" (regular), no label
  - Inline style px dimensions (lines 148-149)
- **`hyperlink_text / nl2br / rich_text`** (typography, `app/helpers/application_helper.rb:172, 183, 227`)
  - hyperlink_text(text); nl2br(text); rich_text(html)
  - Sanitized text with auto-linked URLs/emails/phones (plain <a>, no class) and <br>; nl2br escapes and joins with <br>; rich_text sanitizes with a scrubber keeping lexxy-content__* classes
  - none
- **`hour_not_counted_disclaimer`** (toasts-alerts, `app/helpers/application_helper.rb:231`)
  - hour_not_counted_disclaimer(is_training = false)
  - <div class="my-2 text-sm">Note: ...</div>: a notice as plain small text, not ui_callout_box; the string literal carries embedded newline and indentation
  - none
- **`slot_virtual_venue_badge`** (other, `app/helpers/application_helper.rb:241`)
  - slot_virtual_venue_badge(slot)
  - ui_badge(slot.venue_label, :secondary, icon: "laptop") when the slot is virtual, else nil
  - none
- **`back_to`** (navigation, `app/helpers/application_helper.rb:245`)
  - back_to(label, url, options); icon: default "arrow-left"; icon_type: default :solid; aria_label: default "Back to {label}"
  - <a class="inline-flex-center-gap-2 min-h-9 text-body no-decoration hover:text-stone-emphasis transition-colors" aria-label="Back to {label}"><i fa arrow-left></i><span>label</span></a>. Visible text is label alone; accessible name prefixes "Back to"
  - none
- **`back_to_dashboard`** (navigation, `app/helpers/application_helper.rb:263`)
  - back_to_dashboard()
  - back_to "Clubhouse Dashboard", me_root_path
  - none
- **`yes_no_badge`** (other, `app/helpers/application_helper.rb:270`)
  - yes_no_badge(answer)
  - ui_badge("Yes", :success, icon circle-check solid) or ui_badge("No", :secondary, icon circle-minus solid)
  - none
- **`qualification_icon / qualification_bar_variant / qualification_section / qualification_next_step / qualification_goal_counts / qualification_name / qualification_amount / qualification_unit`** (other, `app/helpers/application_helper.rb:283, 297, 335, 311, 323, 307, 345, 353`)
  - Page-specific helpers for the qualifications page
  - qualification_icon: circle-check solid icon-success / hourglass-half solid text-primary / circle-minus solid text-stone-icon / circle regular text-stone-icon, all unlabeled. qualification_bar_variant: :success/:primary/:secondary. qualification_section: ui_section(title, badge:, badge_color:, html aria-label "{title} Qualification") with <div class="pb-2 text-base text-stone-subtle">rule</div>. qualification_next_step: sentence with <strong class="tabular-nums">. Others return strings
  - none
- **`setting / phone_format / title_marking_inactive / position_choices_by_team`** (other, `app/helpers/application_helper.rb:57, 61, 90, 97`)
  - Value helpers
  - No markup; title_marking_inactive appends " (inactive)" as text
  - none
- **`action_box`** (cards, `app/helpers/ui_components/action_box_helper.rb:49`)
  - action_box(title:, description:, url:, icon:, icon_type: :solid, button_label: "View", button_variant: :primary, options: {}); options[:class] appended; options[:button_data] meant for the button
  - <div class="bg-base-100 border border-line rounded-lg p-4 flex flex-col items-center text-center h-full {class}"><div class="flex-1 flex flex-col items-center justify-center mb-4"><i class="fa-{type} fa-{icon} text-3xl icon-warning mb-2"><h3 class="heading-title text-heading mb-1">title</h3><p class="text-sm text-body leading-relaxed">description</p></div>{button_link(button_label, button_variant, url, icon arrow-right solid, size "sm", class "w-full justify-center mt-auto", icon_position: :end, data: button_data)}</div>. The icon is always gold (icon-warning). Always an h3
  - none
- **`ui_badge`** (other, `app/helpers/ui_components/badge_helper.rb:29`)
  - ui_badge(text, variant, **options) or ui_badge(variant, **options) { block }; variant :primary/:secondary/:error/:success/:warning; size: "xs" (default)/"sm"/"base" (other raises KeyError); icon:, icon_type: default :solid; class: prepended; other HTML attributes
  - <span class="{class} badge badge-{variant} badge-soft {text-xs|text-sm|text-base} [inline-flex items-center gap-2]">[<i fa icon class="{icon tint}">]text</span>. Variant map (line 12): primary="badge-primary badge-soft", secondary="badge-secondary badge-soft", error="badge-error badge-soft", success="badge-success badge-soft", warning="badge-warning badge-soft"; unknown -> secondary. Icon tints (line 26): success=icon-success, warning=icon-warning, error=icon-error, info=icon-info; primary/secondary icons inherit. No size class from daisyUI (badge-sm etc.); size is text size only. Comment line 49 says gap-1.5, code adds gap-2
  - none
- **`bulk_select`** (forms, `app/helpers/ui_components/bulk_select_helper.rb:13`)
  - bulk_select(**options) { block }
  - <div data-controller="checkbox-select-all" ...>
  - none
- **`bulk_select_all`** (forms, `app/helpers/ui_components/bulk_select_helper.rb:22`)
  - bulk_select_all(label: nil, aria_label: nil, selected: 0, checked: selected.positive?, count: true, name: "select_all")
  - Without label: <label class="inline-flex items-center justify-center min-h-9 min-w-9 cursor-pointer"><input type="checkbox" class="{AppFormBuilder::CHECKBOX_CLASSES}" [aria-label] data-checkbox-select-all-target="toggle"></label>. With label: <div class="flex flex-wrap items-center gap-4 my-2"><label class="flex items-center gap-2 min-h-9">box<span>label</span></label>[bulk_select_count]</div>
  - none
- **`bulk_select_count`** (forms, `app/helpers/ui_components/bulk_select_helper.rb:40`)
  - bulk_select_count(selected: 0, **options); class default "text-stone-muted"
  - <span class="text-stone-muted" aria-live="polite" data-checkbox-select-all-target="count">N selected</span>
  - none
- **`position_picker_count_label`** (forms, `app/helpers/ui_components/bulk_select_helper.rb:48`)
  - position_picker_count_label(positions, selected_ids)
  - String "X of Y selected"
  - none
- **`bulk_select_checkbox`** (forms, `app/helpers/ui_components/bulk_select_helper.rb:55`)
  - bulk_select_checkbox(name, value, checked: false, id: nil, aria_label: nil, skip_select_all: false)
  - <label class="inline-flex items-center justify-center min-h-9 min-w-9 cursor-pointer"><input type="checkbox" class="{CHECKBOX_CLASSES}" [id] [aria-label] data-checkbox-select-all-target="checkbox" [data-skip-select-all]></label>; aria_label optional, so a row box can be unnamed
  - none
- **`clipboard_button`** (buttons, `app/helpers/ui_components/clipboard_helper.rb:5`)
  - clipboard_button(text, options = {}) { visible content } (block required: capture(&block) is called unconditionally); options label: (default "Copy to clipboard"), use_flex: bool
  - {content}<button type="button" aria-label="Copy to clipboard" class="no-decoration relative inline-flex items-center justify-center align-middle before:absolute before:-inset-3.5 before:content-[''] [ms-2]" data-controller="copy-to-clipboard" data-action="copy-to-clipboard#copy" data-copy-to-clipboard-success-class="btn-copy-success" data-copy-to-clipboard-content-value=text><i class="fa-regular fa-copy" aria-hidden="true"></i></button>; use_flex wraps both in <div class="flex flex-row items-center">. Raw tag.button, not ButtonHelper, no btn class
  - Arbitrary before:content-[''] (line 25); hit area grown with before:-inset-3.5
- **`filter_bar`** (forms, `app/helpers/ui_components/filter_bar_helper.rb:52`)
  - filter_bar(chips: [], clear_url: nil, count: nil, id: "filter-bar", url: nil, model: nil, scope: nil, open: false, toggle_label: "Filters", toggle_icon: "filter", actions: nil) { form or |f| fields }
  - <div id="filter-bar" class="mb-4"><div class="flex flex-wrap items-center gap-2">{toggle: button_action(toggle_label + ui_badge(count, :primary), :secondary, controller "toggle", icon, aria-controls, aria-expanded)}{chips: <a class="no-decoration inline-flex min-h-9 items-center gap-2 rounded-full border border-line px-3 text-sm text-body transition-colors duration-200 hover:bg-default-strong focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2" aria-label="Remove filter: {label}"><span>label</span><i fa-solid fa-xmark></a>}[button_link "Clear All Filters", :ghost]<span class="ms-2 text-lg text-stone-muted">count</span>[<div class="ms-auto flex flex-wrap items-center gap-2">actions</div>]</div><div id="{id}-panel" class="mt-2 rounded-base border border-line p-4 [hidden]" aria-hidden="true|false">{ui_form(model, url, scope:, method: :get, local: true, no_error_summary: true) or block}</div></div>. Chips are hand-rolled pills (not badge, not btn)
  - none
- **`filter_chips / active_filters / known_filter / filter_time / filter_status_options / filter_select_options / filter_signed_up_options / filter_url`** (forms, `app/helpers/ui_components/filter_bar_helper.rb:73, 87, 102, 117, 139, 154, 163, 180`)
  - Data helpers (several module_function)
  - No markup: chip arrays {label: "Label: value", url:}, filter hashes without "all", select option arrays starting ["All", "all"] with "status (count)" labels, parsed times, and filter URLs
  - none
- **`ui_flash_successful / ui_flash_submit_error / ui_success_text`** (toasts-alerts, `app/helpers/ui_components/flash_helper.rb:5, 12, 16`)
  - ui_flash_successful(thing, verb); ui_flash_submit_error; ui_success_text(thing, verb)
  - Set flash[:success] = "{thing} {verb}."; flash.now[:error] = "The information could not be saved due to form errors."; return "{thing} {verb}." (called from controllers)
  - none
- **`ui_callout_box`** (toasts-alerts, `app/helpers/ui_components/notice_box_helper.rb:15`)
  - ui_callout_box(type, options = {}) { body }; type :success/:info/:warning/:error/:secondary (unknown -> plain "box" with the info icon); accent: true; title:; heading_level: default :h4; icon: name or false; icon_type:; role: default "alert"; class: inserted before the layout classes
  - <div class="p-2 mb-2 {box box-{type} | box-accent box-accent-{type}} {class} flex items-start gap-2" role="alert">[<div class="flex items-center h-lh shrink-0 [mt-1 text-base]"><i class="fa-solid fa-{icon} text-lg leading-none"></div>]<div>[<h4 class="my-1 heading-title">title</h4>]<div>body</div></div></div>. Icons (line 7): success circle-check, info circle-info, warning triangle-exclamation, error triangle-exclamation, secondary hand-point-right. role="alert" is the default for every type, including success, info and secondary static text
  - none
- **`ui_alert_banner`** (toasts-alerts, `app/helpers/ui_components/notice_box_helper.rb:66`)
  - ui_alert_banner(label, type, options = {}) { body }; type as BOX_TYPES (unknown -> success styling); class: appended
  - <div class="mb-4 box box-accent-{type} {class}" role="alert" (warning/danger/error) or role="region" aria-label=label><div class="text-lg px-2 py-1 font-bold flex items-center gap-2"><i icon>label</div><div class="text-base p-4 text-body bg-base-100 rounded-lg">body</div></div>. Checks for :danger, which BOX_TYPES does not define. Uses box + box-accent-{type} without box-accent
  - none
- **`ui_empty_state`** (empty-loading, `app/helpers/ui_components/notice_box_helper.rb:106`)
  - ui_empty_state(message = nil, options = {}) { optional block }; icon:, icon_type: default :regular; class: appended; role default "status"
  - <div class="empty-state {class}" role="status">[<i class="fa-regular fa-{icon} me-2">]message</div>
  - none
- **`ui_toast_render / ui_toast_stream`** (toasts-alerts, `app/helpers/ui_components/toast_helper.rb:34, 65`)
  - ui_toast_render(message, type, for_streaming = false); ui_toast_stream(message, type); type :success/:info/:warning/:notice/:alert/:error (unknown -> info)
  - Renders common/_toast (appended to "toast-container" when streaming): <div class="toast-base {toast-success|toast-info|toast-warning|toast-error}" role="status|alert" data-controller="toast" [data-toast-auto-hide-value="false"] data-turbo-temporary data-action="mouseenter->toast#pause mouseleave->toast#resume"><div class="inline-flex items-center justify-center shrink-0"><i icon></div><div class="ms-3 text-base font-normal w-full">message</div><button type="button" class="btn-toast-close" data-action="click->toast#close" aria-label="Close"><i fa-solid fa-xmark></button>[<div class="toast-progress" data-toast-target="progress">]</div>. Map (line 16): success/notice = toast-success, check, status; info = toast-info, circle-info, status; warning = toast-warning, exclamation, alert; alert/error = toast-error, exclamation, alert, stays until closed. Close is a raw <button> in the partial, not ButtonHelper
  - none
- **`ui_accent_card`** (cards, `app/helpers/ui_components/ui_accent_card_helper.rb:62`)
  - ui_accent_card(title = nil, variant: :primary, icon: nil, icon_type: :solid, badge: nil (HTML string), heading_level: nil (:h2/:h3/:h4, other raises), options: { id:, class:, aria:, data: }) { body }
  - <article class="rounded-lg border-l-4 {border} {bg} px-4 py-2 transition-all duration-200 hover:shadow-sm {class}">[<div class="flex flex-col lg:flex-row lg:items-center gap-2"><{h2|h3|h4|div} class="flex-1 {heading-section if h2 else heading-title} flex items-center gap-2 text-heading">[<span class="shrink-0">icon</span>]<span>title</span></...>[<div class="shrink-0">badge</div>]</div>][<div class="mt-2">body</div>]</article>. Border map (line 18): error border-error/30, info border-info (full opacity, unlike the others), primary border-primary/30, secondary border-base-300, success border-success/30, warning border-warning/30. Bg map (line 28): error bg-error/10, info bg-info/10, primary bg-primary/10, secondary bg-base-200, success bg-success/10, warning bg-warning/10. Unknown variant -> primary. Hover shadow on a non-interactive card. badge string is marked .html_safe inside the helper (line 134)
  - none
- **`ui_accordion`** (modals, `app/helpers/ui_components/ui_accordion_helper.rb:22`)
  - ui_accordion(summary_content, options = {}) { body }; open:, unstyled: (drops every base class), summary_class:, summary_html:, content_class:, content_html:, class: and other attributes on <details>
  - <details class="collapse collapse-arrow rounded-none border-0 bg-transparent {class}" [open]><summary class="collapse-title flex items-center min-h-9 px-0 py-2 pr-10 text-left text-sm font-semibold text-heading {..}">summary</summary><div class="collapse-content px-0 pt-2 {..}">body</div></details>
  - none
- **`ui_card`** (cards, `app/helpers/ui_components/ui_card_helper.rb:37`)
  - ui_card(options = {}) { block }; shadow: :xs (default)/:sm/:md/:lg/:xl/:none (unknown -> xs); width:/height: px numbers; class: appended
  - <div class="card-standard {shadow-xs..shadow-xl or none} {class}" [style="width: Npx; height: Npx;"]>
  - Inline style px width/height (line 101-106)
- **`ui_card_image`** (cards, `app/helpers/ui_components/ui_card_helper.rb:53`)
  - ui_card_image(image:, alt:, width:, height:, class:) or block
  - image_tag(image, alt: alt or "", loading: "lazy", class: "rounded-t-base w-full object-cover") or yields the block. width:/height: are converted to a style on the options hash, but the options are never passed to image_tag, so they have no effect; class: is ignored too
  - none
- **`ui_card_body`** (cards, `app/helpers/ui_components/ui_card_helper.rb:66`)
  - ui_card_body(options = {}) { block }
  - <div class="text-body px-4 {class}">
  - none
- **`ui_card_title`** (typography, `app/helpers/ui_components/ui_card_helper.rb:73`)
  - ui_card_title(title, options = {}) { optional subtitle }; size: :sm/:md/:lg (default)/:xl; class:
  - <div class="{text-sm|text-base|text-lg|text-xl} text-heading text-center p-2 {class}">title</div>[<p class="font-normal text-body px-4">block</p>]. A div, not a heading
  - none
- **`ui_card_section`** (typography, `app/helpers/ui_components/ui_card_helper.rb:86`)
  - ui_card_section(title, options = {}) { body }
  - <h6 class="mt-4 mb-2 font-semibold text-base text-heading {class}">title</h6><div class="font-normal text-body">body</div>
  - none
- **`ui_card_footer`** (cards, `app/helpers/ui_components/ui_card_helper.rb:93`)
  - ui_card_footer(options = {}) { block }
  - <div class="flex items-center justify-center px-4 py-2 {class}">
  - none
- **`ui_data_block`** (other, `app/helpers/ui_components/ui_data_block_helper.rb:23`)
  - ui_data_block(content, max_height: nil (whole class name))
  - <div class="overflow-auto rounded-base border border-base-300 bg-base-100 p-3 shadow-inner {max_height}"><pre class="font-mono text-sm leading-relaxed text-base-content whitespace-pre-wrap break-all">content</pre></div>. Border token border-base-300 while other boxes use border-line
  - none
- **`ui_disclosure`** (modals, `app/helpers/ui_components/ui_disclosure_helper.rb:23`)
  - ui_disclosure(summary_content, options = {}) { body }; variant: :inline (default)/:card (other raises); subtitle: (card only, else raises); open:; summary_class:/summary_html:/content_class:/content_html:; class: (card: on the wrapper div; inline: on <details>)
  - inline: <details><summary class="cursor-pointer min-h-9 py-2">summary</summary><div>body</div></details> (native triangle is the only affordance). card: <div class="disclosure-card rounded-base border border-line {class}"><details class="group"><summary class="cursor-pointer list-none [&::-webkit-details-marker]:hidden px-4 py-3"><div class="flex items-center justify-between gap-3"><div class="text-base text-heading [font-semibold for plain strings]">title</div>[<div class="text-sm text-stone-muted">subtitle</div>]<span class="shrink-0 text-stone-muted transition-transform group-open:rotate-180"><i fa-solid fa-chevron-down></span></div></summary><div class="border-t border-line px-4 pb-4 pt-3">body</div></details></div>
  - Arbitrary variant [&::-webkit-details-marker]:hidden (line 16)
- **`ui_drill_down_row`** (tables-lists, `app/helpers/ui_components/ui_drill_down_row_helper.rb:43`)
  - ui_drill_down_row(url, title, options = {}) { optional second line }; meta:; badges: (pre-rendered); figures: [[Integer, label]] (not with meta:); blocked: bool; icon: default "arrow-right" ("ban" when blocked); class:
  - <a href class="no-decoration box box-default px-4 py-2 my-2 flex justify-between items-center box-hover {class}"><div><div class="text-lg font-semibold">title <span class="my-1">•</span> <span class="text-stone-subtle">meta</span> • badge</div>block</div><div class="text-xl"><i fa-solid fa-arrow-right></div></a>. figures: ledger "flex flex-wrap flex-1 min-w-0 items-baseline gap-x-5 pe-5" with numerals "min-w-9 text-right text-lg" (zero: text-stone-subtle, else font-semibold) and labels "text-sm text-stone-subtle". blocked: a <div aria-disabled="true"> with "opacity-70 cursor-not-allowed" instead of a link. The header comment says chevron; the default icon is an arrow
  - "•" bullet glyph as separator (line 89)
- **`ui_form`** (forms, `app/helpers/ui_components/ui_form_helper.rb:21`)
  - ui_form(model, url, options = {}) { |f| }; no_error_summary: true skips the summary; other form_with options pass through
  - form_error_summary(model) (FormHelper, outside this scope) when the model has errors, then form_with(builder: AppFormBuilder, model:, url:, data-controller="form {existing}")
  - none
- **`hero_panel`** (navigation, `app/helpers/ui_components/ui_hero_panel_helper.rb:242`)
  - hero_panel(icon: (required), id: nil (random "hero-panel-xxxx"), heading_level: :h2 (default), title: nil, description: nil, back_to: nil (:dashboard, [label, path], or rendered HTML)) { |h| h.title, h.description, h.back_to, h.hero_stats, h.stat_badge, h.progress, h.progress_status, h.year_selector }
  - <section class="me-hero-panel" aria-labelledby=id><div class="flex flex-col w-full">[mobile back link <div class="mb-2 lg:hidden">]{title row: <div class="flex items-center gap-2 [mb-1]"><span class="icon-warning"><i fa-solid fa-{icon} fa-lg></span><{h1|h2} id class="{h1: text-2xl font-semibold | h2: text-xl font-semibold} text-heading">title</></div>; with back link or year selector wrapped in <div class="flex justify-between items-center gap-6 [mb-1]"> with year_selector_compact in <div class="hidden lg:block shrink-0"> and the back link in <div class="hidden lg:block shrink-0">}<div class="leading-relaxed">description</div>[<div class="lg:hidden mt-4">year_selector</div>][progress <div class="mt-4">][status]. With stats: two columns "flex flex-col lg:flex-row lg:gap-6 lg:items-start", left "flex-1 min-w-0", stats right "hidden lg:block shrink-0" and repeated in "lg:hidden mt-4". The back link, the year selector and the stats are each rendered twice (one copy per breakpoint, hidden by CSS). A heading_level other than :h1/:h2 gets no size class. Icon is always gold (icon-warning)
  - none
- **`hero_panel builder: hero_stats / stat_badge`** (other, `app/helpers/ui_components/ui_hero_panel_helper.rb:85, 96`)
  - h.hero_stats(class:, role:) { }; h.stat_badge(label, value, color: :default/:warning/:pending/:flame/:award, icon: nil)
  - hero_stats: <div class="flex flex-wrap gap-3" role="list" aria-label="{id} statistics"> (with an auto id the name reads "hero-panel-xxxx statistics"). stat_badge: <div role="listitem" class="{tile}"><div class="{label}">[icon ]label</div><div class="{value}">value</div></div>. Colours (line 31): default tile "rounded-lg px-3 py-2 ring-1 ring-signature-edge bg-base-100/70", label "tracking-wide text-base text-center text-stone-subtle", value "font-semibold text-base text-center text-heading"; warning/pending tile "... bg-hero-tile", label "... icon-warning", value "... text-hero-tile-content"; flame/award "hero-stat hero-stat-flame|award" with hero-stat-label/hero-stat-value (hero-panel.css). Unknown color -> nil hash -> NoMethodError
  - none
- **`hero_panel builder: progress / progress_status / year_selector / back_to / description / title`** (other, `app/helpers/ui_components/ui_hero_panel_helper.rb:106, 112, 116, 76, 80, 69`)
  - h.progress(completed:, total:, start_label:, end_label:, aria_label:); h.progress_status { }; h.year_selector(year:, years:, **year_selector options)
  - progress -> <div class="mt-4">render_progress_bar</div>; progress_status -> render_progress_status; year_selector stores data for year_selector_compact (desktop) and year_selector (mobile)
  - none
- **`ui_icon_item`** (tables-lists, `app/helpers/ui_components/ui_icon_item_helper.rb:26`)
  - ui_icon_item(icon, icon_type = :solid, tone: nil (whole class)) { body }
  - <li class="flex items-start gap-2"><i class="fa-{type} fa-{icon} {tone} mt-0.5 shrink-0" aria-hidden="true"><span>body</span></li>; the caller supplies the <ul>
  - none
- **`ui_label_value`** (tables-lists, `app/helpers/ui_components/ui_label_value_helper.rb:36`)
  - ui_label_value(label_width: nil, size: :sm (default)/:base, **options incl class:, style:) { |list| list.row(label, value = nil, variant: :default, **dd options) { block } }
  - <dl class="ui-label-value {text-sm|text-base} {class}" style="--label-width: X; {style}"><dt>label</dt><dd class="text-body {variant}">value</dd>...</dl>. Variant map (line 5): default none, success text-success, warning text-warning, error text-error, primary text-primary, info text-info; unknown -> none. Row options go on <dd>; label_class: is read as the <dt> options hash (line 77), so a string would fail. Unknown size -> no size class. Empty value renders an empty <dd>
  - label_width becomes an inline style custom property (line 51)
- **`ui_match_stepper`** (navigation, `app/helpers/ui_components/ui_match_stepper_helper.rb:23`)
  - ui_match_stepper(controller, label:, current:, total:)
  - <div class="join" role="group" aria-label=label><span class="btn btn-secondary btn-outline btn-sm join-item pointer-events-none" role="status" data-{controller}-target="count">Match N of M</span>{2 x button_action("", :secondary, icon chevron-up/chevron-down, class "join-item btn-square", aria-label "Previous match"/"Next match")}</div>. A status span styled as a button
  - none
- **`ui_pager`** (navigation, `app/helpers/ui_components/ui_pager_helper.rb:29`)
  - ui_pager(meta (Pagy or {page:, total_pages:, total:, has_previous_page:, has_next_page:}), noun: nil, summary: nil, **options incl class:) { |page| url } (raises without summary: or noun: plus total)
  - <div class="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between {class}"><p class="text-base text-body">Page 2 of 7 · 640 messages</p><div class="flex flex-wrap gap-2">{button_link "Previous Page"/"Next Page", :secondary or button_action(..., :secondary, disabled: true)}</div></div>. No <nav> landmark or aria-label; "·" middot glyph separator
  - none
- **`ui_progress_bar`** (other, `app/helpers/ui_components/ui_progress_bar_helper.rb:52`)
  - ui_progress_bar(percentage, variant_or_options = {}, options = {}); variant positional Symbol or variant: :primary (default)/:secondary/:success/:error/:warning (unknown -> primary); size: :sm/:md/:lg/:xl, default :md, or :lg when label: given; label: true (shows "N%") or string; bar_class: (e.g. progress-projected); aria: hash; class: on container
  - <div class="w-full bg-base-300 rounded-full {height} {class}"><div class="rounded-full flex items-center justify-end overflow-hidden {height} {bg variant} {bar_class}" style="width: N%" role="progressbar" aria-valuenow aria-valuemin="0" aria-valuemax="100" aria-label="label or N%">[<span class="text-xs {fg variant} font-medium leading-none pe-2">label</span>]</div></div>. Heights (line 11): sm h-1.5, md h-2.5, lg h-4.5, xl h-6. Bg: bg-primary/bg-secondary/bg-success/bg-error/bg-warning; label fg: text-*-content. Not the daisyUI <progress> element
  - Inline style width percentage (line 106)
- **`ui_progress_box`** (other, `app/helpers/ui_components/ui_progress_box_helper.rb:97`)
  - ui_progress_box(id: nil) { |b| b.title(icon:, icon_style: :solid) { }, b.subtitle { }, b.progress(completed:, total:, start_label:, end_label:, aria_label:), b.status { } }
  - <section class="mb-2 px-4 py-2 bg-base-100 rounded-xl border border-line shadow-sm" aria-labelledby="{id}-heading"><div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-3 mb-2"><div class="flex items-center gap-3"><div class="flex items-center justify-center w-10 h-10 rounded-full bg-linear-to-br from-amber-100 to-orange-100 dark:from-amber-900/40 dark:to-orange-900/40 ring-1 ring-signature-edge" aria-hidden="true"><span class="icon-warning">icon</span></div><div><h2 id="{id}-heading" class="heading-section text-heading">title</h2>[<p class="text-sm text-stone-subtle">subtitle</p>]</div></div>{status}</div>{render_progress_bar}</section>
  - Raw Tailwind palette colours from-amber-100 to-orange-100 dark:from-amber-900/40 dark:to-orange-900/40 (line 21); w-10 h-10 icon disc
- **`render_progress_bar`** (other, `app/helpers/ui_components/ui_progress_completed_bar_helper.rb:12`)
  - render_progress_bar(completed:, total:, start_label: nil, end_label: nil, aria_label: nil (default "Progress: X of Y"))
  - <div class="progress-container" role="progressbar" aria-valuenow aria-valuemin="0" aria-valuemax="100" aria-label><div class="progress-bar" style="width: N%" aria-hidden="true"></div>[<div class="progress-bar-pulse" style="width: N%" aria-hidden="true">]</div>[<div class="progress-labels-container" aria-hidden="true"><span>start</span><span>end</span></div>]. A second progress-bar implementation with custom CSS classes. Percent is floored to 5 even at 0 completed, and that floored value is what aria-valuenow reports
  - Magic number 5 (minimum percent, line 16); inline style width (lines 32, 40)
- **`render_progress_status`** (other, `app/helpers/ui_components/ui_progress_completed_bar_helper.rb:56`)
  - render_progress_status(content = nil) { block }
  - <div role="status" aria-live="polite" aria-atomic="true" class="mt-2">content</div>
  - none
- **`progress_count_of`** (typography, `app/helpers/ui_components/ui_progress_completed_bar_helper.rb:66`)
  - progress_count_of(completed, total, label)
  - <span class="font-medium text-stone-emphasis">X</span> of <span class="font-medium text-stone-emphasis">Y</span> label. Restates UiProgressBoxHelper::SUBTITLE_EMPHASIS by hand (comment lines 67-69)
  - none
- **`ui_section`** (cards, `app/helpers/ui_components/ui_section_helper.rb:10`)
  - ui_section(title = nil or options hash, options = {}) { body }; class:, id:, style:, html: (attributes), body_class:, border: default true, icon: (icon_type default "regular"), badge:, badge_color: default :secondary, edit_link: url, link: rendered HTML, action: { partial:, locals: }
  - <section class="box box-default mb-4 {class}" [id] [style]>[title header]<div class="text-body rounded-xl px-4 pb-2 {body_class} [px-4 pb-1 when border]">body</div></section>. Title: ui_section_title -> <div class="px-4 pt-2 mb-1 heading-section text-heading-primary" role="heading" aria-level="2">[icon me-2] title [ui_badge(badge, color, size "base")]</div>; badge "0" displays "none". edit_link: wraps in <div class="flex flex-col lg:flex-row items-center justify-between">title<div class="px-4 py-2">edit_link(url, class whitespace-nowrap, aria-label/title "Edit {title}")</div></div>. action: same wrapper with "lg:items-center" and slot "w-full px-4 py-2 lg:w-auto" holding the rendered partial. With the default border: true the body carries both pb-2 and pb-1 (line 57). border: false does not remove any border; it only drops the px-4 pb-1 pair
  - none
- **`ui_section_title`** (typography, `app/helpers/ui_components/ui_section_helper.rb:30`)
  - ui_section_title(title = nil, options = {}) { block }; class:, badge:, badge_color:
  - <div class="px-4 pt-2 mb-1 heading-section text-heading-primary {class}" role="heading" aria-level="2">title [badge]</div>. A div with ARIA heading role rather than an <h2>
  - none
- **`ui_subheading`** (typography, `app/helpers/ui_components/ui_section_helper.rb:39`)
  - ui_subheading(title = nil) { block }
  - <h3 class="heading-title text-heading mt-4 first:mt-0 mb-2">title</h3>. No class: option
  - none
- **`ui_stat_box`** (other, `app/helpers/ui_components/ui_stat_box_helper.rb:47`)
  - ui_stat_box(value, label, variant: :secondary (default)/:success/:warning/:error (unknown -> secondary), icon: nil, icon_type: :solid, size: :sm/:md (default)/:lg (unknown -> md), class:, aria:)
  - <div class="{bg} border {border} rounded-lg p-3 text-center {class}">[<div class="{icon size} {icon tone} mb-1"><i fa icon></div>]<div class="{value size} font-bold {text}">value</div><div class="{label size} {text}">label</div></div>. Variants (line 16): success bg-success/10 border-success/30 text-success icon-success; warning bg-warning/10 border-warning/30 text-warning icon-warning; error bg-error/10 border-error/30 text-error icon-error; secondary bg-base-100 border-line text-heading text-stone-icon. Sizes (line 24): sm value text-lg label text-xs icon text-base; md text-xl/text-sm/text-xl; lg text-2xl/text-base/text-2xl. Other HTML options (id, data) are dropped: only class and aria are read
  - none
- **`ui_stat_link`** (links, `app/helpers/ui_components/ui_stat_box_helper.rb:99`)
  - ui_stat_link(url, aria_label:, active: false, class:) { ui_stat_box }
  - <a class="no-decoration block rounded-lg focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2 {class} [ring-2 ring-primary]" aria-label>. Other options dropped
  - none
- **`ui_stat_row`** (spacing, `app/helpers/ui_components/ui_stat_row_helper.rb:26`)
  - ui_stat_row(**options incl class:) { stat boxes }
  - <div class="flex flex-row flex-wrap gap-2 lg:gap-4 my-4 {class}">
  - none
- **`UiComponentsHelper (module)`** (other, `app/helpers/ui_components_helper.rb:3`)
  - -
  - Includes 13 of the 26 UiComponents modules (ActionBox, Badge, Clipboard, Flash, Toast, Accordion, AccentCard, Card, ProgressBar, ProgressBox, Section, StatBox, StatRow). The other modules (BulkSelect, FilterBar, NoticeBox, DataBlock, Disclosure, DrillDownRow, Form, HeroPanel via ApplicationHelper, IconItem, LabelValue, MatchStepper, Pager, ProgressCompletedBar) reach views through Rails helper loading, not this module
  - none

### helpers-forms (75)

- **`AppFormBuilder (class)`** (forms, `app/helpers/form_helper.rb:22`)
  - ActionView::Helpers::FormBuilder subclass; includes ButtonHelper and IconHelper; form-level option layout: in VALID_LAYOUTS %i[vertical horizontal auto] (form_helper.rb:26), default :vertical, any other value silently becomes :vertical (form_helper.rb:177-181); every field may override with its own layout: (extract_layout, form_helper.rb:578-581)
  - Shared field options removed before Rails sees them (extract_field_options, form_helper.rb:548-576): label, help_text, help_mode (:inline default or :tooltip), show_counter, wrapper_class (REPLACES the default wrapper class, does not add), wrapper: false (no wrapper, no label, no help/error line), layout, wrapper_id, hidden (appends "hidden" to wrapper), width (string substituted for "w-auto" in the field class), required, required_label, hide_label, icon, icon_type (default :solid), icon_class, replace_class, label_position (:inline default or :stacked; collection radios only)
  - Constants block form_helper.rb:32-129: no hex colours or arbitrary values; layout fractions lg:w-1/4 (horizontal label) and lg:w-1/8 (auto label); VANILLA_CALENDAR_DEFAULTS selectionTimeMode 24, inputMode true (form_helper.rb:135-138)
- **`AppFormBuilder class constants (field skin)`** (forms, `app/helpers/form_helper.rb:32-129`)
  - n/a
  - INPUT "input w-auto" / error "input input-error w-auto"; SELECT "select w-auto" / "select select-error w-auto"; TEXTAREA "textarea w-full resize-y" / "textarea textarea-error w-full resize-y"; FILE "file-input w-auto" / "file-input file-input-error w-auto"; RICH_TEXT "lexxy-content w-auto" / "lexxy-content w-auto border-error border-2"; CHECKBOX "checkbox checkbox-primary checkbox-sm" / "checkbox checkbox-error checkbox-sm"; RADIO "radio radio-primary radio-sm" / "radio radio-error radio-sm"; LABEL "block mb-1 font-medium text-heading text-base" / error swaps text-heading for text-error; HELP_TEXT "mt-1 text-sm text-body leading-snug"; ERROR_TEXT "mt-1 text-sm text-error font-medium flex items-center gap-1"; ERROR_ICON "text-error shrink-0"; WRAPPER "mb-3"; TOGGLE_FIELD_WRAPPER "mb-1"; TOGGLE_LABEL "ms-2 inline-flex items-center min-h-9 text-base text-heading select-none cursor-pointer leading-tight" (error: text-error); TOGGLE_WRAPPER "flex items-center"; FIELDSET "form-fieldset"; LEGEND "form-legend"; ICON_CLASSES "absolute inset-y-0 left-0 flex items-center pl-3 pointer-events-none text-stone-muted" (error: text-error); ICON_PADDING_CLASS "has-icon"
  - "has-icon" is custom CSS padding-inline-start: 2.5rem (app/assets/stylesheets/components/forms.css:23-26); min-h-9 = 36px touch floor; left-0/pl-3 are physical (not logical) direction utilities
- **`layout :vertical (build_vertical_field)`** (forms, `app/helpers/form_helper.rb:747-757`)
  - default layout
  - <div class="mb-3" [id=wrapper_id]> + <label for=<field id> class=LABEL_CLASSES> + field + suffix (error div or help div) </div>. Label above the field
  - none
- **`layout :horizontal (build_horizontal_field)`** (forms, `app/helpers/form_helper.rb:117-120, 759-770`)
  - layout: :horizontal
  - <div class="flex flex-col lg:flex-row lg:items-start gap-1 lg:gap-3"> + <label class="font-medium text-heading text-base lg:pt-2 lg:w-1/4 lg:shrink-0 lg:mr-2"> + <div class="flex-1 min-w-0"> field + suffix </div></div>. Stacked below lg, side-by-side from lg. Wrapper has NO bottom margin (vertical has mb-3)
  - lg:w-1/4; error label class omits lg:mr-2 that the normal label has (form_helper.rb:118 vs 119), so the gap differs by state
- **`layout :auto (build_auto_field)`** (forms, `app/helpers/form_helper.rb:126-129, 772-783`)
  - layout: :auto
  - <div class="mb-3 lg:flex lg:flex-row lg:items-start lg:gap-3"> + <label class="block mb-1 font-medium text-heading text-base lg:mb-0 lg:pt-2 lg:w-1/8 lg:shrink-0 "> + <div class="lg:flex-1 lg:min-w-0"> field + suffix </div></div>
  - lg:w-1/8 label column (horizontal uses lg:w-1/4); AUTO_LABEL_CLASSES has a trailing space (form_helper.rb:127)
- **`text_field, email_field, password_field, number_field, url_field, telephone_field, search_field, date_field, time_field, color_field`** (forms, `app/helpers/form_helper.rb:193-200`)
  - (attribute, options = {}) plus shared field options; text/email/url/search get with_length_limit: maxlength from object.class.length_limit(attribute) unless the caller passes :maxlength, and size: nil so Rails does not copy maxlength into size (form_helper.rb:191, 695-700)
  - Rails input of the type with class "input w-auto" (or "input input-error w-auto"), width: replaces w-auto; required: true sets the HTML required attribute; wrapped per layout. date_field and time_field are the native browser <input type=date/time> (no picker controller)
  - none
- **`datetime_field (date/time picker)`** (forms, `app/helpers/form_helper.rb:206-219, 1154-1158`)
  - (attribute, options) + calendar_options: Hash merged into VANILLA_CALENDAR_DEFAULTS, use_calendar: default true
  - use_calendar true: a type="text" input (@template.text_field) with class "input w-auto", data-controller="vanilla-calendar" (appended to any existing controller) and data-vanilla-calendar-options-value=JSON {selectionTimeMode:24,inputMode:true,...}. use_calendar: false: native datetime_local_field. Same wrapper/label/help/error as other fields
  - selectionTimeMode 24 (24-hour clock) hard-coded default
- **`autocomplete_field`** (forms, `app/helpers/form_helper.rb:246-344`)
  - (attribute, options) + url: (required), mode:, limit: (default 5), min_length: (default 2), meta_mapping: Hash, submit_on_select: (default false), recents_key:, display_attribute:; placeholder default "Search…"
  - Inside the standard wrapper: <div id="<id>-ac" role="combobox" aria-expanded="false" aria-haspopup="listbox" aria-owns="<id>-ac-results" class="relative" data-controller="autocomplete" data-autocomplete-url-value data-autocomplete-response-type-value="json" min-length/limit/mode/meta-mapping/submit-on-select/recents-key values> + visible <input type=text id=<field id> name=nil autocomplete=off spellcheck=false autocorrect=off autocapitalize=off class=<field class> aria-autocomplete="list" aria-controls=results [aria-describedby, aria-invalid, aria-required copied from build_field]> + hidden_field id "<id>_value" (target hidden) + <div class="ac-loading" hidden>Searching…</div> (text only, no spinner) + <div role="listbox" class="ac-results" hidden>
  - limit 5, min_length 2 defaults; no delay value set (shared partial sets 300)
- **`callsign_chips_field`** (forms, `app/helpers/form_helper.rb:364-376`)
  - (attribute, options) + url: (required), max: Integer, placeholder: default "Choose a callsign…" when max == 1 else "Add a callsign…"
  - Inside the standard wrapper, renders shared/_callsign_chips with name "<object>[<attr>][]", field_id, describedby/invalid from build_field, box_class "<field class> h-auto flex flex-wrap items-center gap-2 py-1" (so the div carries "input w-auto ... h-auto flex flex-wrap" and acts as the input box)
  - none
- **`text_area`** (forms, `app/helpers/form_helper.rb:382-385`)
  - (attribute, options) ; width defaults to TEXTAREA_DEFAULT_WIDTH "w-full"; with_length_limit applies maxlength from the model
  - <textarea class="textarea w-full resize-y"> (error adds textarea-error) in the standard wrapper
  - none
- **`rich_text_area`** (forms, `app/helpers/form_helper.rb:399-426, 629-667`)
  - (attribute, options) ; required supported
  - <lexxy-editor id name value attachments="false" class="lexxy-content w-auto" data-controller="... lexxy" data-morph-skip> in the standard wrapper; preceded, when the stored HTML has <img>, by ui_callout_box(:warning) with <strong>"This text has N images, which the editor cannot keep."</strong> + " Saving removes them. To keep them, leave this page without saving." Error state: "border-error border-2" utilities instead of a daisyUI error modifier
  - border-2 on error only
- **`select, collection_select`** (forms, `app/helpers/form_helper.rb:432-448, 583-615`)
  - Rails signatures (attribute, choices, options, html_options) ; builder options (label, help_text, width, required, layout, hide_label, icon, ...) accepted in either options or html_options (SELECT_FIELD_OPTION_KEYS, form_helper.rb:35-39) ; class:, required, aria, data moved into html_options
  - <select class="select w-auto"> (error "select select-error w-auto") in the standard wrapper; icon: adds "has-icon"
  - none
- **`check_box`** (forms, `app/helpers/form_helper.rb:454-463, 862-875, 927-940`)
  - (attribute, options, checked_value "1", unchecked_value "0") + label:, inline_label:, layout, wrapper_class, wrapper: false, help_text
  - Vertical: <div class="mb-1"><div class="flex items-center"><label for=<id> class="inline-flex items-center min-h-9 cursor-pointer"> <input type=checkbox class="checkbox checkbox-primary checkbox-sm" [aria-invalid]> <span class=TOGGLE_LABEL>text</span></label></div> + suffix</div>. Label text is label: or inline_label:. required: is consumed but does NOT add the required attribute nor the "(required)" marker (build_toggle_field never calls required_marker). Horizontal/auto: a <span> (not <label>) with the horizontal/auto label classes plus "pt-0"/"lg:pt-0" as a left column, and the box in the input column with inline_label only
  - min-h-9
- **`radio_button`** (forms, `app/helpers/form_helper.rb:469-477, 942-953`)
  - (attribute, tag_value, options) + label: etc.
  - <div class="mb-1"> <div class="flex items-center"> <input type=radio class="radio radio-primary radio-sm"> <label for="<obj>_<attr>_<value slug>" class=TOGGLE_LABEL> </div> + suffix </div>. The label is a sibling (checkbox wraps input in its label); error/hint id is "<obj>_<attr>_hint" so several radios of one attribute each print the same error div id
  - none
- **`collection_radio_buttons`** (forms, `app/helpers/form_helper.rb:483-494, 959-1071`)
  - Rails signature + label:, label_position: :inline (default) or :stacked, layout, required, help_text
  - Vertical: <fieldset class="mb-3" role="radiogroup"><legend class=LABEL_CLASSES>label + required marker</legend><div class="space-y-1"> items </div> + suffix</fieldset>. Horizontal inline: <div HORIZONTAL_WRAPPER><span class=horizontal label>label</span><div class="flex-1 min-w-0"><div class="columns-1 sm:columns-2 lg:columns-3 xl:columns-4 gap-x-4">items</div>suffix</div></div> (span, no fieldset/legend). Horizontal/auto :stacked: fieldset/legend as vertical but item grid per layout. Auto inline grid "space-y-1 lg:columns-2 xl:columns-3 lg:gap-x-4 lg:space-y-0". Each item <div class="flex items-center break-inside-avoid"> radio + b.label(class TOGGLE_LABEL). fieldset carries role="radiogroup" explicitly
  - CSS multi-column (columns-N) for the radio grid; sm: breakpoint used for column count
- **`file_field`** (forms, `app/helpers/form_helper.rb:500-502`)
  - (attribute, options)
  - <input type=file class="file-input w-auto"> (error file-input-error) in the standard wrapper
  - none
- **`fieldset`** (forms, `app/helpers/form_helper.rb:508-530`)
  - (legend_text = nil, options) + block yielding a legend capturer (f.fieldset { |fs| fs.legend "..." }); legend_class: default "form-legend", class: default "form-fieldset" (REPLACES), icon:, icon_type: default :regular; raises ArgumentError without legend
  - <fieldset class="form-fieldset" ...><legend class="form-legend">[fa_icon end:2]text</legend><div class="space-y-3">content</div></fieldset>. form-fieldset = relative mb-2 ps-4 border-l-4 border-primary bg-linear-to-r from-primary/5 to-transparent rounded-r-lg; form-legend = block w-full font-semibold text-lg text-base-content border-b border-base-200 (components/forms.css:7-20); the same CSS also targets every "form fieldset" element, so builder radio groups' fieldsets get the accent too
  - icon default :regular here but :solid for field icons (form_helper.rb:571)
- **`submit`** (buttons, `app/helpers/form_helper.rb:536-540`)
  - (value = nil, options) + variant: default :primary (one of primary secondary tertiary success error warning dark ghost), size: default "sm" (xs sm base lg xl), full_width: true, class: appended
  - Rails <input type="submit" name="commit" value=...> (not a <button>; no icon) with class "btn btn-primary btn-sm [w-full lg:w-auto] <class>" via ButtonHelper#button_classes (app/helpers/button_helper.rb:300-306, VARIANT_CLASSES button_helper.rb:18-26, DEFAULT_SIZE "sm" button_helper.rb:40)
  - none
- **`required marker (required_marker, private)`** (forms, `app/helpers/form_helper.rb:788-794`)
  - triggered by required: true; required_label: "" switches style
  - Default: <span class="ml-2 text-xs text-error">(required)</span> appended inside the label. required_label: "" : fa_icon("asterisk", :solid, class: "text-error", start: 2) with no text alternative. Any other required_label value is ignored (still prints "(required)"). Input gets HTML required attribute (form_helper.rb:716)
  - ml-2 is physical margin while the rest of the builder uses ms-*
- **`help text (help_text_tag, public)`** (forms, `app/helpers/form_helper.rb:1098-1102, 834-845`)
  - help_text: "..." ; help_mode: :inline (default) or :tooltip
  - Inline: <div class="mt-1 text-sm text-body leading-snug" id="<field id>_hint">text</div> after the field; field gets aria-describedby="<field id>_hint". Hidden while the field has errors (the error div takes the same id). :tooltip: no div; label gets <span class="inline-block ms-1 text-stone-muted hover:text-primary cursor-help" title="help">fa_icon circle-info text-sm</span>, but the field's aria-describedby still points at "<id>_hint", which does not exist (form_helper.rb:727-731, 810-819)
  - none
- **`inline field error (error_message, public)`** (validation, `app/helpers/form_helper.rb:1077-1096, 725-731`)
  - automatic when object.errors[attribute].any?
  - Field class switches to its *-error variant; label switches to text-error; field gets aria-invalid="true" and aria-describedby="<field id>_hint"; after the field: <div class="mt-1 text-sm text-error font-medium flex items-center gap-1" id="<field id>_hint" role="alert"> fa_icon circle-exclamation solid "text-error shrink-0" + <span>messages</span></div>. Messages joined with " " when every one ends in . ! or ?, otherwise ", ". Icon prefix turns text-error. Only errors on the exact attribute key show (no base errors inline)
  - none
- **`character counter (show_counter)`** (forms, `app/helpers/form_helper.rb:718-723`)
  - show_counter: true, only effective when options[:maxlength] is set at that point (the model-derived maxlength from with_length_limit counts)
  - Adds data-controller "input-counter" (merged) and data-input-counter-css-value="text-sm ms-2 text-body" to the field itself; the counter element is created by JavaScript (app/javascript, not traced here)
  - none
- **`icon prefix (wrap_with_icon, private)`** (icons, `app/helpers/form_helper.rb:1137-1148`)
  - icon:, icon_type: (default :solid), icon_class: replaces ICON_CLASSES
  - <div class="relative"> field <span class="absolute inset-y-0 left-0 flex items-center pl-3 pointer-events-none text-stone-muted" aria-hidden="true">fa_icon</span></div>; icon after the input in DOM order; field gains "has-icon" (padding-inline-start 2.5rem)
  - 2.5rem in forms.css:25
- **`replace_class option`** (forms, `app/helpers/form_helper.rb:706-714`)
  - replace_class: true together with class:
  - Drops the whole default field class (input/select/... and error variant) and uses class: alone; error styling then depends entirely on the caller
  - none
- **`form_row`** (forms, `app/helpers/form_helper.rb:1174-1177`)
  - (options = {}, &block); class: merged via class_names
  - <div class="flex flex-col lg:flex-row gap-3 mb-1 [class]">; fields keep their own mb-3 wrappers inside
  - none
- **`form_error_summary`** (validation, `app/helpers/form_helper.rb:1184-1205`)
  - (model) ; renders nothing unless model.errors.any?
  - ui_callout_box(:error, id: "form-error-summary", tabindex: "-1") (role="alert" by default from notice_box_helper.rb:31) containing <div class="font-semibold">Please fix the following error|errors:</div><ul class="mt-2 space-y-1"><li class="flex items-start gap-2"><span class="text-error shrink-0" aria-hidden="true">&bullet;</span><span>full message</span></li></ul>. Messages are full_messages (attribute name prefixed), not links to the fields
  - bullet drawn as an HTML entity span rather than list-style
- **`input_counter_data`** (forms, `app/helpers/form_helper.rb:1212-1219`)
  - (target_id = nil)
  - Returns data hash {controller: "input-counter", input_counter_css_value: "text-sm ms-2 text-body", [input_counter_target_id_value]} for hand-built fields
  - none
- **`ui_form`** (forms, `app/helpers/ui_components/ui_form_helper.rb:21-38`)
  - (model, url, options = {}, &block); no_error_summary: true skips summary; other options pass to form_with (method:, scope:, local:, data:, layout: for the builder, ...)
  - form_error_summary(model) (when errors) placed BEFORE (outside) the <form>, then form_with(builder: AppFormBuilder, model:, url:, data-controller="form ...") — the "form" Stimulus controller handles error focus (per comment; JS not traced)
  - none
- **`filter_bar`** (forms, `app/helpers/ui_components/filter_bar_helper.rb:52-66, 188-245`)
  - (chips: [{label:, url:}], clear_url:, count:, id: "filter-bar", url:, model:, scope:, open: false, toggle_label: "Filters", toggle_icon: "filter", actions: markup or Array, &block) ; raises without block
  - <div id="filter-bar" class="mb-4"> row: <div class="flex flex-wrap items-center gap-2"> toggle = button_action(label + ui_badge(count, :primary) when >0, :secondary, controller: "toggle", icon: filter solid, aria-controls=panel, aria-expanded) + one chip link per filter + button_link("Clear All Filters", :ghost, clear_url) when chips + <span class="ms-2 text-lg text-stone-muted">count</span> + <div class="ms-auto flex flex-wrap items-center gap-2">actions</div>; panel <div id="<id>-panel" class="mt-2 rounded-base border border-line p-4 [hidden]" aria-hidden="true|false"> containing ui_form(model, url, scope:, method: :get, local: true, no_error_summary: true) when url:, else the block's own markup
  - count text is text-lg (larger than body)
- **`filter_bar chip (filter_bar_chip, private)`** (navigation, `app/helpers/ui_components/filter_bar_helper.rb:10-13, 224-229`)
  - chip hash {label:, url:}
  - <a href=url class="no-decoration inline-flex min-h-9 items-center gap-2 rounded-full border border-line px-3 text-sm text-body transition-colors duration-200 hover:bg-default-strong focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2" aria-label="Remove filter: <label>"><span>label</span> fa_icon xmark solid</a>
  - duration-200; hand-built pill (not daisyUI badge)
- **`filter_chips`** (forms, `app/helpers/ui_components/filter_bar_helper.rb:73-78`)
  - (active Hash, labels Hash, value_label: lambda, &url)
  - Data only: [{label: "<Label>: <value>", url:}]
  - none
- **`active_filters, known_filter, filter_time, filter_status_options, filter_select_options, filter_signed_up_options, filter_url`** (forms, `app/helpers/ui_components/filter_bar_helper.rb:87-184`)
  - module_function data helpers; ALL_FILTER = "all", ALL_FILTER_OPTION ["All","all"]
  - No markup. Option labels: status options "<status> (<count>)" sorted by count desc; select options "All" first; signed-up "All/Yes/No"; filter_time requires a full date with 4-digit year
  - year range 1000..9999
- **`bulk_select`** (forms, `app/helpers/ui_components/bulk_select_helper.rb:13-16`)
  - (**options, &block)
  - <div data-controller="checkbox-select-all" ...> block </div>
  - none
- **`bulk_select_all`** (forms, `app/helpers/ui_components/bulk_select_helper.rb:22-35`)
  - (label: nil, aria_label: nil, selected: 0, checked: selected.positive?, count: true, name: "select_all")
  - Box: check_box_tag with class "checkbox checkbox-primary checkbox-sm" (AppFormBuilder::CHECKBOX_CLASSES), data target toggle + action change->checkbox-select-all#toggleAll, aria-label when given. Without label: <label class="inline-flex items-center justify-center min-h-9 min-w-9 cursor-pointer">box</label> (table header cell form). With label: <div class="flex flex-wrap items-center gap-4 my-2"><label class="flex items-center gap-2 min-h-9">box <span>label</span></label> + bulk_select_count</div>
  - min-h-9 min-w-9
- **`bulk_select_count`** (forms, `app/helpers/ui_components/bulk_select_helper.rb:40-44`)
  - (selected: 0, **options) ; class default "text-stone-muted"
  - <span class="text-stone-muted" aria-live="polite" data-checkbox-select-all-target="count">N selected</span>
  - none
- **`position_picker_count_label`** (forms, `app/helpers/ui_components/bulk_select_helper.rb:48-50`)
  - (positions, selected_ids)
  - Plain string "N of M selected"
  - none
- **`bulk_select_checkbox`** (forms, `app/helpers/ui_components/bulk_select_helper.rb:55-63`)
  - (name, value, checked: false, id: nil, aria_label: nil, skip_select_all: false)
  - <label class="inline-flex items-center justify-center min-h-9 min-w-9 cursor-pointer"><input type=checkbox class="checkbox checkbox-primary checkbox-sm" data-checkbox-select-all-target="checkbox" data-action="change->checkbox-select-all#refresh" [data-skip-select-all] [aria-label]></label>; no visible text, name comes only from aria_label
  - none
- **`common/_form_wrapper (partial)`** (forms, `app/views/common/_form_wrapper.html.erb:1-4`)
  - locals model, url (no strict-locals comment); yields f
  - form_with(model:, url:, builder: AppFormBuilder) with render "common/error_summary" INSIDE the form when model.errors.any?; no data-controller="form"
  - none
- **`common/_error_summary (partial)`** (validation, `app/views/common/_error_summary.html.erb:1-9`)
  - strict locals (errors:)
  - ui_callout_box :error containing <div class="font-medium">The following errors were found:</div><ul class="mt-2 list-bulleted space-y-1"><li>error</li></ul>; no id, no tabindex
  - none
- **`shared/_autocomplete (partial)`** (forms, `app/views/shared/_autocomplete.html.erb:1-75`)
  - strict locals: url:, mode: nil, name: nil, input_id: nil, field_id: nil, describedby: nil, invalid: false, wrapper_class: nil, form_field: false, placeholder: "Search...", min_length: 2, limit: 5, delay: 300, meta_mapping: nil, submit_on_select: false, recents_key: nil, autofocus: false, input_class: nil, results_class: nil, hidden_field_name: nil, hidden_field_id: nil, aria_label: "Search", input_data: nil, inline: false, select_on_blur: false, keyboard_help: false, type: "text", value: nil, maxlength: nil, free_text: false, positioned: true
  - <div id=input_id or "autocomplete-<hex>" role="combobox" class="[wrapper_class] relative(if positioned)" aria-expanded="false" aria-haspopup="listbox" aria-owns aria-label data-controller="autocomplete" + url/response-type json/min-length/delay/limit/mode/meta-mapping/submit-on-select/form-field/inline/select-on-blur/free-text/recents-key values> <input class=input_class or "input w-auto w-full" autocomplete=off spellcheck=false autocorrect=off autocapitalize=off aria-autocomplete="list" aria-controls aria-label aria-describedby aria-invalid> [hidden input] <div class="ac-loading [left-0]" hidden>fa_icon spinner "animate-spin me-1" Searching…</div> <div role="listbox" class="ac-results [results_class] [left-0]" hidden></div> [keyboard_help: <div class="ac-keyboard-help" aria-hidden="true" hidden><kbd>&uarr;</kbd><kbd>&darr;</kbd> navigate, <kbd>&crarr;</kbd> select, <kbd>esc</kbd> close</div>]
  - delay 300ms, min_length 2, limit 5; default input class string contains both w-auto and w-full
- **`shared/_callsign_chips (partial)`** (forms, `app/views/shared/_callsign_chips.html.erb:1-23`)
  - strict locals (name:, callsigns:, url:, field_id:, box_class:, placeholder:, describedby: nil, invalid: false, max: nil)
  - <div class="relative <box_class>" data-controller="callsign-chips" data-callsign-chips-max-value data-action="autocomplete.change->... keydown ... mousedown ..."><span id="<field_id>_chips" class="contents" data-callsign-chips-target="list"> chips </span> shared/_autocomplete(aria_label: nil, wrapper_class: "flex-1 min-w-32", positioned: false, input_class: "w-full min-h-9 bg-transparent outline-none", form_field: true) <template> blank chip </template></div>
  - min-w-32; input class replaces the daisyUI input skin with "bg-transparent outline-none" (the outer box carries "input")
- **`shared/_callsign_chip (partial)`** (other, `app/views/shared/_callsign_chip.html.erb:1-13`)
  - strict locals (name:, callsign:, controller: "callsign-chips")
  - <span class="inline-flex min-h-9 items-center gap-1 rounded-full border border-line bg-base-200 ps-3 pe-1 text-sm text-body" data-<controller>-target="chip"><span>callsign</span> hidden_field_tag(name, callsign, id: nil) button_action(nil, :ghost, icon: "xmark", icon_type: :solid, class: "btn-square btn-circle", aria-label "Remove <callsign>", data-action "<controller>#remove")</span>
  - hand-built pill; button_action class override btn-square btn-circle
- **`agreement_status, agreement_border_class, agreement_bg_class`** (color, `app/helpers/agreement_helper.rb:9-19, 35-51`)
  - (agreement) -> :signed / :pending / :not_available
  - Class strings from frozen hashes: border signed "border-success/30", pending "border-warning/30", not_available "border-l-secondary"; bg signed "bg-success/10", pending "bg-warning/10", not_available "bg-base-200"
  - opacity steps /30 and /10; not_available uses a directional border-l-secondary while the others are non-directional
- **`agreement_badge`** (other, `app/helpers/agreement_helper.rb:22-26, 53-58`)
  - (agreement)
  - ui_badge(text, variant, size: "sm", aria-label): signed "signed" :success "Status: Agreement signed"; pending "available to sign" :warning "Status: Available to sign"; not_available "coming soon" :secondary "Status: Not available yet" (lower-case badge text)
  - none
- **`agreement_icon`** (icons, `app/helpers/agreement_helper.rb:29-33, 60-71`)
  - (agreement)
  - fa_icon circle-check (class icon-success), pen-to-square (icon-warning), clock (text-secondary), all :solid; colour by status (two custom icon-* classes, one text-* utility)
  - none
- **`AuthorizeHelper (authorize_role, authorize_status, deny_status, authorize_ability, require_current_year_for, can?)`** (other, `app/helpers/authorize_helper.rb:22-79`)
  - controller concern; can?(name) is exposed to views via helper_method
  - No markup. Denials go through not_authorized_redirect (defined elsewhere, not traced)
  - none
- **`BasicCacheHelper (cache_exist?, cache_read, cache_write, cache_delete)`** (other, `app/helpers/basic_cache_helper.rb:11-27`)
  - Rails.cache wrappers
  - No markup
  - none
- **`CountryStateHelper (country_has_states?, is_canada?, is_usa?, state_data_json, country_form_data_attributes, country_data_attributes, state_data_attributes)`** (forms, `app/helpers/country_state_helper.rb:360-404`)
  - option constants COUNTRY_OPTIONS (first entry ["Choose Country", ""], then US, CA, GB, AU, then alphabetical), US_STATE_OPTIONS, CANADIAN_PROVINCES_OPTIONS, AUSTRALIAN_STATES_OPTIONS, STATE_LABELS {US: "State", CA: "Province", AU: "State/Territory"}
  - Data attributes only: form-level data-controller="country-state" data-action="change->country-state#updateStateField" with states JSON and initial value; country select target; state select target + data-morph-skip. Choices built in the browser
  - none
- **`credit_format`** (typography, `app/helpers/credit_helper.rb:4-13`)
  - (credits)
  - "zero credits" / "1 credit" / "%.2f credits" e.g. "2.50 credits"
  - 2 decimals
- **`credit_format_short`** (typography, `app/helpers/credit_helper.rb:16-19`)
  - (credits)
  - "0" / "%.2f" e.g. "2.50"
  - 2 decimals
- **`datetime_format`** (typography, `app/helpers/date_time_helper.rb:49-84, 257-262`)
  - (start, finish = nil, tz: nil, tz_abbr: nil, year: false)
  - Single: "Thu Jan 8 @ 14:30" (MONTH_DAY_TIME "%a %b %-d @ %H:%M"); year: "Thu Jan 8, 2026 @ 14:30"; tz_abbr appends " (PT)" to the start only. Range: same day "Thu Jan 8 @ 14:30 to 18:00"; next day "... to Fri @ 02:00" (HOUR_MIN_DAY "%a @ %H:%M"); 2+ days apart "... to Sat Jan 10 @ 06:00"; different years or year: true both ends with year. Each date wrapped in <span class="inline-block" title="Thu Jan 8, 2026 @ 14:30 (MST)" data-local-time-target="time" data-utc="<iso8601>">; unparseable finish prints "<start> to <raw finish>"; unparseable start returns start.to_s. Returns "" for nil start
  - 24-hour clock; day not zero-padded
- **`slot_shift_time`** (typography, `app/helpers/date_time_helper.rb:93-95`)
  - (slot, year: false)
  - datetime_format(slot.begins, slot.ends, tz: slot.timezone, tz_abbr: slot.timezone_abbr, year:) e.g. "Thu Aug 27 @ 09:00 (PDT) to 17:00"
  - none
- **`zoned_datetime_format`** (typography, `app/helpers/date_time_helper.rb:102-106`)
  - (time, tz:, tz_abbr: nil, year: true)
  - Converts into tz then "Thu Jan 8, 2026 @ 13:30 (PT)" (year default true) or without year; wrapped in the format_date span
  - none
- **`pacific_datetime_format`** (typography, `app/helpers/date_time_helper.rb:110-112`)
  - (time, tz_abbr: "PT", year: true)
  - zoned_datetime_format in America/Los_Angeles e.g. "Thu Jan 8, 2026 @ 13:30 (PT)"
  - zone name hard-coded "America/Los_Angeles" (PACIFIC, date_time_helper.rb:43)
- **`log_time_format`** (typography, `app/helpers/date_time_helper.rb:115-117`)
  - (time)
  - Plain string "2026-01-08 14:30:00" (LOG_TIME), "" for nil; no span
  - none
- **`full_datetime_format`** (typography, `app/helpers/date_time_helper.rb:119-133`)
  - (date: Time or String)
  - Plain string "Thursday, January 8, 2026 @ 14:30"; unparseable input prints "invalid date [<input>]" to the page; "" for blank
  - none
- **`hour_minute_format`** (typography, `app/helpers/date_time_helper.rb:135-141`)
  - (seconds)
  - "5:07" ("%d:%02d", hours unpadded, e.g. "295:20" past a day)
  - none
- **`hour_minute_words`** (typography, `app/helpers/date_time_helper.rb:143-155`)
  - (seconds, full: false)
  - "2 hours 5 mins" / "5 mins"; full: "2 hours and 5 minutes"; "0 mins" for zero
  - none
- **`hour_format`** (typography, `app/helpers/date_time_helper.rb:157-164`)
  - (seconds)
  - Decimal hours "2.50", "0.00" for zero
  - 2 decimals
- **`day_hour_format`** (typography, `app/helpers/date_time_helper.rb:170-176`)
  - (seconds)
  - "12 days 7 hours" (pluralize, "1 day 0 hours")
  - none
- **`hour_minute_or_day_format, hour_minute_words_or_day_format`** (typography, `app/helpers/date_time_helper.rb:182-190`)
  - (seconds)
  - Below 1 day: "5:07" or "5 hours 7 mins"; at/above 1 day: "1 day 3 hours"
  - 1.day threshold
- **`month_day_format`** (typography, `app/helpers/date_time_helper.rb:193-200`)
  - (date or String)
  - "January 8" ("%B %-d"); "" for blank or unparseable
  - none
- **`wday_month_day_format`** (typography, `app/helpers/date_time_helper.rb:204-211`)
  - (date, year: false)
  - "Thu Jan 8" or "Thu Jan 8, 2026"; "" for blank/unparseable
  - none
- **`short_datetime_format`** (typography, `app/helpers/date_time_helper.rb:215-217`)
  - (time)
  - "Wed 9/2 17:29" ("%a %-m/%-d %H:%M"); "" for nil; plain string, no span
  - none
- **`ymd_format`** (typography, `app/helpers/date_time_helper.rb:221-228`)
  - (date or String)
  - "2026-08-08"; "" for blank/unparseable
  - none
- **`mdy_format`** (typography, `app/helpers/date_time_helper.rb:230-239`)
  - (date or String, full: false)
  - "Jan 8, 2026" (DATE "%b %-d, %Y"); full: "Thursday, January 8, 2026" (LONG_DATE); "" for blank/unparseable
  - none
- **`DateTimeHelper format constants`** (typography, `app/helpers/date_time_helper.rb:23-43`)
  - MONTH_DAY_TIME, MONTH_DAY_TIME_YEAR, DAY_LABEL, DATE, LONG_DATE, HOUR_MINS "%H:%M", HOUR_MIN_DAY, SHORT_DAY_TIME, CSV_TIME "%Y-%m-%d %H:%M", CHIP_TIME "%Y-%m-%d %H:%M" (same digits as CSV_TIME), LOG_TIME "%Y-%m-%d %H:%M:%S", PACIFIC
  - Used with strftime in non-helper code; CHIP_TIME is the filter-chip timestamp format (ISO-like, not the human MONTH_DAY_TIME style)
  - none
- **`event_date_window`** (typography, `app/helpers/event_dates_helper.rb:15-21`)
  - (start_time, end_time, year: false)
  - Both present: datetime_format range. Either missing: ui_badge("Not set", :secondary, icon: "circle-minus", icon_type: :solid)
  - none
- **`gender_format`** (typography, `app/helpers/gender_helper.rb:6-15`)
  - (person)
  - Label from GENDER_IDENTITY_LABELS, custom text, or "Not specified"
  - none
- **`pronouns_format`** (typography, `app/helpers/pronouns_helper.rb:6-22`)
  - (person, no_parens = false)
  - "(she/her)" or "she/her" with no_parens; "" when none (blank, not "Not specified")
  - none
- **`has_role? (RolesHelper)`** (other, `app/helpers/roles_helper.rb:4-9`)
  - (role)
  - Returns false with no current_user, otherwise returns Array.wrap(role) (always truthy); never checks the role
  - none
- **`shirt_size_title, shirt_size_label`** (other, `app/helpers/shirt_helper.rb:13-23`)
  - (title) / (person, reader)
  - Known size: plain title. Unknown (ShirtTotals::UNKNOWN): <span class="inline-flex items-center gap-2 text-warning">fa_icon circle-question solid "icon-warning" + title</span> (colour plus icon)
  - none
- **`shirt_select_options, shirt_build_options`** (forms, `app/helpers/shirt_helper.rb:25-41`)
  - (shirts, include_none = true) / (shirts, shirt_type, include_none = false)
  - Option arrays [[title, id]]; placeholder ["Not Selected", ""] prepended when include_none. SHIRT_TYPE_LABELS "T-Shirt", "Long Sleeve Shirt"
  - none
- **`ext_link`** (links, `app/helpers/url_helper.rb:4-9`)
  - (title, url, options = {}) ; class: appended
  - <a href target="_blank" rel="noopener noreferrer" class="inline-block hover:underline [class]">title + fa_icon arrow-up-right-from-square solid start:2</a>; no "opens in new tab" text or aria-label; caller rel/target overwritten
  - none
- **`salesforce_record_url, append_query_params`** (links, `app/helpers/url_helper.rb:16-38`)
  - (record_id) / (base_url, params)
  - URL strings only
  - Salesforce host "https://burningman.my.salesforce.com/" hard-coded

### js (75)

- **`application.js: turbo confirm dialog`** (modals, `app/javascript/application.js:112`)
  - Replaces Turbo's confirm: if the data-turbo-confirm message is HTML holding a <dialog> (ModalHelper#confirm_modal_dialog) it is placed into #turbo-confirm-modal (layouts/application.html.erb:104) and opened with showModal(); every button in it closes it, only the button with id "turbo-confirm-button" counts as yes; Escape/close resolves as no. A plain-string message falls back to window.confirm. Focus trap, Escape and focus return are the native <dialog>'s; no ARIA set in JS
  - none (ids "turbo-confirm-modal", "turbo-confirm-button" hard-coded)
  - global (every data-turbo-confirm; also called by download-confirm and status-warning)
- **`application.js: dropdown auto-close`** (navigation, `app/javascript/application.js:143`)
  - Any document click closes every open details.dropdown (NavigationHelper#dropdown_menu) that the click was outside of, or whose link was clicked (sets menu.open = false). No focus handling, no Escape handling in JS
  - none
  - global (every details.dropdown)
- **`application.js: same-page anchors`** (links, `app/javascript/application.js:44`)
  - Cancels turbo:click for a link to a #fragment on the same page so the browser scrolls instead of Turbo refetching
  - none
  - global
- **`application.js: morph-skip class sync`** (forms, `app/javascript/application.js:22`)
  - Elements with data-morph-skip (Lexxy editor, country-state select, vanilla calendar popup) are kept out of Turbo morphs but still take the server's classes (so an error class such as input-error lands); previous server classes are remembered in data-server-class and removed
  - none
  - global
- **`application.js: turbo-frame missing / page_redirect`** (navigation, `app/javascript/application.js:100`)
  - A frame answer without the frame becomes a full visit of that response (sign-in, error page); custom stream action page_redirect does Turbo.visit(url)
  - none
  - global
- **`application.js: cache clean-up`** (other, `app/javascript/application.js:152`)
  - Before Turbo caches a page: empties #live-region and [data-live-region]; resets #year-selector / #year-selector-compact forms so Back shows the page's own year
  - none
  - global
- **`application.js: messages list scroll restore`** (navigation, `app/javascript/application.js:62`)
  - Saves .drawer-content scrollTop in sessionStorage key "messages-list-scroll" when visiting /me/messages/N and restores it on return to /me/messages
  - storage key "messages-list-scroll"; path regex /me/messages
  - global (/me/messages only)
- **`application.js: analytics page_view`** (other, `app/javascript/application.js:83`)
  - Sends gtag page_view on every turbo:load without query string; no visible UI
  - none
  - global
- **`live_region.js announce()`** (toasts-alerts, `app/javascript/controllers/live_region.js:9`)
  - Appends a <div> with text to the live region inside an open modal dialog ([data-live-region]) or to #live-region in the layout; returns the line so the caller removes its previous one. No classes. Kiosk and print layouts have no region
  - none
  - imported by copy-to-clipboard, autocomplete, table-sort
- **`scrolling.js`** (navigation, `app/javascript/controllers/scrolling.js:11`)
  - Shared scroll helpers: scrollParent (nearest scrolling ancestor, usually div.drawer-content), scrollWithin, reveal (scroll into view respecting scroll-margin-top and a self-scrolling container such as .review-pane), scrollBehavior (smooth unless prefers-reduced-motion), onScreen hit-test
  - hit-test inset 2px (line 95); 1px rounding tolerance (line 74)
  - imported by form, hq-shift, onboarding, photo-board, scroll-to-element, scroll-to-top, search-matches
- **`storage.js`** (other, `app/javascript/controllers/storage.js:5`)
  - localStorage/sessionStorage wrapper that swallows errors; no UI
  - none
  - imported by application.js, theme, autocomplete, search-bar
- **`requests.js readJson()`** (validation, `app/javascript/controllers/requests.js:9`)
  - For request.js JSON calls: a redirected answer becomes Turbo.visit (sign-in page); an error answer throws with server's data.error or the caller's fallback text, which callers show in their error box or alert()
  - none
  - imported by passkey, photo-cropper, photo-upload
- **`confirm_checkbox.js confirmChecked()`** (modals, `app/javascript/controllers/confirm_checkbox.js:2`)
  - window.confirm(message); on No unticks the checkbox. Native browser dialog, not the app's <dialog>
  - none
  - imported by membership-editor, permission-editor
- **`active-links`** (navigation, `app/javascript/controllers/active_links_controller.js:20`)
  - On connect and on turbo:after-stream-nav-render, walks every a[href] inside the element and toggles class "active" plus aria-current="true"/"false" by matching pathname (and query when the link has one) or data-active-prefix. Skips links with #, class "tab", data-turbo-frame other than _top, and anything inside [data-active-ignore]. Writes aria-current="false" rather than removing it
  - none
  - 1 (layouts/application.html.erb:58)
- **`asset-form`** (forms, `app/javascript/controllers/asset_form_controller.js:3`)
  - Rewrites the two duration radio labels when the asset type select changes: "Shift"/"Event" for radio type, "Temporary"/"Permanent" otherwise (label[for$="_false"/"_true"] textContent)
  - user-facing strings in JS: "Shift", "Event", "Temporary", "Permanent"
  - 1
- **`autocomplete`** (forms, `app/javascript/controllers/autocomplete_controller.js:59`)
  - Combobox for search modal and form fields. Builds JSON-mode markup with createElement: filter bar div.ac-filter-bar role=toolbar aria-label="Filter results" holding <button type=button> chips class "ac-filter-chip" (+ "ac-filter-chip-active") with span.ac-filter-count; groups div.ac-group with div.ac-group-header role=presentation and a role=group aria-label list; rows div.ac-option role=option (server html via innerHTML or label text); flat list role=listbox; footer div.ac-keyboard-help aria-hidden with <kbd> glyphs (line 859); empty div.ac-empty role=status; error div.ac-error role=alert; searching bar div.ac-filter-bar role=status with span.ac-searching and <i class="fa-solid fa-spinner animate-spin me-1" aria-hidden="true"> (line 894); recents header "Recent". Highlight: aria-selected="true" plus selected class (default "ac-option-active"), input aria-activedescendant; container aria-expanded true/false; results shown via hidden attribute; floating list placed above/below with class "ac-results-above" and inline style max-height. Keys: ArrowUp/Down wrap, Enter commits (queues during search), Tab commits only in form fields, Escape closes and stops propagation only when list is open; IME keyCode 229 ignored. Sets input autocomplete=off, spellcheck=false. Focus returned to input after chip click / list click. Result count announced via live region. Recents in localStorage "ac-recents-<key>"
  - timings: debounce 300ms default (line 75), slow message after 10000ms (line 30); sizes: LIST_MAX 320px, LIST_GAP 16px, LIST_FLOOR 96px, LIST_MARGIN 4px (lines 36-39); inline styles: scroll-padding-top px (line 194), min-height px on searching bar (line 910), max-height px (line 1052); strings: "No results found", "Search failed. Please try again.", "Searching…", "Still searching. Your connection may be slow.", "Recent", "Filter results", "N result(s) available", "navigate", "select", "close"; minLength 2, limit 5, maxRecents 5
  - 2 (shared/_autocomplete.html.erb, form_helper.rb) plus 27 more files reference its targets/values
- **`autofocus`** (forms, `app/javascript/controllers/autofocus_controller.js:4`)
  - Focuses the element on connect and moves the caret to the end of its value
  - none
  - 2
- **`bookmark (extends kiosk)`** (other, `app/javascript/controllers/bookmark_controller.js:10`)
  - Kiosk bookmark page: writes a live clock into the clock target every second (toLocaleString weekday/month/day/hour/minute/second) and words the countdown "Page refresh in N minutes" (minutes rounded up; seconds only in the last minute)
  - strings "Page refresh in", "second(s)", "minute(s)"; 1s tick
  - 1
- **`bulk-edit`** (forms, `app/javascript/controllers/bulk_edit_controller.js:20`)
  - Spreadsheet table: snapshots each row; a changed row gets data-dirty="true", the dirty classes from the view (BMID grid passes "bg-warning/10", bmid/manage_helper.rb:81) and its [data-bulk-edit-marker] unhidden; count target text "No rows changed" / "1 row changed" / "N rows changed"; Save and Discard targets disabled while nothing changed; Discard restores values. On submit, pristine rows' fields are disabled (not sent) and re-enabled on turbo:submit-end
  - strings "No rows changed", "1 row changed", "N rows changed"
  - 1
- **`callsign-chips`** (forms, `app/javascript/controllers/callsign_chips_controller.js:16`)
  - Chip input: clones the view's <template> chip, writes callsign into its span and hidden input, sets the remove button aria-label "Remove <callsign>"; Enter in the text field makes a chip (form not submitted); duplicates (case-insensitive) ignored; past max the oldest chips are removed; form submit turns leftover typed text into a chip; clicking the box (not a button/link/input/listbox) focuses the input; removing a chip refocuses the input
  - string "Remove <callsign>"
  - 1 (shared/_callsign_chips.html.erb)
- **`camera`** (forms, `app/javascript/controllers/camera_controller.js:23`)
  - Upload/Camera tab pair on photo upload: selectTab toggles class "tab-active", aria-selected, tabIndex 0/-1 and panel hidden attribute. Starts getUserMedia, shows loading target (spinner from view) until first frame, then shows preview; one of four error boxes unhidden by kind (unsupported, permission, no-camera, in-use); camera select shown only with 2+ cameras, options built with new Option(label or "Camera N"). Capture draws mirrored frame to canvas, hands JPEG to photo-upload via camera:captured, or sends a message via camera:failed
  - video ideal 1280x720 (line 95); JPEG quality 0.92 (line 177); strings "Camera N", "The camera is still starting. Please try again in a moment.", "Failed to capture photo. Please try again."
  - 1 (profile_photos/new.html.erb, only when selfie_enabled?)
- **`checkbox-select-all`** (tables-lists, `app/javascript/controllers/checkbox_select_all_controller.js:14`)
  - Header toggle checks/unchecks all row checkboxes (skipping data-skip-select-all), toggle state kept in sync; count target text "N selected" (written only when it differs, to avoid live-region chatter); submit targets disabled while none checked
  - string "N selected" (must match BulkSelectHelper#bulk_select_count)
  - 2 (ticketing/trs_export/index.html.erb, bulk_select_helper.rb)
- **`conditional-show`** (forms, `app/javascript/controllers/conditional_show_controller.js:3`)
  - On change of the element, toggles class "hidden" on the element with id idValue when the value equals revealValue. No aria-expanded/aria-controls set
  - none
  - 6
- **`copy-to-clipboard`** (buttons, `app/javascript/controllers/copy_to_clipboard_controller.js:10`)
  - Copies contentValue; adds the success class (views pass "btn-copy-success") to the button's <i>; appends span.copy-tip "Copied" aria-hidden inside the control, as a manual popover where CSS anchor-scope is supported; screen readers hear "Copied" from the live region. Failure is silent (empty catch)
  - tip duration 2000ms (line 5); string "Copied"
  - 3
- **`country-state`** (forms, `app/javascript/controllers/country_state_controller.js:5`)
  - Rebuilds the state <select> options for the chosen country (first option "-"), renames the label's text node per country (fallback "State"), and for countries without states disables the select, adds class "opacity-60" to the label and inserts a hidden empty input so the value clears
  - class "opacity-60" (line 56, 74); strings "-", "State"
  - 1 (country_state_helper.rb)
- **`dialog (base)`** (modals, `app/javascript/controllers/dialog_controller.js:19`)
  - Base for native <dialog> modals: open() closes any other open dialog:modal then showModal(); close; toggle; hotkey (ignored for non-KeyboardEvent, repeat, while driver.js tour is active, or when focus is in contenteditable/lexxy-editor/.ProseMirror); backdropClose closes only on clicks outside the dialog box rect; showError(kind) unhides the one [data-kind] callout target ("slow" is a warning). Closes and clears errors before Turbo cache. Focus trap, Escape and focus return are native
  - SLOW_MS 10000 (line 17)
  - unused directly (base class of search-bar and mega-menu)
- **`disclosure-fields`** (forms, `app/javascript/controllers/disclosure_fields_controller.js:8`)
  - On a <details>: disables every input/select/textarea inside while it is closed (sync on toggle), so folded fields are not sent
  - none
  - 1 (common/messages/_compose.html.erb)
- **`download-confirm`** (modals, `app/javascript/controllers/download_confirm_controller.js:11`)
  - On link click (unmodified), asks through Turbo.config.forms.confirm (the app dialog or window.confirm) and then sets window.location.href to download
  - none
  - 1 (shift_operations/payroll_export_helper.rb)
- **`dropdown-fit`** (navigation, `app/javascript/controllers/dropdown_fit_controller.js:16`)
  - When a <details> dropdown in the row opens, sets CSS custom property --dropdown-fit-shift on its .dropdown-content to a negative px so the panel's right edge stays inside the row
  - inline style custom property in px (line 23)
  - 1 (common/_dropdown_scroll_list.html.erb)
- **`form`** (validation, `app/javascript/controllers/form_controller.js:4`)
  - On connect focuses and centre-scrolls #form-error-summary (role=alert, a sibling of the form) or, failing that, the first field with class input-error/select-error/textarea-error/radio-error/file-input-error. submit action calls requestSubmit (auto-submit on change)
  - none
  - 8
- **`hq-shift (extends unsaved-changes)`** (other, `app/javascript/controllers/hq_shift_controller.js:20`)
  - HQ shift page state: suggested-task checklist chips painted in JS (paintChip line 216): removes text-primary/text-stone-muted/animate-pulse, then ignored = "text-stone-muted" + icon "fa-solid fa-ban", completed = "text-stone-muted" + "fa-solid fa-check", open = "fa-regular fa-circle" (+ "animate-pulse" when data-blink); first open chip gets "text-primary"; new chips cloned from <template> with server label. Count text "N suggested task(s):", all-done target, "Next:" label. Skip Review toggles per-entry status targets via hidden; start panel / review notice / skip-all row via hidden. Opens one details[data-hq-section] and closes the others, then scrolls under the pinned #hq-todo-list; focuses #checkout-barcode. Leave guards use window.confirm
  - colour/state classes text-primary, text-stone-muted, animate-pulse; icon classes fa-solid fa-ban, fa-solid fa-check, fa-regular fa-circle; strings "N suggested task(s):", "It looks like a shift was not started.", "It looks like a shift was not ended.", " Leave this page anyway?", "A barcode was entered but not checked out. Check out the asset or clear the barcode field before leaving this page. Navigate away anyway?"
  - 1 (hq/shift_manage/index.html.erb; targets in 5 more partials)
- **`hq-wizard`** (modals, `app/javascript/controllers/hq_wizard_controller.js:20`)
  - On-site registration wizard in one native <dialog>: showModal on start, one step section visible at a time (hidden attribute), step scrolled into view and its [autofocus] field focused; Back/Cancel client side; Escape (native close) and Cancel unhide the "not completed" notice and scroll it into view; advances on a streamed signal element or a document click on [data-hq-wizard-confirm]. Does not use dialog or modal controller
  - none
  - 1 (hq/site_registration/show.html.erb)
- **`input-counter`** (forms, `app/javascript/controllers/input_counter_controller.js:3`)
  - Character counter: creates a <div> after the field (or uses the element named by targetId) with classes from cssValue (helpers pass "text-sm ms-2 text-body", form_helper.rb:722 and 1215) and text "N of MAX characters", updated on input. Not a live region, no aria-describedby link
  - string "N of MAX characters"
  - 1 helper file (form_helper.rb, two call sites); input_counter_data used by 5 views
- **`kiosk (base)`** (empty-loading, `app/javascript/controllers/kiosk_controller.js:10`)
  - Unattended page: 1s interval timer counts down and reloads the Turbo Frame; on fetch error or missing frame retries after retrySeconds; countdown target shows bare seconds (subclasses reword). No spinner or error message in UI
  - retrySeconds default 30, tick 1000ms
  - unused directly (base of bookmark, photo-board)
- **`lexxy`** (forms, `app/javascript/controllers/lexxy_controller.js:101`)
  - Lazy-loads the Lexxy rich text editor; gives its inner inputs/selects form="" so the editor's link box does not block form validation; copies typed value into the value attribute before Turbo cache and rebuilds a toolbar left empty; global click on label[for] focuses a lexxy-editor; paste from Google Docs rewrites styled spans to strong/em/u/s
  - none
  - 1 (form_helper.rb:408, merged into rich text fields)
- **`link-options`** (forms, `app/javascript/controllers/link_options_controller.js:7`)
  - On position select change, points a Turbo Frame src at the link-options URL so trainer/parent link fieldsets re-render. No loading indicator
  - none
  - 1 (scheduling/slots/_form.html.erb)
- **`list-filter`** (tables-lists, `app/javascript/controllers/list_filter_controller.js:19`)
  - Client-side filter: hides rows (hidden attribute) whose data-<key> lacks the typed term; hides group headings whose rows are all hidden; unhides the empty target only when a term matches nothing; hides the summary target while filtering. Re-filters rows streamed in
  - none
  - 2 (people/languages_known/index, shift_operations/rollcall/_roster)
- **`live-log`** (tables-lists, `app/javascript/controllers/live_log_controller.js:38`)
  - Live tab of Request Log / Action Logs: creates the turbo-cable-stream-source from a template while the tab is visible; keeps newest-first order; trims rows over the cap from the bottom; swaps table and empty target via hidden; unhides the "stalled" target when no confirmed subscription after the grace period
  - cap 200 rows, lookback 100 (line 40); STALL_GRACE_MS 10000 (line 33)
  - 2
- **`local-time`** (typography, `app/javascript/controllers/local_time_controller.js:13`)
  - On body: rewrites each time target's title tooltip to the browser's zone, format weekday long, year, month long, day, 2-digit hour:minute h23, short zone name
  - Intl format options (line 5)
  - 4 (layouts application, bookmark, photo_board, print)
- **`login-submit`** (buttons, `app/javascript/controllers/login_submit_controller.js:13`)
  - On session forms (non-Turbo full page submit) disables the [type=submit] and sets its value to data-pending-label or "Working…"; a second submit is prevented
  - string "Working…"
  - 1 (layouts/sessions.html.erb)
- **`mark-result`** (forms, `app/javascript/controllers/mark_result_controller.js:10`)
  - Writes a result value into the selector field of every row whose checkbox is ticked, dispatching change so unsaved-changes notices. No visible feedback beyond the field values
  - none
  - 1 (mentoring/alpha_mentor_assignments/index.html.erb)
- **`mega-menu (extends dialog)`** (navigation, `app/javascript/controllers/mega_menu_controller.js:12`)
  - Navbar mega menu dialog: panels switched by hidden attribute, chrome buttons get aria-current "true"/"false"; on opening focuses the search box; client filter hides .mega-menu-item rows not matching data-search-text and unhides no-results target; Escape clears the query before closing; focus moved to first visible control of a newly shown panel; star toggles restore focus to the star by id. Errors: callouts by kind (slow after 10s, failed, expired on 401, offline); before the menu loads a failure hides the frame and focuses the callout's button; Retry reloads or makes the lazy frame eager
  - SLOW_MS 10000 (inherited)
  - 2 (application/_top_menu.html.erb, application/_mega_menu.html.erb)
- **`membership-editor`** (forms, `app/javascript/controllers/membership_editor_controller.js:13`)
  - Team/position checkboxes: ticking a dangerous team or position asks via window.confirm and unticks on No; manager box on a cadre/delegation asks too; joining a team ticks its all-members positions and unticks deselect-on-join ones; leaving unticks all-members and optional positions
  - long confirm texts in JS (lines 57-61, 93-95) e.g. "Grant this <type> anyway?", "Make them a Clubhouse Manager anyway?"
  - 1
- **`message-search (extends callsign-chips)`** (forms, `app/javascript/controllers/message_search_controller.js:21`)
  - Mailbox search field: taking a person suggestion makes a chip and submits; removing a chip submits; on failed search resets text and chips from the URL (q, with[]); rewrites the autocomplete URL's with[] params to exclude chipped people
  - none
  - 2 (common/messages/_search_field, _workspace)
- **`modal`** (modals, `app/javascript/controllers/modal_controller.js:7`)
  - Native <dialog> with daisyUI modal classes: auto showModal() on connect (except inside #turbo-confirm-modal); closable=false blocks Escape (cancel prevented); on close focuses the autofocusOnCloseId selector and removes the dialog from the DOM; closeOnSubmit hides. No backdrop-click handler of its own; no one-at-a-time check
  - removal delay 100ms after close (line 71)
  - 2 (modal_helper.rb:42, hq/site_registration/_no_radio_modal.html.erb)
- **`onboarding`** (other, `app/javascript/controllers/onboarding_controller.js:31`)
  - First-sign-in tour with driver.js: steps from <template> targets, progress shown, page interaction disabled, no animation, overlay click does nothing, Back button text "Back", close button label "Skip the tour". Dresses popover buttons with "btn btn-sm btn-ghost" (Back) and "btn btn-sm btn-primary" (Next) and focuses Next. Scrolls each step's element to centre of the pane before moving. On Done scrolls pane to top and appends the view's toast template into #toast-container; focus goes to #menu-open / #menu-open-phone; PATCHes the url to record dismissal
  - class strings "btn btn-sm btn-ghost", "btn btn-sm btn-primary" (lines 127-128); 700ms fallback wait after smooth scroll (line 108); strings "Back", "Skip the tour"
  - 1 (me/dashboard/_onboarding.html.erb)
- **`passkey`** (forms, `app/javascript/controllers/passkey_controller.js:36`)
  - Passkey ceremony: unhides wrapper when supported, else unhides the unsupported notice and disables submit; while waiting disables submit and swaps an <input>'s value to data-pending-label; failures write a message into errorMessage target and unhide error target
  - strings: "That was cancelled or timed out. Try again when you are ready.", "This device or key already has a passkey for this account.", "The passkey could not be added. Try again, or use a different device or key.", "Passkey sign-in was cancelled or timed out. Try again, or sign in with your email address and password.", "That passkey could not be used. Try again, or sign in with your email address and password."
  - 3
- **`password-reveal`** (forms, `app/javascript/controllers/password_reveal_controller.js:12`)
  - Toggles input type password/text; button aria-pressed true/false (label unchanged); swaps show/hide icon targets with class "hidden". Focus stays on the button
  - none
  - 1 (sessions/_password_form.html.erb)
- **`permission-editor`** (forms, `app/javascript/controllers/permission_editor_controller.js:13`)
  - window.confirm when manually granting a role already held through team/position (unticks on No); on submit window.confirm for newly added council-approval roles, cancelling the submit on No
  - strings "<role> is already granted through a team membership and/or a position.", "Grant it manually as well?", "WARNING: <titles> require prior approval by the Ranger Council. ... Grant <titles> anyway?"
  - 1
- **`photo-board (extends kiosk)`** (other, `app/javascript/controllers/photo_board_controller.js:9`)
  - Wall display: every dwell seconds advances the current group, toggles "photo-board-group-active" on groups and "photo-board-rail-item-active" on rail items, scrolls the group to top (window to 0 for the first); sets --photo-board-header-height to the measured header px; frame reload every 300s
  - refreshSeconds 300, dwellSeconds 5 (lines 13-14); inline custom property px (line 97)
  - 1 (shift_operations/roc_photo_board/index.html.erb)
- **`photo-cropper`** (forms, `app/javascript/controllers/photo_cropper_controller.js:11`)
  - CropperJS 2 cropper: drag image with pointer, zoom in/out, rotate ±45deg, reset. Validation and errors use window.alert(); submit button disabled with textContent "Saving…", restored to "Save Crop Data" on error; success visits redirect_url
  - canvas 350x450 default (lines 27, 31); zoom 1.1/0.9, rotation 45deg, gap tolerance 2px (lines 20-23); alert strings "Cropper not initialized", "Please select a crop area before saving", "The image does not fully cover the selection area. Please adjust the image position, zoom, or selection to eliminate gaps before saving.", "Error: <message>"; button text "Saving…", "Save Crop Data"
  - 1 (profile_photos/crop.html.erb)
- **`photo-upload`** (forms, `app/javascript/controllers/photo_upload_controller.js:11`)
  - Upload form: client-side checks (no file, type, size) write a message into errorMessage target and unhide error target; busy hides the form, unhides loading target and disables submit; dropzone highlight toggles "border-primary", "bg-primary/5" and "border-base-300"; file info shows name and size; thumbnail built by innerHTML <img alt="Preview" class="w-16 h-16 object-cover rounded-lg border border-line shadow-xs">, with a fallback icon/note unhidden if the image cannot decode
  - class strings lines 147-149 and 184; strings "Please select an image", "File must be less than N MB", "Upload failed", "Preview", "0 Bytes", "Bytes/KB/MB/GB"
  - 1 (profile_photos/new.html.erb)
- **`pod-people (extends sortable package)`** (tables-lists, `app/javascript/controllers/pod_people_controller.js:22`)
  - Drag a person between pod lists (SortableJS group "cruise-direction-people", in-list sorting off); on drop PATCHes new_pod_id and renders the turbo-stream answer. No JS visual feedback or error message
  - none
  - 1 (shift_operations/cruise_direction/_pod.html.erb)
- **`position-picker (extends checkbox-select-all)`** (forms, `app/javascript/controllers/position_picker_controller.js:7`)
  - Select all / none / every position with a paycode buttons; count text "N of M selected"
  - string "N of M selected" (must match BulkSelectHelper#position_picker_count_label)
  - 3
- **`read-more`** (other, `app/javascript/controllers/read_more_controller.js:3`)
  - Swaps short/full targets with class "hidden", sets toggle aria-expanded, writes "more"/"less" (or values) into label target or the toggle itself, rotates icon target with "rotate-180"
  - default strings "more", "less"; class "rotate-180"
  - 3
- **`register-intent`** (validation, `app/javascript/controllers/register_intent_controller.js:12`)
  - Auditor form: when the reason radio equals the trigger value, unhides the message target (class "hidden" removed) and disables submit
  - none
  - 1 (register/_form.html.erb, controller name merged with a dynamic form_data[:controller])
- **`review-pane`** (navigation, `app/javascript/controllers/review_pane_controller.js:27`)
  - List + detail pane: marks the line whose data-review-id matches the pane with aria-current="true" (removes it elsewhere; CSS keys on it); below lg moves the pane under the selected <li> (park) or toggles "hidden"/"lg:block" on pane and list when the viewport crosses lg (mailbox); enables/disables the frame by breakpoint; resets pane scrollTop to 0 on new record; keeps aria-current, href and data-landing through morphs
  - breakpoint media query "(width >= 64rem)" (line 36)
  - 2
- **`scroll-to-element`** (navigation, `app/javascript/controllers/scroll_to_element_controller.js:28`)
  - On connect and turbo:morph brings the element named by id or selector into view (scrolling.js reveal) unless already visible
  - none
  - 3
- **`scroll-to-top`** (navigation, `app/javascript/controllers/scroll_to_top_controller.js:16`)
  - Scrolls the nearest scrolling ancestor (or window) to 0,0 on connect, for result pages rendered by form submission
  - none
  - 29
- **`search-bar (extends dialog)`** (navigation, `app/javascript/controllers/search_bar_controller.js:37`)
  - Global search dialog, Cmd/Ctrl+K: open focuses the input and retries a failed search; failure callouts by kind (autocomplete.error cancelled so the dialog shows its own); editing hides the callout; mode radios/select synced and saved in localStorage "search-mode"; mode hint label text swapped from server labels; on a person page a mode change navigates to that person's page for the mode and reopens the dialog after the visit (sessionStorage "search-bar-reopen")
  - none (labels from server)
  - 1 (application/_search_bar_placeholder.html.erb)
- **`search-matches`** (navigation, `app/javascript/controllers/search_matches_controller.js:21`)
  - Mailbox thread match stepper: next/previous moves data-landing (ring) between article cards holding mark.search-hit, wraps around, writes "Match N of M" into count target, reveals card instantly
  - string "Match N of M"
  - 1 (common/messages/_messages_panel.html.erb)
- **`session-watch`** (other, `app/javascript/controllers/session_watch_controller.js:26`)
  - No visible UI of its own: when the sign-in ends elsewhere, clears Turbo cache and visits "/" (replace), setting html[data-signed-out] so leave guards do not ask; waits while html[aria-busy] or a busy form exists
  - retry delay 100ms (line 71)
  - 1 (layouts/application.html.erb)
- **`sidebar`** (navigation, `app/javascript/controllers/sidebar_controller.js:5`)
  - closeDrawer unticks the daisyUI drawer checkbox #sidebar-drawer
  - id "sidebar-drawer"
  - 1 (sidebar_helper.rb)
- **`sortable (package re-export)`** (tables-lists, `app/javascript/controllers/sortable_controller.js:15`)
  - @stimulus-components/sortable drag-to-reorder, PATCHes position; no app code
  - none
  - 1 (shift_operations/cruise_direction/_board.html.erb)
- **`stale-results`** (forms, `app/javascript/controllers/stale_results_controller.js:8`)
  - First edit after a verify hides the commit target and shows the stale explanation (class "hidden" toggles)
  - none
  - 1 (vc/reserved_handles/upload.html.erb)
- **`status-warning`** (modals, `app/javascript/controllers/status_warning_controller.js:4`)
  - Person status form: if the new status has a server-supplied warning (dialog HTML in warningsValue), submit is held and the dialog is shown through Turbo.config.forms.confirm; yes re-submits
  - none
  - 1 (person/statuses/edit.html.erb)
- **`stream-nav`** (navigation, `app/javascript/controllers/stream_nav_controller.js:18`)
  - Sidebar links fetched as turbo-stream and rendered without a page load; history pushed through Turbo; dispatches turbo:after-stream-nav-render (active-links listens). Falls back to Turbo.visit on error. No loading indicator
  - none
  - 1 (sidebar_helper.rb)
- **`table-sort`** (tables-lists, `app/javascript/controllers/table_sort_controller.js:25`)
  - Client sort on th buttons: moves tbody rows, sets aria-sort on the th, swaps the button's <i> className: none "fa-solid fa-sort text-stone-subtle", ascending "fa-solid fa-caret-up", descending "fa-solid fa-caret-down"; status target text and live region "Sorted by <col>, ascending/descending."
  - icon/colour classes lines 18-20; string "Sorted by <col>, <direction>."
  - 1 (admin/salesforce_query/index.html.erb)
- **`tabs`** (navigation, `app/javascript/controllers/tabs_controller.js:6`)
  - Tabs: on click removes active classes (helper passes "tab-active", tabs_helper.rb:39) and adds inactive classes from all [role=tab], aria-selected false/true, tabindex -1/0; panels [role=tabpanel] get class "hidden" except the target; remote tabs GET a turbo-stream. No arrow-key navigation; failure only logged to console
  - none
  - 1 (tabs_helper.rb)
- **`theme`** (color, `app/javascript/controllers/theme_controller.js:9`)
  - Dark mode: on connect applies saved localStorage "theme" or prefers-color-scheme; toggle flips; sets html class "dark" and html data-theme "dark"/"light". Toggle icon is drawn by CSS
  - none
  - 3 (application/_public_menu, application/_top_menu, layouts/bookmark)
- **`thread-live`** (other, `app/javascript/controllers/thread_live_controller.js:18`)
  - When an unread card ([data-unread]) is added to the open thread while the tab is visible, POSTs mark-read with the list's folder/search fields; answer is turbo-streams. No JS UI
  - none
  - 1 (common/messages/_messages_panel.html.erb)
- **`toast`** (toasts-alerts, `app/javascript/controllers/toast_controller.js:3`)
  - Toast (markup from common/_toast via ui_toast_render): adds class "show" on connect, auto-hides after delay with progress bar target shrunk via inline transition to width 0%; mouseenter pauses (freezes width, transition none), mouseleave resumes for remaining time; close button and timeout remove "show" then remove the element. Error types pass auto-hide false (stay until closed). No focus handling, no Escape
  - delay 6000ms default (line 7); removal wait 300ms (line 100); inline styles width, transition, transition-duration (lines 42-43, 63-64, 85, 89)
  - 1 (ui_components/toast_helper.rb; appended to #toast-container; onboarding also appends a toast template)
- **`toggle`** (other, `app/javascript/controllers/toggle_controller.js:3`)
  - Disclosure trigger: toggles both "hidden" and "hidden!" classes and aria-hidden on the target element (by dom id), aria-expanded on the trigger (stamped false on connect); optional labelValue replaces the trigger's innerHTML while open and restores it when closed; optional turboSrc loads a frame on first open
  - none (label HTML from server)
  - 7
- **`unsaved-changes`** (forms, `app/javascript/controllers/unsaved_changes_controller.js:15`)
  - Marks dirty on input/change, clears on submit; on turbo:before-visit asks with window.confirm, on beforeunload triggers the browser's generic prompt; skips asking when html[data-signed-out]
  - string "You have unsaved changes. Leaving this page will discard them. Continue?"
  - 5
- **`vanilla-calendar`** (forms, `app/javascript/controllers/vanilla_calendar_controller.js:8`)
  - Desktop date/time picker (Vanilla Calendar Pro, 24h, Sunday first, theme "system") with a custom layout adding footer <button type="button" class="vc-close-btn" data-vc-close aria-label="Close calendar">Close</button>; popup marked data-morph-skip. On mobile (width <= 768 or mobile UA) switches the field to native type datetime-local instead
  - breakpoint 768px (line 177); string "Close", aria-label "Close calendar"
  - 1 (form_helper.rb:1156)

## Design tokens and base rules (stylesheet layer)

- TOKEN `daisyUI themes list` (`app/assets/tailwind/application.css:24-26`): themes: light --default | dark | daisyUI plugin enables two themes, light default; no --prefersdark (comment 3-23: the only dark switch is the `.dark` class plus data-theme set by theme_controller.js)
- TOKEN `--color-base-100` (`app/assets/tailwind/application.css:34,74`): oklch(97.5% 0.005 80) | oklch(18% 0.005 260) | page/card surface; bg-base-100, text-base-100 etc.; also used as ring-offset colour (base.css:84)
- TOKEN `--color-base-200` (`app/assets/tailwind/application.css:35,75`): oklch(96% 0.004 80) | oklch(22% 0.005 260) | secondary surface; bg-base-200 (table headers, panels)
- TOKEN `--color-base-300` (`app/assets/tailwind/application.css:36,76`): oklch(92% 0.004 80) | oklch(28% 0.005 260) | deepest surface; row-hover fill (table-row-hover), borders border-base-300
- TOKEN `--color-base-content` (`app/assets/tailwind/application.css:37,77`): oklch(40% 0.01 60) | oklch(75% 0.01 80) | default ink; text-base-content; aliased by --color-body
- TOKEN `--color-primary` (`app/assets/tailwind/application.css:38,78`): oklch(0.52 0.2 262) | oklch(0.68 0.19 262) | brand blue; links (link utility), btn-primary, focus rings ring-primary
- TOKEN `--color-primary-content` (`app/assets/tailwind/application.css:39,79`): oklch(100% 0 0) | oklch(18% 0.02 70) | ink on primary fill
- TOKEN `--color-secondary` (`app/assets/tailwind/application.css:40,80`): oklch(48% 0 89.876) | oklch(65% 0.01 260) | grey secondary; btn-secondary, badge-secondary, bg-secondary (camera-preview)
- TOKEN `--color-secondary-content` (`app/assets/tailwind/application.css:41,81`): oklch(100% 0 0) | oklch(18% 0.005 260) | ink on secondary
- TOKEN `--color-accent` (`app/assets/tailwind/application.css:42,82`): oklch(50% 0.2 300) | oklch(65% 0.2 300) | purple accent; *-accent utilities
- TOKEN `--color-accent-content` (`app/assets/tailwind/application.css:43,83`): oklch(100% 0 0) | oklch(100% 0 0) | ink on accent
- TOKEN `--color-neutral` (`app/assets/tailwind/application.css:44,84`): oklch(30% 0.01 260) | oklch(40% 0.01 260) | dark neutral; copy-tip fill, dark badge-soft secondary override
- TOKEN `--color-neutral-content` (`app/assets/tailwind/application.css:45,85`): oklch(98% 0 0) | oklch(90% 0 0) | ink on neutral; navbar ghost-button ink (navbar.css:22); print sheet solid-chip ink
- TOKEN `--color-info` (`app/assets/tailwind/application.css:46,86`): oklch(55% 0.2 260) | oklch(65% 0.18 260) | info status; icon-info, box-theme-info, toast-info, vc-progress-pending
- TOKEN `--color-info-content` (`app/assets/tailwind/application.css:47,87`): oklch(100% 0 0) | oklch(0.398 0.072 264.921) | ink on info
- TOKEN `--color-success` (`app/assets/tailwind/application.css:48,88`): oklch(48% 0.15 160) | oklch(60% 0.15 160) | success status; icon-success, ac-option-active tint, photo-board active group
- TOKEN `--color-success-content` (`app/assets/tailwind/application.css:49,89`): oklch(100% 0 0) | oklch(100% 0 0) | ink on success
- TOKEN `--color-warning` (`app/assets/tailwind/application.css:50,90`): oklch(48% 0.138 52.532) | oklch(72% 0.17 55) | warning/amber; icon-warning, box-theme-warning, unread tint, the whole login door accent
- TOKEN `--color-warning-content` (`app/assets/tailwind/application.css:51,91`): oklch(100% 0 0) | oklch(18% 0.02 55) | ink on warning
- TOKEN `--color-error` (`app/assets/tailwind/application.css:52,92`): oklch(0.395 0.16 24.035) | oklch(0.598 0.237 28.536) | error status; icon-error, box-theme-error, text-error
- TOKEN `--color-error-content` (`app/assets/tailwind/application.css:53,93`): oklch(100% 0 0) | oklch(97% 0.01 25) | ink on error
- TOKEN `--radius-selector` (`app/assets/tailwind/application.css:55,95`): 1rem | same | daisyUI radius for checkbox/toggle/badge (rounded-selector; 0 call sites)
- TOKEN `--radius-field` (`app/assets/tailwind/application.css:56,96`): 0.5rem | same | daisyUI radius for buttons/inputs (rounded-field; 1 call site in views/helpers; copy-tip uses it)
- TOKEN `--radius-box` (`app/assets/tailwind/application.css:57,97`): 0.75rem | same | daisyUI radius for cards/modals/alerts (rounded-box; 3 call sites; table-container, dropdown-panel, driver popover)
- TOKEN `--size-selector` (`app/assets/tailwind/application.css:58,98`): 0.25rem | same | daisyUI selector base size unit
- TOKEN `--size-field` (`app/assets/tailwind/application.css:59,99`): 0.25rem | same | daisyUI field size unit (btn/input height = n x this); accessibility.css:22 multiplies by 9 for sm
- TOKEN `--border` (`app/assets/tailwind/application.css:60,100`): 1px | same | daisyUI component border width
- TOKEN `--depth` (`app/assets/tailwind/application.css:61,101`): 1 | same | daisyUI depth effect on (subtle shadows/gradients on components)
- TOKEN `--noise` (`app/assets/tailwind/application.css:62,102`): 0 | same | daisyUI noise texture off
- TOKEN `--font-sans` (`app/assets/tailwind/application.css:106`): "Atkinson Hyperlegible", system-ui stack | same | font-sans, default body family; faces declared in fonts.css (variable 200-800, latin/latin-ext/italic)
- TOKEN `--font-mono` (`app/assets/tailwind/application.css:107`): "Atkinson Hyperlegible Mono", ui-monospace stack | same | font-mono; kbd (base.css:59-61); --lexxy-font-mono
- TOKEN `--color-default / --color-default-soft / --color-default-strong` (`app/assets/tailwind/application.css:109-111`): var(base-200) / var(base-100) / var(base-300) | follows base tokens | bg-default (18 files), bg-default-strong (3 files, messages hover), lexxy ink-lightest; bg-default-soft and text-default unused
- TOKEN `--color-heading` (`app/assets/tailwind/application.css:125,236`): oklch(30% 0.01 60) | oklch(85% 0.01 80) (.dark, [data-theme=dark]) | text-heading (129 files); text-heading-primary utility also reads it
- TOKEN `--color-body` (`app/assets/tailwind/application.css:126`): var(--color-base-content) | follows base-content | text-body (116 files); text-stone-emphasis utility reads it
- TOKEN `--color-body-subtle` (`app/assets/tailwind/application.css:139,230`): oklch(50% 0.012 60) | oklch(66% 0.012 80) | text-stone-subtle / text-stone-icon; Tailwind also emits text-body-subtle (0 view/helper files; applied in login.css:88,349)
- TOKEN `--color-line` (`app/assets/tailwind/application.css:140,226`): oklch(30% 0.01 260) | oklch(52% 0.01 260) | border-line (66 files); paper-preview borders of print sheets; card-standard edge
- TOKEN `--color-chrome` (`app/assets/tailwind/application.css:156`): oklch(0% 0 0) | same (always dark) | bg-chrome: sidebar field, navbar at /80 (3 files)
- TOKEN `--color-sidebar-content` (`app/assets/tailwind/application.css:157`): oklch(95.5% 0 0) | same | text-sidebar-content (sidebar_helper.rb), sidebar ghost button ink
- TOKEN `--color-sidebar-link` (`app/assets/tailwind/application.css:158`): oklch(38.0% 0.011 248.1) | same | bg-sidebar-link via sidebar-link-default
- TOKEN `--color-sidebar-link-hq` (`app/assets/tailwind/application.css:159`): oklch(40.4% 0.030 77.0) | same | bg-sidebar-link-hq via sidebar-link-hq (HQ brown)
- TOKEN `--color-sidebar-title-hq` (`app/assets/tailwind/application.css:160`): oklch(28.8% 0.059 70.7) | same | bg-sidebar-title-hq via sidebar-group-title-hq
- TOKEN `--color-sidebar-divider` (`app/assets/tailwind/application.css:161`): oklch(17.3% 0 0) | same | border-sidebar-divider (sidebar-nav-item, sidebar_helper.rb:83)
- TOKEN `--color-sidebar-active` (`app/assets/tailwind/application.css:162`): #ffc107 (hex) | same | active sidebar item text and 5px right border (sidebar.css:62-65)
- TOKEN `--color-signature-edge` (`app/assets/tailwind/application.css:173,239`): oklch(92.4% 0.12 95.746 / 0.4) | oklch(55.5% 0.163 48.998 / 0.3) | ring-signature-edge: hero panel amber ring, hero tiles, trophies, progress box badge (3 files + me-hero-panel)
- TOKEN `--color-hero-tile` (`app/assets/tailwind/application.css:174,240`): oklch(98.7% 0.022 95.277) | oklch(41.4% 0.112 45.904 / 0.3) | bg-hero-tile (ui_hero_panel_helper.rb:26)
- TOKEN `--color-hero-tile-content` (`app/assets/tailwind/application.css:175,241`): oklch(47.3% 0.137 46.201) | oklch(96.2% 0.059 95.617) | text-hero-tile-content (ui_hero_panel_helper.rb:28)
- TOKEN `--text-2xs` (`app/assets/tailwind/application.css:178`): 0.625rem | same | text-2xs; 0 call sites
- TOKEN `--text-base / --text-base--line-height` (`app/assets/tailwind/application.css:179-180`): 0.9rem / 1.2 | same | text-base shrunk from Tailwind's 1rem; line-height 1.2
- TOKEN `--text-lg` (`app/assets/tailwind/application.css:181`): 1.1rem | same | text-lg (Tailwind default 1.125rem); other text-* sizes are Tailwind defaults
- TOKEN `--spacing-8xl` (`app/assets/tailwind/application.css:182`): 90rem | same | *-8xl spacing/size utilities; 0 call sites
- TOKEN `--spacing-list-indent` (`app/assets/tailwind/application.css:189`): 1.5em | same | ps-list-indent, applied by list-bulleted/list-numbered and .lexxy-content lists
- TOKEN `--font-size` (`app/assets/tailwind/application.css:192`): 0.9rem | same | daisyUI base font size
- TOKEN `--leading-4..9` (`app/assets/tailwind/application.css:194-199`): 16px 20px 24px 28px 32px 36px (px) | same | leading-4..leading-9 in px; leading-4 and leading-9 0 call sites
- TOKEN `--leading-heading-none` (`app/assets/tailwind/application.css:201`): 60px | same | leading-heading-none; 0 call sites
- TOKEN `--tracking-tight / --tracking-tighter` (`app/assets/tailwind/application.css:200,202`): -0.4px / -0.8px | same | tracking-tight (1 file), tracking-tighter (0)
- TOKEN `--radius-0 / -xxs / -xs / -sm / --radius / -base / -lg` (`app/assets/tailwind/application.css:205-211`): 0 / 2px / 4px / 6px / 8px / 12px / 16px | same | rounded-* scale in px, overriding Tailwind defaults; rounded-lg (34 files) = 16px, larger than daisyUI --radius-box 0.75rem; rounded-base 13 files, rounded-xs 2, rounded-sm 1, rounded-0/xxs 0
- TOKEN `--default-border-width` (`app/assets/tailwind/application.css:214`): 1px | same | bare `border` width
- TOKEN `--container-brand` (`app/assets/tailwind/application.css:222`): 7rem | same | @min-brand container variant (application/_top_menu.html.erb, 1 file)
- TOKEN `@custom-variant dark` (`app/assets/tailwind/application.css:294`): &:where(.dark, .dark *) | - | dark: variant is class-based on .dark; daisyUI theme switches on data-theme; theme_controller.js:24-25 sets both
- TOKEN `@source list` (`app/assets/tailwind/application.css:251-261`): javascript, config, views, helpers, lib (not vendor lexxy) | - | only places class names compile from
- TOKEN `--lexxy-* re-theme` (`app/assets/stylesheets/components/lexxy.css:23-63`): ink=body, ink-medium=body-subtle, ink-lighter=line, ink-lightest=default-strong, canvas=base-100, accent=primary, red=error, radius=radius-field, toolbar button 2.25rem, content margin 0.5rem | follows tokens | maps rich-text editor variables onto app tokens; accent-medium = color-mix(primary, #000 7%)
- TOKEN `--button-row-gap` (`app/assets/stylesheets/components/buttons.css:32`): 1.5vh | same | button_row row gap (column gap 1.5vw literal at :41)
- TOKEN `--button-row-pad-bottom` (`app/assets/stylesheets/components/safe-area.css:61`): max(1rem, env(safe-area-inset-bottom)) | same | sticky button row and spacer bottom padding
- TOKEN `--hero-stat-hue` (`app/assets/stylesheets/components/hero-panel.css:39,49,53`): flame: mix(warning 68%, error); award: oklch(50% 0.13 85) | award dark: oklch(83% 0.17 90) | per-tile hue for hero stat badges
- TOKEN `--ct-s1..s8, --ct-grid` (`app/assets/stylesheets/components/credit-chart.css:16-24,28-35`): #2a78d6 #eb6834 #1baf7a #eda100 #e87ba4 #008300 #4a3aa7 #e34948; grid mix(base-content 15%, base-100) | #3987e5 #d95926 #199e70 #c98500 #d55181 #008300 #9085e9 #e66767 (.dark only) | credit timeline chart series palette (hex); ct-s0 #898781 fallback grey
- TOKEN `--login-drop / --login-cut` (`app/assets/stylesheets/login.css:27-28,36-37`): oklch(0% 0 0 / 0.35) / (0.22) | oklch(0% 0 0 / 0.9) / (0.7) | login panel drop shadow and field inset shadow
- TOKEN `--photo-board-header-height` (`app/assets/stylesheets/components/photo-board.css:25`): 4rem (JS overwrites) | same | sticky header offset for ROC wall display
- TOKEN `--zoom` (`app/assets/stylesheets/components/hq-window.css:121,175`): 1.15 at >=112.5rem, 1.35 at >=150rem | same | HQ shell zoom; read by review-pane max-height
- BASE `turbo-frame` (`app/assets/stylesheets/base.css:44-46`): display: block (layered base) | none
- BASE `main` (`app/assets/stylesheets/base.css:48-50`): bg-base-100 (layered base) | none
- BASE `kbd` (`app/assets/stylesheets/base.css:59-61`): font-mono | none
- BASE `p` (`app/assets/stylesheets/base.css:63-65`): mb-2 (layered base, so p utilities win) | none
- BASE `a:not(.no-decoration)` (`app/assets/stylesheets/base.css:67-69`): applies `link` utility = text-primary underline; opt-out class no-decoration (20 files) | none
- BASE `button` (`app/assets/stylesheets/base.css:71-73`): cursor-pointer | none
- BASE `*, ::before, ::after` (`app/assets/stylesheets/base.css:83-85`): --tw-ring-offset-color: base-100 so ring-offset gaps match the surface | none
- BASE `iOS focus zoom guard` (`app/assets/stylesheets/base.css:97-105`): @media (pointer: coarse) + @supports (-webkit-touch-callout) : text inputs/select/textarea/contenteditable :focus font-size 1rem (unlayered) | 1rem literal
- BASE `th:not(.text-center):not(.text-end):not(.text-right)` (`app/assets/stylesheets/components/tables.css:7-9`): text-align left (unlayered) | none
- BASE `table` (`app/assets/stylesheets/components/tables.css:17-19`): font-variant-numeric: tabular-nums | none
- BASE `mark` (`app/assets/stylesheets/components/lexxy.css:120-122`): bg-transparent text-inherit everywhere (removes UA highlighter) | none
- BASE `form fieldset / form fieldset > legend` (`app/assets/stylesheets/components/forms.css:7-20`): every fieldset in a form: left 4px primary border, primary/5 gradient, ps-4 mb-2 rounded-r-lg; legend: block w-full font-semibold text-lg border-b base-200 (unlayered) | none
- BASE `.navbar padding` (`app/assets/stylesheets/components/safe-area.css:20-23`): padding-inline max(0.5rem, safe-area inset) | 0.5rem
- BASE `.drawer-side > aside` (`app/assets/stylesheets/components/safe-area.css:41-43`): padding-inline-start env(safe-area-inset-left) | none
- BASE `@font-face Atkinson Hyperlegible (4 faces)` (`app/assets/stylesheets/fonts.css:22-56`): self-hosted woff2, weight 200-800, normal + italic, latin + latin-ext, font-display swap | none
- BASE `@font-face Atkinson Hyperlegible Mono (4 faces)` (`app/assets/stylesheets/fonts.css:58-92`): same four faces for mono | none
- BASE `@media (prefers-reduced-motion) .animate-pulse` (`app/assets/stylesheets/accessibility.css:40-44`): animation none (only global reduced-motion rule; ac-option/ac-filter-chip transitions and login-panel descendants have their own) | none
- BASE `touch-target floor .btn-sm, .select-sm, .btn-toast-close` (`app/assets/stylesheets/accessibility.css:19-23`): --size: calc(--size-field * 9) = 36px, lifting daisyUI sm (32px) | none
- BASE `@media print .disclosure-card` (`app/assets/stylesheets/components/disclosure.css:18-22`): hides closed disclosure cards holding an instruction-list | none
- BASE `print rules (all)` (`roster-matrix.css:68-82, top-hour-earners.css:48-52, hours-credits.css:71-84, disclosure.css:18`): only four @media print blocks; print sheets use @media screen for paper preview instead | none
- BASE `breakpoints in media queries` (`buttons.css:63,111,117; tables.css:52,140; safe-area.css:64; shift-coverage.css:12; hq-forecast.css:151; sandman-qualified.css:19; photo-board.css:52,156; review-pane.css:24; hq-window.css:37,114,162,172; login.css:302; mega-menu.css:20; label-value.css:33`): theme(--breakpoint-md/lg) in most; literal 1024px in mega-menu.css:20 and label-value.css:33; 112.5rem and 150rem in hq-window; container queries hq-forecast.css:127,133 (2rem, 3.25rem) and hq-window.css:201 (50rem) | 1024px, 112.5rem, 150rem, 50rem

## Observations recorded by the inventory agents

### admin

- All admin pages use layout "admin" from each controller (layout "admin"; shift coverage via Admin::ShiftCoverageBaseController); fragments render layout: false.
- Every page opens with hero_panel heading_level: :h1 and an id, except settings/edit.html.erb (no id, no description) and shift_coverage_groups/show.html.erb (no description). settings/index description "Adjust system settings" has no full stop.
- content_for :title is set on some pages (documents, jobs, oauth_clients, shift_coverage, sms_management) and not on the others.
- ui_table striped: is passed explicitly almost everywhere; tables with detail rows pass striped: false with a comment explaining why. rbs_alerts/_group.html.erb:7 and salesforce_query/_results.html.erb:37 pass responsive: false.
- ui_label_value label_width is chosen per page as a literal: 6rem, 8rem, 9rem, 10rem (action_logs/_table.html.erb:58; bug_reports:56; error_logs:82; request_logs:142; jobs/_job:26; sms_management index:28, twilio:19, _lookup:19); helper constant ACTION_LOG_METADATA_LABEL_WIDTH "12rem" (action_logs_helper.rb:6) has no caller in app/.
- Status is carried by ui_badge colour throughout, usually paired with an icon and text (jobs, sms, request logs, workers); the one text-only colour status is strong.text-error "* unknown *" in enrollment_roster.html.erb:30.
- No icon-only controls were found in scope; move buttons come from common/_move_buttons (not inventoried here). The salesforce sort heading button has visible column text plus a sort icon.
- Buttons that perform POST actions are button_link with method: :post (online_courses/edit.html.erb:10; jobs_helper.rb:134) rather than button_to/button_action.
- Turbo frame fragments in sms_management show outcomes as callout boxes, including flash messages (twilio.html.erb:4-9), because toasts cannot render inside a frame (comment at line 2-3).
- The Salesforce results area uses an arbitrary value lg:max-h-[70vh] with a comment citing the design guide; ACTION_LOG_EVENT_MAX_WIDTH max-w-[30ch] lives in a helper constant, outside class= so the census regex did not see it.

### common-a

- used-by | app/views/common/_checkbox_grid.html.erb | admin/action_logs/index:63, admin/legacy_log/index:80, vc/handle_checker/index:51,76, vc/thank_you_cards/index:33, people/search/index:84,138, people/people_by_location/_filter_fields:15, communication/rbs_broadcasts/_audience_fields:42, communication/rbs_messages/index:43,55
- used-by | app/views/common/_checkbox_row.html.erb | teams_positions/special_teams_hours/index:82, teams_positions/team_records/_form:67, teams_positions/position_lineups/_form:22, teams_positions/position_records/_form:148, admin/shift_coverage_groups/_form:28, shift_operations/payroll_export/index:61, communication/rbs_broadcasts/_position_checkboxes:25 (all via render layout:)
- used-by | app/views/common/_checkbox_tile.html.erb | common/_checkbox_grid:12, person/timesheets/backfill:23, vc/handle_checker/index:65 (render layout:)
- used-by | app/views/common/_dashboard_group.html.erb | me/dashboard/index:25, person/dashboard/show:24
- used-by | app/views/common/_dashboard_progress.html.erb | me/dashboard/index:18, person/dashboard/show:23
- used-by | app/views/common/_dashboard_section_header.html.erb | common/_dashboard_group:4
- used-by | app/views/common/_dashboard_step.html.erb | common/_dashboard_group:6 (collection)
- used-by | app/views/common/_dropdown_scroll_list.html.erb | ApplicationHelper#dropdown_scroll_list (app/helpers/application_helper.rb:77), called from teams_positions/position_grants/index, teams_positions/team_records/index, teams_positions/position_records/index, timesheets/timesheets_by_callsign/index, scheduling/schedule_by_position/index, scheduling/schedule_by_callsign/index, person/memberships/edit, me/directory/index, people/unified_flagging/index
- used-by | app/views/common/_entry_card_grid.html.erb | common/available_sign_ups/_slot:84, common/timesheet/_listing:5, common/timesheet/_entry_with_action:26
- used-by | app/views/common/_error_summary.html.erb | common/_form_wrapper:2 only
- used-by | app/views/common/_event_summary_breakdown.html.erb | me/event_summary/index:12, person/timesheets/breakdown:16, hq/timesheets/event_summary:15
- used-by | app/views/common/_event_summary_counts.html.erb | common/_event_summary_breakdown:22, person/swag/index:18
- used-by | app/views/common/_form_wrapper.html.erb | no caller found in app/views, app/helpers, app/controllers, app/models, app/lib (appears unused)
- used-by | app/views/common/_hours_not_eligible.html.erb | common/available_sign_ups/show:7
- used-by | app/views/common/_icon_block.html.erb | common/_timesheet_confirm:101,108, me/tickets/_ticket_overview_item:26 (render layout:)
- used-by | app/views/common/_legal_name_fields.html.erb | register/_form:81, people/create_account/new:38
- used-by | app/views/common/_mailing_address_fields.html.erb | register/_form:89, profile/mailing_address_edit:27, people/create_account/new:46
- used-by | app/views/common/_move_buttons.html.erb | admin/shift_coverage_groups/index:53, admin/shift_coverage_groups/show:53, bmid/titles/index:43, communication/surveys/_group_actions:9, communication/surveys/_group:52
- used-by | app/views/common/_photo_none.html.erb | hq/shared/_summary_column:11, person/_photo:19, common/mentoring/_mentee_card:15, profile/_bmid:14
- used-by | app/views/common/_preferred_name_disclaimer.html.erb | no caller found (appears unused)
- used-by | app/views/common/_skipped_years_pair.html.erb | teams_positions/special_teams_hours/index:42, timesheets/top_hour_earners/index:28, people/retention_report/index:36
- used-by | app/views/common/_status_medallion.html.erb | me/agreements/index:58, me/vehicles_dashboard/index:33, me/vehicles_dashboard/_pvr_status_agreement_needed:3,34
- used-by | app/views/common/_time_warnings.html.erb | person/timesheets/edit:94, person/timesheets/_desired_changes:35, person/missing_requests/edit:39
- used-by | app/views/common/_timesheet_confirm.html.erb | common/timesheet/index:38
- used-by | app/views/common/_timesheet_notes.html.erb | person/timesheets/edit:35,67,75, person/missing_requests/edit:95,103, person/missing_requests/show:32, common/missing_requests/_form:17, common/missing_requests/_entry:63, common/timesheet/edit:10, common/timesheet/_entry_with_action:134
- used-by | app/views/common/_toast.html.erb | UiComponents::ToastHelper (app/helpers/ui_components/toast_helper.rb:55,57,59)
- used-by | app/views/common/_trophies.html.erb | me/awards/index:20,25,30
- used-by | app/views/common/_turbo_partial_wrapper.html.erb | no caller found (appears unused)
- used-by | app/views/common/_years_breakdown.html.erb | YearHelper#years_breakdown (app/helpers/year_helper.rb:5), called from person/work_history/index:18, person/swag/index:15, me/work_history/index:20
- used-by | app/views/common/messages/_arrival.turbo_stream.erb | PersonMessage model broadcast (app/models/person_message.rb:826)
- used-by | app/views/common/messages/_compose_buttons.html.erb | common/messages/index:21, common/messages/show:20
- used-by | app/views/common/messages/_compose.html.erb | common/messages/new:26
- used-by | app/views/common/messages/_conversation_list.html.erb | common/messages/_list_frame:16, MessagesConcern:459 (turbo_stream.update)
- used-by | app/views/common/messages/_conversation_summary.html.erb | common/messages/_conversation_list:20 (collection), common/messages/_list_reply:14, MessagesConcern:488
- used-by | app/views/common/messages/_find_recipient.html.erb | MessagesConcern:109 (turbo_stream.append "modal")
- used-by | app/views/common/messages/_find_recipient_form.html.erb | common/messages/_find_recipient:4, MessagesConcern:121,176,192
- used-by | app/views/common/messages/_folder_selector.html.erb | common/messages/_workspace:50, MessagesConcern:465
- used-by | app/views/common/messages/_list_frame.html.erb | common/messages/_workspace:52, MessagesConcern:53
- used-by | app/views/common/messages/_list_reply.turbo_stream.erb | PersonMessage model broadcast (app/models/person_message.rb:858)
- used-by | app/views/common/messages/_message_card.html.erb | common/messages/_thread:29, MessagesConcern:277,700, PersonMessage model (person_message.rb:865)
- used-by | app/views/common/messages/_messages_panel_header.html.erb | common/messages/_messages_panel:16, MessagesConcern:725
- used-by | app/views/common/messages/_messages_panel.html.erb | common/messages/_pane:27
- used-by | app/views/common/messages/_pane.html.erb | common/messages/_workspace:55, MessagesConcern:76,680 (pane-only answer)
- used-by | app/views/common/messages/_reply_form.html.erb | common/messages/_messages_panel:50, MessagesConcern:708
- used-by | app/views/common/messages/_search_field.html.erb | common/messages/_workspace:43
- used-by | app/views/common/messages/_thread.html.erb | common/messages/_messages_panel:44
- used-by | app/views/common/messages/_workspace.html.erb | common/messages/index:24, common/messages/show:23
- used-by | app/views/common/unified_flagging/_detail_frame.html.erb | mentoring/convert_prospectives/index:157
- used-by | app/views/common/unified_flagging/_group_tiles.html.erb | common/unified_flagging/index:19, people/unified_flagging/index:23
- used-by | app/views/common/unified_flagging/_history.html.erb | common/unified_flagging/_review_pane:43, common/unified_flagging/detail:8
- used-by | app/views/common/unified_flagging/_lead_legend.html.erb | common/unified_flagging/index:29, people/unified_flagging/index:36, mentoring/post_season_summary/index:44, mentoring/alpha_status/index:58, mentoring/potential_alphas/index:44
- used-by | app/views/common/unified_flagging/_list_row.html.erb | common/unified_flagging/_review_list:8 (collection)
- used-by | app/views/common/unified_flagging/_name_line.html.erb | common/unified_flagging/_review_pane:27
- used-by | app/views/common/unified_flagging/_note_buttons.html.erb | common/unified_flagging/_review_pane:40, common/unified_flagging/_history:144
- used-by | app/views/common/unified_flagging/_personnel_warning.html.erb | common/unified_flagging/index:22, people/unified_flagging/index:26, mentoring/post_season_summary/index:36, mentoring/potential_alphas/index:36
- used-by | app/views/common/unified_flagging/_rank_legend.html.erb | common/unified_flagging/index:30, people/unified_flagging/index:37, mentoring/alpha_status/index:59, mentoring/post_season_summary/index:45, mentoring/convert_prospectives/index:68, mentoring/potential_alphas/index:45
- used-by | app/views/common/unified_flagging/_review_legend.html.erb | common/unified_flagging/index:28, people/unified_flagging/index:35, mentoring/post_season_summary/index:43, mentoring/alpha_status/index:57, mentoring/potential_alphas/index:43
- used-by | app/views/common/unified_flagging/_review_list.html.erb | common/unified_flagging/index:68, people/unified_flagging/index:108, mentoring/post_season_summary/index:102, mentoring/alpha_status/index:111,125,129, mentoring/potential_alphas/index:101
- used-by | app/views/common/unified_flagging/_review_pane.html.erb | common/unified_flagging/index:61, people/unified_flagging/index:101, mentoring/post_season_summary/index:92, mentoring/alpha_status/index:89, mentoring/potential_alphas/index:75, UnifiedFlaggingConcern:149
- used-by | app/views/common/unified_flagging/_review_workspace.html.erb | common/unified_flagging/index:62, people/unified_flagging/index:104, mentoring/alpha_status/index:90, mentoring/post_season_summary/index:94, mentoring/potential_alphas/index:76 (render layout:)
- used-by | app/views/common/unified_flagging/_signal_line.html.erb | common/unified_flagging/_review_pane:28
- used-by | app/views/common/surveys/_answers.html.erb | common/surveys/_question:43,49, me/feedback/_survey:75
- used-by | app/views/common/surveys/_question.html.erb | common/surveys/report:106, common/surveys/trainer:50
- used-by | app/views/common/surveys/_ratings_table.html.erb | common/surveys/report:67, common/surveys/trainer:37
- used-by | app/views/common/surveys/_session_label.html.erb | common/surveys/_question:40, common/surveys/_ratings_table:26, me/feedback/_survey:35,73
- used-by | app/views/common/surveys/_survey_name.html.erb | common/surveys/_survey_table:28,30, communication/surveys/index:49
- used-by | app/views/common/surveys/_survey_table.html.erb | training/surveys/index:40, mentoring/surveys/index:27
- used-by | app/views/common/mail_log/_legend.html.erb | person/mail_log/index:20, admin/mail_log/index:22
- used-by | app/views/common/mail_log/_table.html.erb | person/mail_log/index:30, admin/mail_log/index:72
- used-by | app/views/common/rbs/_delivery_summary.html.erb | communication/rbs_broadcasts/sent:20, communication/rbs_history/retried:14
- used-by | app/views/common/rbs/_delivery_table.html.erb | communication/rbs_broadcasts/sent:25, communication/rbs_history/retried:24
- used-by | app/views/common/rbs/_sandbox_notice.html.erb | common/rbs/_delivery_summary:31, communication/rbs_broadcasts/review:28, communication/rbs_broadcasts/_notices:23, communication/rbs/index:20
- used-by | app/views/common/resource_documents/_document.html.erb | teams_positions/team_documents/show:13, training/resources/show:13
- used-by | app/views/common/resource_documents/_form.html.erb | common/resource_documents/edit:18
- used-by | app/views/common/documents/_body_field.html.erb | admin/documents/_form:23, common/resource_documents/_form:16
- used-by | app/views/common/assets/_change_attachment_modal.html.erb | AssetManagementConcern#render_asset_modal("change_attachment_modal") (app/controllers/concerns/asset_management_concern.rb:92), included by hq/assets, person/assets, hq/shift_manage, hq/site_registration controllers
- used-by | app/views/common/assets/_expired_modal.html.erb | AssetManagementConcern#render_asset_modal("expired_modal") (asset_management_concern.rb:62)
- used-by | app/views/common/assets/_checkout_form.html.erb | hq/site_registration/_radios_step:22, hq/shift_manage/_assets_section:59, hq/assets/index:16, person/assets/index:20
- used-by | app/views/common/assets/_checkout_history.html.erb | asset_management/search/index:118, asset_management/records/show:63
- used-by | app/views/common/assets/_duration_label.html.erb | common/assets/_table:38, hq/shift_manage/_asset_table:21
- used-by | app/views/common/assets/_radio_agreement_warning.html.erb | hq/shift_manage/_assets_section:14, hq/assets/index:20
- used-by | app/views/common/assets/_table.html.erb | hq/site_registration/_radios_step:26, hq/assets/index:24,34, person/assets/index:28
- used-by | app/views/common/bmids/_fields.html.erb | person/bmids/show:45, bmid/badges/edit:106
- used-by | app/views/common/bmids/_flag_legend.html.erb | bmid/manage/index:114, bmid/export/index:66
- used-by | app/views/common/bmids/_warnings.html.erb | person/bmids/show:30, bmid/badges/edit:43
- used-by | app/views/common/provisions/_form.html.erb | common/provisions/new:9, common/provisions/edit:12, bmid/provisions/_modal:23 (modal: true)
- used-by | app/views/common/provisions/_list.html.erb | person/provisions/_section:49, bmid/provisions/_list:25
- used-by | app/views/common/ticketing_maintenance/_results_table.html.erb | ticketing/trs_export/mark_submitted:34, ticketing/unsubmit_provisions/results:32, ticketing/maintenance/results:31, ticketing/maintenance/preview:39
- used-by | app/views/common/missing_requests/_entry.html.erb | common/missing_requests/index:16,25
- used-by | app/views/common/missing_requests/_form.html.erb | common/missing_requests/new:5, common/missing_requests/edit:5
- app/views/common/_timesheet_confirm.html.erb reads controller instance variables (@corrections_enabled, @have_outstanding, @final_confirmation, @timesheets_unverified, etc.) rather than locals
- app/views/common/_entry_card_grid.html.erb declares a signups_label local (default "SIGN-UPS") in its strict-locals line but never renders it
- app/views/common/surveys/_session_label.html.erb and _ratings_table.html.erb read @slots / @survey and params[:report_id] from the controller, not locals
- app/helpers/unified_flagging_helper.rb GROUP_META gives personnel and flagged groups the same stat_variant :warning while their section badge colours differ (:error vs :warning), lines 15-16
- messages/_pane.html.erb:22 carries `review-pane box box-default` inside a class_names() string; the census recorded these classes for unified_flagging/_review_pane but has no row for messages/_pane
- bulk_upload index and preview depend on per-controller partials (advisory, extra_fields, formats, consequence) that sit outside this scope and were not opened
- app/views/common/messages/_reply_form.html.erb and _compose.html.erb use rich_text_area (Lexxy editor); _reply_form hides the label and supplies aria-label
- app/views/common/unified_flagging/_detail_frame.html.erb, _review_pane.html.erb and messages/_pane.html.erb all target "_top" from inside their frames

### common-b

- used-by | app/views/common/schedule/_signed_up_row.html.erb | common/schedule/index.html.erb:115,129 (collection render); also wrapped by me/schedule/_signed_up_row.html.erb, for which no renderer was found in app/views, app/helpers or app/controllers
- used-by | app/views/common/schedule/_export_warning.html.erb | common/schedule/index.html.erb:86,152 (rendered into confirm_modal message); also wrapped by me/schedule/_export_warning.html.erb, for which no renderer was found
- used-by | app/views/common/schedule/_people_signed_up.html.erb | me/schedule/_people_signed_up, person/scheduling/_people_signed_up, hq/scheduling/_people_signed_up wrappers; those are rendered by ScheduleConcern#signups (app/controllers/concerns/schedule_concern.rb:39) as turbo_stream.update into "signups-<slot id>", for both the schedule rows and the available sign-up slot cards
- used-by | app/views/common/scheduling/_signup_blockers.html.erb | common/schedule/index.html.erb:24
- used-by | app/views/common/scheduling/_burn_weekend_shift_recommendation.html.erb | common/schedule/index.html.erb:49
- used-by | app/views/common/scheduling/_overlapping_sign_ups_list.html.erb | common/schedule/index.html.erb:106; common/available_sign_ups/show.html.erb:58
- used-by | app/views/common/scheduling/_overlapping_sign_ups.html.erb | common/schedule/_signed_up_row.html.erb:58; common/available_sign_ups/_slot.html.erb:97
- used-by | app/views/common/scheduling/_slot_additional_info.html.erb | common/schedule/_signed_up_row.html.erb:61; common/available_sign_ups/_slot.html.erb:106; scheduling/slots/position.html.erb:107 (collapsed: true); scheduling/slot_bulk_edits/new.html.erb:108
- used-by | app/views/common/scheduling/_confirm_signup_removal.html.erb | confirm_modal message in common/schedule/_signed_up_row.html.erb:81 and common/available_sign_ups/_slot.html.erb:122
- used-by | app/views/common/scheduling/_alpha_shift_info.html.erb | common/available_sign_ups/show.html.erb:53
- used-by | app/views/common/scheduling/_slot_additional_info_modal.html.erb | AvailableSignUpsConcern (app/controllers/concerns/available_sign_ups_concern.rb:70) sets @modal; common/available_sign_ups/create.turbo_stream.erb:17 renders it
- used-by | app/views/common/scheduling/_missing_requirements_modal.html.erb | available_sign_ups_concern.rb:82 via @modal, rendered at common/available_sign_ups/create.turbo_stream.erb:17
- used-by | app/views/common/scheduling/_multiple_enrollment_modal.html.erb | available_sign_ups_concern.rb:84 via @modal, rendered at common/available_sign_ups/create.turbo_stream.erb:17
- used-by | app/views/common/scheduling/_missing_requirements.html.erb | common/scheduling/_missing_requirements_modal.html.erb:5
- used-by | app/views/common/scheduling/_mvr_eligible.html.erb | common/scheduling/_slot_additional_info_modal.html.erb:9
- used-by | app/views/common/scheduling/_linked_slots_full.html.erb | common/scheduling/_slot_additional_info_modal.html.erb:12
- used-by | app/views/common/shift_manage/_check_in_out.html.erb | me/shift_manage/index.html.erb:15 (GET /me/shift-manage); person/timesheets/shift_manage.html.erb:16 (GET /person/:person_id/shift-manage)
- used-by | app/views/common/shift_manage/_alerts.html.erb | common/shift_manage/_check_in_out.html.erb:4; hq/shift_manage/index.html.erb:48
- used-by | app/views/common/shift_manage/_on_duty.html.erb | common/shift_manage/_check_in_out.html.erb:7; hq/shift_manage/index.html.erb:91
- used-by | app/views/common/shift_manage/_start_shift.html.erb | common/shift_manage/_check_in_out.html.erb:9; hq/shift_manage/index.html.erb:97
- used-by | app/views/common/shift_manage/_converted_modal.html.erb | common/shift_manage/_alerts.html.erb:6
- used-by | app/views/common/shift_manage/_blocked_modal.html.erb | ShiftManageConcern#render_shift_modal (app/controllers/concerns/shift_manage_concern.rb:55,135,247) as turbo_stream.update("modal")
- used-by | app/views/common/shift_manage/_too_short_modal.html.erb | shift_manage_concern.rb:78 via render_shift_modal (turbo_stream.update "modal")
- used-by | app/views/common/shift_manage/_correct_position_modal.html.erb | shift_manage_concern.rb:119 via render_shift_modal (turbo_stream.update "modal")
- used-by | app/views/common/available_sign_ups/_slots.html.erb | common/available_sign_ups/show.html.erb:68,83
- used-by | app/views/common/available_sign_ups/_slot.html.erb | common/available_sign_ups/_slots.html.erb:5; create.turbo_stream.erb:4; destroy.turbo_stream.erb:4
- used-by | app/views/common/available_sign_ups/_training_months.html.erb | common/schedule/index.html.erb:34
- used-by | app/views/common/timesheet/_listing_with_actions.html.erb | common/timesheet/index.html.erb:96,99,105
- used-by | app/views/common/timesheet/_listing.html.erb | common/timesheet/index.html.erb:112
- used-by | app/views/common/timesheet/_entry_with_action.html.erb | common/timesheet/_listing_with_actions.html.erb:5; TimesheetCorrectionsConcern (app/controllers/concerns/timesheet_corrections_concern.rb:24) turbo-stream replace after Mark as Verified
- used-by | app/views/common/work_history/_matrix.html.erb | me/work_history/index.html.erb:23 (GET /me/timesheet/work-history); person/work_history/index.html.erb:49 (GET /person/:person_id/work-history)
- used-by | app/views/common/training/_status_badge.html.erb | common/training/_education_detail.html.erb:6
- used-by | app/views/common/training/_education_detail.html.erb | hq/training/index.html.erb:28,39; person/training/index.html.erb:91,102
- used-by | app/views/common/training/_online_course_status.html.erb | hq/training/index.html.erb:23; person/training/index.html.erb:19
- used-by | app/views/common/mentoring/_mentee_card.html.erb | common/mentoring/index.html.erb:12,53; common/mentoring/_art_section.html.erb:35
- used-by | app/views/common/mentoring/_art_section.html.erb | common/mentoring/index.html.erb:84
- used-by | app/views/common/mentoring/_shift_card.html.erb | common/mentoring/_alpha_shift_card.html.erb:11; training/mentoring/assignments/_upcoming_card.html.erb:3; training/mentoring/assignments/_shift_card.html.erb:26
- used-by | app/views/common/mentoring/_alpha_shift_card.html.erb | mentoring/alpha_schedule/index.html.erb:24; mentoring/shift_report/index.html.erb:44; mentoring/alpha_signout/index.html.erb:86; mentoring/alpha_pods/index.html.erb:26
- used-by | app/views/common/qualifications/_qualification_row.html.erb | common/qualifications/index.html.erb:64,67,77,81,98,100,106,109,112
- used-by | app/views/common/qualifications/_track.html.erb | common/qualifications/_qualification_row.html.erb:28,35
- mentoring/index.html.erb uses locals (description_text, back_link, link_to_person, send_message_path_builder, status_form_path_builder, can_edit_status) without a locals comment
- Several titles and labels in scope carry em dashes in user-facing text: scheduling/_burn_weekend_shift_recommendation.html.erb:2, scheduling/_mvr_eligible.html.erb:4,14, shift_manage/_too_short_modal.html.erb:31,52, shift_manage/_alerts.html.erb:20
- shift_manage partials read instance variables (@on_duty_entry, @upcoming_slots, @recent_entry, @status_converted) and helper methods (shift_person, shift_self_serve?, shift_can_force?) rather than locals; voice switches between second and third person on shift_self_serve? / timesheet_self_serve?
- hq/shift_manage/index.html.erb renders _alerts, _on_duty and _start_shift directly instead of through _check_in_out, so HQ and /me, /person compose the same pieces differently
- The "Show Sign-Ups" toggle on schedule rows and slot cards loads people_signed_up into an empty turbo-frame; no spinner, skeleton or placeholder text is defined in these views
- Buttons stay "secondary" for Add to Schedule and Remove from Schedule alike (available_sign_ups/_slot.html.erb:119-127); the only primary button in the schedule page body is the Available Sign-Up link and the disclosure gate summary

### communication

- mail_templates_controller.rb sets layout "admin" while every other controller under communication/ sets layout "communication"
- content_for :title is set on most pages but not on announcements/index, new, edit or person_banners/index
- rbs_history/show.html.erb:9 back_to label reads "Broadcast history" (lower-case h) where rbs_history/retried.html.erb:32, rbs/index.html.erb:43 and sent.html.erb:32 say "Broadcast History"; alerts/edit.html.erb:52 label "SMS Phone " has a trailing space
- The broadcast wizard (rbs_broadcasts new/review/sent) answers POSTs at 422 and uses hidden scroll-to-top divs and a hero progress bar (1/3, 2/3, 3/3) as its step indicator; review and sent both offer cancel_link/back actions in a final button_row as well as hero back_to
- Email layout (mail/layouts/mailer.html.erb) has no dark-mode rules; its link and button blue #0066cc and warning red #ff0000 are not taken from the app tokens, while its greys are copies of light-theme token values per its comment
- Info callouts in this scope carry several bodies: plain sentence with <strong> lead (rbs_history/index 22, surveys/index 11), instruction-list (rbs_phone_numbers/index 24), code lists (mail_templates/edit 13), forms (alerts/edit 119)
- rbs_messages/index.html.erb renders the same ui_pager twice (79 and 124); the second sits outside the empty/non-empty branch so it also shows under an empty state
- Several pages repeat the same stat-box variant rule (variant switches to :warning/:error when a count is positive, else :secondary/:success): announcements/index 13, rbs_phone_numbers/index 17,20, rbs_messages/index 21, rbs_history/index 18, rbs_history/show 57,62

### css

- application.css:105-223 overrides Tailwind defaults inside @theme: text-base 0.9rem with line-height 1.2, text-lg 1.1rem, the whole radius scale in px (rounded-lg = 16px, rounded-sm 6px, rounded-xs 4px), leading-4..9 in px, tracking-tight/-tighter in px. Unused tokens: --text-2xs, --spacing-8xl, --leading-heading-none, --radius-0, --radius-xxs, --color-default-soft (0 call sites in views/helpers/javascript/lib/config)
- --color-sidebar-active is the one hex left in the theme block (#ffc107, application.css:162); other hex literals live in credit-chart.css (17 hex), the five print-sheet files (#fff #111 #222 #ccc #bbb #999 #888 #777 #a3000c), progress.css:37 (#000 in a mask), and lexxy.css:38 (#000 in color-mix)
- The arbitrary shadow shadow-[0px_0px_6px_4px_rgba(0,0,0,0.1)] is written twice: .box (boxes.css:15) and .me-hero-panel (hero-panel.css:6); card-standard comment says cards are flat and lift belongs to .box and the hero panel
- .me-hero-panel applies `rounded` (hero-panel.css:6) and then `rounded-lg` (hero-panel.css:12) in the same rule
- !important in scope: buttons.css:65-66 (button-row column stacking below md), mega-menu.css:81,109 ([hidden] panels/items), lexxy.css:94 (provisional paragraph), login.css:436-437 (reduced motion)
- Unlayered rules that beat utilities on purpose: base.css:97-105 iOS zoom guard, tables.css:259-262 text-left in folded tables, boxes.css:65-71 warning descendant colour inherit, sidebar.css:62-65 active marker, mega-menu.css (all rules unlayered), login.css (all), autocomplete non-@utility rules, safe-area.css. Layered (components) on purpose: .box/.box-accent geometry, .responsive-table fold, .ui-label-value, review-pane, copy-tip relative anchor, lexxy.css and driver.css imports
- Minimum-size rules below the 36px floor named in accessibility.css:8-9: mega-menu-chrome-btn, mega-menu-item-link, mega-menu-back, mega-menu-close all min-h-8 (32px) (mega-menu.css:69,113,160,164); mega-menu-star min-w-8 (mega-menu.css:131)
- Literal breakpoint 1024px used where other files use theme(--breakpoint-lg): mega-menu.css:20 (min-width: 1024px) and label-value.css:33 (width >= 1024px); tables.css:126-128 comment describes an @3xl container-query fold but the rule is a viewport lg media query (tables.css:140)
- Reduced-motion handling is per component: accessibility.css:40-44 (only .animate-pulse), autocomplete.css:200-205, login.css:432-439. Animations without a reduced-motion rule: btn-copy-success keyframes (buttons.css:123-155), toast-base slide (toasts.css:9-20), progress-bar transition 500ms (progress.css:16), photo-board 0.3s transitions, login-submit-button transform
- z-index values in the stylesheet layer: -2/-1 (login.css:67,47,134,333), 0 (top-hour-earners), 10 (copy-tip, ac-filter-bar, photo-board-header, roster/hours/shift-coverage frozen cells), 20 (hq-gantt-mark hover, hq-forecast thead), 30 (roster/hours frozen headings), 40 (sticky-progress-container), 50 (ac-results, ac-loading, dropdown-panel)
- text-colors.css:19-23 says text-body-subtle is deliberately unused, but login.css:88 and login.css:349 @apply it
- Five login.css classes have no reference in app/views, app/helpers or app/javascript: login-beta, login-beta-summary, login-beta-body, login-doors-lede, login-foot. The box-theme-* @utility names are only used through @apply inside boxes.css
- badges.css:35-38 comment says icons.css uses raw Tailwind ramps (amber-600, red-400); icons.css:24-38 now maps them to theme tokens, so the comment is out of date
- flex-center applies only items-center (flex-patterns.css:5-7), not justify-center; one call site seen pairs it with `justify-center` (training/sessions/_trainee_card.html.erb:13)
- The amber login door: login.css colours almost everything from --color-warning (frame, wash, backdrop logo, links, submit gradient, focus outline, caret, selection) rather than primary; login-input replaces daisyUI's input focus outline
- Print support: four @media print blocks (roster-matrix, top-hour-earners, hours-credits, disclosure); print sheets rely on @media screen for the paper preview and on layouts/print pinning data-theme="light"; print-color-adjust: exact appears in 13 rules across signup-sheet, trainers-report, shift-lead-sheet, alpha-sheets, acceptance-sheet, hq-forecast, hours-credits
- Fixed dimensions repeated: 36px floor written as min-h-9 (many), calc(--size-field * 9) (accessibility.css:22), 2.25rem (lexxy.css:62, hq-forecast.css:102), w-9 h-9 (driver.css:82); 48px avatar w-12 h-12 written four times in messages.css:51-73
- app/assets/stylesheets/components/driver.css re-themes vendor classes only; the tour's buttons get btn classes from onboarding_controller.js, not CSS

### helpers-components

- action_box passes icon_position: :end to button_link (action_box_helper.rb:56), but ButtonHelper has no icon_position option: it reaches link_to as an HTML attribute (icon_position="end") and the arrow still renders before the label (button_helper.rb:259-266). Not verified in rendered HTML
- action_box builds container_options = options.merge(class:) (action_box_helper.rb:51) before removing :button_data (line 61), so a caller's button_data (person/callsigns/edit.html.erb:31 passes confirm_modal data) also reaches the container <div> as a button_data attribute. Not verified in rendered HTML
- ui_card_image computes width/height into a style on its options hash (ui_card_helper.rb:57) but never passes the hash to image_tag (line 60): width:, height: and class: are ignored. common/mentoring/_mentee_card.html.erb:12 passes height: PersonPhoto::AVATAR_HEIGHT
- sidebar_item accepts icon:, icon_type:, badge: and badge_variant: (sidebar_helper.rb:129-130) and renders none of them; render_sidebar_content (line 255) and sidebar_badge (line 240) that would draw them have no caller. badge_variant appears 3 times in app/views and app/helpers
- sidebar_menu documents width default 'w-65 lg:w-55' (sidebar_helper.rb:52) while the code default is "w-65 lg:w-50" (line 55); it also accepts and discards **_options
- modal documents :md as the default size (modal_helper.rb:13) but the code default is :lg = max-w-2xl (line 35); an unknown size falls back to :md. confirm_modal_dialog therefore opens at max-w-2xl. In views, modal/modal_dialog pass size: :lg 15 times and size: :xl 10 times (single-line grep)
- modal <dialog> has no aria-labelledby pointing at the h3 title and no aria-modal (modal_helper.rb:40-45); the backdrop close <button> has visible text "close" in lowercase and no type attribute (line 57)
- ui_alert_banner checks for type :danger (notice_box_helper.rb:70), which BOX_TYPES lacks, so :danger gets success styling with role="alert"
- ui_callout_box with an unknown type renders class "box" with no tint plus the info icon (notice_box_helper.rb:16, 25)
- ui_badge: :info is in BADGE_ICON_TINTS (badge_helper.rb:27) but not BADGE_VARIANTS, so an :info badge gets badge-secondary colours with an icon-info icon; one call does this (app/helpers/training/mentoring_helper.rb:167). Unknown size raises KeyError (line 46)
- ui_stat_box :primary is not a defined variant and falls back to secondary (ui_stat_box_helper.rb:51); one call passes it (app/views/timesheets/timesheet_unconfirmed/index.html.erb:30)
- ButtonHelper variants :tertiary and :dark (button_helper.rb:21,25) have no call site with that symbol in app/views or app/helpers; :tertiary and :ghost both map to btn-ghost. Single-line grep of button_link/button_action variant symbols: secondary 211, primary 108, ghost 29, error 10, warning 10, success 5
- ButtonHelper: secondary is "btn-secondary btn-outline" (button_helper.rb:20); a disabled button loses its variant entirely (btn-disabled replaces it, line 282)
- hero_panel defaults heading_level: :h2 (ui_hero_panel_helper.rb:242) while 404 single-line call sites pass heading_level: :h1; a level other than :h1/:h2 gets no size class (HEADING_CLASSES line 9-12). hero_stats aria-label uses the panel id, so an auto id names the list "hero-panel-xxxxxxxx statistics" (line 90). stat_badge with an unknown color raises NoMethodError (line 97-100)
- hero_panel renders the back link, the year selector and the stats twice each, one copy per breakpoint hidden with lg:hidden / hidden lg:block (ui_hero_panel_helper.rb:131-135, 167-169, 204, 209-231)
- render_progress_bar floors progress to 5% (ui_progress_completed_bar_helper.rb:16) and reports that floored value in aria-valuenow, so 0 of N is announced as 5
- ui_progress_box icon disc uses raw palette gradient from-amber-100 to-orange-100 dark:from-amber-900/40 dark:to-orange-900/40 (ui_progress_box_helper.rb:21); comment line 15-20 records it as knowingly left
- button_row sticky uses arbitrary shadows with literal rgba values and z-50 (button_helper.rb:63); sidebar logo uses h-[140px] w-[140px] (sidebar_helper.rb:100)
- ui_section: with border: true (the default) the body gets both pb-2 (BODY_BASE) and pb-1 (ui_section_helper.rb:7, 57); border: false removes only that px-4 pb-1 pair, not a border. 74 single-line view calls pass border: false
- ui_section_title is a <div role="heading" aria-level="2">, not an <h2> (ui_section_helper.rb:60-65)
- ui_label_value: label_class: is used as the <dt> options hash (ui_label_value_helper.rb:77), so the name suggests a string but a string would fail; 0 call sites pass label_class:
- ui_stat_box keeps only class: and aria: from **options (ui_stat_box_helper.rb:67-68); id and data are silently dropped. ui_stat_link likewise reads only class:
- tab_navigation stores options[:remote] (tabs_helper.rb:31) and never reads it; every tablist gets aria-label="Tabs" (line 74)
- sidebar_submenu puts aria-expanded="false" on a non-interactive <div> that never changes (sidebar_helper.rb:122)
- fa_icon builds "fa-#{size}" by interpolation (icon_helper.rb:107); the other options map through frozen hashes
- record_title, qualification_icon and photo_tag's fallback user icon carry no label: (application_helper.rb:110-112, 284-291, 155), so the icon's meaning is not exposed to assistive technology; the comment at line 279 says the row text beside it carries the words
- Helpers that take a free class: string appended to their own classes: button_row, button_action, button_link (and cancel/edit/export/delete/submit), dropdown_menu (class/summary_class/menu_class), dropdown_item, dropdown_button, callsign_link, ui_table (class and container_class) and every builder part, modal (class on <dialog>), ModalBuilder title/body/footer, ui_badge, ui_callout_box, ui_alert_banner, ui_empty_state, ui_accent_card (options[:class]), ui_accordion (class/summary_class/content_class), ui_disclosure, ui_drill_down_row, ui_card and parts, ui_section (class/body_class), ui_section_title, ui_label_value, ui_pager, ui_progress_bar (class/bar_class), ui_stat_box, ui_stat_link, ui_stat_row, action_box (options[:class]), hero builder title/description/hero_stats. No class: on ui_subheading, ui_icon_item (tone: only), ui_data_block (max_height: only), ui_match_stepper, ui_progress_box, filter_bar, back_to
- Approximate single-line counts of class: passed to helpers in app/views: ui_callout_box 58, button_link/button_action 8, ui_section 9, ui_badge (views+helpers) 15, ui_empty_state 2, ui_stat_box 1 (multi-line calls not counted)
- ui_callout_box accent: true appears 162 times (single-line grep of app/views and app/helpers). ui_callout_box type counts (single-line): warning 218, info 117, error 100, success 42, secondary 30
- ui_table builder usage (app/views + app/helpers, by grep): .row_header 195, .detail_row 14, .detail_row_toggle 14, state: : 27
- Unicode glyphs used as UI marks inside helpers: "—" em dash for empty values (application_helper.rb:85, link_helper.rb:36), "•" separator (ui_drill_down_row_helper.rb:89), "·" separator (ui_pager_helper.rb:34), "⌘ ⌃ ⇧" keyboard glyphs (navbar_helper.rb:80)
- Usage counting method: occurrences of the bare method name in app/views and app/helpers outside comments and def lines, counting calls prefixed by template./context. but not other receivers; counts include keyword-style mentions and are approximate. "other" = app/controllers, app/lib, app/models, app/presenters, app/services, app/forms, app/mailers
- usage | button_row | views 370, helpers 2
- usage | button_action | views 56, helpers 14
- usage | button_link | views 329, helpers 17
- usage | cancel_button | views 15, helpers 1
- usage | cancel_link (alias of cancel_button) | views 69, helpers 1; the two names are used side by side for the same control
- usage | edit_link | views 58, helpers 1
- usage | export_csv_link | views 85, helpers 1
- usage | delete_button | views 58, helpers 2
- usage | submit_button | views 34, helpers 1
- usage | button_classes | views 6, helpers 3
- usage | ui_table | views 263, helpers 3
- usage | ui_table_rows | views 3, helpers 2
- usage | modal | not counted reliably (the word collides with the "modal" frame id and class); census.tsv has the call sites
- usage | modal_dialog | views 48, helpers 0
- usage | modal_form_footer | views 32, helpers 0
- usage | modal_close_dialog | views 0, helpers 0; 15 in controllers
- usage | modal_close_button | views 31, helpers 1
- usage | confirm_modal | views 76, helpers 7
- usage | confirm_modal_dialog | views 24, helpers 5
- usage | modal_placement_class | views 0, helpers 1 (internal to modal)
- usage | tab_navigation | views 1 (me/event_info.html.erb:3), helpers 0
- usage | fa_icon | views 355, helpers 78
- usage | nav_link_to | ZERO call sites anywhere in app/
- usage | callsign_link | views 62, helpers 4
- usage | email_link_or_dash | views 23, helpers 0
- usage | person_display_name | views 12, helpers 15
- usage | person_display_link | views 94, helpers 11
- usage | can_view_person_page? | views 8, helpers 2
- usage | dropdown_menu | views 10, helpers 0 (plus the dropdown_scroll_list partial, counted in views)
- usage | dropdown_item | views 20, helpers 1
- usage | dropdown_button | views 1, helpers 0
- usage | dropdown_divider | views 2, helpers 2
- usage | dropdown_item_disabled | ZERO call sites anywhere in app/
- usage | page_title | views 3, helpers 1
- usage | render_for_user | ZERO call sites anywhere in app/
- usage | render_partial_for_user | ZERO call sites anywhere in app/
- usage | year_selector | views 1, helpers 2 (hero builder h.year_selector calls not counted here)
- usage | year_selector_compact | views 0, helpers 1 (only from hero_panel)
- usage | year_selector_keep_fields | views 0, helpers 2 (internal)
- usage | title_year_selector | ZERO call sites anywhere in app/
- usage | turbo_empty_frame | views 0, helpers 1 (modal_close_dialog), controllers 1
- usage | turbo_response | ZERO call sites anywhere in app/
- usage | page_redirect | views 0, helpers 0; 1 in app/controllers/concerns/timesheet_corrections_concern.rb:21
- usage | severity_style | views 0, helpers 3
- usage | menu_build / menu_uses_person? / menu_resolve_path / menu_item_active? / menu_item_options / menu_item_confirm_data | helpers only: 2 / 2 / 3 / 1 / 3 / 2
- usage | menu_each_section | only its own recursive call (menu_helper.rb:109); no external caller
- usage | menu_section_has_content? | ZERO call sites anywhere in app/
- usage | mega_* helpers | views: mega_menu_offered? 2, mega_recent_items 2, mega_favorite_items 3, mega_favorite_categories 3, mega_search_items 1, mega_labeled 2, mega_category_groups 1, mega_panel 5, mega_chrome_button 6, mega_category_index_button 2, mega_star_button 1, mega_category_star_button 2, mega_item_link_options 1
- usage | navbar_render_menu | views 1
- usage | kbd_shortcut / kbd_modifier_name / kbd_modifier_filter | views 2 / 3 / 2
- usage | sidebar_menu | views 21
- usage | sidebar_render_menu | views 21
- usage | sidebar_section / sidebar_submenu / sidebar_item | helpers only (1 / 2 / 2), no direct view calls
- usage | sidebar_submenu_item | ZERO call sites anywhere in app/
- usage | render_sidebar_content (private) | ZERO call sites; sidebar_badge reachable only through it
- usage | years_breakdown | views 3, helpers 1
- usage | year_range | views 13
- usage | dropdown_scroll_list | views 9, helpers 1
- usage | none_stated | views 10
- usage | value_or_dash | views 111, helpers 16
- usage | record_title | views 3
- usage | value_list | views 7, helpers 3
- usage | expires_on_cell / expires_at_cell | views 1 / 3
- usage | photo_tag | views 18
- usage | hyperlink_text / nl2br / rich_text | views 9 / 9 / 11
- usage | hour_not_counted_disclaimer | views 1
- usage | slot_virtual_venue_badge | views 4
- usage | back_to | views 292 (includes hero_panel back_to: keywords), helpers 8
- usage | back_to_dashboard | views 5, helpers 1
- usage | yes_no_badge | views 14, helpers 1
- usage | qualification_* | views: icon 1, bar_variant 1, section 4, next_step 1, goal_counts 1, name 1, amount 3, unit 1
- usage | action_box | views 8
- usage | ui_badge | views 267, helpers 172
- usage | bulk_select / bulk_select_all / bulk_select_count / bulk_select_checkbox | views 24 / 20 / 3 / 20
- usage | position_picker_count_label | views 3
- usage | clipboard_button | views 10
- usage | filter_bar | views 100, helpers 1
- usage | filter_chips | views 5, helpers 66
- usage | active_filters / known_filter / filter_time | views 19 / 0 / 0; helpers 28 / 0 / 0; known_filter and filter_time are called only from app/forms and controllers (UiComponents::FilterBarHelper.x)
- usage | filter_status_options / filter_select_options / filter_signed_up_options / filter_url | views 12 / 1 / 2 / 0; helpers 0 / 7 / 0 / 7
- usage | ui_flash_successful / ui_flash_submit_error | views 0, helpers 0; controllers 7 / 3
- usage | ui_success_text | helpers 1
- usage | ui_callout_box | views 519, helpers 2
- usage | ui_alert_banner | views 5
- usage | ui_empty_state | views 413
- usage | ui_toast_render / ui_toast_stream | views 4 / 2; helpers 2 / 0; ui_toast_stream 33 in controllers
- usage | ui_accent_card | views 17, helpers 1
- usage | ui_accordion | views 11, helpers 2
- usage | ui_card / ui_card_image / ui_card_body / ui_card_title / ui_card_section / ui_card_footer | views 11 / 2 / 7 / 2 / 4 / 5
- usage | ui_data_block | views 4, helpers 3
- usage | ui_disclosure | views 148, helpers 4 (134 single-line calls pass variant: :card)
- usage | ui_drill_down_row | views 36, helpers 4
- usage | ui_form | views 166, helpers 1
- usage | hero_panel | views 404
- usage | hero builder stat_badge / hero_stats / progress_status | 2 / 1 / 1 (grep of ".name"); stat_badge colors used: award 1, flame 1; warning and pending unused
- usage | ui_icon_item | views 24, helpers 7
- usage | ui_label_value | views 30
- usage | ui_match_stepper | views 1
- usage | ui_pager | views 15, helpers 1
- usage | ui_progress_bar | views 10, helpers 1
- usage | ui_progress_box | views 1
- usage | render_progress_bar / render_progress_status | helpers 2 / 2 (via hero panel and progress box only)
- usage | progress_count_of | views 2
- usage | ui_section | views 481, helpers 1
- usage | ui_section_title | views 10, helpers 1
- usage | ui_subheading | views 10
- usage | ui_stat_box | views 440, helpers 6
- usage | ui_stat_link | views 5, helpers 2
- usage | ui_stat_row | views 134

### helpers-forms

- help_mode: :tooltip puts the help only in a title attribute on an icon span (not focusable, no aria) while aria-describedby on the field still names "<id>_hint", an element that is not rendered (app/helpers/form_helper.rb:727-731, 810-819, 839)
- Help text and error share one slot and one id: when a field has errors its help text is not rendered at all (field_suffix, app/helpers/form_helper.rb:834-845)
- Inline errors carry role="alert" on every field error div (form_helper.rb:1090) and the summary callout is also role="alert" (via ui_callout_box default, notice_box_helper.rb:31), so a failed submit announces several alerts
- radio_button computes hint id from the attribute only ("<obj>_<attr>_hint", form_helper.rb:835), so several f.radio_button calls for one attribute with errors each emit a div with the same id
- The required-asterisk variant (required_label: "") is an fa_icon with no visually hidden text (form_helper.rb:790); fa_icon's own aria handling not traced here
- f.submit emits <input type="submit"> (Rails default) with btn classes and no icon support; ButtonHelper's other buttons are not used for it (form_helper.rb:536-540)
- date_field and time_field use native browser pickers; only datetime_field uses Vanilla Calendar Pro (text input + vanilla-calendar controller), so date and date-time pickers look different (form_helper.rb:193-219)
- form-fieldset CSS also matches every "form fieldset" and "form fieldset > legend" (components/forms.css:7-20), so builder radio-group fieldsets (class mb-3) pick up the left primary accent border and gradient as well
- ext_link adds an external-link icon but no accessible text that the link opens a new tab; it overwrites any caller-supplied rel/target (app/helpers/url_helper.rb:5-6)
- ui_form places the error summary outside and before the <form> element (app/helpers/ui_components/ui_form_helper.rb:37); filter_bar always passes no_error_summary: true (filter_bar_helper.rb:233-234)
- filter_bar panel uses the "hidden" class plus aria-hidden toggled by the "toggle" controller (filter_bar_helper.rb:241-244); the result count is text-lg text-stone-muted, larger than surrounding chip text (filter_bar_helper.rb:195)
- RolesHelper#has_role? never tests the role: it returns Array.wrap(role), always truthy for a signed-in user (app/helpers/roles_helper.rb:4-9). ApplicationController also declares helper_method :has_role? (app/controllers/application_controller.rb:35, 106); which definition views resolve to was not verified
- common/_form_wrapper has no caller found by grep in app/ or test/ (searched "form_wrapper"); common/_error_summary is rendered only by it
- app/forms/** emits no markup (grep for tag/content_tag/html_safe found none); only request_log_filter_form.rb:55 passes a status_class value
- Physical-direction utilities mixed with logical ones in the builder: ml-2 (required marker), left-0 pl-3 (icon prefix), lg:mr-2 (horizontal label) vs ms-1, ms-2, ps-3, pe-1 elsewhere (form_helper.rb:49, 87, 118, 792, 813)
- Character counter, autocomplete results, vanilla calendar and error focus ("form" controller) are produced by Stimulus controllers in app/javascript, which were not opened in this group

### hq-assets

- app/views/hq/shift_manage/_section.html.erb lines 38-41: the comment describes "lg:ms-auto, not ms-auto" but the span class is "ms-2 font-semibold text-lg"
- app/helpers/quartermaster/swag_distribution_helper.rb lines 59-62: comment reads "text-stone-muted, not text-stone-muted" (both names identical), so the stated reason cannot be matched to the code
- HQ pages (layouts/hq.html.erb) wrap every child in hq/shared/_shell: header hero_panel, person banners, danger notices, a photo/summary column that reorders on lg, and auto-opening warning modals; scoped CSS lives in components/hq-window.css (per _shell comment)
- About half of the hq templates (available_sign_ups, messages, missing_requests, scheduling, timesheets index/edit) are one-line wrappers over app/views/common templates; their UI is outside this group
- hq/shift_manage page is a Stimulus-driven guided flow (hq-shift controller): sections are <details> collapses opened by server state, a sticky checklist, hidden beacons, and many hidden-attribute toggles; final visible state depends on JS not inspectable here
- hq/site_registration wizard renders all steps up front inside one raw <dialog>, each <section hidden>, shown by the hq-wizard controller; step outcome notices are rendered as ui_callout_box inline instead of toasts (comment _radios_step.html.erb:6-8)
- ui_callout_box :error is used for non-error advisories (hq/site_registration/_emergency_contact_step.html.erb:29 off-season notice; hq/shift_manage/_pogs.html.erb:33 Mentor shift note; _pog_cancel_modal.html.erb:7)
- ui_empty_state is used for positive confirmations, not only empty lists: asset_management/records/show.html.erb:59 "currently checked in", assets_outstanding:30 "every asset has been checked back in", radio_checkout:124
- ui_badge carries full sentences as warnings in hq/shift_manage/_verification.html.erb:48,53 ("Entry might be too long at ...")
- hq/site_registration/show.html.erb:54-55 renders a permanently disabled full-width lg "Begin On-Site Registration" button when the person is already on site
- Report pages in asset_management, quartermaster, vehicles and pogs share one skeleton: hero_panel (+year_selector keep:) > ui_stat_row > ui_disclosure "About This Report" card > filter_bar > ui_section > ui_table > ui_pager

### js

- Hard-coded colour classes applied from JS: "text-primary", "text-stone-muted", "animate-pulse" (app/javascript/controllers/hq_shift_controller.js:227-249); "text-stone-subtle" (app/javascript/controllers/table_sort_controller.js:18); "border-primary", "bg-primary/5", "border-base-300", "border-line" (app/javascript/controllers/photo_upload_controller.js:147-149, 184); "opacity-60" for a disabled label (app/javascript/controllers/country_state_controller.js:56, 74); "btn btn-sm btn-ghost" / "btn btn-sm btn-primary" on driver.js popover buttons (app/javascript/controllers/onboarding_controller.js:127-128). Values passed from views: "bg-warning/10" bulk-edit dirty row (app/helpers/bmid/manage_helper.rb:81), "btn-copy-success", "text-sm ms-2 text-body" counter (app/helpers/form_helper.rb:722, 1215), "tab-active" (app/helpers/tabs_helper.rb:25)
- Custom CSS class names produced only in JS (not visible to a view scan): ac-filter-bar, ac-filter-chip, ac-filter-chip-active, ac-filter-count, ac-group, ac-group-header, ac-option, ac-option-active, ac-keyboard-help, ac-searching, ac-empty, ac-error, ac-results-above (autocomplete_controller.js); copy-tip (copy_to_clipboard_controller.js:54); show (toast_controller.js:12); photo-board-group-active, photo-board-rail-item-active (photo_board_controller.js:66, 70); vc-header, vc-wrapper, vc-content, vc-footer, vc-close-btn (vanilla_calendar_controller.js:83-101); active (active_links_controller.js:64)
- Inline styles set from JS: autocomplete max-height, scroll-padding-top, min-height in px (autocomplete_controller.js:194, 910, 1052); toast progress width/transition/transition-duration (toast_controller.js:42-43, 63-64, 85, 89); custom properties --dropdown-fit-shift (dropdown_fit_controller.js:23) and --photo-board-header-height (photo_board_controller.js:97)
- User-facing text lives in JS for: unsaved-changes leave prompt, hq-shift leave prompts and checklist count, membership-editor and permission-editor confirm texts (multi-paragraph, \n\n separated, "WARNING:" prefix), passkey error messages, photo-upload/photo-cropper/camera errors, autocomplete states, bulk-edit and select-all counts, search-matches "Match N of M", bookmark countdown, asset-form radio labels, login-submit "Working…", vanilla-calendar "Close", onboarding "Back" / "Skip the tour", copy "Copied", table-sort sentence, input-counter "N of MAX characters"
- Live-region announcements are used by copy-to-clipboard, autocomplete (result count) and table-sort only; checkbox-select-all relies on its count target being a live region in markup; input-counter, bulk-edit count, search-matches count and hq-shift count are updated silently from JS's side (whether their containers are live regions depends on the views)
- Keyboard handling in JS: autocomplete (arrows, Enter, Tab, Escape), dialog base hotkey Cmd/Ctrl+K (search-bar) and Cmd/Ctrl+Shift+K (mega-menu), mega-menu Escape clears search first, callsign-chips Enter makes a chip. tabs controller has no arrow-key support though it manages tabindex roving (tabs_controller.js:63, 77)
- Focus handling from JS: form focuses #form-error-summary or first errored field; autocomplete keeps focus in its input; mega-menu/search-bar focus their search inputs and error buttons; hq-wizard focuses [autofocus] of each step; hq-shift focuses #checkout-barcode; modal focuses autofocusOnCloseId on close; onboarding focuses Next then the menu button; callsign-chips refocuses its input; password-reveal keeps focus on its button. The toast takes no focus and has no keyboard dismissal besides its close button
- Two different mobile breakpoints hard-coded in JS: vanilla-calendar uses window.innerWidth <= 768 plus a mobile user-agent test (vanilla_calendar_controller.js:177-182); review-pane uses matchMedia "(width >= 64rem)" (review_pane_controller.js:36)
- Failures that show nothing to the user: copy-to-clipboard empty catch (copy_to_clipboard_controller.js:30); tabs remote fetch logs "Request failed" to console only (tabs_controller.js:52); camera enumerate errors console only (camera_controller.js:138); stream-nav falls back to a full visit (stream_nav_controller.js:38); pod-people and sortable drag PATCH failures have no JS handling
- app/javascript/controllers/application.js:6 sets application.debug = true unconditionally (Stimulus debug logging in every environment)
- Menu icons (app/lib/menus.rb): only categories carry an icon, as a bare Font Awesome name without style prefix: house (168), circle-user (1289), screwdriver-wrench (182), file-signature (260), users-gear (287), certificate (353), clipboard-user (383), handshake-angle (453), calendar-days (520), clock-rotate-left (641), ticket (706), clock (763), utensils (851), shirt (873), people-group (940), id-card (1031), car (1068), walkie-talkie (1103), bullhorn (117, COMMUNICATION_MANAGEMENT). Menu items carry no icons and no class strings. Account items: Bug Report opens in the "modal" turbo frame (1314), Clear Cache is a turbo_method post (1322), Logout has confirm: true (1328)
- app/lib/mega_menu.rb and app/lib/menu_builder.rb hold no class strings and no icon names (visibility and path logic only)
- Usage counts are files under app/views and app/helpers whose controller attribute names the controller; dialog and kiosk are base classes only; register-intent's attribute is built with a dynamic form_data[:controller] (register/_form.html.erb:25) and mega-menu's with token_list (application/_top_menu.html.erb:8), lexxy's with merge_data_controllers (form_helper.rb:408), camera/photo-upload with a selfie_enabled? ternary (profile_photos/new.html.erb:71)

### me

- Every dashboard task partial renders inside common/_dashboard_step's ui_accent_card body div "pl-6 me-muted" (border-l-2 when actionable); the partials themselves add no card, so most are bare text nodes, <p> or <div> fragments with no consistent outer element.
- The "Go To <page>" CTA in dashboard tasks is a text link with class tap-target-link, never a button helper; its wrapper varies (bare, div mt-1, div mt-2, p mt-1, p mb-2, p mt-2).
- ALL-CAPS shouting is used for warnings in dashboard tasks: "ARRIVE 20 MIN EARLY" (_attend_alpha_shift_pending:9), "ARRIVE 15 MIN EARLY" (_attend_cheetah_cub_shift_pending:2), "PRIVILEGES SUSPENDED" (_sign_nda_needed:3), "FULL DAY required" (_attend_training_pending:11), "DEADLINE" (_verify_timesheets:12); also "NO EXCEPTIONS!" (tickets/sap_so:69), "MUST" (online_course/index:13), "NOT authorized" (operational_summary/_basic_driving:21).
- dashboard_tasks/_dashboard_survey.html.erb is never rendered (no task returns that partial; grep finds no reference) and its strict locals (survey_type:, surveys:) would fail with the step:/facts: locals _dashboard_step passes. DashboardHelper#dashboard_step_status_class, #dashboard_step_icon and #dashboard_resolve_path have no callers.
- 21 dashboard_tasks partials have no strict-locals comment (e.g. _after_event_no_more_things, _no_things_at_the_moment, _online_course_completed, _sign_up_for_alpha_shift_needed, _vehicle_requests_*, _verify_timesheets_finished); several files end without a newline so wc reports 0 lines though they hold one line.
- app/views/me/event_info.html.erb has a controller action (MeController#event_info) but no route; it shows tab_navigation panes containing literal placeholder text.
- Ticketing partials _claimed_overview and _section_detail repeat the same SAP, vehicle-pass, SO-SAP and provisions detail blocks almost line for line (_claimed_overview:121-141 vs _section_detail:125-145; 155-172 vs 150-166; 176-189 vs 109-120); detail colours are symbols in one and strings in the other.
- Ticket "bank" action is labelled three ways on one page: "Bank This Ticket", "Bank It", "Bank for Later" (tickets/ticket:87,91,145).
- Colour is the only carrier of state in a few places: announcement h3 text-body vs text-heading for read/unread (_announcement:27, though a badge also states it); ticket card h3 text-success when claimed (ticket:65, badge also present); _ticket_overview_item h4 coloured by type with a coloured icon.
- Warning-coloured text (text-warning) is placed inside :info callouts in vehicles_dashboard (_eligible_positions:25,30, _pvr_status_ineligible:10, _pvr_status_potential:4).
- Several pages pass aria-label to button_link that differs from the visible text (vehicles_dashboard/_mvr_status_eligible:36, _pvr_status_agreement_needed:29, _pvr_status_eligible:12, _pvr_status_potential:20, vehicles_dashboard/index:46, announcements/_announcement:77,84).
- No spinners or skeletons in scope. Busy/lazy states: menu/show is the body of the lazily loaded "mega-menu" frame; announcements _unread_count is a stream-replaced frame; surveys/show and passkeys/new set submit busy labels; passkeys/new reveals hidden callouts from script; DashboardHelper adds animate-pulse to the "action needed" badge.
- Census rows css:icon-error / icon-warning / icon-success / icon-info are filed under "other" (badges.css) but in this scope they only colour fa_icon glyphs; census misses the literal &bullet; glyph bullets at dashboard_tasks/_bmid_will_not_be_printed:5,9 (it records only line 7).
- Twelve /me templates are thin wrappers that render a common/ template with path-builder lambdas (available_sign_ups x4, mentoring, messages x3, missing_requests x3, schedule x2 plus three schedule partials, timesheet edit/index); their markup is in app/views/common and was not inventoried here.
- Two info icons are used interchangeably: "circle-info" and "info-circle" (dashboard_tasks/_after_event_status_advisory:3,9, announcements/index:14, awards/index:5, vehicles_dashboard/_pvr_status_*); and "triangle-exclamation" vs "exclamation-triangle" (awards/index:12).

### mentoring

- Four shift-picker pages repeat the same markup: alpha_schedule_days loop, h2 "heading-section text-heading mt-6 mb-2", div.two-column-lg of common/mentoring/alpha_shift_card (alpha_schedule/index:19-28, alpha_pods/index:20-33, alpha_signout/index:81-90, shift_report/index:39-48)
- Every pipeline/report page puts guidance in ui_disclosure variant :card class "my-4" titled "How This Page Works" or "About This Report" containing dl.instruction-list (acceptance, alpha_status, post_season, convert_prospectives, shift_report, surveys, alphas_convert, alpha_signout, alpha_pods/show); alpha_mentor_assignments instead uses a visible ui_callout_box :info (99-104)
- Red ui_callout_box :error is used for a non-error "live data" banner on shift_report/index:54 and alpha_signout/index:97; :success callouts announce a scheduled shift (shift_report:59, alpha_signout:102)
- Bulk-action submits stay disabled until a checkbox is checked (data checkbox_select_all_target submit) on acceptance, convert_prospectives, alphas_convert, alpha_signout, alpha_mentor_assignments (also on a button_action), alpha_pods/people/new
- Irreversible bulk actions pair a :warning accent callout stating the consequence with a confirm_modal_dialog on the submit (convert_prospectives:164-177, alphas_convert/_section:75-85, alpha_signout:144-161); delete_button confirm_modal on single removals (alpha_schedule/show:112, _pod_card:93); pod member removal deliberately unconfirmed (people/edit:48)
- Print sheets pin section data-theme="light" so ui_badge colours print light (print_sheets:29, info_sheet:38, alpha_mentor_assignments/print_sheet:21); signup_sheet, apparel and pods print_sheet do not set it (they render no badges)
- HTML strings marked html_safe after interpolating stored data: alpha_mentor_assignments/index.html.erb:213-215 (mentor callsigns), alpha_acceptance_sheets_helper.rb:44-46 (slot description), alpha_mentor_assignments_helper.rb:78
- Hero panels: year_selector on post_season_summary, shift_report, alpha_schedule/index, alpha_pods/index only; back_to inside hero on alpha_schedule/show, alpha_pods/show, shift_report (report mode), alpha_signout (roster mode); print sheets use standalone back_to above the sheet
- Stat rows appear on every screen page except alpha_schedule/index, alpha_pods/index, surveys; tile variants are chosen per count (e.g. :warning when positive else :success) inline in each view
- alpha_pods writes respond with turbo_stream replace of #alpha-pods-board plus ui_toast_stream; refusals toast or render unavailable.html.erb into the modal frame; roster add/remove report through redirect flash (controller), refused sign-up re-renders rosters/_blocked into the modal frame
- mentoring/surveys/trainer.html.erb and report.html.erb are one-line render template delegates to common/surveys; nothing to inventory in this scope
- Census missed the literal ⚑ glyph at alpha_schedule/signup_sheet.html.erb:48 (its html-entity row lists 20,23,33,61,99,109)

### person

- cancel_link is an alias of cancel_button (app/helpers/button_helper.rb:175); the census pattern list has cancel_button but not cancel_link, so the 14 cancel_link calls in app/views/person are not counted. back_to (application_helper.rb:245) is also absent from the census list.
- Seven person-area controllers declare no layout (PersonController, Banners, Callsigns, Fka, Memberships, Passwords, Statuses), so show, banners/*, callsigns/edit, fka/*, memberships/edit, passwords/edit and statuses/edit render in layouts/application while every other person page uses layouts/person.
- Twelve templates are thin wrappers that render a common/ template with locals (available_sign_ups/*, messages/*, mentoring/index, provisions/new+edit, scheduling/index, signup_summary); their UI is inventoried by the common group.
- callsigns/edit.html.erb:22 hides the Release Callsign action below the lg breakpoint ("hidden lg:flex"); there is no alternative control on phones.
- timesheets/index.html.erb:55 comment says the quick-link buttons are mobile-only with an action sidebar on desktop, but the div at 56 has no responsive visibility class.
- tickets_provisions/show.html.erb:21 row of four bordered boxes uses "flex justify-start gap-2" without flex-wrap.
- provisions/_section.html.erb:28 collapses with class "hidden hidden!" (Tailwind important modifier) plus aria-hidden, driven by a toggle controller on a button_action placed in the ui_section link: slot.
- Person::TimesheetsHelper#timesheet_status_icon (60) and #missing_request_status_icon (93) have no callers in app/.
- Person overview has no back link; the hero back slot is "Switch to HQ Interface". Child pages back_to the callsign (person_path), except work_history (back to Timesheet) and edit/history pages (back to their parent list).
- Pages differ in whether the body sits in an untitled ui_section: applications, certifications/index, status_history wrap everything in ui_section with no title; scheduling/log puts its table straight on the page but its empty state in a ui_section.
- membership_history and scheduling/log are the only person pages using ui_table striped: true; site_log and permissions use ui_section border: false.
- pogs/new, pogs/edit, pogs/index, swag/new, swag/edit, missing_requests/show, timesheets/edit, tickets_provisions/show heroes have no description; most other person pages pass one.
- Busy/loading states in scope: only passkeys/new f.submit pending_label; no spinners, skeletons or lazy turbo-frames in app/views/person.
- Validation display: every form goes through ui_form/AppFormBuilder (errors-via-form-builder); no person template renders a form_error_summary or custom error markup. Script-side errors only on passkeys/new (data-passkey-target error callout).

### scheduling

- Every report page sets content_for :title; none of the admin pages do (position_credits/index, position, edit, new, timeline; slots/index, position, edit, new; slot_copies/new; position_credit_copies/new; slot_bulk_edits/new).
- cancel_link is an alias of cancel_button (app/helpers/button_helper.rb:175); the census does not count it: position_credits/_form:41, slot_copies/new:153, slots/_form:70, slot_bulk_edits/new:122, position_credit_copies/new:110.
- dropdown_scroll_list (application_helper.rb:65) is not in the census helper list; its lead-in text is a bare text node with no element at schedule_by_position/index:22 and schedule_by_callsign/index:54.
- ui_disclosure "About This Report" (variant :card, class "my-4") holding dl.instruction-list appears on 13 pages in this scope; shift_signups wraps a partial of dt/dd pairs.
- flake_report/position:94-96 passes an interpolated string marked .html_safe (contains &mdash;) to ui_empty_state; shift_drop_report index:56-58 and position:86-88 build messages by String + concatenation.
- No spinners, skeletons or disabled-while-submitting markup in scope. Busy-free behaviours: auto-submitting selects (shift_lead/_picker, _sort_control) and the link-options turbo-frame swap (slots/_form).
- Two hand-built charts live entirely in area helpers with custom CSS files and inline custom properties: credit timeline (position_credits_helper, credit-chart.css) and HQ Gantt (hq_forecast_helper, hq-forecast.css). Both use daisyUI tooltips for hover detail.
- hq_forecast/shift and hq_forecast/people are opened via data-turbo-frame "modal" links built in hq_forecast_helper:32-37,234-235; the controller renders them with the normal scheduling layout.
- shift_lead roster renders the same data twice (desktop table hidden below lg, phone card list hidden from lg) in _roster:35,92; shift_coverage hides vacant cells below lg and adds a mobile-only line (shift_coverage_helper:21,40).
- event_stats/_share_bar has no strict-locals magic comment and reads caption through local_assigns; most other partials in scope declare `locals:`.
- Colour-word copy: shift_signups/_legend:6-7 explains rows as "red" and "amber".

### shell-auth-profile

- profile/_emergency_contact_denied.html.erb is the only partial in profile/ without a strict-locals magic comment.
- Layout chain: every area layout is five lines (sidebar_menu + render template "layouts/application"); hq and training add args; me/timesheet nests in me; sessions sets content_for :main. Only print, photo_board, bookmark (and the two test fixtures) are standalone documents and each repeats the head (fonts preload, importmap, modulepreload) by hand.
- Toasts render only in layouts/application.html.erb:107-114; print, photo_board and bookmark layouts have no flash/toast output, so a flash set before those pages is not shown there.
- The application shell sets no max-width on <main>; page width limits are per page (register/show:8 max-w-4xl, sessions layout max-w-md, profile pages none).
- No footer exists in any layout.
- sessions/new.html.erb:82 uses class "flex-column", which is not a Tailwind 4 utility (flex-col is) and has no definition in app/assets; not verified against the compiled CSS.
- profile/show.html.erb:62 copy reads "Be alerted when to when new Clubhouse Message are received"; profile/_mailing_address.html.erb:8-9 repeats "update update".
- profile/_alerts.html.erb yes/no icon cells have no text alternative; the state is conveyed by icon shape and colour only.
- crop.html.erb is shared by me, person and vc (photos_review) routes, so its back link and cancel target come from helpers (profile_index_label/path, crop_cancel_deletes?) rather than the view.
- The login pages restyle form builder fields wholesale through replace_class: true plus login.css classes (login-input, login-field, login-submit-button); register/_form on the same signed-out shell uses the builder's default look.
- pwa/manifest.json.erb and service-worker.js are unused scaffolding (manifest link commented out at layouts/application.html.erb:17).

### teams-people

- Every bulk/preview POST page renders a hidden div[data-controller=scroll-to-top] to reset scroll after a 422 render (bulk_teams index:9 preview:5, bulk_positions index:9 preview:5, roster preview:5, sanity _results:6, status_change show:11, bulk_lookup:32).
- bulk_teams_helper.rb and bulk_positions_helper.rb carry identical DIRECTION/VERDICT_BADGES tables, preview titles and outcome text; bulk_teams names unusable callsigns, bulk_positions only counts them.
- Three-arm summary callout (nothing to confirm / problems / no problems) is duplicated verbatim between bulk_teams/preview.html.erb:26-44 and bulk_positions/preview.html.erb:26-44.
- About cards are always ui_disclosure variant :card class "my-4" with dl.instruction-list, across 11 pages in scope; instruction-list is defined in accessibility.css (census files it under boxes.css/cards).
- Drill-down index pages consistently wrap rows in div.lg:w-3/4; table pages (team_records, position_records, lineups) use full-width ui_table with no wrapper; bulk_lookup form uses lg:w-1/2.
- roster_management/show.html.erb builds the only sticky two-row table header by hand; people/search uses the shared TableHelper::PINNED_HEADER_CLASSES with an arbitrary lg:max-h-[70vh] container.
- Destructive confirms use confirm_modal_dialog via turbo_confirm on f.submit (bulk previews, roster preview, status_change show) and delete_button confirm_modal: on record forms.
- people/languages_known/index.html.erb is the only page in scope with client-side live filtering (list-filter controller) and a raw form_with search bar outside filter_bar.
- No spinner, skeleton or lazy turbo-frame appears anywhere in scope; busy state relies on whatever the shared submit helpers provide.

### ticketing-bmid

- Every ticketing report page shares one skeleton: hero_panel (title kwarg) > ui_stat_row > ui_disclosure card "About This Report" class my-4 > area _filter_bar partial (filter_bar + form_row of selects, width w-full, wrapper_class flex-1, f.submit "Apply Filters") > ui_section "table-list" > two ui_empty_state branches (magnifying-glass filtered, circle-check or type icon empty) > ui_table with callsign_link row headers
- No ticketing page has breadcrumbs or tabs; report pages have no back link at all (reached from the ticketing layout's menu); task and result pages use hero_panel back_to. The bmid manage and export pages carry a hero year_selector; titles and sanity check do not
- Results pages rendered at 422 (maintenance/results, unsubmit_provisions/results, trs_export/export, mark_submitted, bmid/export/create, unsubmit, bmid/titles/apply) each start with a hidden div data-controller="scroll-to-top"
- Colour carries status in many places but is paired with an icon or word each time: _pipeline_card chips, _summary_value badges with sr-only status, bmid row accent borders paired with flag icons and sr-only text, sanity tiles switching warning/success with icon change
- ui_disclosure is used both as a page-level card (variant :card, class my-4) and as an in-table-cell expander with summary_class "font-semibold text-heading" (claimed_with_no_signups:113, sap_candidates:89); bmid/export/_buckets builds a rich summary with an embedded ui_badge
- Copy in ticketing/bulk_access_documents/_consequence.html.erb:15 tells the reader "those rows are the amber ones above", naming a colour as the identifier
- bmid/titles/_cell renders select_tag/text_field_tag with AppFormBuilder class constants and aria-label only; the 3 pickers per row have no visible labels beyond the column heading
- bmid/manage/_edit_grid and _table set responsive: false on ui_table (scroll in box); bmid/titles/apply, set and bmid/export/unsubmit do too; sanity_check comments that it relies on the responsive card fold
- Helpers in scope that produce markup: bmid/manage_helper.rb (sort links with hand-written focus ring, provision cell buttons, status/SAP badges, flag icons, row accent classes, modal frame). bmid_helper.rb, tickets_provisions_helper.rb, bmid/export_helper.rb, bmid/sanity_check_helper.rb, bmid/titles_helper.rb, ticketing/*_helper.rb return options, labels, chips or data only
- yes_no_badge and value_or_dash (app/helpers/application_helper.rb:270, :84) are heavily used in scope but live outside it and were not opened

### timesheets-shiftops

- All timesheets/* controllers set layout "timesheets"; shift_operations controllers set layout "shift_operations" except roc_photo_board ("photo_board", and board action renders layout: false)
- Census does not record hero_panel back_to: passed as a keyword (four timesheets detail pages); only the panel.back_to block form in rollcall is counted
- Census does not record dropdown_scroll_list (timesheets_by_callsign/index.html.erb:67), detail_row/detail_row_toggle on ui_table (correction_requests), t.row state:/align: options, or ui_table container_class/caption options
- Stat-box colour is chosen per page with no common rule visible: the same "Credits" box is :success on two detail pages (timesheet_by_position/position.html.erb:25, timesheets_by_callsign/person.html.erb:28) and the same count switches :warning/:secondary or :success/:error depending on page
- The year-scoped filter forms all add hidden_field_tag :year by hand inside filter_bar (correction_requests, early_late_checkins, forced_shift_start, hours_credits, timesheet_by_position, timesheet_totals_report, timesheets_by_callsign)
- Nearly every view carries long explanatory ERB comments; the user-facing explanation is consistently moved into an "About This Report" card disclosure rather than the hero
- cruise_direction/_board.html.erb:33 empty text names a "Create pod" control; the actual button is "Add Pod" (_pickers.html.erb:43) and the dialog title is "Create a Pod" (pods/new.html.erb:5)
- Roll call rows (rollcall/_row.html.erb) are full-width button_to elements styled entirely with utilities and a state map; these are the largest one-off interactive controls in scope
- payroll_export/_person.html.erb comment says row tint needs an important flag, but the code uses t.row state: :warning; bulk_sign_in_out/preview.html.erb:84-88 has the same comment over t.row state: :error

### training

- sessions/index.html.erb sets no content_for :title, unlike every other training page.
- Back links: every report hero uses panel.back_to to "<year> Sessions"; resources/show passes back_to: as a hero_panel option instead of the block (line 4); sessions/index and mentoring/landing have no back link; mentoring subpages go back to "Mentoring"; completed_training/show goes back to "All <year> Sessions".
- Year selector min_year differs by report: 2008 default, 2018 all_notes, 2022 online_course_progress, 2012 surveys; mentees/index and resources have none.
- Stat tiles that are always :warning regardless of count: all_notes "With Notes", trained_no_work and untrained_people "People", multiple_enrollments "Trainees"; others flip variant on count (sessions_helper, mentoring_helper, _stats).
- Print views signup_sheet and trainers_report each embed a near-identical inline <style> @page block with a hard-coded #444 colour and font stack; both share _print_screen_nav for the screen-only back link.
- ui_callout_box :success is used as a neutral information header for a mentoring shift (_roster.html.erb:43, _upcoming.html.erb:7), not to report success.
- Busy states are limited to data turbo_submits_with on the mentoring roster and its dialogs (_roster:265, _pass_dialog:59, _promote_dialog:27); no other training form has a busy label, spinner or skeleton.
- Modal fragments (graduations/show, notes/edit, rosters/new, scores/edit, general_notes/edit, work_histories/show) only wrap a dialog partial in turbo_frame_tag "modal"; whether a frame-specific layout applies was not checked.
- Icons: every icon in scope goes through fa_icon or a helper icon: option except the ✔ glyph in trainers_report; no icon-only controls were found in scope.

### vc

- cancel_link (edit_details.html.erb:51, edit_personal_info.html.erb:43, reserved_handles/_form.html.erb:42, reserved_handles/upload.html.erb:146) is not counted by the census; maintenance previews use cancel_button (preview_pnvs.html.erb:33, preview_past_prospectives.html.erb:34)
- vc_check_link (app/helpers/vc/applications_helper.rb:106) has an icon_only: option that collapses the label to sr-only text with class vc-check-chip; nothing in app/views or app/helpers calls it with icon_only, so the action bar shows labelled chips
- The status dashboard icons in status_dashboard_groups (app/helpers/vc/applications_helper.rb:40-51) are defined but not passed to ui_stat_box at index.html.erb:46
- Dialog forms in applications/dialogs/*.erb post with data turbo_frame "_top" and have no inline error display or error summary in the markup; how failures surface (flash or redirect) is decided in the controller, which was not traced
- Status of a person prints in five ways across scope: application_status_badge (applications), person_status_badge (bpguid/index.html.erb:38), plain text cell (thank_you_cards/index.html.erb:61, shiny_penny_report/index.html.erb:37, maintenance/_results_table.html.erb:32), literal "<status>" in angle brackets (photos_review/_photo.html.erb:11), "(status)" suffix in a link (_banners.html.erb:28, _callsign_stage.html.erb:61, create_prospectives_helper.rb:112)
- The spigot flow table right-aligns column headings (index.html.erb:66 right: true) while cells are centred (center: true at 73,83,85,91)
- Year selector options differ between reports: applications index passes years: @years (6); thank_you_cards min_year: year_floor, skip_pandemic (6); shiny_penny min_year 2010 no skip (4); spigot_flow min_year 2010 skip_pandemic (4)
- Photo review decisions are reflected through turbo streams that replace the card and stats and clear the modal (Vc::PhotosReviewController lines 99-101); errors there go through ui_toast_stream (line 43), the only toast path found for this scope
- app/views/vc/applications/_action_bar.html.erb:36-38 uses a primary button_link as an in-page jump (#stage-key) labelled by next_stage.jump_label, so the primary button on the page scrolls instead of acting

## Census rows dropped as false positives

- `app/views/admin/documents/body.html.erb` navigation `css:lexxy-content`: lexxy-content is a content/typography wrapper for the document body, not navigation (admin)
- `app/helpers/admin/salesforce_query_helper.rb` icons `fa_icon`: detail "class=sr-only" belongs to a sibling tag.span at line 58, not to the fa_icon call at line 48 (admin)
- `app/helpers/admin/action_logs_helper.rb` icons `html-entity-or-glyph`: lines 72,171,214,218,222 are "•"/"·" text separators, not icons (same for jobs_helper.rb:190, permissions_helper.rb:5,10, sms_management_helper.rb:140,149, request_logs/index.html.erb:150, action_logs/_table.html.erb:77, moodle_catalog_courses.html.erb:22) (admin)
- `app/views/admin/rbs_alerts/index.html.erb` icons `html-entity-or-glyph`: line 10 is &mdash; punctuation in prose, not an icon (admin)
- `app/helpers/admin/jobs_helper.rb` modals `confirm_modal`: detail "icon=circle-question" does not appear at line 73-74; the call passes only title, method and message (admin)
- `app/views/common/_checkbox_row.html.erb` forms `class:select`: `select-none` is a Tailwind utility, not the daisyUI select component (common-a)
- `app/views/common/_checkbox_tile.html.erb` forms `class:select`: `select-none` is a Tailwind utility, not the daisyUI select component (common-a)
- `app/views/common/_toast.html.erb` buttons `class:btn`: `btn-toast-close` is a custom class, not daisyUI btn (common-a)
- `app/views/common/_toast.html.erb` toasts-alerts `class:toast`: `toast-progress` is a custom class, not daisyUI toast (common-a)
- `app/views/common/_icon_block.html.erb` typography `<h4>`: line 10 is inside an ERB comment; no heading is rendered (common-a)
- `app/views/common/_dashboard_progress.html.erb` icons `html-entity-or-glyph`: line 14 is `&mdash;` punctuation in title text, not an icon (common-a)
- `app/views/common/_legal_name_fields.html.erb` validation `required-attribute`: lines 4-5 are in the header comment (common-a)
- `app/views/common/_mailing_address_fields.html.erb` validation `required-attribute`: lines 9-10 are in the header comment (common-a)
- `app/views/common/_dashboard_step.html.erb` cards `css:me-muted`: me-muted is a muted text colour, filed under cards (common-a)
- `app/views/common/_trophies.html.erb` cards `css:me-muted`: me-muted is a muted text colour, filed under cards (common-a)
- `app/views/common/surveys/_answers.html.erb` tables-lists `class:list`: `list-none` is a Tailwind utility, not the daisyUI list component (common-a)
- `app/views/common/ticketing_maintenance/_results_table.html.erb` icons `html-entity-or-glyph`: line 6 `→` is in a header comment (common-a)
- `app/views/common/messages/_pane.html.erb` toasts-alerts `flash-read-in-view`: `notice` is a partial local (MessagesConcern#refuse_message), not the flash (common-a)
- `app/views/common/resource_documents/_document.html.erb` navigation `css:lexxy-content`: lexxy-content styles rich-text body content; not navigation (common-a)
- `app/views/common/_hours_not_eligible.html.erb` other `tooltip-or-title-attribute`: title: is the callout's heading, not a tooltip (common-a)
- `app/views/common/assets/_change_attachment_modal.html.erb` other `tooltip-or-title-attribute`: title: is the modal_dialog heading (common-a)
- `app/views/common/assets/_expired_modal.html.erb` other `tooltip-or-title-attribute`: title: is the modal_dialog / callout heading (common-a)
- `app/views/common/assets/_radio_agreement_warning.html.erb` other `tooltip-or-title-attribute`: title: is the callout heading (common-a)
- `app/views/common/bmids/_warnings.html.erb` other `tooltip-or-title-attribute`: title: is the callout heading (common-a)
- `app/views/common/bulk_upload/preview.html.erb` other `tooltip-or-title-attribute`: title: is the confirm_modal_dialog heading (common-a)
- `app/views/common/mail_log/body.html.erb` other `tooltip-or-title-attribute`: title= on the iframe is its accessible name, not a tooltip (common-a)
- `app/views/common/messages/_find_recipient.html.erb` other `tooltip-or-title-attribute`: title: is the modal_dialog heading (common-a)
- `app/views/common/messages/index.html.erb` other `tooltip-or-title-attribute`: title: is the hero_panel heading (common-a)
- `app/views/common/messages/new.html.erb` other `tooltip-or-title-attribute`: title: is the hero_panel heading (common-a)
- `app/views/common/messages/show.html.erb` other `tooltip-or-title-attribute`: title: is the hero_panel heading (common-a)
- `app/views/common/missing_requests/index.html.erb` other `tooltip-or-title-attribute`: title: is the hero_panel heading (common-a)
- `app/views/common/missing_requests/new.html.erb` other `tooltip-or-title-attribute`: title: is the hero_panel heading (common-a)
- `app/views/common/missing_requests/edit.html.erb` other `tooltip-or-title-attribute`: title: is the hero_panel heading (common-a)
- `app/views/common/provisions/_form.html.erb` other `tooltip-or-title-attribute`: title: is the confirm_modal heading (common-a)
- `app/views/common/resource_documents/_document.html.erb` other `tooltip-or-title-attribute`: title: is the callout heading (common-a)
- `app/views/common/resource_documents/_form.html.erb` other `tooltip-or-title-attribute`: title: is the confirm_modal heading (common-a)
- `app/views/common/unified_flagging/index.html.erb` other `tooltip-or-title-attribute`: title: is the hero_panel heading (common-a)
- `app/helpers/unified_flagging_helper.rb` other `tooltip-or-title-attribute`: lines 15-17 are `title:` keys in the GROUP_META constant hash (common-a)
- `app/views/common/messages/index.html.erb` icons `html-entity-or-glyph`: `&mdash;` in the title text, not an icon (common-a)
- `app/views/common/messages/show.html.erb` icons `html-entity-or-glyph`: `&mdash;` in the title text, not an icon (common-a)
- `app/views/common/provisions/edit.html.erb` icons `html-entity-or-glyph`: `&mdash;` in the title text, not an icon (common-a)
- `app/views/common/provisions/new.html.erb` icons `html-entity-or-glyph`: `&mdash;` in the title text, not an icon (common-a)
- `app/views/common/provisions/_form.html.erb` icons `html-entity-or-glyph`: line 78 `&middot;` is a text separator, not an icon (common-a)
- `app/views/common/surveys/report.html.erb` icons `html-entity-or-glyph`: `&mdash;` in description text, not an icon (common-a)
- `app/views/common/surveys/trainer.html.erb` icons `html-entity-or-glyph`: `&mdash;` in description text, not an icon (common-a)
- `app/views/common/surveys/_session_label.html.erb` icons `html-entity-or-glyph`: `·` is a text separator, not an icon (common-a)
- `app/views/common/schedule/_signed_up_row.html.erb` cards `class:card`: Line 6 class is "card-standard", an @utility in components/cards.css, not the daisyUI card component (common-b)
- `app/views/common/available_sign_ups/show.html.erb` navigation `css:lexxy-content`: lexxy-content is the rich-text content style (components/lexxy.css); bookmark.css only scopes it under .bookmark-page, it is not navigation (common-b)
- `app/views/common/available_sign_ups/show.html.erb` other `tooltip-or-title-attribute`: Lines 3,22,33,42 are title: keyword arguments to hero_panel/ui_callout_box (visible headings), not title attributes or tooltips; same for schedule/_export_warning.html.erb:2,13 and available_sign_ups/_slot.html.erb:122 (confirm_modal title) (common-b)
- `app/views/common/qualifications/_track.html.erb` other `class:progress`: Line 17 token is "progress-projected" passed as bar_class, a custom class in components/progress.css, not the daisyUI progress class (common-b)
- `app/views/alerts/_alert_group.html.erb` forms `class:select`: Lines 57,75,94 match the utility "select-none" on label spans, not the daisyUI select class (communication)
- `app/views/alerts/_alert_group.html.erb` cards `class:card`: Line 8 is "card-standard", an @utility in components/cards.css, not the daisyUI card class (communication)
- `app/views/bug_reports/new.html.erb` modals `modal`: Line 3 is inside an ERB comment ("dialog puts focus..."), no modal call (communication)
- `app/views/bookmarks/_document.html.erb` navigation `css:lexxy-content`: lexxy-content is rich-text content styling, not navigation; the same misfiling appears for communication/announcements/_announcement.html.erb:43 and communication/surveys/show.html.erb:45,51 (communication)
- `app/views/bookmarks/_document.html.erb` cards `css:me-muted`: me-muted is a muted text colour class (hero-panel.css), not a card (communication)
- `app/views/bookmarks/document.html.erb` empty-loading `turbo_frame_tag`: The frame is the timed-refresh target, not a loading or empty state (same for bookmarks/show.html.erb:19) (communication)
- `app/views/alerts/edit.html.erb` other `tooltip-or-title-attribute`: Lines 20,91,119,149 are ui_callout_box title: arguments, not title attributes; the same false positive covers every title: kwarg on hero_panel/modal_dialog/confirm_modal in this scope (e.g. bug_reports/new 11,20,35; rbs_helper 11-61 are hash keys; surveys_helper 100) (communication)
- `app/helpers/mail_log_helper.rb` other `tooltip-or-title-attribute`: Line 5 is a comment mentioning a tooltip (communication)
- `app/helpers/mailer_helper.rb` typography `date-format-call`: Line 9 is asset_url for the logo, not a date format call (communication)
- `app/views/alerts/edit.html.erb` cards `css:instruction-list`: instruction-list is defined in accessibility.css (census attributes it to boxes.css) and is a Q/A definition list, not a card; same for every instruction-list row in this scope (communication)
- `app/helpers/asset_management/radio_checkout_helper.rb` links `<a>`: Line 11 is a Ruby comment ("every <a> on the page"), not markup (hq-assets)
- `app/helpers/hq_helper.rb` modals `modal`: Line 14 is a comment mentioning "modal"; no modal call (hq-assets)
- `app/views/hq/shared/_summary_column.html.erb` modals `modal`: Line 3 is in the ERB comment; the file renders a button_link into the modal frame, no modal helper (hq-assets)
- `app/views/hq/shared/_warning_modals.html.erb` modals `modal`: Lines 2 and 4 are in the ERB comment; real calls are 10,19,34 only (hq-assets)
- `app/views/hq/tickets_provisions/show.html.erb` modals `modal`: Line 2 is in the ERB comment; real call is line 7 (hq-assets)
- `app/views/hq/tickets_provisions/show.html.erb` empty-loading `spinner-icon`: Line 5 is the word "spinner" in the comment; the real hand-rolled spinner (animate-spin div) is line 14 and is not recorded as such (hq-assets)
- `app/views/hq/site_registration/show.html.erb` modals `<dialog>`: Line 3 is in the ERB comment; only line 70 is a real <dialog> (hq-assets)
- `app/views/hq/shared/_shell.html.erb` other `class:stack`: "stack-to-row-lg" is a custom layout class, not daisyUI stack (hq-assets)
- `app/views/hq/shared/_provision_info.html.erb` icons `html-entity-or-glyph`: Line 30 &mdash; is punctuation, not an icon (hq-assets)
- `app/views/hq/shift_manage/_pog_guidelines.html.erb` icons `html-entity-or-glyph`: Lines 12,48,60 are &mdash;/&rsquo; punctuation (hq-assets)
- `app/views/hq/shift_manage/_pog_cancel_modal.html.erb` icons `html-entity-or-glyph`: Line 12 &mdash; punctuation (hq-assets)
- `app/views/hq/site_registration/_radio_authorization_status.html.erb` icons `html-entity-or-glyph`: Lines 15,31 &mdash; punctuation (hq-assets)
- `app/views/hq/site_registration/show.html.erb` icons `html-entity-or-glyph`: Line 32 &mdash; punctuation (hq-assets)
- `app/views/hq/tickets_provisions/_row.html.erb` icons `html-entity-or-glyph`: Line 11 &mdash; punctuation (hq-assets)
- `app/views/quartermaster/swag_distribution/index.html.erb` icons `html-entity-or-glyph`: Line 11 &mdash; punctuation (hq-assets)
- `app/helpers/vehicles/registry_helper.rb` icons `html-entity-or-glyph`: Line 105 " · " is a text separator, not an icon (hq-assets)
- `app/views/hq/site_registration/show.html.erb` other `tooltip-or-title-attribute`: Lines 12,101 are ui_callout_box title: arguments (visible headings), not title attributes (hq-assets)
- `app/views/hq/tickets_provisions/progress.html.erb` other `tooltip-or-title-attribute`: Lines 12,19,26,35,52 are ui_callout_box title: and partial locals title:, not tooltips (hq-assets)
- `app/views/hq/shift_manage/index.html.erb` other `tooltip-or-title-attribute`: Lines 34,111,124,151 are ui_callout_box/section locals/confirm_modal title: arguments (hq-assets)
- `app/views/hq/shift_manage/_pogs.html.erb` other `tooltip-or-title-attribute`: Lines 29,103 are ui_callout_box and confirm_modal title: arguments (hq-assets)
- `app/views/hq/shift_manage/_assets_section.html.erb` other `tooltip-or-title-attribute`: Lines 10,18 are section local and ui_callout_box title: (hq-assets)
- `app/views/hq/shift_manage/_verification.html.erb` other `tooltip-or-title-attribute`: Line 14 ui_callout_box title: (hq-assets)
- `app/views/hq/shift_manage/_correction_modal.html.erb` other `tooltip-or-title-attribute`: Line 7 modal_dialog title: (hq-assets)
- `app/views/hq/shift_manage/_missing_request_modal.html.erb` other `tooltip-or-title-attribute`: Line 5 modal_dialog title: (hq-assets)
- `app/views/hq/shift_manage/_pog_cancel_modal.html.erb` other `tooltip-or-title-attribute`: Line 5 modal_dialog title: (hq-assets)
- `app/views/hq/shift_manage/_pog_edit_modal.html.erb` other `tooltip-or-title-attribute`: Line 4 modal_dialog title: (hq-assets)
- `app/views/hq/shift_manage/_pog_issue_modal.html.erb` other `tooltip-or-title-attribute`: Line 5 modal_dialog title: (hq-assets)
- `app/views/hq/shared/_danger_notices.html.erb` other `tooltip-or-title-attribute`: Lines 6,20 ui_callout_box title: (hq-assets)
- `app/views/hq/site_registration/_emergency_contact_step.html.erb` other `tooltip-or-title-attribute`: Line 30 ui_callout_box title: (hq-assets)
- `app/views/hq/assets/index.html.erb` other `tooltip-or-title-attribute`: Line 6 hero_panel title: (hq-assets)
- `app/views/hq/training/index.html.erb` other `tooltip-or-title-attribute`: Line 16 ui_callout_box title: (hq-assets)
- `app/views/asset_management/asset_history/index.html.erb` other `tooltip-or-title-attribute`: Line 10 hero_panel title: (hq-assets)
- `app/views/asset_management/assets_outstanding/index.html.erb` other `tooltip-or-title-attribute`: Line 10 hero_panel title: (hq-assets)
- `app/views/asset_management/radio_assets/index.html.erb` other `tooltip-or-title-attribute`: Line 9 hero_panel title: (hq-assets)
- `app/views/asset_management/radio_checkout/index.html.erb` other `tooltip-or-title-attribute`: Line 13 hero_panel title: (hq-assets)
- `app/views/asset_management/records/_form.html.erb` other `tooltip-or-title-attribute`: Line 101 confirm_modal title: (hq-assets)
- `app/views/asset_management/records/edit.html.erb` other `tooltip-or-title-attribute`: Line 2 hero_panel title: (hq-assets)
- `app/views/asset_management/records/index.html.erb` other `tooltip-or-title-attribute`: Line 2 hero_panel title: (hq-assets)
- `app/views/asset_management/records/new.html.erb` other `tooltip-or-title-attribute`: Line 2 hero_panel title: (hq-assets)
- `app/views/asset_management/records/show.html.erb` other `tooltip-or-title-attribute`: Lines 2,13,43 hero_panel / confirm_modal / ui_callout_box title: (hq-assets)
- `app/views/asset_management/records/type.html.erb` other `tooltip-or-title-attribute`: Line 2 hero_panel title: (hq-assets)
- `app/views/asset_management/search/index.html.erb` other `tooltip-or-title-attribute`: Lines 9,56,74 hero_panel / ui_callout_box title: (hq-assets)
- `app/helpers/pogs/administration_helper.rb` other `tooltip-or-title-attribute`: Line 43 confirm-modal hash title: (hq-assets)
- `app/views/pogs/administration/edit.html.erb` other `tooltip-or-title-attribute`: Line 5 hero_panel title: (hq-assets)
- `app/views/pogs/administration/index.html.erb` other `tooltip-or-title-attribute`: Line 12 hero_panel title: (hq-assets)
- `app/views/pogs/dashboard/index.html.erb` other `tooltip-or-title-attribute`: Lines 9,127,129 hero_panel title: and _top_list partial local title: (hq-assets)
- `app/views/quartermaster/alpha_shirts/index.html.erb` other `tooltip-or-title-attribute`: Line 9 hero_panel title: (hq-assets)
- `app/views/quartermaster/events_rangered/index.html.erb` other `tooltip-or-title-attribute`: Line 10 hero_panel title: (hq-assets)
- `app/views/quartermaster/freaking_years/index.html.erb` other `tooltip-or-title-attribute`: Line 9 hero_panel title: (hq-assets)
- `app/views/quartermaster/potential_shirts/index.html.erb` other `tooltip-or-title-attribute`: Line 12 hero_panel title: (hq-assets)
- `app/views/quartermaster/potential_swag/index.html.erb` other `tooltip-or-title-attribute`: Line 11 hero_panel title: (hq-assets)
- `app/views/quartermaster/swag/_form.html.erb` other `tooltip-or-title-attribute`: Line 47 confirm_modal title: (hq-assets)
- `app/views/quartermaster/swag/index.html.erb` other `tooltip-or-title-attribute`: Line 1 hero_panel title: (hq-assets)
- `app/views/quartermaster/swag_distribution/index.html.erb` other `tooltip-or-title-attribute`: Line 9 hero_panel title: (hq-assets)
- `app/views/vehicles/paperwork/index.html.erb` other `tooltip-or-title-attribute`: Line 7 hero_panel title: (hq-assets)
- `app/views/vehicles/registry/_form.html.erb` other `tooltip-or-title-attribute`: Lines 78,81,83,87,89 are eligibility_list partial locals title:, 138 confirm_modal title: (hq-assets)
- `app/views/vehicles/registry/edit.html.erb` other `tooltip-or-title-attribute`: Line 2 hero_panel title: (hq-assets)
- `app/views/vehicles/registry/index.html.erb` other `tooltip-or-title-attribute`: Line 5 hero_panel title: (hq-assets)
- `app/views/vehicles/registry/new.html.erb` other `tooltip-or-title-attribute`: Line 2 hero_panel title: (hq-assets)
- `app/views/vehicles/registry/permit.html.erb` other `tooltip-or-title-attribute`: Line 4 hero_panel title: (hq-assets)
- `app/views/dashboard_tasks/_after_event_status_advisory.html.erb` tables-lists `class:list`: list-numbered is a custom @utility (app/assets/stylesheets/components/lists.css:11 area), not daisyUI's list component (me)
- `app/views/dashboard_tasks/_attend_alpha_shift_pending.html.erb` tables-lists `class:list`: list-bulleted is a custom @utility in components/lists.css, not daisyUI list (me)
- `app/views/dashboard_tasks/_attend_training_no_show.html.erb` tables-lists `class:list`: list-bulleted custom @utility, not daisyUI list (me)
- `app/views/dashboard_tasks/_dashboard_tickets.html.erb` tables-lists `class:list`: list-bulleted custom @utility, not daisyUI list (me)
- `app/views/dashboard_tasks/_green_dot_mentee_shift_needed.html.erb` tables-lists `class:list`: list-numbered custom @utility, not daisyUI list (me)
- `app/views/dashboard_tasks/_missing_bpguid.html.erb` tables-lists `class:list`: list-numbered custom @utility, not daisyUI list (me)
- `app/views/dashboard_tasks/_sign_motor_pool_protocol_needed.html.erb` tables-lists `class:list`: list-bulleted custom @utility, not daisyUI list (me)
- `app/views/dashboard_tasks/_take_student_survey.html.erb` tables-lists `class:list`: list-bulleted custom @utility, not daisyUI list (me)
- `app/views/dashboard_tasks/_trainer_survey.html.erb` tables-lists `class:list`: list-bulleted custom @utility, not daisyUI list (me)
- `app/views/dashboard_tasks/_upload_photo_rejected.html.erb` tables-lists `class:list`: list-bulleted custom @utility, not daisyUI list (me)
- `app/views/dashboard_tasks/_verify_personal_info.html.erb` tables-lists `class:list`: list-numbered custom @utility, not daisyUI list (me)
- `app/views/me/awards/index.html.erb` tables-lists `class:list`: list-bulleted custom @utility, not daisyUI list (me)
- `app/views/me/operational_summary/_teams_and_positions.html.erb` tables-lists `class:list`: list-bulleted custom @utility, not daisyUI list (me)
- `app/views/me/tickets/_announce.html.erb` tables-lists `class:list`: list-bulleted custom @utility, not daisyUI list (me)
- `app/views/me/tickets/_closed.html.erb` tables-lists `class:list`: list-bulleted / list-numbered custom @utility, not daisyUI list (me)
- `app/views/me/tickets/_landing.html.erb` tables-lists `class:list`: list-bulleted / list-numbered custom @utility, not daisyUI list (me)
- `app/views/me/tickets/_off_season.html.erb` tables-lists `class:list`: list-bulleted custom @utility, not daisyUI list (me)
- `app/views/me/vehicles_dashboard/_eligible_positions.html.erb` tables-lists `class:list`: list-bulleted custom @utility, not daisyUI list (me)
- `app/views/me/dashboard/_announcements_section.html.erb` cards `class:card`: card-standard is a custom @utility (components/cards.css:24), not the daisyUI card class (me)
- `app/views/me/vehicles_dashboard/_pvr_requests.html.erb` cards `class:card`: card-standard is a custom @utility (components/cards.css:24), not the daisyUI card class (me)
- `app/views/me/vehicles_dashboard/index.html.erb` other `class:stack`: stack-to-row-lg is a custom @utility (components/layout-patterns.css:14), not daisyUI stack (me)
- `app/views/me/agreements/show.html.erb` navigation `css:lexxy-content`: lexxy-content styles rich-text body content; it is not navigation (me)
- `app/views/me/announcements/_announcement.html.erb` navigation `css:lexxy-content`: rich-text content styling, not navigation (me)
- `app/views/me/dashboard/_dashboard_document.html.erb` navigation `css:lexxy-content`: rich-text content styling (body_class of ui_section), not navigation (me)
- `app/views/me/surveys/show.html.erb` navigation `css:lexxy-content`: rich-text content styling for prologue/epilogue, not navigation (me)
- `app/views/me/team_documents/show.html.erb` navigation `css:lexxy-content`: rich-text content styling, not navigation (me)
- `app/views/me/agreements/index.html.erb` cards `css:me-muted`: me-muted is a text colour class, not a card (me)
- `app/views/me/vehicles_dashboard/_pvr_requests.html.erb` cards `css:me-muted`: me-muted is a text colour class on labels/meta text, not a card (me)
- `app/views/me/vehicles_dashboard/_pvr_status_agreement_needed.html.erb` cards `css:me-muted`: me-muted is a text colour class on p, not a card (me)
- `app/views/me/vehicles_dashboard/index.html.erb` cards `css:me-muted`: me-muted is a text colour class on p, not a card (me)
- `app/views/me/announcements/_unread_count.html.erb` empty-loading `turbo_frame_tag`: The frame is a stream replace target for the unread badge, not a loading or lazy frame (me)
- `app/views/me/awards/index.html.erb` other `tooltip-or-title-attribute`: title: here is the hero_panel/ui_callout_box/render-locals heading argument, not a tooltip (me)
- `app/views/me/dashboard/_dashboard_past_prospective.html.erb` other `tooltip-or-title-attribute`: title: argument of ui_callout_box, not a tooltip (me)
- `app/views/me/dashboard/_onboarding.html.erb` other `tooltip-or-title-attribute`: data-title attributes are tour step headings for the onboarding controller, not tooltips (me)
- `app/views/me/dashboard/index.html.erb` other `tooltip-or-title-attribute`: title: arguments to hero_panel and _dashboard_document locals, not tooltips (me)
- `app/views/me/event_info.html.erb` other `tooltip-or-title-attribute`: hero_panel title: argument, not a tooltip (me)
- `app/views/me/online_course/index.html.erb` other `tooltip-or-title-attribute`: hero_panel title: argument, not a tooltip (me)
- `app/views/me/passkeys/index.html.erb` other `tooltip-or-title-attribute`: hero_panel title: argument, not a tooltip (me)
- `app/views/me/passkeys/new.html.erb` other `tooltip-or-title-attribute`: hero_panel / ui_callout_box title: arguments, not tooltips (me)
- `app/views/me/password/edit.html.erb` other `tooltip-or-title-attribute`: hero_panel title: argument, not a tooltip (me)
- `app/views/me/personal_vehicles/edit.html.erb` other `tooltip-or-title-attribute`: hero_panel title: argument, not a tooltip (me)
- `app/views/me/personal_vehicles/new.html.erb` other `tooltip-or-title-attribute`: hero_panel title: argument, not a tooltip (me)
- `app/views/me/surveys/show.html.erb` other `tooltip-or-title-attribute`: hero_panel title: argument, not a tooltip (me)
- `app/views/me/tickets/_announce.html.erb` other `tooltip-or-title-attribute`: ui_callout_box title: arguments, not tooltips (me)
- `app/views/me/tickets/_claimed_overview.html.erb` other `tooltip-or-title-attribute`: title: locals passed to _ticket_overview_item, not tooltips (me)
- `app/views/me/tickets/_closed.html.erb` other `tooltip-or-title-attribute`: ui_callout_box title: arguments, not tooltips (me)
- `app/views/me/tickets/_contact_ticketing.html.erb` other `tooltip-or-title-attribute`: ui_callout_box title: argument, not a tooltip (me)
- `app/views/me/tickets/_faqs_section.html.erb` other `tooltip-or-title-attribute`: ui_callout_box title: argument, not a tooltip (me)
- `app/views/me/tickets/_landing.html.erb` other `tooltip-or-title-attribute`: title: keys in the section_meta hash and ui_callout_box titles, not tooltips (me)
- `app/views/me/tickets/_off_season.html.erb` other `tooltip-or-title-attribute`: ui_callout_box title: arguments, not tooltips (me)
- `app/views/me/tickets/gift.html.erb` other `tooltip-or-title-attribute`: hero_panel / ui_callout_box title: arguments, not tooltips (me)
- `app/views/me/tickets/provisions.html.erb` other `tooltip-or-title-attribute`: hero_panel / ui_callout_box title: arguments, not tooltips (me)
- `app/views/me/tickets/review.html.erb` other `tooltip-or-title-attribute`: hero_panel / ui_callout_box title: arguments, not tooltips (me)
- `app/views/me/tickets/sap.html.erb` other `tooltip-or-title-attribute`: hero_panel title and _section_header title: locals, not tooltips (me)
- `app/views/me/tickets/sap_so.html.erb` other `tooltip-or-title-attribute`: hero_panel / ui_callout_box title: arguments, not tooltips (me)
- `app/views/me/tickets/ticket.html.erb` other `tooltip-or-title-attribute`: hero_panel / ui_callout_box title: arguments, not tooltips (me)
- `app/views/me/tickets/vehicle_pass.html.erb` other `tooltip-or-title-attribute`: hero_panel / ui_callout_box title: arguments, not tooltips (me)
- `app/views/me/timesheet/final_confirmation.html.erb` other `tooltip-or-title-attribute`: hero_panel title: argument, not a tooltip (me)
- `app/views/me/vehicles_dashboard/_eligible_positions.html.erb` other `tooltip-or-title-attribute`: ui_callout_box title: argument, not a tooltip (me)
- `app/views/me/vehicles_dashboard/_pvr_status_agreement_needed.html.erb` other `tooltip-or-title-attribute`: ui_callout_box title: argument, not a tooltip (me)
- `app/views/me/vehicles_dashboard/_pvr_status_ineligible.html.erb` other `tooltip-or-title-attribute`: ui_callout_box title: argument, not a tooltip (me)
- `app/views/me/vehicles_dashboard/_pvr_status_potential.html.erb` other `tooltip-or-title-attribute`: ui_callout_box title: argument, not a tooltip (me)
- `app/views/me/vehicles_dashboard/index.html.erb` other `tooltip-or-title-attribute`: hero_panel title: argument, not a tooltip (me)
- `app/views/me/vehicles_dashboard/mvr_submit.html.erb` other `tooltip-or-title-attribute`: hero_panel title: argument, not a tooltip (me)
- `app/views/me/work_history/index.html.erb` other `tooltip-or-title-attribute`: hero_panel title: argument, not a tooltip (me)
- `app/views/mentoring/alpha_mentor_assignments/index.html.erb` other `tooltip-or-title-attribute`: Lines 9,33,41,50,57,88 are title: arguments of hero_panel/ui_callout_box, not tooltip/title attributes (mentoring)
- `app/views/mentoring/alpha_acceptance_sheets/index.html.erb` other `tooltip-or-title-attribute`: Line 9 is hero_panel title: (mentoring)
- `app/views/mentoring/alpha_status/index.html.erb` other `tooltip-or-title-attribute`: Line 9 is hero_panel title: (mentoring)
- `app/views/mentoring/post_season_summary/index.html.erb` other `tooltip-or-title-attribute`: Line 10 is hero_panel title: (mentoring)
- `app/views/mentoring/potential_alphas/index.html.erb` other `tooltip-or-title-attribute`: Line 9 is hero_panel title: (mentoring)
- `app/views/mentoring/convert_prospectives/index.html.erb` other `tooltip-or-title-attribute`: Lines 14,174 are hero_panel title: and confirm_modal_dialog title: (mentoring)
- `app/views/mentoring/alphas_convert/index.html.erb` other `tooltip-or-title-attribute`: Lines 13,85,102 are hero_panel title: and confirm hash title: (mentoring)
- `app/views/mentoring/alpha_signout/index.html.erb` other `tooltip-or-title-attribute`: Lines 15,158 are hero_panel title: and confirm_modal_dialog title: (mentoring)
- `app/views/mentoring/shift_report/index.html.erb` other `tooltip-or-title-attribute`: Line 10 is hero_panel title: (mentoring)
- `app/views/mentoring/surveys/index.html.erb` other `tooltip-or-title-attribute`: Line 9 is hero_panel title: (mentoring)
- `app/views/mentoring/alpha_schedule/index.html.erb` other `tooltip-or-title-attribute`: Line 8 is hero_panel title: (mentoring)
- `app/views/mentoring/alpha_schedule/show.html.erb` other `tooltip-or-title-attribute`: Line 115 is delete_button confirm_modal title: (mentoring)
- `app/views/mentoring/alpha_schedule/no_alphas.html.erb` other `tooltip-or-title-attribute`: Line 4 is modal_dialog title: (mentoring)
- `app/views/mentoring/alpha_schedule/rosters/_dialog.html.erb` other `tooltip-or-title-attribute`: Line 6 is modal_dialog title: (mentoring)
- `app/views/mentoring/alpha_schedule/rosters/_blocked.html.erb` other `tooltip-or-title-attribute`: Line 5 is modal_dialog title: (mentoring)
- `app/views/mentoring/alpha_pods/index.html.erb` other `tooltip-or-title-attribute`: Line 8 is hero_panel title: (mentoring)
- `app/views/mentoring/alpha_pods/show.html.erb` other `tooltip-or-title-attribute`: Line 10 is hero_panel title: (mentoring)
- `app/views/mentoring/alpha_pods/_pod_card.html.erb` other `tooltip-or-title-attribute`: Line 96 is confirm_modal title: (mentoring)
- `app/views/mentoring/alpha_pods/unavailable.html.erb` other `tooltip-or-title-attribute`: Line 9 is modal_dialog title: (mentoring)
- `app/views/mentoring/alpha_pods/people/edit.html.erb` other `tooltip-or-title-attribute`: Line 11 is modal_dialog title: (mentoring)
- `app/views/mentoring/alpha_pods/people/new.html.erb` other `tooltip-or-title-attribute`: Lines 13,34 are modal_dialog title: and a render title: local (mentoring)
- `app/helpers/mentoring/alpha_status_helper.rb` other `tooltip-or-title-attribute`: title: keys in the SECTIONS/WAITING_SUBGROUPS constants (section headings), not attributes (mentoring)
- `app/helpers/mentoring/post_season_summary_helper.rb` other `tooltip-or-title-attribute`: Lines 23,25 are SECTIONS title: keys (mentoring)
- `app/helpers/mentoring/potential_alphas_helper.rb` other `tooltip-or-title-attribute`: Lines 18,26 are COHORTS title: keys (mentoring)
- `app/helpers/mentoring/alpha_pods_helper.rb` other `tooltip-or-title-attribute`: Line 25 is a code comment mentioning a tooltip (mentoring)
- `app/helpers/mentoring/alpha_signout_helper.rb` other `tooltip-or-title-attribute`: Line 24 is a code comment mentioning a tooltip (mentoring)
- `app/views/mentoring/alpha_schedule/info_sheet.html.erb` modals `modal`: Line 9 is the word "modal" in an ERB comment; the page has no modal (mentoring)
- `app/views/mentoring/alpha_signout/_on_duty_table.html.erb` modals `modal`: Line 57 is the word "modal" in an ERB comment (mentoring)
- `app/views/mentoring/alpha_pods/people/new.html.erb` modals `modal`: Line 16 is "modal frame" in an ERB comment (the real dialog is the modal_dialog row) (mentoring)
- `app/helpers/mentor_helper.rb` typography `hero_panel`: Line 67 is a comment; the helper does not call hero_panel (mentoring)
- `app/helpers/mentoring/alpha_mentor_assignments_helper.rb` forms `f.select`: Line 45 is a comment ("rendered for f.select") (mentoring)
- `app/helpers/mentoring/post_season_summary_helper.rb` forms `f.select`: Line 86 is a comment (mentoring)
- `app/views/mentoring/alpha_mentor_assignments/index.html.erb` forms `select_tag`: Line 242 of the 172,242,249,258 list is inside an ERB comment; only 172,249,258 are calls (mentoring)
- `app/views/person/_contact_details.html.erb` icons `<i>`: The two <i> tags (9,26) are italic "None" text, not icons (person)
- `app/views/person/_summary_strip.html.erb` icons `<i>`: The five <i> tags (25,51,62,72,94) are italic "None" placeholders, not icons (person)
- `app/views/person/_timestamp_value.html.erb` icons `<i>`: <i> at 8 is italic placeholder text, not an icon (person)
- `app/views/person/certifications/show.html.erb` icons `<i>`: <i> at 27 is italic "— imported —" text, not an icon (person)
- `app/views/person/memberships/_team_card.html.erb` cards `class:card`: Token is "card-standard", an @utility in components/cards.css, not the daisyUI card class (person)
- `app/views/person/memberships/edit.html.erb` cards `class:card`: Token is "card-standard" (custom @utility), not daisyUI card (person)
- `app/views/person/memberships/_position_checkbox.html.erb` navigation `class:menu`: Token is "menu-title" on an li inside a dropdown_menu block, not a standalone menu (person)
- `app/views/person/memberships/_team_card.html.erb` navigation `class:menu`: Token is "menu-title" inside dropdown_menu, not a standalone menu (person)
- `app/views/person/passkeys/new.html.erb` tables-lists `class:list`: Token is the custom "list-bulleted" class, not daisyUI list (person)
- `app/views/person/access_documents/edit.html.erb` icons `html-entity-or-glyph`: &mdash; separator in a hero title (punctuation, not an icon); the same holds for every hero-title &mdash; row in app/views/person/** (about 40 files: access_documents/new, history; awards/edit, new; banners/*; bmids/show:15; callsigns/edit; certifications/*; dashboard/show; external_ids/show; fka/*; missing_requests/*; passkeys/*; passwords/edit; pogs/*; sessions/index:4; site_log; status_history; statuses/edit; swag/*; tickets_provisions/*; timesheets/* line 4-7; training/index; vehicles/index) (person)
- `app/views/person/provisions/_section.html.erb` icons `html-entity-or-glyph`: &middot; at 21,23 is a text separator, not an icon (same for access_documents/_form:69, bmids/show:57, memberships/edit:12-15) (person)
- `app/helpers/person/email_suppression_helper.rb` buttons `button_link`: Detail "variant=:error" belongs to the confirm_modal_dialog argument; the button_link itself is :secondary (person)
- `app/views/person/awards/index.html.erb` buttons `button_link`: Detail "method=:post" is a confirm_modal argument, not a button_link option (same misattribution in timesheets/_entries_table:53 and missing_requests/edit:146 method=:delete) (person)
- `app/helpers/scheduling/shift_coverage_helper.rb` tables-lists `class:table`: `lg:table-cell` at line 21 is the Tailwind display utility, not the daisyUI table class. (scheduling)
- `app/views/scheduling/slots/_form.html.erb` empty-loading `turbo_frame_tag`: Frame at line 41 is a swap target for link options with no src/lazy load; not a loading state. (scheduling)
- `app/views/scheduling/slots/link_options.html.erb` empty-loading `turbo_frame_tag`: Response wrapper for the frame swap; not a loading state. (scheduling)
- `app/views/scheduling/early_arrivals/index.html.erb` tables-lists `ui_stat_row`: ui_stat_row is a row of stat tiles, not a table or list. (scheduling)
- `app/views/scheduling/event_stats/index.html.erb` tables-lists `ui_stat_row`: Stat tile row, not a table or list. (scheduling)
- `app/views/scheduling/flake_report/position.html.erb` tables-lists `ui_stat_row`: Stat tile row, not a table or list. (scheduling)
- `app/views/scheduling/hq_forecast/index.html.erb` tables-lists `ui_stat_row`: Stat tile row, not a table or list. (scheduling)
- `app/views/scheduling/no_shows_report/position.html.erb` tables-lists `ui_stat_row`: Stat tile row, not a table or list. (scheduling)
- `app/views/scheduling/position_credits/position.html.erb` tables-lists `ui_stat_row`: Stat tile row, not a table or list. (scheduling)
- `app/views/scheduling/position_credits/timeline.html.erb` tables-lists `ui_stat_row`: Stat tile row, not a table or list. (scheduling)
- `app/views/scheduling/schedule_by_callsign/person.html.erb` tables-lists `ui_stat_row`: Stat tile row, not a table or list. (scheduling)
- `app/views/scheduling/schedule_by_position/position.html.erb` tables-lists `ui_stat_row`: Stat tile row, not a table or list. (scheduling)
- `app/views/scheduling/shift_drop_report/position.html.erb` tables-lists `ui_stat_row`: Stat tile row, not a table or list. (scheduling)
- `app/views/scheduling/shift_signups/position.html.erb` tables-lists `ui_stat_row`: Stat tile row, not a table or list. (scheduling)
- `app/views/scheduling/slots/position.html.erb` tables-lists `ui_stat_row`: Stat tile row, not a table or list. (scheduling)
- `app/views/scheduling/sandman_qualified/index.html.erb` cards `css:instruction-list`: instruction-list styles a <dl> glossary (filed under cards); it is a list. (scheduling)
- `app/views/scheduling/shift_lead/_legend.html.erb` cards `css:instruction-list`: dl glossary, a list rather than a card. (scheduling)
- `app/views/scheduling/event_stats/index.html.erb` cards `css:instruction-list`: dl glossary, a list rather than a card. (scheduling)
- `app/views/layouts/print.html.erb` modals `modal`: Line 2 is the word "modal" inside an ERB comment; no modal helper is called. (shell-auth-profile)
- `app/views/register/show.html.erb` other `tooltip-or-title-attribute`: Line 10 is hero_panel's title: keyword, not a title attribute or tooltip. (shell-auth-profile)
- `app/views/application/_mega_menu.html.erb` other `tooltip-or-title-attribute`: Lines 24,28,32,37 are the title: local passed to application/_dialog_status (a callout heading), not tooltips. (shell-auth-profile)
- `app/views/sessions/_password_form.html.erb` forms `<label>`: Line 26 is "<label>" inside an ERB comment; the real label is f.label at 29. (shell-auth-profile)
- `app/views/shared/_autocomplete.html.erb` forms `<label>`: Line 5 is "<label for=field_id>" inside an ERB comment. (shell-auth-profile)
- `app/views/profile_photos/new.html.erb` cards `class:card`: card-standard is a custom @utility (components/cards.css:24), not a daisyUI card class; impl should be custom-css. (shell-auth-profile)
- `app/views/profile_photos/crop.html.erb` cards `class:card`: card-standard is a custom @utility (components/cards.css:24), not daisyUI. (shell-auth-profile)
- `app/views/profile_photos/new.html.erb` tables-lists `class:list`: list-numbered is a custom @utility (components/lists.css:15), not daisyUI list. (shell-auth-profile)
- `app/views/profile/show.html.erb` cards `css:instruction-list`: instruction-list is a dl style defined in accessibility.css:55, not boxes.css, and is a tables-lists/definition pattern rather than a card (same for every css:instruction-list row in profile/*, register/*, profile_languages/index, profile_photos/crop). (shell-auth-profile)
- `app/views/sessions/new.html.erb` icons `fa_icon`: Detail "class=login-door-lead" belongs to the enclosing link_to/ext_link, not to any fa_icon. (shell-auth-profile)
- `app/views/application/_search_bar_placeholder.html.erb` icons `fa_icon`: Detail lists button_action/kbd classes (min-w-9, hidden md:inline-flex ...) that belong to the button, not the icons. (shell-auth-profile)
- `app/views/people/bulk_status/_consequence.html.erb` tables-lists `class:list`: list-bulleted is a custom @utility in components/lists.css, not the daisyUI list component (teams-people)
- `app/views/people/status_change_recommendations/show.html.erb` tables-lists `class:list`: list-bulleted is a custom @utility (components/lists.css), not daisyUI list (teams-people)
- `app/helpers/people/languages_known_helper.rb` cards `css:me-muted`: me-muted is a muted-text colour class (hero-panel.css), used on spans, not a card (teams-people)
- `app/helpers/teams_positions/membership_report_helper.rb` icons `html-entity-or-glyph`: middots are text separators in count strings (73,77,82,110), not icons (teams-people)
- `app/helpers/teams_positions/position_grants_helper.rb` icons `html-entity-or-glyph`: middot separators in summary strings, not icons (teams-people)
- `app/helpers/teams_positions/special_teams_hours_helper.rb` icons `html-entity-or-glyph`: middot separator in parameter summary, not an icon (teams-people)
- `app/views/teams_positions/membership_report/index.html.erb` icons `html-entity-or-glyph`: &mdash; is punctuation in the hero description (teams-people)
- `app/views/teams_positions/membership_report/show.html.erb` icons `html-entity-or-glyph`: &mdash; is punctuation in a dd sentence (teams-people)
- `app/views/teams_positions/position_grants/index.html.erb` icons `html-entity-or-glyph`: &mdash; is punctuation in a dd sentence (teams-people)
- `app/views/teams_positions/bulk_teams/index.html.erb` other `tooltip-or-title-attribute`: matched hero_panel title:, not a tooltip (teams-people)
- `app/views/teams_positions/bulk_teams/preview.html.erb` other `tooltip-or-title-attribute`: matched confirm_modal_dialog title:, not a tooltip (teams-people)
- `app/views/teams_positions/bulk_positions/index.html.erb` other `tooltip-or-title-attribute`: hero_panel title: (teams-people)
- `app/views/teams_positions/bulk_positions/preview.html.erb` other `tooltip-or-title-attribute`: confirm_modal_dialog title: (teams-people)
- `app/views/teams_positions/membership_report/show.html.erb` other `tooltip-or-title-attribute`: hero_panel title: (teams-people)
- `app/views/teams_positions/position_grants/index.html.erb` other `tooltip-or-title-attribute`: hero_panel title: (teams-people)
- `app/views/certificates/certificates_report/index.html.erb` other `tooltip-or-title-attribute`: hero_panel title: (teams-people)
- `app/views/people/bulk_lookup/index.html.erb` other `tooltip-or-title-attribute`: hero_panel title: (teams-people)
- `app/views/people/create_account/new.html.erb` other `tooltip-or-title-attribute`: hero_panel title: (teams-people)
- `app/views/people/languages_known/index.html.erb` other `tooltip-or-title-attribute`: hero_panel title: and _language_group title: locals (5,66,67) (teams-people)
- `app/views/people/people_by_location/index.html.erb` other `tooltip-or-title-attribute`: hero_panel title: and country_group title: locals (teams-people)
- `app/views/people/people_by_location/country.html.erb` other `tooltip-or-title-attribute`: hero_panel title: (teams-people)
- `app/views/people/people_by_location/_status_notice.html.erb` other `tooltip-or-title-attribute`: ui_callout_box title: (visible heading) (teams-people)
- `app/views/people/shared/_privacy_notice.html.erb` other `tooltip-or-title-attribute`: ui_callout_box title: (visible heading) (teams-people)
- `app/views/people/people_by_status/index.html.erb` other `tooltip-or-title-attribute`: hero_panel title: (teams-people)
- `app/views/people/retention_report/index.html.erb` other `tooltip-or-title-attribute`: hero_panel title: (teams-people)
- `app/views/people/search/index.html.erb` other `tooltip-or-title-attribute`: hero_panel title: (teams-people)
- `app/views/people/status_change_recommendations/index.html.erb` other `tooltip-or-title-attribute`: hero_panel title: (teams-people)
- `app/views/people/unified_flagging/index.html.erb` other `tooltip-or-title-attribute`: hero_panel title: (teams-people)
- `app/views/teams_positions/position_sanity_checker/index.html.erb` other `tooltip-or-title-attribute`: hero_panel title: (teams-people)
- `app/helpers/teams_positions/position_sanity_checker_helper.rb` other `tooltip-or-title-attribute`: BAND_META title: keys are heading text, not tooltips (teams-people)
- `app/helpers/teams_positions/membership_report_helper.rb` other `tooltip-or-title-attribute`: SORT/labels hash key, not a tooltip (teams-people)
- `app/helpers/people/unified_flagging_helper.rb` other `tooltip-or-title-attribute`: GROUP_META title: merge, not a tooltip (teams-people)
- `app/helpers/bmid/manage_helper.rb` modals `modal`: lines 243 and 273 are comments mentioning the "modal frame"; no modal helper call (ticketing-bmid)
- `app/helpers/bmid/manage_helper.rb` icons `html-entity-or-glyph`: line 90 is a comment ("its ×"), not a rendered glyph (ticketing-bmid)
- `app/helpers/bmid/manage_helper.rb` other `tooltip-or-title-attribute`: line 97 is a labels-hash key (title: "Title") and 305 a comment; only 156, 447, 452 set a real title attribute (ticketing-bmid)
- `app/helpers/bmid/manage_helper.rb` typography `date-format-call`: lines 271, 360, 398, 413, 416, 419 are label/badge helpers (bmid_provision_add_label, bmid_dirty_count_label, bmid_meals_short_label, bmid_sap_cell), not date formatting (ticketing-bmid)
- `app/helpers/bmid_helper.rb` cards `ui_stat_box`: line 32 is a comment naming ui_stat_box; no call (ticketing-bmid)
- `app/helpers/bmid/titles_helper.rb` typography `date-format-call`: line 19 is def bmid_title_cell; no date formatting (ticketing-bmid)
- `app/views/bmid/export/_selection_table.html.erb` forms `bulk_select`: line 8 is in the ERB comment; the partial calls bulk_select_all only (ticketing-bmid)
- `app/views/ticketing/trs_export/_rows_table.html.erb` forms `bulk_select`: line 14 is in the ERB comment ("bulk_select block") (ticketing-bmid)
- `app/views/bmid/manage/_edit_grid.html.erb` modals `modal`: line 14 is in the ERB comment ("modal frame"); no modal call (ticketing-bmid)
- `app/views/bmid/manage/_edit_grid.html.erb` typography `date-format-call`: line 31 is ui_badge bmid_dirty_count_label, not a date (ticketing-bmid)
- `app/views/bmid/manage/_meals_cell.html.erb` typography `date-format-call`: line 19 is bmid_meals_short_label, not a date (ticketing-bmid)
- `app/views/bmid/provisions/_list.html.erb` typography `date-format-call`: line 34 is bmid_provision_add_label, not a date (ticketing-bmid)
- `app/views/bmid/titles/set.html.erb` typography `date-format-call`: line 64 is bmid_title_cell, not a date (ticketing-bmid)
- `app/views/bmid/export/_selection_table.html.erb` typography `date-format-call`: line 50 is bmid_meals_short_label, not a date (ticketing-bmid)
- `app/views/bmid/export/create.html.erb` typography `date-format-call`: line 66 is bmid_meals_short_label, not a date (ticketing-bmid)
- `app/views/bmid/export/_skipped.html.erb` other `tooltip-or-title-attribute`: line 7 is the title: of ui_callout_box (a visible heading), not a title attribute (ticketing-bmid)
- `app/views/ticketing/trs_export/_skipped.html.erb` other `tooltip-or-title-attribute`: line 8 is ui_callout_box title:, a visible heading (ticketing-bmid)
- `app/views/bmid/export/unsubmit.html.erb` other `tooltip-or-title-attribute`: line 43 is ui_callout_box title: (ticketing-bmid)
- `app/views/bmid/export/_previous_exports.html.erb` other `tooltip-or-title-attribute`: line 47 is the confirm_modal title: (ticketing-bmid)
- `app/views/bmid/export/index.html.erb` other `tooltip-or-title-attribute`: line 7 is hero_panel title:, line 88 confirm_modal_dialog title: (ticketing-bmid)
- `app/views/bmid/manage/index.html.erb` other `tooltip-or-title-attribute`: line 5 is hero_panel title:, line 44 ui_callout_box title: (ticketing-bmid)
- `app/views/bmid/sanity_check/index.html.erb` other `tooltip-or-title-attribute`: line 2 is hero_panel title: (ticketing-bmid)
- `app/views/bmid/titles/_form.html.erb` other `tooltip-or-title-attribute`: line 42 is the confirm_modal title: (ticketing-bmid)
- `app/views/bmid/titles/apply.html.erb` other `tooltip-or-title-attribute`: line 6 is hero_panel title: (ticketing-bmid)
- `app/views/bmid/titles/index.html.erb` other `tooltip-or-title-attribute`: line 3 is hero_panel title: (line 49 is a real title attribute on edit_link) (ticketing-bmid)
- `app/views/bmid/titles/set.html.erb` other `tooltip-or-title-attribute`: line 2 is hero_panel title: (ticketing-bmid)
- `app/views/ticketing/access_documents/records.html.erb` other `tooltip-or-title-attribute`: line 6 is hero_panel title: (ticketing-bmid)
- `app/views/ticketing/claimed_with_no_signups/index.html.erb` other `tooltip-or-title-attribute`: line 13 is hero_panel title: (ticketing-bmid)
- `app/views/ticketing/expiring/index.html.erb` other `tooltip-or-title-attribute`: line 8 is hero_panel title: (ticketing-bmid)
- `app/views/ticketing/maintenance/index.html.erb` other `tooltip-or-title-attribute`: line 10 hero_panel title:, line 17 ui_callout_box title: (ticketing-bmid)
- `app/views/ticketing/maintenance/preview.html.erb` other `tooltip-or-title-attribute`: line 21 is ui_callout_box title: (ticketing-bmid)
- `app/views/ticketing/maintenance/results.html.erb` other `tooltip-or-title-attribute`: line 21 is ui_callout_box title: (ticketing-bmid)
- `app/views/ticketing/provisions/index.html.erb` other `tooltip-or-title-attribute`: line 6 is hero_panel title: (ticketing-bmid)
- `app/views/ticketing/sap_candidates/index.html.erb` other `tooltip-or-title-attribute`: line 12 is hero_panel title: (ticketing-bmid)
- `app/views/ticketing/unclaimed_with_signups/index.html.erb` other `tooltip-or-title-attribute`: line 10 is hero_panel title: (ticketing-bmid)
- `app/views/ticketing/trs_export/export.html.erb` other `tooltip-or-title-attribute`: line 56 is confirm_modal_dialog title: (ticketing-bmid)
- `app/views/ticketing/trs_export/index.html.erb` other `tooltip-or-title-attribute`: line 10 hero_panel title:, 103 and 111 confirm_modal_dialog title: (ticketing-bmid)
- `app/views/ticketing/trs_export/mark_submitted.html.erb` other `tooltip-or-title-attribute`: line 22 is ui_callout_box title: (ticketing-bmid)
- `app/views/ticketing/unsubmit_provisions/index.html.erb` other `tooltip-or-title-attribute`: line 93 is confirm_modal_dialog title: (ticketing-bmid)
- `app/views/ticketing/unsubmit_provisions/results.html.erb` other `tooltip-or-title-attribute`: line 22 is ui_callout_box title: (ticketing-bmid)
- `app/views/bmid/badges/edit.html.erb` icons `html-entity-or-glyph`: lines 19 and 111 are &mdash; and &middot; punctuation in text, not icons (same for &mdash; rows in _buckets:37, _skipped:10, unsubmit:36,46, provisions/_list:16, _modal:12,14, sanity_check:91, titles/set:5,58, statistics/index:41, access_documents/index:26, claimed:40, sap_candidates:37, trs_export/_skipped:11, export:29,41, trs index:28, mark_submitted:23) (ticketing-bmid)
- `app/views/ticketing/access_documents/_summary_value.html.erb` icons `html-entity-or-glyph`: line 13 &mdash; is an empty-value placeholder, not an icon (same for _summary_notes:11, _summary_special:7) (ticketing-bmid)
- `app/views/bmid/badges/edit.html.erb` cards `css:me-muted`: me-muted at line 109 colours a timestamp paragraph; it is muted text, not a card (ticketing-bmid)
- `app/views/ticketing/statistics/index.html.erb` cards `css:instruction-list`: instruction-list is a dl question/answer list (tables-lists or typography), not a card; same filing in every file in scope that uses it (access_documents/index, records, expiring, unclaimed, claimed, sap_candidates, provisions, bulk_access_documents/_formats, bmid titles/index, _form, set, sanity_check, manage/index, export/index) (ticketing-bmid)
- `app/helpers/shift_operations/payroll_export_helper.rb` icons `html-entity-or-glyph`: Line 57 " · " is a text separator in a subtitle string, not an icon (timesheets-shiftops)
- `app/helpers/shift_operations/rollcall_helper.rb` icons `html-entity-or-glyph`: Lines 153,155 " · " are text separators in the row detail, not icons (timesheets-shiftops)
- `app/helpers/timesheets/on_duty_helper.rb` icons `html-entity-or-glyph`: Line 65 " · " is a join separator, not an icon (timesheets-shiftops)
- `app/helpers/timesheets/timesheet_by_position_helper.rb` icons `html-entity-or-glyph`: Lines 8,9 " • " are meta-line separators, not icons (timesheets-shiftops)
- `app/helpers/timesheets/timesheet_totals_report_helper.rb` icons `html-entity-or-glyph`: Line 8 " • " is a separator, not an icon (timesheets-shiftops)
- `app/helpers/timesheets/timesheets_by_callsign_helper.rb` icons `html-entity-or-glyph`: Line 11 " • " is a separator, not an icon (timesheets-shiftops)
- `app/views/shift_operations/cruise_direction/_pod.html.erb` icons `html-entity-or-glyph`: Line 84 &middot; is a text separator, not an icon (timesheets-shiftops)
- `app/views/shift_operations/cruise_direction/people/_pool.html.erb` icons `html-entity-or-glyph`: Line 24 &middot; is a text separator, not an icon (timesheets-shiftops)
- `app/views/timesheets/correction_requests/index.html.erb` icons `html-entity-or-glyph`: Line 125 " ·" separator between author and date, not an icon (timesheets-shiftops)
- `app/views/timesheets/early_late_checkins/_section.html.erb` icons `html-entity-or-glyph`: Line 62 " · " safe_join separator, not an icon (timesheets-shiftops)
- `app/views/timesheets/correction_requests/index.html.erb` tables-lists `ui_stat_row`: ui_stat_row is a stat strip (pattern other), not a table/list; same filing on every ui_stat_row row in scope (timesheets-shiftops)
- `app/views/timesheets/correction_requests/index.html.erb` cards `ui_stat_box`: ui_stat_box is a statistic tile (pattern other), filed under cards on every page in scope (timesheets-shiftops)
- `app/views/timesheets/sanity_checker/index.html.erb` tables-lists `ui_drill_down_row`: Detail "size=base" belongs to the nested timesheet_check_badge call, not to ui_drill_down_row; and the rows are navigation (timesheets-shiftops)
- `app/views/training/sessions/_trainees_section.html.erb` buttons `class:btn`: Line 53 "btn-copy-success" is a Stimulus data value (copy_to_clipboard_success_class), not a class on an element (training)
- `app/views/training/untrained_people/index.html.erb` buttons `class:btn`: Line 58 "btn-copy-success" is a Stimulus data value, not a btn class (training)
- `app/views/training/mentoring/assignments/_roster.html.erb` other `class:stack`: "stack-to-row-lg" is a custom layout class, not daisyUI stack (training)
- `app/views/training/online_course_progress/index.html.erb` icons `content_tag/tag.i`: tag.i at 95 is italic blank-marker text, not an icon (training)
- `app/views/training/mentoring/assignments/_roster.html.erb` validation `model-errors-inline`: Line 28 is the refusal summary text fed to an error callout; the actual inline per-row error is line 231 (training)
- `app/views/training/mentees/index.html.erb` icons `html-entity-or-glyph`: &mdash; in title text is punctuation, not an icon (training)
- `app/views/training/all_notes/index.html.erb` icons `html-entity-or-glyph`: &mdash; / &middot; at 4,35,36 are punctuation (training)
- `app/views/training/all_notes/_notes.html.erb` icons `html-entity-or-glyph`: &middot; separator (training)
- `app/views/training/completed_training/show.html.erb` icons `html-entity-or-glyph`: "·" separator in description (training)
- `app/views/training/sessions/show.html.erb` icons `html-entity-or-glyph`: "·" separator (training)
- `app/views/training/sessions/_trainee_card.html.erb` icons `html-entity-or-glyph`: "·" separators in meta line (training)
- `app/views/training/sessions/_trainees_section.html.erb` icons `html-entity-or-glyph`: "—" and "·" in section title (training)
- `app/views/training/sessions/graduations/_dialog.html.erb` icons `html-entity-or-glyph`: "·" in sentence (training)
- `app/views/training/sessions/work_histories/show.html.erb` icons `html-entity-or-glyph`: "·" separators (training)
- `app/views/training/trained_no_work/index.html.erb` icons `html-entity-or-glyph`: &mdash; punctuation (training)
- `app/views/training/online_course_progress/index.html.erb` icons `html-entity-or-glyph`: &mdash; punctuation (training)
- `app/views/training/mentoring/assignments/_roster.html.erb` icons `html-entity-or-glyph`: &mdash; punctuation (training)
- `app/views/training/mentoring/assignments/_upcoming.html.erb` icons `html-entity-or-glyph`: &mdash; punctuation (training)
- `app/views/training/mentoring/assignments/_general_notes_list.html.erb` icons `html-entity-or-glyph`: &middot; separator (training)
- `app/helpers/training/mentoring_helper.rb` icons `html-entity-or-glyph`: "·" separators inside label strings (training)
- `app/views/training/untrained_people/index.html.erb` icons `html-entity-or-glyph`: &mdash; and &middot; punctuation; 120 is an empty-value dash (training)
- `app/views/training/sessions/trainers_report.html.erb` icons `html-entity-or-glyph`: Lines 5,50,68,82,141,143,148 are "·"/"—" separators; the real glyph icon (✔ at 48,94) is under emoji-or-symbol-character (training)
- `app/views/training/sessions/signup_sheet.html.erb` icons `html-entity-or-glyph`: "·" / "—" / &middot; punctuation (training)
- `app/views/training/capacity/index.html.erb` other `tooltip-or-title-attribute`: Line 15 is an ERB comment; the real tooltip is t.heading title: at 61 (training)
- `app/views/training/completed_training/_pager.html.erb` other `tooltip-or-title-attribute`: Lines 3,4 are comment text; the real title: tooltips are at 14,22 (training)
- `app/views/training/mentees/_row.html.erb` other `tooltip-or-title-attribute`: title: at 31 is a confirm_modal heading, not a tooltip (training)
- `app/views/training/mentoring/_missing_positions.html.erb` other `tooltip-or-title-attribute`: title: is the callout heading (training)
- `app/views/training/mentoring/assignments/_general_notes_list.html.erb` other `tooltip-or-title-attribute`: title: is a confirm_modal heading (training)
- `app/views/training/mentoring/assignments/_roster.html.erb` other `tooltip-or-title-attribute`: title: at 33 is the callout heading (training)
- `app/views/training/mentoring/general_notes/_dialog.html.erb` other `tooltip-or-title-attribute`: title: is the modal_dialog heading (training)
- `app/views/training/sessions/_trainer_section.html.erb` other `tooltip-or-title-attribute`: title: is a confirm_modal heading (training)
- `app/views/training/sessions/graduations/_dialog.html.erb` other `tooltip-or-title-attribute`: title: are modal_dialog and callout headings (training)
- `app/views/training/sessions/graduations/_results.html.erb` other `tooltip-or-title-attribute`: modal_dialog heading (training)
- `app/views/training/sessions/notes/_dialog.html.erb` other `tooltip-or-title-attribute`: modal_dialog heading (training)
- `app/views/training/sessions/rosters/_blocked.html.erb` other `tooltip-or-title-attribute`: modal_dialog heading (training)
- `app/views/training/sessions/rosters/_dialog.html.erb` other `tooltip-or-title-attribute`: modal_dialog and callout headings (training)
- `app/views/training/sessions/scores/_dialog.html.erb` other `tooltip-or-title-attribute`: modal_dialog, callout and confirm_modal headings (training)
- `app/views/training/sessions/show.html.erb` other `tooltip-or-title-attribute`: ui_callout_box title: headings (training)
- `app/views/training/sessions/work_histories/show.html.erb` other `tooltip-or-title-attribute`: modal_dialog heading (training)
- `app/views/training/sessions/graduations/show.html.erb` empty-loading `turbo_frame_tag`: "modal" frame wrapper for a dialog, not a loading frame (same for notes/edit, rosters/new, scores/edit, general_notes/edit) (training)
- `app/views/vc/photos_review/_photo.html.erb` other `class:stack`: stack-to-row-lg is a custom @utility in components/layout-patterns.css:14, not the daisyUI stack component (vc)
- `app/views/vc/photos_review/info.html.erb` other `class:stack`: stack-to-row-lg is a custom layout utility, not daisyUI stack (vc)
- `app/views/vc/photos_review/reject_dialog.html.erb` other `class:stack`: stack-to-row-lg is a custom layout utility, not daisyUI stack (vc)
- `app/views/vc/applications/_callsign_stage.html.erb` tables-lists `class:list`: list-bulleted is a custom @utility in components/lists.css:11, not the daisyUI list component (vc)
- `app/views/vc/applications/extract_handles.html.erb` tables-lists `class:list`: list-bulleted is a custom utility, not daisyUI list (vc)
- `app/views/vc/create_prospectives/_group.html.erb` validation `model-errors-inline`: result.errors are the account creator's verdict messages shown in a results table column, not form validation errors (vc)
- `app/views/vc/spigot_flow_report/_callsign_cell.html.erb` spacing `inline-style`: The inline styles are CSS anchor positioning (anchor-name / position-anchor) for a popover, not spacing; pattern should be other (vc)
- `app/views/vc/spigot_flow_report/_callsign_cell.html.erb` navigation `class:dropdown`: dropdown classes style a popover panel listing people in a table cell, not navigation (vc)
- `app/views/vc/applications/dialogs/adjust_status.html.erb` other `tooltip-or-title-attribute`: line 1 is modal_dialog title: (the dialog heading), not a tooltip; same for every file in applications/dialogs/ and extract_handles.html.erb:1 (vc)
- `app/views/vc/photos_review/reject_dialog.html.erb` other `tooltip-or-title-attribute`: line 1 is modal_dialog title:, not a tooltip (vc)
- `app/views/vc/applications/index.html.erb` other `tooltip-or-title-attribute`: line 2 is hero_panel title:, not a tooltip; same for hero title: rows in search, bpguid, handle_checker, photos, photos_review, reserved_handles index:4, shiny_penny_report, spigot_flow_report, thank_you_cards, maintenance index:10, create_prospectives index:10, application_import index:10 (vc)
- `app/views/vc/application_import/_results.html.erb` other `tooltip-or-title-attribute`: lines 11,52,58 are ui_callout_box title: and render local title:, not tooltips (vc)
- `app/helpers/vc/create_prospectives_helper.rb` other `tooltip-or-title-attribute`: title: keys in the GROUPS constant are section titles, not tooltips (vc)
- `app/views/vc/applications/_rail.html.erb` other `tooltip-or-title-attribute`: lines 16,24 are the title: local passed to _notes_list, not tooltips (vc)
- `app/views/vc/applications/_admin_section.html.erb` other `tooltip-or-title-attribute`: line 16 is confirm_modal title:, not a tooltip (also reserved_handles/_form.html.erb:46, reserved_handles/index.html.erb:41, photos_review/_photo.html.erb:46, bpguid/_results.html.erb:101, create_prospectives/index.html.erb:77, application_import/index.html.erb:48) (vc)
- `app/views/vc/bpguid/_results.html.erb` other `tooltip-or-title-attribute`: line 7 is ui_callout_box title:, not a tooltip (also _link_refused.html.erb:7, create_prospectives index:17, maintenance index:16, application_import index:17) (vc)
- `app/views/vc/applications/_mail_log_section.html.erb` other `tooltip-or-title-attribute`: line 21 is the iframe's title attribute (its accessible name), not a hover tooltip (vc)
- `app/views/vc/applications/show.html.erb` icons `html-entity-or-glyph`: &mdash; in the title is punctuation, not an icon; the same applies to the &mdash;/&ldquo; rows in edit_details, edit_personal_info, index:85, extract_handles:9, _callsign_stage:40, create_prospectives, application_import, maintenance, photos, photos_review/info:12, reserved_handles index:24 and upload:24,95 (vc)

## Not fully audited


Templates with no agent PAGE row (census data only): 0
